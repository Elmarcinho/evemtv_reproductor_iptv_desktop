import '../../core/utils/stable_id.dart';
import '../../domain/entities/live.dart';
import '../../domain/entities/vod.dart';
import 'm3u_parser.dart';

/// Catálogo armado a partir de una lista M3U: canales, películas y series,
/// cada uno con sus categorías (`group-title`).
///
/// Los ids son `m3u:<hash>` (de la URL, o del grupo y nombre para una serie):
/// estables entre sesiones y sin credenciales en claro. Las URLs reales se
/// guardan aparte en [urls], solo en memoria.
class M3uCatalog {
  M3uCatalog._({
    required this.liveCategories,
    required this.channels,
    required this.vodCategories,
    required this.movies,
    required this.seriesCategories,
    required this.series,
    required this.seriesDetails,
    required this.urls,
  });

  static const String uncategorizedId = '__sin_categoria__';
  static const String uncategorizedName = 'Sin categoría';

  final List<ContentCategory> liveCategories;
  final List<LiveChannel> channels;
  final List<ContentCategory> vodCategories;
  final List<VodItem> movies;
  final List<ContentCategory> seriesCategories;
  final List<SeriesItem> series;
  final Map<String, SeriesDetail> seriesDetails;

  /// Id de canal, película o episodio → URL del stream.
  final Map<String, Uri> urls;

  /// `Nombre S01E02`, `Nombre - S1 E2 - Título`, `Nombre 1x02`.
  static final RegExp _episodePattern = RegExp(
    r'^(.*?)[\s._\-–|:]*(?:[Ss](\d{1,2})[\s._-]*[Ee](\d{1,4})|(\d{1,2})x(\d{1,4}))\b[\s._\-–|:]*(.*)$',
  );

  static final RegExp _yearPattern = RegExp(r'[\(\[](\d{4})[\)\]]');

  static M3uCatalog build(M3uPlaylist playlist) {
    final urls = <String, Uri>{};
    final liveCategories = <String, ContentCategory>{};
    final channels = <LiveChannel>[];
    final vodCategories = <String, ContentCategory>{};
    final movies = <VodItem>[];
    final seriesCategories = <String, ContentCategory>{};
    final seriesBuilders = <String, _SeriesBuilder>{};

    String categoryOf(M3uEntry entry, Map<String, ContentCategory> into) {
      final id = entry.group ?? uncategorizedId;
      into.putIfAbsent(
        id,
        () => ContentCategory(id: id, name: entry.group ?? uncategorizedName),
      );
      return id;
    }

    for (final entry in playlist.entries) {
      final id = 'm3u:${stableHash(entry.url.toString())}';
      if (urls.containsKey(id)) continue; // URL repetida en la lista.
      urls[id] = entry.url;

      switch (entry.kind) {
        case M3uKind.live:
          channels.add(
            LiveChannel(
              id: id,
              name: entry.name,
              number: entry.channelNumber,
              logoUrl: entry.logoUrl,
              categoryId: categoryOf(entry, liveCategories),
              epgChannelId: entry.tvgId,
            ),
          );
        case M3uKind.movie:
          movies.add(
            VodItem(
              id: id,
              name: entry.name,
              posterUrl: entry.logoUrl,
              categoryId: categoryOf(entry, vodCategories),
              containerExtension: _extension(entry.url),
              year: _year(entry.name),
            ),
          );
        case M3uKind.series:
          final categoryId = categoryOf(entry, seriesCategories);
          final parsed = parseEpisodeName(entry.name);
          final key = '$categoryId|${parsed.show.toLowerCase()}';
          final builder = seriesBuilders.putIfAbsent(
            key,
            () => _SeriesBuilder(
              id: 'm3u:${stableHash(key)}',
              name: parsed.show,
              categoryId: categoryId,
            ),
          );
          builder.posterUrl ??= entry.logoUrl;
          builder.add(
            Episode(
              id: id,
              season: parsed.season ?? 1,
              number: parsed.episode ?? builder.count + 1,
              title: parsed.title ?? entry.name,
              containerExtension: _extension(entry.url),
            ),
          );
      }
    }

    final series = <SeriesItem>[];
    final details = <String, SeriesDetail>{};
    for (final builder in seriesBuilders.values) {
      final item = builder.item;
      series.add(item);
      details[item.id] = builder.detail(item);
    }

    return M3uCatalog._(
      liveCategories: liveCategories.values.toList(),
      channels: channels,
      vodCategories: vodCategories.values.toList(),
      movies: movies,
      seriesCategories: seriesCategories.values.toList(),
      series: series,
      seriesDetails: details,
      urls: urls,
    );
  }

  /// Separa serie, temporada, episodio y título de un nombre de episodio.
  /// Si no reconoce el patrón, todo el nombre es la serie.
  static ({String show, int? season, int? episode, String? title})
  parseEpisodeName(String name) {
    final m = _episodePattern.firstMatch(name.trim());
    if (m == null) {
      return (show: name.trim(), season: null, episode: null, title: null);
    }
    final show = m.group(1)!.trim();
    final title = m.group(6)?.trim();
    return (
      show: show.isEmpty ? name.trim() : show,
      season: int.tryParse(m.group(2) ?? m.group(4) ?? ''),
      episode: int.tryParse(m.group(3) ?? m.group(5) ?? ''),
      title: (title == null || title.isEmpty) ? null : title,
    );
  }

  static String? _extension(Uri url) {
    final path = url.path;
    final dot = path.lastIndexOf('.');
    if (dot < 0) return null;
    final ext = path.substring(dot + 1).toLowerCase();
    return RegExp(r'^[a-z0-9]{1,5}$').hasMatch(ext) ? ext : null;
  }

  static int? _year(String name) {
    final year = int.tryParse(_yearPattern.firstMatch(name)?.group(1) ?? '');
    return (year != null && year >= 1900 && year <= 2100) ? year : null;
  }
}

class _SeriesBuilder {
  _SeriesBuilder({
    required this.id,
    required this.name,
    required this.categoryId,
  });

  final String id;
  final String name;
  final String categoryId;
  String? posterUrl;
  final Map<int, List<Episode>> _seasons = {};
  int count = 0;

  void add(Episode episode) {
    _seasons.putIfAbsent(episode.season, () => []).add(episode);
    count++;
  }

  SeriesItem get item => SeriesItem(
    id: id,
    name: name,
    posterUrl: posterUrl,
    categoryId: categoryId,
  );

  SeriesDetail detail(SeriesItem item) => SeriesDetail(
    series: item,
    seasons: [
      for (final number in _seasons.keys.toList()..sort())
        Season(
          number: number,
          episodes: _seasons[number]!
            ..sort((a, b) => a.number.compareTo(b.number)),
        ),
    ],
  );
}
