import 'dart:convert';

import 'package:dio/dio.dart';

import '../../core/errors/app_failure.dart';
import '../../core/logging/app_logger.dart';
import '../../core/network/network_failure.dart';
import '../../core/network/retry_interceptor.dart';
import '../../domain/entities/source_credentials.dart';

/// Cliente de bajo nivel de la API Xtream Codes (`player_api.php`).
///
/// Devuelve JSON decodificado; el mapeo a entidades vive en los parsers.
/// Nunca registra la URL ni el cuerpo: solo eventos con la acción y el
/// código HTTP.
class XtreamClient {
  XtreamClient(this._dio, this.credentials);

  final Dio _dio;
  final XtreamCredentials credentials;

  /// `{servidor}/player_api.php?username=…&password=…[&action=…]`.
  Uri apiUri([Map<String, String> params = const {}]) {
    final server = credentials.server;
    return server.replace(
      pathSegments: [
        ...server.pathSegments.where((s) => s.isNotEmpty),
        'player_api.php',
      ],
      queryParameters: {
        'username': credentials.username,
        'password': credentials.password,
        ...params,
      },
    );
  }

  /// Ejecuta una acción de la API y devuelve el JSON decodificado.
  /// [action] `null` = login / información de la cuenta.
  Future<Object?> get(
    String? action, {
    Map<String, String> params = const {},
    int? maxRetries,
  }) async {
    final name = action ?? 'login';
    final uri = apiUri({'action': ?action, ...params});
    final Response<String> response;
    try {
      response = await _dio.getUri<String>(
        uri,
        options: Options(
          responseType: ResponseType.plain,
          extra: <String, Object?>{RetryInterceptor.maxRetriesKey: ?maxRetries},
        ),
      );
    } on DioException catch (e) {
      final failure = mapDioException(e);
      AppLogger.event('xtream.error', {
        'action': name,
        'http': e.response?.statusCode,
        'failure': failure.runtimeType,
      }, LogLevel.warning);
      throw failure;
    }

    AppLogger.event('xtream.response', {
      'action': name,
      'http': response.statusCode,
    }, LogLevel.debug);

    final body = response.data?.trim() ?? '';
    if (body.isEmpty) return null;
    try {
      return jsonDecode(body);
    } on FormatException catch (e) {
      // No se registra el cuerpo: podría ser una página HTML con datos.
      throw InvalidResponseFailure(detail: 'json inválido ($name)', cause: e);
    }
  }
}
