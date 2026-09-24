import 'package:dio/dio.dart';

import '../config/app_config.dart';
import 'retry_interceptor.dart';

/// Cliente HTTP de la app.
///
/// - Sin interceptores de log: las URLs llevan credenciales. Cada cliente
///   registra eventos propios con `AppLogger.event`.
/// - Validación TLS por defecto (nunca se desactiva de forma global).
/// - Respuestas como texto: el JSON se decodifica aparte para controlar los
///   errores de formato sin registrar el cuerpo.
Dio createDio() {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      sendTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
      responseType: ResponseType.plain,
      followRedirects: true,
      maxRedirects: 5,
      headers: {'User-Agent': AppConfig.userAgent},
    ),
  );
  dio.interceptors.add(RetryInterceptor(dio));
  return dio;
}
