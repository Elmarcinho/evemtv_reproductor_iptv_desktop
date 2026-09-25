import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/utils/server_url.dart';
import '../../../data/content_source_factory.dart';
import '../../../data/providers.dart';
import '../../../domain/entities/account_info.dart';
import '../../../domain/entities/profile.dart';
import '../../../domain/entities/source_credentials.dart';
import '../../../domain/repositories/credential_store.dart';
import '../../../domain/repositories/profile_repository.dart';
import '../../images/app_images.dart';
import 'session.dart';

/// Casos de uso de autenticación y perfiles.
class AuthService {
  AuthService({
    required this._profiles,
    required this._credentials,
    required this._sources,
    required this._session,
    this._cleaners = const [],
  });

  /// Limpiezas extra al eliminar un perfil (p. ej. caché de imágenes). Sus
  /// errores se registran pero no impiden la eliminación.
  final List<Future<void> Function(int profileId)> _cleaners;

  final ProfileRepository _profiles;
  final CredentialStore _credentials;
  final ContentSourceFactory _sources;
  final SessionController _session;

  /// Valida la URL, verifica la cuenta contra el servidor y, si todo está
  /// bien, guarda el perfil y abre la sesión.
  Future<void> addXtream({
    String name = '',
    required String url,
    required String username,
    required String password,
  }) async {
    if (username.trim().isEmpty || password.isEmpty) {
      throw const InvalidCredentialsFailure(detail: 'campos vacíos');
    }
    final credentials = XtreamCredentials(
      server: ServerUrl.normalizeXtream(url),
      username: username.trim(),
      password: password,
    );
    final info = await _sources.create(credentials).verify();
    await _saveAndStart(name, credentials, info);
  }

  Future<void> addM3u({String name = '', required String url}) async {
    final credentials = M3uCredentials(
      playlist: ServerUrl.validatePlaylist(url),
    );
    await _sources.create(credentials).verify();
    await _saveAndStart(name, credentials, null);
  }

  /// Abre un perfil guardado. No valida contra el servidor: la pantalla de
  /// inicio carga los datos de la cuenta y muestra el error si lo hay, así
  /// se puede entrar aunque el servidor esté caído.
  ///
  /// Devuelve `false` si la apertura quedó obsoleta mientras esperaba (el
  /// perfil se eliminó o se abrió otra sesión): en ese caso no abre nada.
  Future<bool> open(Profile profile) async {
    final token = _session.token;
    final credentials = await _credentials.read(profile.id);
    if (!_session.isCurrent(token)) return _discarded(profile);
    if (credentials == null) {
      throw StorageFailure(StorageFailureKind.readWrite);
    }
    final exists = await _profiles.markUsed(profile.id);
    if (!exists || !_session.isCurrent(token)) return _discarded(profile);
    _session.start(Session(profile: profile, credentials: credentials));
    AppLogger.event('session.open', {
      'profile': profile.id,
      'type': profile.type,
    });
    return true;
  }

  bool _discarded(Profile profile) {
    AppLogger.event('session.open_discarded', {'profile': profile.id});
    return false;
  }

  /// Vuelve al selector de perfiles sin borrar nada.
  void switchProfile() => _session.end();

  /// Cierra sesión: borra credenciales y todos los datos locales del perfil
  /// y, **solo si el borrado se completó**, termina la sesión. Si falla,
  /// lanza [StorageFailure] (`deleteFailed`) y la sesión sigue abierta, así
  /// el inicio puede mostrar el error y el usuario reintentar.
  Future<void> logout(Profile profile) async {
    await removeProfile(profile);
    _session.end();
  }

  /// Elimina un perfil guardado y sus credenciales. Invalida primero las
  /// operaciones pendientes (aperturas, actualizaciones de cuenta) para que
  /// ninguna reviva el perfil al terminar.
  Future<void> removeProfile(Profile profile) async {
    _session.invalidatePending();
    try {
      await _credentials.delete(profile.id);
      await _profiles.delete(profile.id);
    } on Object catch (e) {
      AppLogger.e('No se pudo eliminar el perfil', e);
      throw StorageFailure(StorageFailureKind.deleteFailed, cause: e);
    }
    for (final clean in _cleaners) {
      try {
        await clean(profile.id);
      } on Object catch (e) {
        AppLogger.w('Limpieza del perfil incompleta', e);
      }
    }
    AppLogger.event('profile.removed', {'profile': profile.id});
  }

  /// Nombre por defecto: nunca el host del servidor (es un dato sensible).
  Future<String> suggestName() async => 'Cuenta ${await _profiles.count() + 1}';

  Future<void> _saveAndStart(
    String name,
    SourceCredentials credentials,
    AccountInfo? info,
  ) async {
    final cleanName = name.trim().isEmpty ? await suggestName() : name.trim();
    final profile = await _profiles.create(
      name: cleanName.length > 60 ? cleanName.substring(0, 60) : cleanName,
      type: credentials.type,
    );
    try {
      await _credentials.write(profile.id, credentials);
    } on Object {
      // Sin credenciales el perfil no sirve: se deshace para no dejarlo roto.
      await _profiles.delete(profile.id);
      rethrow;
    }
    await _profiles.markUsed(profile.id);
    _session.start(
      Session(
        profile: profile,
        credentials: credentials,
        initialAccountInfo: info,
      ),
    );
    AppLogger.event('profile.created', {
      'profile': profile.id,
      'type': credentials.type,
    });
  }
}

final authServiceProvider = Provider<AuthService>(
  (ref) => AuthService(
    profiles: ref.watch(profileRepositoryProvider),
    credentials: ref.watch(credentialStoreProvider),
    sources: ref.watch(contentSourceFactoryProvider),
    session: ref.watch(sessionProvider.notifier),
    cleaners: [
      (id) => clearProfileImageCache(ref.read(imageCacheKeyStoreProvider), id),
    ],
  ),
);

/// Nombre visible de un perfil (por id): el usuario de la cuenta, leído del
/// almacén seguro. `null` si no se puede leer (llavero bloqueado o sin
/// usuario); la interfaz usa entonces el nombre guardado ("Cuenta N").
final profileDisplayNameProvider = FutureProvider.autoDispose
    .family<String?, int>((ref, profileId) async {
      try {
        final credentials = await ref
            .watch(credentialStoreProvider)
            .read(profileId);
        return credentials?.displayName;
      } on AppFailure {
        return null;
      }
    });

/// Perfiles guardados, en tiempo real.
final profilesProvider = StreamProvider<List<Profile>>(
  (ref) => ref.watch(profileRepositoryProvider).watchAll(),
);
