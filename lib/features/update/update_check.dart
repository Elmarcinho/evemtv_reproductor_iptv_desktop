import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/logging/app_logger.dart';
import '../../core/network/retry_interceptor.dart';
import '../../data/providers.dart';
import '../../domain/repositories/settings_repository.dart';

/// Aviso de actualización (Fase 5; ver docs/decisiones.md §19).
///
/// Consulta `GET https://godebol.com/api/evemtv/version`, que devuelve
/// `{ "ultima_version": "1.1.0", "descarga": "https://…", "minima": "1.0.0" }`.
/// La consulta no lleva datos de la cuenta ni de la instalación: solo el
/// User-Agent con la versión. Si falla, no pasa nada: se vuelve a consultar
/// más tarde.
abstract final class UpdateConfig {
  /// Destino en las compilaciones release.
  static final Uri releaseEndpoint = Uri.parse(
    'https://godebol.com/api/evemtv/version',
  );

  /// Destino en depuración y perfil: desactivado salvo que se pase
  /// `--dart-define=UPDATE_CHECK_URL=http://127.0.0.1:18080/…`.
  static const String devEndpoint = String.fromEnvironment('UPDATE_CHECK_URL');

  /// Página de descargas usada si el enlace recibido no es de confianza.
  static final Uri fallbackDownload = Uri.parse(
    'https://github.com/${AppConfig.githubRepo}/releases/latest',
  );

  /// Guía de instalación para usuarios (enlace visible en el bloqueo).
  static final Uri installGuide = Uri.parse(
    'https://github.com/${AppConfig.githubRepo}/blob/main/docs/instalacion.md',
  );

  /// Plazo para actualizar desde que se detecta por primera vez que la
  /// versión instalada es menor que la mínima. Después, bloqueo.
  static const Duration gracePeriod = Duration(days: 3);

  /// Primera consulta tras abrir la app, y cada cuánto se repite.
  static const Duration firstDelay = Duration(seconds: 3);
  static const Duration interval = Duration(hours: 12);
}

/// Adónde se consulta, o `null` si está desactivado. Solo las compilaciones
/// release apuntan al servidor real; los tests lo reemplazan.
final updateEndpointProvider = Provider<Uri?>((ref) {
  if (kReleaseMode) return UpdateConfig.releaseEndpoint;
  const dev = UpdateConfig.devEndpoint;
  return dev.isEmpty ? null : Uri.parse(dev);
});

/// Versión `mayor.menor.parche`. Tolera una `v` inicial, partes faltantes
/// (`1.2` = `1.2.0`) y sufijos de compilación (`1.2.3+4`, `1.2.3-beta`, que
/// se ignoran).
@immutable
class AppVersion implements Comparable<AppVersion> {
  const AppVersion(this.major, this.minor, this.patch);

  final int major;
  final int minor;
  final int patch;

  static final RegExp _pattern = RegExp(
    r'^v?(\d{1,6})(?:\.(\d{1,6}))?(?:\.(\d{1,6}))?(?:[-+].*)?$',
  );

  /// `null` si no tiene forma de versión.
  static AppVersion? tryParse(Object? raw) {
    if (raw == null) return null;
    final m = _pattern.firstMatch(raw.toString().trim());
    if (m == null) return null;
    int part(int i) => int.parse(m.group(i) ?? '0');
    return AppVersion(part(1), part(2), part(3));
  }

  @override
  int compareTo(AppVersion other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    return patch.compareTo(other.patch);
  }

  bool operator <(AppVersion other) => compareTo(other) < 0;
  bool operator >(AppVersion other) => compareTo(other) > 0;

  @override
  bool operator ==(Object other) =>
      other is AppVersion && compareTo(other) == 0;

  @override
  int get hashCode => Object.hash(major, minor, patch);

  @override
  String toString() => '$major.$minor.$patch';
}

/// Solo se abren enlaces de descarga por HTTPS de los releases de
/// `github.com/Elmarcinho/…`, de `godebol.com` o de la página de descarga
/// `evemtv.godebol.com`. Cualquier otro (o uno con
/// usuario, contraseña o puerto raro) se reemplaza por la página de releases.
bool isTrustedDownload(Uri url) {
  if (url.scheme != 'https') return false;
  if (url.userInfo.isNotEmpty) return false;
  if (url.hasPort && url.port != 443) return false;
  final host = url.host.toLowerCase();
  if (host == 'godebol.com' || host == 'evemtv.godebol.com') return true;
  if (host == 'github.com') {
    final segments = url.pathSegments;
    return segments.isNotEmpty && segments.first.toLowerCase() == 'elmarcinho';
  }
  return false;
}

/// Hay una versión nueva. Si [forced], la instalada es menor que
/// [minimum]: aviso con plazo y, vencido el plazo, bloqueo.
@immutable
class UpdateInfo {
  const UpdateInfo({
    required this.current,
    required this.latest,
    required this.download,
    this.minimum,
  });

  final AppVersion current;
  final AppVersion latest;
  final Uri download;
  final AppVersion? minimum;

  bool get forced => minimum != null && current < minimum!;

  /// El mismo aviso, solo informativo (sin plazo ni bloqueo).
  UpdateInfo withoutMinimum() =>
      UpdateInfo(current: current, latest: latest, download: download);

  @override
  bool operator ==(Object other) =>
      other is UpdateInfo &&
      other.current == current &&
      other.latest == latest &&
      other.download == download &&
      other.minimum == minimum;

  @override
  int get hashCode => Object.hash(current, latest, download, minimum);
}

/// Respuesta válida del servidor: [info] es `null` si la app está al día.
/// (Sin respuesta, la consulta devuelve `null` en lugar de esto.)
@immutable
class UpdateAnswer {
  const UpdateAnswer(this.info, {this.serverDate});

  final UpdateInfo? info;

  /// Fecha del encabezado HTTP `Date` de la respuesta: la referencia del
  /// plazo de la versión mínima (el reloj del equipo puede estar mal o
  /// cambiarse a mano). `null` si falta o no se pudo interpretar: entonces
  /// no hay plazo ni bloqueo.
  final DateTime? serverDate;
}

/// Interpreta la respuesta del servidor. `null` si no hay nada que avisar
/// o si la respuesta no sirve (nunca lanza por un campo raro).
///
/// La mínima (plazo y después bloqueo) solo cuenta con una respuesta
/// **coherente**: `ultima_version`, `minima` y `descarga` presentes y
/// válidas, el enlace de confianza y `minima <= ultima_version`. Si no, a lo
/// sumo un aviso informativo: ante la duda, la app sigue funcionando.
@visibleForTesting
UpdateInfo? parseUpdate(Object? json, AppVersion current) {
  if (json is! Map) return null;
  final latest = AppVersion.tryParse(json['ultima_version']);
  final minimum = AppVersion.tryParse(json['minima']);
  // Sin una "última versión" válida no hay nada que ofrecer.
  if (latest == null || !(latest > current)) return null;
  final raw = json['descarga'];
  final parsed = raw is String ? Uri.tryParse(raw.trim()) : null;
  final trusted = parsed != null && isTrustedDownload(parsed);
  if (!trusted) {
    AppLogger.event('update.enlace', {'resultado': 'rechazado'});
  }
  final coherent = minimum != null && trusted && !(minimum > latest);
  if (minimum != null && !coherent) {
    AppLogger.event('update.minima', {'resultado': 'ignorada'});
  }
  return UpdateInfo(
    current: current,
    latest: latest,
    download: trusted ? parsed : UpdateConfig.fallbackDownload,
    minimum: coherent ? minimum : null,
  );
}

/// Fecha del encabezado HTTP `Date`, o `null` si falta o no es válida.
///
/// Estricta: solo el formato estándar `Sat, 26 Sep 2026 12:00:00 GMT`
/// (IMF-fixdate, el que envían los servidores), con día, mes, año, hora,
/// minutos, segundos y día de la semana válidos. `HttpDate.parse` acepta
/// fechas imposibles y las "corrige" (`99 Sep` pasa a diciembre): con una
/// fecha así el plazo sería falso, así que se trata como ausente.
@visibleForTesting
DateTime? parseServerDate(String? header) {
  if (header == null) return null;
  final m = _imfFixdate.firstMatch(header.trim());
  if (m == null) return null;
  final weekday = _weekdays.indexOf(m.group(1)!) + 1;
  final day = int.parse(m.group(2)!);
  final month = _months.indexOf(m.group(3)!) + 1;
  final year = int.parse(m.group(4)!);
  final hour = int.parse(m.group(5)!);
  final minute = int.parse(m.group(6)!);
  final second = int.parse(m.group(7)!);
  if (year < 2000 || hour > 23 || minute > 59 || second > 59) return null;
  final date = DateTime.utc(year, month, day, hour, minute, second);
  // DateTime también "corrige" (31 Feb → 3 Mar): si algún campo cambió, la
  // fecha no existía.
  if (date.year != year || date.month != month || date.day != day) {
    return null;
  }
  if (date.weekday != weekday) return null;
  return date;
}

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];
final _imfFixdate = RegExp(
  r'^(Mon|Tue|Wed|Thu|Fri|Sat|Sun), (\d{2}) '
  r'(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec) (\d{4}) '
  r'(\d{2}):(\d{2}):(\d{2}) GMT$',
);

/// Consulta la última versión. Nunca lanza.
class UpdateChecker {
  UpdateChecker({
    required this.dio,
    required this.endpoint,
    AppVersion? current,
  }) : current = current ?? AppVersion.tryParse(AppConfig.version)!;

  final Dio dio;
  final Uri? endpoint;
  final AppVersion current;

  /// `null` si no hubo respuesta válida (sin conexión, error del servidor,
  /// JSON raro): en ese caso nada cambia y nunca se bloquea la app.
  Future<UpdateAnswer?> check() async {
    final url = endpoint;
    if (url == null) return null;
    try {
      final response = await dio.getUri<String>(
        url,
        options: Options(
          responseType: ResponseType.plain,
          receiveTimeout: const Duration(seconds: 10),
          validateStatus: (_) => true,
          extra: <String, Object?>{RetryInterceptor.maxRetriesKey: 0},
        ),
      );
      final status = response.statusCode ?? 0;
      if (status != 200) {
        AppLogger.event('update.check', {
          'resultado': 'fallido',
          'http': status,
        }, LogLevel.info);
        return null;
      }
      final json = jsonDecode(response.data ?? '');
      if (json is! Map) {
        AppLogger.event('update.check', {
          'resultado': 'fallido',
          'error': 'formato',
        }, LogLevel.info);
        return null;
      }
      final info = parseUpdate(json, current);
      AppLogger.event('update.check', {
        'resultado': info == null
            ? 'al_dia'
            : info.forced
            ? 'obligatoria'
            : 'nueva',
        if (info != null) 'version': info.latest.toString(),
      });
      return UpdateAnswer(
        info,
        serverDate: parseServerDate(response.headers.value('date')),
      );
    } on Object catch (e) {
      // Sin conexión, JSON inválido, certificado… Se ignora.
      AppLogger.event('update.check', {
        'resultado': 'fallido',
        'error': e is DioException ? e.type.name : e.runtimeType,
      }, LogLevel.info);
      return null;
    }
  }
}

final updateCheckerProvider = Provider<UpdateChecker>(
  (ref) => UpdateChecker(
    dio: ref.watch(dioProvider),
    endpoint: ref.watch(updateEndpointProvider),
  ),
);

/// Estado del aviso.
///
/// - Versión nueva: aviso cerrable (hasta la próxima apertura de la app).
/// - Instalada menor que la mínima: aviso cerrable con [deadline]; vencido
///   el plazo, [locked] (bloqueo que no se cierra).
@immutable
class UpdateState {
  const UpdateState({
    this.info,
    this.dismissed = false,
    this.deadline,
    this.locked = false,
  });

  final UpdateInfo? info;
  final bool dismissed;

  /// Fecha límite para actualizar (solo si la instalada es menor que la
  /// mínima).
  final DateTime? deadline;
  final bool locked;

  /// Si el aviso se ve ahora.
  bool get visible => info != null && (locked || !dismissed);

  UpdateState copyWith({bool? dismissed, bool? locked}) => UpdateState(
    info: info,
    dismissed: dismissed ?? this.dismissed,
    deadline: deadline,
    locked: locked ?? this.locked,
  );
}

class UpdateController extends Notifier<UpdateState> {
  Timer? _timer;
  Timer? _deadlineTimer;

  @override
  UpdateState build() {
    ref.onDispose(() {
      _timer?.cancel();
      _deadlineTimer?.cancel();
    });
    if (ref.watch(updateEndpointProvider) != null) {
      _timer = Timer(UpdateConfig.firstDelay, _checkAndRepeat);
    }
    return const UpdateState();
  }

  Future<void> _checkAndRepeat() async {
    await check();
    if (!ref.mounted) return;
    _timer = Timer(UpdateConfig.interval, _checkAndRepeat);
  }

  /// Consulta ahora. Sin respuesta del servidor nada cambia: la app nunca
  /// se bloquea por no poder consultar.
  ///
  /// El plazo de la versión mínima se mide con la fecha del servidor
  /// (encabezado `Date`), nunca con el reloj del equipo; sin esa fecha, el
  /// aviso es solo informativo.
  Future<void> check() async {
    final answer = await ref.read(updateCheckerProvider).check();
    if (!ref.mounted || answer == null) return;
    var info = answer.info;
    if (info == null) {
      _deadlineTimer?.cancel();
      state = const UpdateState();
      return;
    }
    final serverNow = answer.serverDate;
    DateTime? deadline;
    if (info.forced) {
      if (serverNow == null) {
        AppLogger.event('update.minima', {'resultado': 'sin_fecha'});
        info = info.withoutMinimum();
      } else {
        deadline = await _deadlineFor(info.minimum!, serverNow);
        if (!ref.mounted) return;
      }
    }
    final locked = deadline != null && !serverNow!.isBefore(deadline);
    // Otra versión u otro tipo de aviso lo vuelve a mostrar aunque se haya
    // cerrado.
    final same =
        state.info?.latest == info.latest && state.info?.forced == info.forced;
    state = UpdateState(
      info: info,
      dismissed: same && state.dismissed,
      deadline: deadline,
      locked: locked,
    );
    _deadlineTimer?.cancel();
    if (deadline != null && !locked) {
      // Si la app sigue abierta cuando vence el plazo, se bloquea. El
      // temporizador mide tiempo transcurrido (no la hora del equipo),
      // desde la fecha que dio el servidor.
      _deadlineTimer = Timer(deadline.difference(serverNow!), () {
        if (ref.mounted && state.info?.forced == true) {
          state = state.copyWith(locked: true);
        }
      });
    }
  }

  /// Fecha límite: primera vez que se vio esta mínima (fecha del servidor)
  /// + el plazo. Se guarda por versión mínima; si la mínima cambia, el
  /// plazo empieza de nuevo.
  Future<DateTime> _deadlineFor(AppVersion minimum, DateTime serverNow) async {
    final settings = ref.read(settingsRepositoryProvider);
    var first = serverNow;
    try {
      final saved = await settings.get(SettingsKeys.updateMinimumSeen);
      final parts = saved?.split('|');
      final savedDate = parts != null && parts.length == 2
          ? DateTime.tryParse(parts[1])
          : null;
      if (parts != null && parts[0] == '$minimum' && savedDate != null) {
        // Una fecha guardada posterior a la del servidor (p. ej. de una
        // versión que usaba el reloj del equipo) no alarga el plazo.
        first = savedDate.isAfter(serverNow) ? serverNow : savedDate;
      } else {
        await settings.set(
          SettingsKeys.updateMinimumSeen,
          '$minimum|${serverNow.toUtc().toIso8601String()}',
        );
      }
    } on Object catch (e) {
      // Sin preferencias: el plazo cuenta desde ahora (nunca bloquea antes).
      AppLogger.w('No se pudo leer la fecha del aviso obligatorio', e);
    }
    return first.add(UpdateConfig.gracePeriod);
  }

  /// Cierra el aviso hasta la próxima apertura. El bloqueo no se cierra.
  void dismiss() {
    if (state.info == null || state.locked) return;
    state = state.copyWith(dismissed: true);
  }
}

final updateProvider = NotifierProvider<UpdateController, UpdateState>(
  UpdateController.new,
);
