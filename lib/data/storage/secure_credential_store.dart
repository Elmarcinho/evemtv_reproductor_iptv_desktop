import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/errors/app_failure.dart';
import '../../core/logging/app_logger.dart';
import '../../core/utils/json_read.dart';
import '../../domain/entities/source_credentials.dart';
import '../../domain/repositories/credential_store.dart';

/// Credenciales en el almacén seguro del sistema (Keychain, Credential
/// Manager/DPAPI, libsecret). Una entrada JSON por perfil.
///
/// Si el almacén no está disponible (típico en Linux sin GNOME Keyring o
/// KWallet) lanza [StorageFailure] y **no** guarda nada en otro lugar.
class SecureCredentialStore implements CredentialStore {
  SecureCredentialStore(this._storage, {bool? isLinux})
    : _isLinux = isLinux ?? Platform.isLinux;

  final FlutterSecureStorage _storage;
  final bool _isLinux;

  static String _key(int profileId) => 'profile.$profileId.credentials';

  @override
  Future<SourceCredentials?> read(int profileId) async {
    final raw = await _guard('read', () => _storage.read(key: _key(profileId)));
    if (raw == null) return null;
    try {
      final json = JsonRead.map(jsonDecode(raw));
      return json == null ? null : SourceCredentials.fromJson(json);
    } on FormatException {
      AppLogger.event('credentials.corrupt', {
        'profile': profileId,
      }, LogLevel.warning);
      return null;
    }
  }

  @override
  Future<void> write(int profileId, SourceCredentials credentials) => _guard(
    'write',
    () => _storage.write(
      key: _key(profileId),
      value: jsonEncode(credentials.toJson()),
    ),
  );

  @override
  Future<void> delete(int profileId) =>
      _guard('delete', () => _storage.delete(key: _key(profileId)));

  Future<T> _guard<T>(String op, Future<T> Function() action) async {
    try {
      return await action();
    } on PlatformException catch (e) {
      // Solo el código: el mensaje de la plataforma no se registra.
      AppLogger.event('credentials.error', {
        'op': op,
        'code': e.code,
      }, LogLevel.error);
      throw StorageFailure(
        _isLinux
            ? StorageFailureKind.keyringUnavailable
            : StorageFailureKind.readWrite,
        cause: e,
      );
    }
  }
}
