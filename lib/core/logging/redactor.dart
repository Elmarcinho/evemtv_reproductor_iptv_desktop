import 'dart:convert';

/// Enmascara credenciales en cualquier texto antes de que llegue a un log.
///
/// Es la **segunda barrera**: la primera es no registrar nunca cuerpos de
/// respuesta, JSON crudo ni excepciones completas del servidor.
///
/// Orden de trabajo (importa, ver [redact]):
/// 1. Secretos registrados sobre el texto original (incluye sus variantes
///    codificadas para URL).
/// 2. Decodificación tolerante (`%xx`, `\/`, `\uXXXX`), repetida para cubrir
///    doble codificación.
/// 3. Secretos registrados otra vez, ya sobre el texto decodificado.
/// 4. Patrones genéricos: rutas Xtream, pares clave/valor sensibles (query,
///    formularios, JSON, mapas de Dart) y `usuario:clave@host`.
class Redactor {
  Redactor._();

  static const String mask = '***';

  /// Secretos con menos caracteres se enmascaran solo como "palabra"
  /// completa (rodeados de caracteres no alfanuméricos): reemplazar cada
  /// aparición de una contraseña "1" destruiría el log sin aportar nada.
  static const int shortSecretLength = 3;

  static final Map<String, RegExp> _secrets = <String, RegExp>{};

  /// Rutas de reproducción `/live|movie|series|timeshift/usuario/clave/`.
  static final RegExp _streamPath = RegExp(
    r'/(live|movie|series|timeshift)/[^/\s?#]+/[^/\s?#]+/',
    caseSensitive: false,
  );

  /// Clave sensible con su valor, con o sin comillas, separada por `=` o `:`.
  /// Cubre `?password=x`, `password=x` (formulario), `"password":"x"`,
  /// `"password": 123` y `{password: x}`.
  static final RegExp _sensitivePair = RegExp(
    r'''(["']?)\b(username|password|passwd|pass|pwd|user|token|auth|key)\1(\s*[:=]\s*)("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'|[^&#\s,;}\])]*)''',
    caseSensitive: false,
  );

  /// `esquema://usuario:clave@host` o `esquema://usuario@host`.
  static final RegExp _userInfo = RegExp(
    r'([a-z][a-z0-9+.\-]*://)[^/@\s]+@',
    caseSensitive: false,
  );

  static final RegExp _percentRun = RegExp(r'(?:%[0-9a-fA-F]{2})+');
  static final RegExp _unicodeEscape = RegExp(r'\\u([0-9a-fA-F]{4})');

  /// Registra un valor que nunca debe aparecer en logs (usuario, contraseña,
  /// URL del perfil activo). Se guardan también sus variantes codificadas.
  static void registerSecret(String? value) {
    if (value == null || value.isEmpty) return;
    final variants = <String>{
      value,
      if (value.trim().isNotEmpty) value.trim(),
      Uri.encodeComponent(value),
      Uri.encodeQueryComponent(value),
      value.replaceAll(' ', '+'),
    };
    for (final v in variants) {
      if (v.isEmpty) continue;
      _secrets[v] = RegExp(
        v.length < shortSecretLength
            ? '(?<![A-Za-z0-9])${RegExp.escape(v)}(?![A-Za-z0-9])'
            : RegExp.escape(v),
      );
    }
  }

  /// Olvida todos los secretos registrados (al cerrar sesión o cambiar perfil).
  static void clearSecrets() => _secrets.clear();

  /// Devuelve [input] con todas las credenciales conocidas enmascaradas.
  ///
  /// El resultado puede quedar decodificado (`%2F` → `/`); para un log es
  /// aceptable y además más legible.
  static String redact(String input) {
    if (input.isEmpty) return input;
    // Secretos primero: si un patrón corta un valor con espacios, el resto
    // del secreto ya no coincidiría y se filtraría.
    var out = _replaceSecrets(input);
    out = _decode(out);
    out = _replaceSecrets(out);
    return out
        .replaceAllMapped(_streamPath, (m) => '/${m[1]}/$mask/$mask/')
        .replaceAllMapped(_sensitivePair, _maskPair)
        .replaceAllMapped(_userInfo, (m) => '${m[1]}$mask@');
  }

  static String _maskPair(Match m) {
    final quote = m[1]!;
    final value = m[4]!;
    final maskedValue = value.startsWith('"')
        ? '"$mask"'
        : value.startsWith("'")
        ? "'$mask'"
        : mask;
    return '$quote${m[2]}$quote${m[3]}$maskedValue';
  }

  static String _replaceSecrets(String input) {
    if (_secrets.isEmpty) return input;
    var out = input;
    // Del más largo al más corto: un secreto contenido en otro no debe dejar
    // restos del más largo sin enmascarar.
    final ordered = _secrets.entries.toList()
      ..sort((a, b) => b.key.length.compareTo(a.key.length));
    for (final entry in ordered) {
      out = out.replaceAll(entry.value, mask);
    }
    return out;
  }

  /// Decodificación que nunca lanza: `%xx` (mayúsculas o minúsculas) como
  /// UTF-8, y los escapes JSON `\/` y `\uXXXX`. Hasta 3 pasadas para cubrir
  /// doble o triple codificación.
  static String _decode(String input) {
    var current = input;
    for (var i = 0; i < 3; i++) {
      final next = current
          .replaceAll(r'\/', '/')
          .replaceAllMapped(
            _unicodeEscape,
            (m) => String.fromCharCode(int.parse(m[1]!, radix: 16)),
          )
          .replaceAllMapped(_percentRun, (m) {
            final hex = m[0]!;
            final bytes = <int>[
              for (var j = 0; j < hex.length; j += 3)
                int.parse(hex.substring(j + 1, j + 3), radix: 16),
            ];
            return utf8.decode(bytes, allowMalformed: true);
          });
      if (next == current) break;
      current = next;
    }
    return current;
  }

  /// Versión segura de `toString()` para objetos arbitrarios.
  static String redactObject(Object? value) =>
      value == null ? 'null' : redact(value.toString());
}
