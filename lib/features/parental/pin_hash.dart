import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Hash del PIN del control parental: PBKDF2-HMAC-SHA256 con sal aleatoria
/// de 16 bytes. Se guarda `pbkdf2-sha256$<iteraciones>$<sal>$<hash>` (base64);
/// el PIN nunca se guarda ni se registra en texto plano.
abstract final class PinHash {
  static const int iterations = 20000;
  static const String _scheme = 'pbkdf2-sha256';

  static String create(String pin, {Random? random}) {
    final rng = random ?? Random.secure();
    final salt = Uint8List.fromList(
      List<int>.generate(16, (_) => rng.nextInt(256)),
    );
    final hash = _pbkdf2(utf8.encode(pin), salt, iterations);
    return '$_scheme\$$iterations\$${base64.encode(salt)}\$${base64.encode(hash)}';
  }

  /// `false` si no coincide o si el valor guardado está dañado.
  static bool verify(String pin, String stored) {
    final parts = stored.split(r'$');
    if (parts.length != 4 || parts[0] != _scheme) return false;
    final rounds = int.tryParse(parts[1]);
    if (rounds == null || rounds < 1 || rounds > 1000000) return false;
    try {
      final salt = base64.decode(parts[2]);
      final expected = base64.decode(parts[3]);
      final actual = _pbkdf2(utf8.encode(pin), salt, rounds);
      return constantTimeEquals(actual, expected);
    } on FormatException {
      return false;
    }
  }

  /// Comparación que tarda lo mismo acierte o no.
  static bool constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  /// PBKDF2 con un solo bloque (32 bytes, el tamaño de SHA-256).
  static List<int> _pbkdf2(List<int> password, List<int> salt, int rounds) {
    final hmac = Hmac(sha256, password);
    var u = hmac.convert([...salt, 0, 0, 0, 1]).bytes;
    final out = List<int>.of(u);
    for (var i = 1; i < rounds; i++) {
      u = hmac.convert(u).bytes;
      for (var j = 0; j < out.length; j++) {
        out[j] ^= u[j];
      }
    }
    return out;
  }
}
