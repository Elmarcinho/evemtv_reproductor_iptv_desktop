import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../core/errors/app_failure.dart';
import '../../core/logging/app_logger.dart';
import '../../core/network/linked_cancel_token.dart';
import '../../core/network/network_failure.dart';
import '../../core/network/retry_interceptor.dart';
import '../../domain/entities/account_info.dart';
import '../../domain/entities/live.dart';
import '../../domain/entities/profile.dart';
import '../../domain/entities/source_credentials.dart';
import '../../domain/entities/vod.dart';
import '../../domain/repositories/content_source.dart';
import 'm3u_catalog.dart';
import 'm3u_parser.dart';

/// Fuente de contenido basada en una lista M3U/M3U8.
///
/// La lista se descarga una vez por sesión, se parsea y organiza (vivo,
/// películas y series) en otro isolate y se mantiene en memoria. Las listas no traen EPG corta: la guía XMLTV
/// completa llega en la Fase 6.
class M3uSource implements ContentSource {
  M3uSource(this._dio, this.credentials, {CancelToken? cancelToken})
    : _sessionToken = cancelToken;

  /// Bytes que se leen para reconocer la cabecera sin descargar la lista
  /// completa (puede pesar decenas de MB).
  static const int probeBytes = 4096;

  /// Tope de descarga: protege la memoria ante una respuesta enorme.
  static const int maxPlaylistBytes = 64 * 1024 * 1024;

  static const String uncategorizedId = M3uCatalog.uncategorizedId;

  final Dio _dio;
  final M3uCredentials credentials;

  /// Token de la sesión dueña de la fuente (ver [_requestToken]).
  final CancelToken? _sessionToken;

  Future<M3uCatalog>? _catalogFuture;
  final Map<String, Uri> _urls = {};

  @override
  SourceType get type => SourceType.m3u;

  @override
  Future<AccountInfo?> fetchAccountInfo() async => null;

  @override
  Future<AccountInfo?> verify() async {
    final cancel = _requestToken();
    final List<int> head;
    try {
      final response = await _open(cancel, maxRetries: 1);
      head = await readHead(response.data!.stream);
    } on DioException catch (e) {
      throw _mapError(e);
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

  // --- TV en vivo ---

  @override
  Future<List<ContentCategory>> liveCategories() async =>
      (await _catalog()).liveCategories;

  @override
  Future<List<LiveChannel>> liveChannels({String? categoryId}) async =>
      _filter((await _catalog()).channels, categoryId, (c) => c.categoryId);

  @override
  Future<List<EpgEntry>> shortEpg(
    LiveChannel channel, {
    int limit = 4,
    bool Function()? isCancelled,
  }) async => const [];

  /// No hay trabajo en segundo plano que cancelar: el catálogo se libera
  /// junto con la fuente.
  @override
  void dispose() {}

  @override
  PlaybackCandidates liveStream(
    LiveChannel channel, {
    List<String> allowedFormats = const [],
  }) => _stream(channel.id);

  // --- Películas ---

  @override
  Future<List<ContentCategory>> vodCategories() async =>
      (await _catalog()).vodCategories;

  @override
  Future<List<VodItem>> vodItems({String? categoryId}) async =>
      _filter((await _catalog()).movies, categoryId, (m) => m.categoryId);

  /// Las listas no traen sinopsis ni reparto: ficha mínima.
  @override
  Future<VodDetail> vodDetail(VodItem item) async => VodDetail(item: item);

  @override
  PlaybackCandidates movieStream(VodItem item) => _stream(item.id);

  // --- Series ---

  @override
  Future<List<ContentCategory>> seriesCategories() async =>
      (await _catalog()).seriesCategories;

  @override
  Future<List<SeriesItem>> seriesItems({String? categoryId}) async =>
      _filter((await _catalog()).series, categoryId, (s) => s.categoryId);

  @override
  Future<SeriesDetail> seriesDetail(SeriesItem series) async {
    final detail = (await _catalog()).seriesDetails[series.id];
    if (detail == null) {
      throw const InvalidPlaylistFailure(detail: 'serie fuera de la lista');
    }
    return detail;
  }

  @override
  PlaybackCandidates episodeStream(Episode episode) => _stream(episode.id);

  // --- Carga ---

  static List<T> _filter<T>(
    List<T> items,
    String? categoryId,
    String? Function(T) categoryOf,
  ) => categoryId == null
      ? items
      : [
          for (final item in items)
            if (categoryOf(item) == categoryId) item,
        ];

  PlaybackCandidates _stream(String id) {
    final url = _urls[id];
    if (url == null) {
      throw const InvalidPlaylistFailure(detail: 'elemento fuera de la lista');
    }
    return PlaybackCandidates([url]);
  }

  Future<M3uCatalog> _catalog() =>
      _catalogFuture ??= _load().catchError((Object e) {
        // Si falla, el próximo intento vuelve a descargar.
        _catalogFuture = null;
        throw e;
      });

  Future<M3uCatalog> _load() async {
    final text = await _download();
    final catalog = await Isolate.run(() {
      final playlist = M3uParser.parse(text);
      return playlist.entries.isEmpty ? null : M3uCatalog.build(playlist);
    });
    if (catalog == null) {
      throw const InvalidPlaylistFailure(detail: 'lista vacía');
    }
    _urls
      ..clear()
      ..addAll(catalog.urls);
    AppLogger.event('m3u.loaded', {
      'live': catalog.channels.length,
      'movies': catalog.movies.length,
      'series': catalog.series.length,
    });
    return catalog;
  }

  Future<String> _download() async {
    try {
      final response = await _open(
        _requestToken(),
        receiveTimeout: const Duration(minutes: 3),
      );
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response.data!.stream) {
        bytes.add(chunk);
        if (bytes.length > maxPlaylistBytes) {
          throw const InvalidPlaylistFailure(detail: 'lista demasiado grande');
        }
      }
      return utf8.decode(bytes.takeBytes(), allowMalformed: true);
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  /// Token propio de una petición, enlazado al de la sesión: se cancela
  /// solo (p. ej. tras leer la cabecera) o cuando termina la sesión.
  CancelToken _requestToken() => linkedCancelToken([_sessionToken]);

  Future<Response<ResponseBody>> _open(
    CancelToken cancel, {
    int? maxRetries,
    Duration? receiveTimeout,
  }) => _dio.getUri<ResponseBody>(
    credentials.playlist,
    cancelToken: cancel,
    options: Options(
      responseType: ResponseType.stream,
      receiveTimeout: receiveTimeout,
      extra: <String, Object?>{RetryInterceptor.maxRetriesKey: ?maxRetries},
    ),
  );

  AppFailure _mapError(DioException e) {
    final failure = mapDioException(e);
    AppLogger.event('m3u.error', {
      'http': e.response?.statusCode,
      'failure': failure.runtimeType,
    }, LogLevel.warning);
    return failure;
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
    final text = head.replaceFirst('﻿', '');
    for (final line in const LineSplitter().convert(text)) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final upper = trimmed.toUpperCase();
      return upper.startsWith('#EXTM3U') || upper.startsWith('#EXTINF:');
    }
    return false;
  }
}
