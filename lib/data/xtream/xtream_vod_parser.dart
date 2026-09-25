import '../../core/utils/json_read.dart';
import '../../domain/entities/vod.dart';

/// Interpreta películas y series de Xtream de forma tolerante: los elementos
/// que no se pueden usar se omiten y los campos raros quedan vacíos.
abstract final class XtreamVodParser {
  // --- Películas ---

  /// `get_vod_streams`. Se omiten las que no tienen `stream_id`.
  static List<VodItem> movies(Object? json) => [
    for (final item in JsonRead.list(json)) ?_movie(JsonRead.map(item)),
  ];

  static VodItem? _movie(Map<String, Object?>? m) {
    if (m == null) return null;
    final id = JsonRead.integer(m['stream_id']);
    if (id == null || id < 0) return null;
    final name = JsonRead.string(m['name']);
    return VodItem(
      id: '$id',
      name: name ?? 'Película $id',
      posterUrl: httpUrl(JsonRead.string(m['stream_icon'])),
      rating: rating(m['rating']),
      categoryId: JsonRead.string(m['category_id']),
      containerExtension: _extension(m['container_extension']),
      year: _year(m['year']) ?? _year(m['releasedate']) ?? yearInName(name),
      added: _timestamp(m['added']),
    );
  }

  /// `get_vod_info`: `{"info": {...}, "movie_data": {...}}`. `info` puede
  /// llegar como `[]` si el panel no tiene metadatos: se devuelve la ficha
  /// mínima con los datos de [item].
  static VodDetail movieDetail(VodItem item, Object? json) {
    final root = JsonRead.map(json) ?? const {};
    final info = JsonRead.map(root['info']) ?? const {};
    final data = JsonRead.map(root['movie_data']) ?? const {};
    final releaseDate =
        JsonRead.string(info['releasedate']) ??
        JsonRead.string(info['release_date']);
    final enriched = VodItem(
      id: item.id,
      name: item.name,
      posterUrl:
          item.posterUrl ??
          httpUrl(JsonRead.string(info['movie_image'])) ??
          httpUrl(JsonRead.string(info['cover_big'])),
      rating: item.rating ?? rating(info['rating']),
      categoryId: item.categoryId,
      containerExtension:
          item.containerExtension ?? _extension(data['container_extension']),
      year: item.year ?? _year(releaseDate),
    );
    return VodDetail(
      item: enriched,
      plot:
          JsonRead.string(info['plot']) ?? JsonRead.string(info['description']),
      genre: JsonRead.string(info['genre']),
      cast: JsonRead.string(info['cast']) ?? JsonRead.string(info['actors']),
      director: JsonRead.string(info['director']),
      releaseDate: releaseDate,
      duration: duration(info['duration_secs'], info['duration']),
      backdropUrl: _firstUrl(info['backdrop_path']),
      country: JsonRead.string(info['country']),
    );
  }

  // --- Series ---

  /// `get_series`. Se omiten las que no tienen `series_id`.
  static List<SeriesItem> series(Object? json) => [
    for (final item in JsonRead.list(json)) ?_series(JsonRead.map(item)),
  ];

  static SeriesItem? _series(Map<String, Object?>? m) {
    if (m == null) return null;
    final id = JsonRead.integer(m['series_id']);
    if (id == null || id < 0) return null;
    final name = JsonRead.string(m['name']);
    return SeriesItem(
      id: '$id',
      name: name ?? 'Serie $id',
      posterUrl: httpUrl(JsonRead.string(m['cover'])),
      rating: rating(m['rating']),
      categoryId: JsonRead.string(m['category_id']),
      year:
          _year(m['releaseDate']) ??
          _year(m['release_date']) ??
          _year(m['year']) ??
          yearInName(name),
      added: _timestamp(m['last_modified']),
    );
  }

  /// `get_series_info`: `{"seasons": [...], "info": {...}, "episodes": ...}`.
  ///
  /// `episodes` llega como objeto `{"1": [...], "2": [...]}`, como lista de
  /// listas o como lista plana según el panel: se aceptan las tres formas y
  /// cada episodio se agrupa por su propio campo `season` si lo trae.
  static SeriesDetail seriesDetail(SeriesItem series, Object? json) {
    final root = JsonRead.map(json) ?? const {};
    final info = JsonRead.map(root['info']) ?? const {};

    final seasonMeta = <int, Map<String, Object?>>{};
    for (final raw in JsonRead.list(root['seasons'])) {
      final m = JsonRead.map(raw);
      final number = JsonRead.integer(m?['season_number']);
      if (m != null && number != null) seasonMeta[number] = m;
    }

    final bySeason = <int, Map<String, Episode>>{};
    void addEpisode(Object? raw, int? fallbackSeason) {
      final m = JsonRead.map(raw);
      if (m == null) return;
      final episode = _episode(m, fallbackSeason);
      if (episode == null) return;
      bySeason.putIfAbsent(episode.season, () => {})[episode.id] = episode;
    }

    final episodes = root['episodes'];
    if (episodes is Map) {
      for (final entry in episodes.entries) {
        final season = JsonRead.integer(entry.key);
        for (final raw in JsonRead.list(entry.value)) {
          addEpisode(raw, season);
        }
      }
    } else {
      // Lista de listas: cada lista interna es una temporada. Si sus
      // episodios no traen `season`, se toma la i-ésima temporada declarada
      // en `seasons` (o i + 1 si no hay declaradas), para no mezclarlas.
      final declared = seasonMeta.keys.toList()..sort();
      var listIndex = 0;
      for (final item in JsonRead.list(episodes)) {
        if (item is List) {
          final fallback = listIndex < declared.length
              ? declared[listIndex]
              : listIndex + 1;
          for (final raw in item) {
            addEpisode(raw, fallback);
          }
          listIndex++;
        } else {
          addEpisode(item, null);
        }
      }
    }

    final seasons = [
      for (final number in bySeason.keys.toList()..sort())
        Season(
          number: number,
          name: JsonRead.string(seasonMeta[number]?['name']),
          posterUrl:
              httpUrl(JsonRead.string(seasonMeta[number]?['cover_big'])) ??
              httpUrl(JsonRead.string(seasonMeta[number]?['cover'])),
          episodes: bySeason[number]!.values.toList()
            ..sort((a, b) => a.number.compareTo(b.number)),
        ),
    ];

    return SeriesDetail(
      series: series,
      seasons: seasons,
      plot: JsonRead.string(info['plot']),
      genre: JsonRead.string(info['genre']),
      cast: JsonRead.string(info['cast']),
      director: JsonRead.string(info['director']),
      releaseDate:
          JsonRead.string(info['releaseDate']) ??
          JsonRead.string(info['release_date']),
      backdropUrl: _firstUrl(info['backdrop_path']),
    );
  }

  static Episode? _episode(Map<String, Object?> m, int? fallbackSeason) {
    final id = JsonRead.integer(m['id']);
    if (id == null || id < 0) return null;
    final info = JsonRead.map(m['info']) ?? const {};
    final season =
        JsonRead.integer(m['season']) ??
        JsonRead.integer(info['season']) ??
        fallbackSeason ??
        1;
    final number = JsonRead.integer(m['episode_num']) ?? 0;
    return Episode(
      id: '$id',
      season: season,
      number: number,
      title:
          JsonRead.string(m['title']) ??
          JsonRead.string(info['name']) ??
          'Episodio $number',
      plot: JsonRead.string(info['plot']),
      duration: duration(info['duration_secs'], info['duration']),
      imageUrl: httpUrl(JsonRead.string(info['movie_image'])),
      containerExtension: _extension(m['container_extension']),
    );
  }

  // --- Utilidades ---

  /// Puntaje de 0 a 10; `0` o valores fuera de rango = sin puntaje.
  static double? rating(Object? value) {
    final r = JsonRead.decimal(value);
    if (r == null || r <= 0 || r > 10) return null;
    return r;
  }

  /// Duración desde segundos o desde `"hh:mm:ss"` / `"mm:ss"`.
  static Duration? duration(Object? seconds, Object? text) {
    final secs = JsonRead.integer(seconds);
    if (secs != null && secs > 0 && secs < 86400 * 2) {
      return Duration(seconds: secs);
    }
    final parts = JsonRead.string(text)?.split(':');
    if (parts == null || parts.length < 2 || parts.length > 3) return null;
    final numbers = parts.map(int.tryParse).toList();
    if (numbers.any((n) => n == null || n < 0)) return null;
    final total = numbers.fold<int>(0, (acc, n) => acc * 60 + n!);
    return total > 0 ? Duration(seconds: total) : null;
  }

  /// Solo URLs http(s).
  static String? httpUrl(String? url) {
    if (url == null) return null;
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      return null;
    }
    return url;
  }

  static String? _firstUrl(Object? value) {
    if (value is String) return httpUrl(JsonRead.string(value));
    for (final item in JsonRead.list(value)) {
      final url = httpUrl(JsonRead.string(item));
      if (url != null) return url;
    }
    return null;
  }

  /// Extensión segura para armar la URL: solo letras y números.
  static String? _extension(Object? value) {
    final ext = JsonRead.string(value)?.toLowerCase();
    if (ext == null || !RegExp(r'^[a-z0-9]{1,5}$').hasMatch(ext)) return null;
    return ext;
  }

  /// Año escrito en el nombre, como hacen muchos paneles que no llenan el
  /// campo: `"Título (2026)"`, `"Título [2026]"` o `"Título - 2026"`. Un año
  /// suelto al final no cuenta ("Blade Runner 2049" no es de 2049).
  static int? yearInName(String? name) {
    if (name == null) return null;
    final match = _yearInName.firstMatch(name.trim());
    final year = int.tryParse(match?.group(1) ?? match?.group(2) ?? '');
    if (year == null || year < 1900 || year > 2100) return null;
    return year;
  }

  static final RegExp _yearInName = RegExp(
    r'[\(\[](\d{4})[\)\]]|\s[-–]\s(\d{4})$',
  );

  /// Fecha Unix en segundos (`"1767225600"`), o `null` si no es válida.
  static DateTime? _timestamp(Object? value) {
    final seconds = JsonRead.integer(value);
    // Entre 2000 y 2100: descarta 0, valores en milisegundos y basura.
    if (seconds == null || seconds < 946684800 || seconds > 4102444800) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
  }

  /// Año de 4 cifras al inicio de un texto (`"2021-05-01"`) o numérico.
  static int? _year(Object? value) {
    final text = JsonRead.string(value);
    if (text == null) return null;
    final match = RegExp(r'^(\d{4})').firstMatch(text);
    final year = int.tryParse(match?.group(1) ?? '');
    if (year == null || year < 1900 || year > 2100) return null;
    return year;
  }
}
