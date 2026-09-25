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
    required this._imageCaches,
  });

  final ImageCacheRegistry _imageCaches;

  /// Eliminaciones en curso, por perfil: una segunda llamada para el mismo
  /// perfil reutiliza la primera en lugar de borrar dos veces.
  final Map<int, Future<void>> _removing = {};

  /// Cola de eliminaciones: de a una, para que dos cierres nunca se crucen.
  Future<void> _queue = Future.value();

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
    // Un perfil que se está eliminando no se abre.
    if (_removing.containsKey(profile.id)) return _discarded(profile);
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

  /// Cierra sesión y borra todo lo del perfil, en este orden:
  ///
  /// 1. Cierra su caché de imágenes: rechaza escrituras, cancela descargas
  ///    y espera las que estaban en curso.
  /// 2. Borra credenciales y datos locales. Si falla, lanza
  ///    [StorageFailure] (`deleteFailed`), reabre la caché y la sesión
  ///    **sigue abierta** para reintentar.
  /// 3. Termina la sesión **que inició el cierre** (se destruye su
  ///    contenedor). Si mientras tanto se cambió a otra cuenta, esa sigue
  ///    abierta.
  /// 4. Borra la carpeta de imágenes y su clave, y comprueba que ya no
  ///    estén. Si algo quedó, lanza [StorageFailure] (`cleanupIncomplete`):
  ///    la sesión ya se cerró, pero no se informa éxito.
  ///
  /// Si ya hay un cierre o eliminación de este perfil en curso, devuelve
  /// ese mismo; si es de otro perfil, espera a que termine.
  Future<void> logout(Profile profile) {
    final session = _session.current;
    return _serialized(
      profile.id,
      () => _remove(
        profile,
        session: session != null && session.profile.id == profile.id
            ? session
            : null,
      ),
    );
  }

  /// Elimina un perfil guardado y todo lo suyo (ver [logout]), sin tocar la
  /// sesión activa.
  Future<void> removeProfile(Profile profile) =>
      _serialized(profile.id, () => _remove(profile));

  Future<void> _serialized(int profileId, Future<void> Function() task) {
    final running = _removing[profileId];
    if (running != null) return running;
    // Ya desde ahora (aunque espere en la cola) ninguna apertura pendiente
    // de este perfil debe completarse.
    _session.invalidatePending();
    late final Future<void> future;
    future = _queue.then((_) => task()).whenComplete(() {
      if (identical(_removing[profileId], future)) _removing.remove(profileId);
    });
    _removing[profileId] = future;
    // La cola sigue aunque esta eliminación falle.
    _queue = future.catchError((Object _) {});
    return future;
  }

  /// [session]: la sesión a terminar al completar el borrado (la que
  /// estaba abierta al pedir el cierre), o `null` para no terminar ninguna.
  Future<void> _remove(Profile profile, {Session? session}) async {
    // Invalida las aperturas pendientes para que ninguna reviva el perfil.
    _session.invalidatePending();
    await _imageCaches.close(profile.id);
    try {
      await _credentials.delete(profile.id);
      await _profiles.delete(profile.id);
    } on Object catch (e) {
      _imageCaches.reopen(profile.id);
      AppLogger.e('No se pudo eliminar el perfil', e);
      throw StorageFailure(StorageFailureKind.deleteFailed, cause: e);
    }
    if (session != null && !_session.endIf(session)) {
      AppLogger.event('session.end_skipped', {'reason': 'changed'});
    }
    try {
      await _imageCaches.purge(profile.id);
    } on Object catch (e) {
      AppLogger.e('Limpieza del perfil incompleta', e);
      throw StorageFailure(StorageFailureKind.cleanupIncomplete, cause: e);
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
    // Protección adicional: con AUTOINCREMENT la base no repite ids, pero
    // la carpeta de imágenes y el llavero viven fuera de ella. Si la base
    // se recreó, un perfil nuevo podría tener el id de uno anterior cuyos
    // restos quedaron: no deben heredarse. Si no se pueden borrar, el
    // perfil no se crea.
    try {
      await _imageCaches.purge(profile.id);
    } on Object catch (e) {
      await _profiles.delete(profile.id);
      AppLogger.e('Restos de caché de imágenes sin borrar', e);
      throw StorageFailure(StorageFailureKind.readWrite, cause: e);
    }
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
    imageCaches: ref.watch(imageCacheRegistryProvider),
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
