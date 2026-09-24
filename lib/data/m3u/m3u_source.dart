import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

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
      head = await readHead(response.data!.stream);
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
      throw const InvalidPlaylistFailure(detail: 'sin directiva de lista');
    }
    AppLogger.event('m3u.ok', {'bytes': head.length}, LogLevel.debug);
    return null;
  }

  /// Lee como máximo [probeBytes] bytes y corta la descarga. Si un chunk
  /// supera lo que falta, solo se conserva la parte necesaria.
  @visibleForTesting
  static Future<List<int>> readHead(Stream<List<int>> stream) async {
    final bytes = <int>[];
    await for (final chunk in stream) {
      final remaining = probeBytes - bytes.length;
      bytes.addAll(
        chunk.length > remaining ? chunk.sublist(0, remaining) : chunk,
      );
      if (bytes.length >= probeBytes) break;
    }
    return bytes;
  }

  /// La primera línea con contenido (tolerando BOM y espacios) debe ser una
  /// directiva de lista: `#EXTM3U` o, en listas sin cabecera, `#EXTINF:`.
  /// No basta con que la cadena aparezca en cualquier lugar: una página de
  /// error HTML puede mencionarla.
  static bool looksLikePlaylist(String head) {
    final text = head.replaceFirst('\uFEFF', '');
    for (final line in const LineSplitter().convert(text)) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final upper = trimmed.toUpperCase();
      return upper.startsWith('#EXTM3U') || upper.startsWith('#EXTINF:');
    }
    return false;
  }
}
