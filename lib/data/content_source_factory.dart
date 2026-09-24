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

  ContentSource create(SourceCredentials credentials) => switch (credentials) {
    XtreamCredentials() => XtreamSource(XtreamClient(_dio, credentials)),
    M3uCredentials() => M3uSource(_dio, credentials),
  };
}
