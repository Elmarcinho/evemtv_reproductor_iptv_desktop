import 'package:dio/dio.dart';

import '../../core/logging/app_logger.dart';
import '../../core/network/linked_cancel_token.dart';
import '../../core/network/retry_interceptor.dart';

/// Consulta el código HTTP de un stream pidiendo solo el primer byte. Se usa
/// cuando mpv no logra abrir un archivo, para distinguir "no existe en el
/// servidor" (4xx, no tiene sentido reintentar) de un fallo pasajero.
///
/// Devuelve `null` si no se pudo consultar (sin red, otro protocolo…).
typedef StreamProbe = Future<int?> Function(Uri url);

/// [cancelWhen]: tokens cuyo cierre corta la consulta en curso (el del
/// reproductor y el de la sesión); sin ellos la conexión seguiría abierta
/// hasta responder o agotar el tiempo aunque ya nadie espere el resultado.
StreamProbe httpStreamProbe(
  Dio dio, {
  Iterable<CancelToken?> cancelWhen = const [],
}) => (url) async {
  if (!url.isScheme('http') && !url.isScheme('https')) return null;
  final cancel = linkedCancelToken(cancelWhen);
  try {
    final response = await dio.getUri<ResponseBody>(
      url,
      cancelToken: cancel,
      options: Options(
        responseType: ResponseType.stream,
        headers: {'Range': 'bytes=0-0'},
        // Cualquier código es una respuesta válida para esta consulta.
        validateStatus: (_) => true,
        receiveTimeout: const Duration(seconds: 10),
        extra: <String, Object?>{RetryInterceptor.maxRetriesKey: 0},
      ),
    );
    AppLogger.event('player.probe', {'http': response.statusCode});
    return response.statusCode;
  } on DioException catch (e) {
    AppLogger.event('player.probe', {'error': e.type});
    return null;
  } finally {
    cancel.cancel();
  }
};
