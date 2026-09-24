import 'dart:convert';

import 'package:dio/dio.dart';

import '../../core/errors/app_failure.dart';
import '../../core/logging/app_logger.dart';
import '../../core/network/network_failure.dart';
import '../../core/network/retry_interceptor.dart';
import '../../domain/entities/account_info.dart';
import '../../domain/entities/profile.dart';
import '../../domain/entities/source_credentials.dart';
import '../../domain/repositories/content_source.dart';

/// Fuente de contenido basada en una lista M3U/M3U8.
///
/// En la Fase 1 solo verifica que la URL devuelva una lista; el parser
/// completo llega con la TV en vivo (Fase 2).
class M3uSource implements ContentSource {
  M3uSource(this._dio, this.credentials);

  /// Bytes que se leen para reconocer la cabecera sin descargar la lista
  /// completa (puede pesar decenas de MB).
  static const int probeBytes = 4096;

  final Dio _dio;
  final M3uCredentials credentials;

  @override
  SourceType get type => SourceType.m3u;

  @override
  Future<AccountInfo?> fetchAccountInfo() async => null;

  @override
  Future<AccountInfo?> verify() async {
    final cancel = CancelToken();
    final List<int> head;
    try {
      final response = await _dio.getUri<ResponseBody>(
        credentials.playlist,
        cancelToken: cancel,
        options: Options(
          responseType: ResponseType.stream,
          extra: <String, Object?>{RetryInterceptor.maxRetriesKey: 1},
        ),
      );
      head = await _readHead(response.data!.stream);
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) rethrow;
      final failure = mapDioException(e);
      AppLogger.event('m3u.error', {
        'http': e.response?.statusCode,
        'failure': failure.runtimeType,
      }, LogLevel.warning);
      throw failure;
    } finally {
      // Corta la descarga: ya se leyó lo necesario.
      cancel.cancel();
    }

    if (!looksLikePlaylist(utf8.decode(head, allowMalformed: true))) {
      AppLogger.event('m3u.invalid', {'bytes': head.length}, LogLevel.warning);
      throw const InvalidPlaylistFailure(detail: 'sin #EXTM3U');
    }
    AppLogger.event('m3u.ok', {'bytes': head.length}, LogLevel.debug);
    return null;
  }

  static Future<List<int>> _readHead(Stream<List<int>> stream) async {
    final bytes = <int>[];
    await for (final chunk in stream) {
      bytes.addAll(chunk);
      if (bytes.length >= probeBytes) break;
    }
    return bytes;
  }

  /// `#EXTM3U` al inicio (tolerando BOM y espacios) o, en listas sin
  /// cabecera, alguna línea `#EXTINF`.
  static bool looksLikePlaylist(String head) {
    final text = head.replaceFirst('﻿', '').trimLeft();
    return text.toUpperCase().startsWith('#EXTM3U') ||
        text.toUpperCase().contains('#EXTINF');
  }
}
