import '../../core/utils/task_pool.dart';
import '../../domain/entities/account_info.dart';
import '../../domain/entities/live.dart';
import '../../domain/entities/profile.dart';
import '../../domain/entities/vod.dart';
import '../../domain/repositories/content_source.dart';
import 'xtream_account_parser.dart';
import 'xtream_client.dart';
import 'xtream_live_parser.dart';
import 'xtream_vod_parser.dart';

/// Fuente de contenido Xtream Codes.
class XtreamSource implements ContentSource {
  XtreamSource(this._client, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final XtreamClient _client;
  final DateTime Function() _clock;

  /// Como máximo 4 peticiones de EPG corta a la vez.
  final TaskPool _epgPool = TaskPool(4);

  /// Formatos de vivo en orden de preferencia (spec: `.m3u8`, `.ts` de
  /// respaldo).
  static const List<String> _liveFormats = ['m3u8', 'ts'];

  @override
  SourceType get type => SourceType.xtream;

  /// Login: valida `auth == 1`, estado `Active` y vencimiento. Con un solo
  /// reintento para no hacer esperar demasiado si el servidor está caído.
  @override
  Future<AccountInfo> verify() async {
    final info = XtreamAccountParser.parse(
      await _client.get(null, maxRetries: 1),
    );
    XtreamAccountParser.ensureUsable(info, now: _clock());
    return info;
  }

  @override
  Future<AccountInfo> fetchAccountInfo() async =>
      XtreamAccountParser.parse(await _client.get(null));

  @override
  Future<List<ContentCategory>> liveCategories() async =>
      XtreamLiveParser.categories(await _client.get('get_live_categories'));

  @override
  Future<List<LiveChannel>> liveChannels({String? categoryId}) async =>
      XtreamLiveParser.channels(
        await _client.get(
          'get_live_streams',
          params: {'category_id': ?categoryId},
        ),
      );

  @override
  Future<List<EpgEntry>> shortEpg(LiveChannel channel, {int limit = 4}) =>
      _epgPool.run(
        () async => XtreamLiveParser.shortEpg(
          await _client.get(
            'get_short_epg',
            params: {'stream_id': channel.id, 'limit': '$limit'},
            maxRetries: 0,
          ),
        ),
      );

  @override
  PlaybackCandidates liveStream(
    LiveChannel channel, {
    List<String> allowedFormats = const [],
  }) => PlaybackCandidates([
    for (final ext in liveExtensions(allowedFormats))
      _client.streamUri('live', '${channel.id}.$ext'),
  ]);

  // --- Películas ---

  @override
  Future<List<ContentCategory>> vodCategories() async =>
      XtreamLiveParser.categories(await _client.get('get_vod_categories'));

  @override
  Future<List<VodItem>> vodItems({String? categoryId}) async =>
      XtreamVodParser.movies(
        await _client.get(
          'get_vod_streams',
          params: {'category_id': ?categoryId},
        ),
      );

  @override
  Future<VodDetail> vodDetail(VodItem item) async =>
      XtreamVodParser.movieDetail(
        item,
        await _client.get('get_vod_info', params: {'vod_id': item.id}),
      );

  @override
  PlaybackCandidates movieStream(VodItem item) => PlaybackCandidates([
    _client.streamUri(
      'movie',
      '${item.id}.${item.containerExtension ?? 'mp4'}',
    ),
  ]);

  // --- Series ---

  @override
  Future<List<ContentCategory>> seriesCategories() async =>
      XtreamLiveParser.categories(await _client.get('get_series_categories'));

  @override
  Future<List<SeriesItem>> seriesItems({String? categoryId}) async =>
      XtreamVodParser.series(
        await _client.get('get_series', params: {'category_id': ?categoryId}),
      );

  @override
  Future<SeriesDetail> seriesDetail(SeriesItem series) async =>
      XtreamVodParser.seriesDetail(
        series,
        await _client.get('get_series_info', params: {'series_id': series.id}),
      );

  @override
  PlaybackCandidates episodeStream(Episode episode) => PlaybackCandidates([
    _client.streamUri(
      'series',
      '${episode.id}.${episode.containerExtension ?? 'mp4'}',
    ),
  ]);

  /// Extensiones a probar según `allowed_output_formats`: primero `m3u8` y
  /// luego `ts`, solo las que la cuenta permite. Si no se conocen los
  /// formatos o la cuenta solo permite otros (p. ej. `rtmp`), se prueban
  /// ambas igualmente.
  static List<String> liveExtensions(List<String> allowedFormats) {
    final allowed = {for (final f in allowedFormats) f.trim().toLowerCase()};
    final usable = [
      for (final f in _liveFormats)
        if (allowed.contains(f)) f,
    ];
    return usable.isEmpty ? _liveFormats : usable;
  }
}
