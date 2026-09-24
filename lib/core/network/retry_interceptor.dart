import 'dart:async';

import 'package:dio/dio.dart';

import '../logging/app_logger.dart';

/// Reintenta peticiones GET ante fallos transitorios (timeouts, conexión
/// caída, errores 5xx) con espera progresiva: 0,8 s, 1,6 s, 3,2 s…
///
/// No reintenta 4xx (credenciales, recurso inexistente): repetir no cambia
/// el resultado. Cada petición puede fijar su propio máximo con
/// `Options(extra: {RetryInterceptor.maxRetriesKey: n})`.
class RetryInterceptor extends Interceptor {
  RetryInterceptor(
    this._dio, {
    this.maxRetries = 2,
    this.baseDelay = const Duration(milliseconds: 800),
    Future<void> Function(Duration)? sleep,
  }) : _sleep = sleep ?? Future<void>.delayed;

  static const String maxRetriesKey = 'evemtv_max_retries';
  static const String _attemptKey = 'evemtv_retry_attempt';

  final Dio _dio;
  final int maxRetries;
  final Duration baseDelay;
  final Future<void> Function(Duration) _sleep;

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final options = err.requestOptions;
    final attempt = (options.extra[_attemptKey] as int?) ?? 0;
    final max = (options.extra[maxRetriesKey] as int?) ?? maxRetries;

    if (attempt >= max || !_isRetryable(err) || options.method != 'GET') {
      return handler.next(err);
    }

    final delay = baseDelay * (1 << attempt);
    AppLogger.event('http.retry', {
      'attempt': attempt + 1,
      'of': max,
      'reason': err.type,
      'http': err.response?.statusCode,
      'delay_ms': delay.inMilliseconds,
    }, LogLevel.debug);
    await _sleep(delay);

    options.extra[_attemptKey] = attempt + 1;
    try {
      // `dynamic` a propósito: con cualquier otro tipo, Dio fuerza
      // `responseType = json` y el reintento decodificaría distinto que la
      // petición original.
      handler.resolve(await _dio.fetch<dynamic>(options));
    } on DioException catch (e) {
      handler.next(e);
    }
  }

  static bool _isRetryable(DioException err) {
    switch (err.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
        return true;
      case DioExceptionType.transformTimeout:
        return false;
      case DioExceptionType.badResponse:
        final status = err.response?.statusCode ?? 0;
        return status >= 500 && status != 501;
      case DioExceptionType.badCertificate:
      case DioExceptionType.cancel:
      case DioExceptionType.unknown:
        return false;
    }
  }
}
