import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../core/errors/app_failure.dart';
import '../../core/logging/app_logger.dart';
import '../../core/network/network_failure.dart';
import '../../core/network/retry_interceptor.dart';
import '../../core/utils/stable_id.dart';
import '../../domain/entities/account_info.dart';
import '../../domain/entities/live.dart';
import '../../domain/entities/profile.dart';
import '../../domain/entities/source_credentials.dart';
import '../../domain/repositories/content_source.dart';
import 'm3u_parser.dart';

/// Fuente de contenido basada en una lista M3U/M3U8.
///
/// La lista se descarga una vez por sesión, se parsea en otro isolate y se
/// mantiene en memoria. Las listas no traen EPG corta: la guía XMLTV
/// completa llega en la Fase 6.
class M3uSource implements ContentSource {
  M3uSource(this._dio, this.credentials);

  /// Bytes que se leen para reconocer la cabecera sin descargar la lista
  /// completa (puede pesar decenas de MB).
  static const int probeBytes = 4096;

  /// Tope de descarga: protege la memoria ante una respuesta enorme.
  static const int maxPlaylistBytes = 64 * 1024 * 1024;

  static const String uncategorizedId = '__sin_categoria__';

  final Dio _dio;
  final M3uCredentials credentials;

  Future<_LiveIndex>? _live;
  final Map<String, Uri> _urlsById = {};

  @override
  SourceType get type => SourceType.m3u;

  @override
  Future<AccountInfo?> fetchAccountInfo() async => null;

  @override
  Future<AccountInfo?> verify() async {
    final cancel = CancelToken();
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

  @override
  Future<List<ContentCategory>> liveCategories() async =>
      (await _liveIndex()).categories;

  @override
  Future<List<LiveChannel>> liveChannels({String? categoryId}) async {
    final index = await _liveIndex();
    if (categoryId == null) return index.channels;
    return [
      for (final c in index.channels)
        if (c.categoryId == categoryId) c,
    ];
  }

  @override
  Future<List<EpgEntry>> shortEpg(LiveChannel channel, {int limit = 4}) async =>
      const [];

  @override
  PlaybackCandidates liveStream(
    LiveChannel channel, {
    List<String> allowedFormats = const [],
  }) {
    final url = _urlsById[channel.id];
    if (url == null) {
      throw const InvalidPlaylistFailure(detail: 'canal fuera de la lista');
    }
    return PlaybackCandidates([url]);
  }

  Future<_LiveIndex> _liveIndex() =>
      _live ??= _loadLive().catchError((Object e) {
        // Si falla, el próximo intento vuelve a descargar.
        _live = null;
        throw e;
      });

  Future<_LiveIndex> _loadLive() async {
    final text = await _download();
    final playlist = await Isolate.run(() => M3uParser.parse(text));
    if (playlist.entries.isEmpty) {
      throw const InvalidPlaylistFailure(detail: 'lista vacía');
    }
    final index = _LiveIndex.build(playlist);
    _urlsById
      ..clear()
      ..addAll(index.urls);
    AppLogger.event('m3u.loaded', {
      'entries': playlist.entries.length,
      'live': index.channels.length,
      'groups': index.categories.length,
    });
    return index;
  }

  Future<String> _download() async {
    try {
      final response = await _open(
        CancelToken(),
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

/// Canales en vivo de la lista, agrupados por `group-title`.
class _LiveIndex {
  const _LiveIndex(this.categories, this.channels, this.urls);

  factory _LiveIndex.build(M3uPlaylist playlist) {
    final categories = <String, ContentCategory>{};
    final channels = <LiveChannel>[];
    final urls = <String, Uri>{};
    for (final entry in playlist.entries) {
      if (entry.kind != M3uKind.live) continue;
      // Id estable sin credenciales: hash de la URL.
      final id = 'm3u:${stableHash(entry.url.toString())}';
      if (urls.containsKey(id)) continue; // URL repetida en la lista.
      final group = entry.group;
      final categoryId = group ?? M3uSource.uncategorizedId;
      categories.putIfAbsent(
        categoryId,
        () => ContentCategory(id: categoryId, name: group ?? 'Sin categoría'),
      );
      urls[id] = entry.url;
      channels.add(
        LiveChannel(
          id: id,
          name: entry.name,
          number: entry.channelNumber,
          logoUrl: entry.logoUrl,
          categoryId: categoryId,
          epgChannelId: entry.tvgId,
        ),
      );
    }
    return _LiveIndex(categories.values.toList(), channels, urls);
  }

  final List<ContentCategory> categories;
  final List<LiveChannel> channels;
  final Map<String, Uri> urls;
}
