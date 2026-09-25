import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Clave aleatoria por perfil para nombrar los archivos de la caché de
/// imágenes (HMAC). Vive en el almacén seguro, junto a las credenciales.
class ImageCacheKeyStore {
  ImageCacheKeyStore(this._storage);

  final FlutterSecureStorage _storage;

  static String _key(int profileId) => 'profile.$profileId.image_cache_key';

  /// Devuelve la clave del perfil, creándola si no existe.
  Future<List<int>> keyFor(int profileId) async {
    final existing = await _storage.read(key: _key(profileId));
    if (existing != null) {
      try {
        final bytes = base64.decode(existing);
        if (bytes.length == 32) return bytes;
      } on FormatException {
        // Dañada: se reemplaza.
      }
    }
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    await _storage.write(key: _key(profileId), value: base64.encode(bytes));
    return bytes;
  }

  Future<void> delete(int profileId) => _storage.delete(key: _key(profileId));

  /// `true` si el perfil todavía tiene clave guardada.
  Future<bool> exists(int profileId) async =>
      await _storage.read(key: _key(profileId)) != null;
}
