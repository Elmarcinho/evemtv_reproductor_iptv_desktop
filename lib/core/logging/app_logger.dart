import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

import '../errors/app_failure.dart';
import 'redactor.dart';

enum LogLevel { debug, info, warning, error }

/// Destino final de los logs. Se puede reemplazar en tests.
typedef LogSink = void Function(LogLevel level, String message);

/// Logger de la app. Todo pasa por [Redactor] antes de salir.
///
/// Primera barrera: nunca registrar URLs, cuerpos de respuesta, JSON crudo ni
/// textos externos. Usar [event] con campos propios (acción, stream_id,
/// formato, código HTTP). Los errores de red se convierten a [AppFailure]
/// antes de registrarse. Aun así, este logger se defiende:
/// - [AppFailure]: solo su [AppFailure.logDescription].
/// - Otros errores (Dio, mpv, etc.): en release solo el tipo; en debug, el
///   texto pasa por el redactor y se recorta a [maxErrorLength] caracteres.
///
/// No envía nada fuera del equipo (sin telemetría). En release solo se
/// registran advertencias y errores, sin stack traces.
class AppLogger {
  AppLogger._();

  static const int maxErrorLength = 300;

  static LogLevel minLevel = kReleaseMode ? LogLevel.warning : LogLevel.debug;

  /// Solo para tests: permite verificar el comportamiento de release.
  @visibleForTesting
  static bool releaseMode = kReleaseMode;

  static LogSink sink = _defaultSink;

  static void d(String message) => _log(LogLevel.debug, message);

  static void i(String message) => _log(LogLevel.info, message);

  static void w(String message, [Object? error]) =>
      _log(LogLevel.warning, message, error);

  static void e(String message, [Object? error, StackTrace? stackTrace]) =>
      _log(LogLevel.error, message, error, stackTrace);

  /// Forma preferida de registrar: un evento propio con campos armados por
  /// nuestro código. Ejemplo:
  ///
  /// ```dart
  /// AppLogger.event('xtream.request', {'action': 'get_live_streams', 'http': 200});
  /// AppLogger.event('player.open', {'kind': 'live', 'stream_id': 123, 'format': 'ts'});
  /// ```
  ///
  /// Nunca pasar URLs, cuerpos de respuesta ni textos externos como valores.
  /// Los valores de tipo `String` igual pasan por el redactor.
  static void event(
    String name, [
    Map<String, Object?> fields = const {},
    LogLevel level = LogLevel.info,
  ]) {
    final buffer = StringBuffer(name);
    fields.forEach((key, value) {
      buffer.write(' $key=${value is Enum ? value.name : value}');
    });
    _log(level, buffer.toString());
  }

  static void _log(
    LogLevel level,
    String message, [
    Object? error,
    StackTrace? stackTrace,
  ]) {
    if (level.index < minLevel.index) return;
    final buffer = StringBuffer(message);
    if (error != null) buffer.write(' | ${describeError(error)}');
    if (stackTrace != null && !releaseMode) buffer.write('\n$stackTrace');
    sink(level, Redactor.redact(buffer.toString()));
  }

  /// Descripción segura y acotada de un error arbitrario.
  static String describeError(Object error) {
    if (error is AppFailure) return error.logDescription;
    if (releaseMode) return '${error.runtimeType}';
    final text = Redactor.redactObject(error);
    return text.length <= maxErrorLength
        ? text
        : '${text.substring(0, maxErrorLength)}… (recortado)';
  }

  static void _defaultSink(LogLevel level, String message) {
    if (kReleaseMode) {
      developer.log(message, name: 'EvemTv', level: _developerLevel(level));
    } else {
      debugPrint('[EvemTv][${level.name.toUpperCase()}] $message');
    }
  }

  static int _developerLevel(LogLevel level) => switch (level) {
    LogLevel.debug => 500,
    LogLevel.info => 800,
    LogLevel.warning => 900,
    LogLevel.error => 1000,
  };
}
