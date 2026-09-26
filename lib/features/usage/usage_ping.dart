import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logging/app_logger.dart';
import '../../core/network/retry_interceptor.dart';
import '../../data/providers.dart';
import '../../domain/entities/source_credentials.dart';
import '../../domain/repositories/settings_repository.dart';
import '../auth/application/session.dart';
import '../auth/application/terms_controller.dart';

/// Conteo de uso mínimo (Fase 4.5; ver docs/decisiones.md §18).
///
/// Una vez al día como máximo se envía `install_id`, `os` y, si hay una
/// sesión abierta, `account_hash` (SHA-256 de "usuario|host"). Nunca el
/// usuario, la contraseña ni la URL. Si falla, se ignora: se vuelve a
/// intentar en la próxima apertura de la app o al día siguiente.
abstract final class UsagePingConfig {
  /// Destino en las compilaciones release.
  static final Uri releaseEndpoint = Uri.parse(
    'https://godebol.com/api/evemtv/ping',
  );

  /// Destino en depuración y perfil: desactivado salvo que se pase
  /// `--dart-define=USAGE_PING_URL=http://127.0.0.1:18080/…`.
  static const String devEndpoint = String.fromEnvironment('USAGE_PING_URL');

  /// Espera tras abrir la app: si en ese tiempo se abre una cuenta, el
  /// envío del día sale con su huella.
  static const Duration appOpenDelay = Duration(seconds: 60);
}

/// Adónde se envía el conteo, o `null` si está desactivado. Los tests lo
/// reemplazan; solo las compilaciones release apuntan al servidor real.
final usagePingEndpointProvider = Provider<Uri?>((ref) {
  if (kReleaseMode) return UsagePingConfig.releaseEndpoint;
  const dev = UsagePingConfig.devEndpoint;
  return dev.isEmpty ? null : Uri.parse(dev);
});

/// Huella de la cuenta: SHA-256 (hex en minúsculas) de
/// "usuario_en_minúsculas|host", con el host sin esquema ni puerto.
/// `null` si la cuenta no tiene usuario (p. ej. una lista M3U sin él).
String? accountHash(SourceCredentials credentials) {
  final user = credentials.displayName?.trim().toLowerCase();
  if (user == null || user.isEmpty) return null;
  final host = switch (credentials) {
    XtreamCredentials(:final server) => server.host,
    M3uCredentials(:final playlist) => playlist.host,
  }.toLowerCase();
  if (host.isEmpty) return null;
  return sha256.convert(utf8.encode('$user|$host')).toString();
}

String get _currentOs => Platform.isWindows
    ? 'windows'
    : Platform.isMacOS
    ? 'macos'
    : 'linux';

/// Envía el conteo del día. Sin estado propio entre ejecuciones más allá de
/// las preferencias locales (`install_id` y el día del último envío).
class UsagePingService {
  UsagePingService({
    required this.dio,
    required this.settings,
    required this.endpoint,
    String? os,
    DateTime Function()? clock,
  }) : _os = os ?? _currentOs,
       _clock = clock ?? DateTime.now;

  final Dio dio;
  final SettingsRepository settings;
  final Uri? endpoint;
  final String _os;
  final DateTime Function() _clock;

  /// Ya se intentó en esta ejecución y falló: no se insiste hasta la
  /// próxima apertura.
  bool _failedThisRun = false;
  Future<bool>? _inFlight;

  /// Día (UTC) en formato `aaaa-mm-dd`.
  String _today() => _clock().toUtc().toIso8601String().substring(0, 10);

  /// Id de esta instalación (UUID v4), creado la primera vez.
  Future<String> installId() async {
    final saved = await settings.get(SettingsKeys.installId);
    if (saved != null && saved.isNotEmpty) return saved;
    final id = _uuidV4();
    await settings.set(SettingsKeys.installId, id);
    return id;
  }

  /// Cuerpo del envío: solo estos tres campos (el servidor rechaza otros).
  @visibleForTesting
  Future<Map<String, String>> body(SourceCredentials? credentials) async => {
    'install_id': await installId(),
    'os': _os,
    'account_hash': ?(credentials == null ? null : accountHash(credentials)),
  };

  /// Envía el conteo si hoy no se envió y no falló ya en esta ejecución.
  /// Devuelve `true` si se envió ahora. Nunca lanza.
  Future<bool> pingIfDue(SourceCredentials? credentials) =>
      _inFlight ??= _ping(credentials).whenComplete(() => _inFlight = null);

  Future<bool> _ping(SourceCredentials? credentials) async {
    final url = endpoint;
    if (url == null || _failedThisRun) return false;
    try {
      if (await settings.get(SettingsKeys.usagePingDay) == _today()) {
        return false;
      }
      final response = await dio.postUri<void>(
        url,
        data: await body(credentials),
        options: Options(
          contentType: Headers.jsonContentType,
          responseType: ResponseType.plain,
          sendTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
          // Cualquier código es una respuesta: se decide abajo.
          validateStatus: (_) => true,
          extra: <String, Object?>{RetryInterceptor.maxRetriesKey: 0},
        ),
      );
      final status = response.statusCode ?? 0;
      if (status >= 200 && status < 300) {
        await settings.set(SettingsKeys.usagePingDay, _today());
        AppLogger.event('usage.ping', {'resultado': 'enviado', 'http': status});
        return true;
      }
      _failedThisRun = true;
      AppLogger.event('usage.ping', {
        'resultado': 'fallido',
        'http': status,
      }, LogLevel.info);
      return false;
    } on Object catch (e) {
      // Sin conexión, tiempo agotado, certificado… Se ignora.
      _failedThisRun = true;
      AppLogger.event('usage.ping', {
        'resultado': 'fallido',
        'error': e is DioException ? e.type.name : e.runtimeType,
      }, LogLevel.info);
      return false;
    }
  }

  static String _uuidV4() {
    final random = Random.secure();
    final b = List<int>.generate(16, (_) => random.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40; // versión 4
    b[8] = (b[8] & 0x3f) | 0x80; // variante RFC 4122
    String hex(int from, int to) =>
        [for (var i = from; i < to; i++) b[i].toRadixString(16).padLeft(2, '0')]
            .join();
    return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
  }
}

final usagePingServiceProvider = Provider<UsagePingService>(
  (ref) => UsagePingService(
    dio: ref.watch(dioProvider),
    settings: ref.watch(settingsRepositoryProvider),
    endpoint: ref.watch(usagePingEndpointProvider),
  ),
);

/// Dispara el conteo: al abrir una cuenta (con su huella) y, si nadie abre
/// una cuenta en [UsagePingConfig.appOpenDelay] tras abrir la app, sin
/// huella. Solo después de aceptar los términos, que lo informan.
class UsagePingTrigger extends Notifier<void> {
  Timer? _appOpen;

  @override
  void build() {
    ref.onDispose(() => _appOpen?.cancel());
    ref.listen(sessionProvider, (previous, next) {
      if (next != null && !identical(previous, next)) {
        _appOpen?.cancel();
        unawaited(_send(next.credentials));
      }
    });
    ref.listen(termsProvider, (_, next) {
      if (next.value == true) _scheduleAppOpen();
    }, fireImmediately: true);
  }

  void _scheduleAppOpen() {
    if (_appOpen != null) return;
    _appOpen = Timer(UsagePingConfig.appOpenDelay, () {
      final session = ref.read(sessionProvider);
      unawaited(_send(session?.credentials));
    });
  }

  Future<void> _send(SourceCredentials? credentials) async {
    try {
      if (!await ref.read(termsProvider.future)) return;
    } on Object {
      return;
    }
    if (!ref.mounted) return;
    await ref.read(usagePingServiceProvider).pingIfDue(credentials);
  }
}

final usagePingTriggerProvider = NotifierProvider<UsagePingTrigger, void>(
  UsagePingTrigger.new,
);
