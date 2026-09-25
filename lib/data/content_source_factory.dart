import 'package:dio/dio.dart';

import '../domain/entities/source_credentials.dart';
import '../domain/repositories/content_source.dart';
import 'm3u/m3u_source.dart';
import 'xtream/xtream_client.dart';
import 'xtream/xtream_source.dart';

/// Crea la fuente de contenido que corresponde a unas credenciales.
class ContentSourceFactory {
  const ContentSourceFactory(this._dio);

  final Dio _dio;

  /// [cancelToken]: el de la sesión; al cancelarse, todas las peticiones
  /// de la fuente se cortan (las nuevas fallan al instante).
  ContentSource create(
    SourceCredentials credentials, {
    CancelToken? cancelToken,
  }) => switch (credentials) {
    XtreamCredentials() => XtreamSource(
      XtreamClient(_dio, credentials, cancelToken: cancelToken),
    ),
    M3uCredentials() => M3uSource(_dio, credentials, cancelToken: cancelToken),
  };
}
