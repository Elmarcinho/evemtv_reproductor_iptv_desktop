import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

import '../errors/app_failure.dart';
import 'redactor.dart';

enum LogLevel { debug, info, warning, error }

/// Destino final de los logs. Se puede reemplazar en tests.
typedef LogSink = void Function(LogLevel level, String message);

/// Logger de la app. Todo pasa por [Redactor] antes de salir.
///
/// Regla: no pasar aquí cuerpos de respuesta, JSON crudo ni excepciones
/// completas del servidor. Para errores de red, convertir primero a
/// [AppFailure] y registrar esa. Aun así, este logger se defiende:
/// - [AppFailure]: solo su [AppFailure.logDescription].
/// - Otros errores: en release solo el tipo; en debug, el texto redactado y
///   recortado a [maxErrorLength] caracteres.
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
