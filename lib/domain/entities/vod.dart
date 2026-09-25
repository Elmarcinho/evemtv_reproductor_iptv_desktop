/// Película del catálogo (vista de grilla).
///
/// [id] es el `stream_id` en Xtream o `m3u:<hash de la URL>` en M3U: nunca
/// contiene credenciales.
class VodItem {
  const VodItem({
    required this.id,
    required this.name,
    this.posterUrl,
    this.rating,
    this.categoryId,
    this.containerExtension,
    this.year,
    this.added,
  });

  final String id;
  final String name;
  final String? posterUrl;

  /// Cuándo se agregó al servidor, si lo informa (para "Recién agregadas").
  final DateTime? added;

  /// Puntaje de 0 a 10, si el panel lo informa.
  final double? rating;
  final String? categoryId;

  /// Extensión del archivo (`mp4`, `mkv`…), necesaria para la URL Xtream.
  final String? containerExtension;
  final int? year;

  @override
  bool operator ==(Object other) => other is VodItem && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Ficha de una película.
class VodDetail {
  const VodDetail({
    required this.item,
    this.plot,
    this.genre,
    this.cast,
    this.director,
    this.releaseDate,
    this.duration,
    this.backdropUrl,
    this.country,
  });

  final VodItem item;
  final String? plot;
  final String? genre;
  final String? cast;
  final String? director;
  final String? releaseDate;
  final Duration? duration;
  final String? backdropUrl;
  final String? country;
}

/// Serie del catálogo (vista de grilla).
class SeriesItem {
  const SeriesItem({
    required this.id,
    required this.name,
    this.posterUrl,
    this.rating,
    this.categoryId,
    this.year,
    this.added,
  });

  final String id;
  final String name;
  final String? posterUrl;
  final double? rating;
  final String? categoryId;
  final int? year;

  /// Última vez que el servidor la agregó o actualizó (p. ej. episodios
  /// nuevos), si lo informa (para "Recién agregadas").
  final DateTime? added;

  @override
  bool operator ==(Object other) => other is SeriesItem && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Ficha de una serie con sus temporadas y episodios.
class SeriesDetail {
  const SeriesDetail({
    required this.series,
    required this.seasons,
    this.plot,
    this.genre,
    this.cast,
    this.director,
    this.releaseDate,
    this.backdropUrl,
  });

  final SeriesItem series;

  /// Ordenadas por número; solo las que tienen episodios.
  final List<Season> seasons;
  final String? plot;
  final String? genre;
  final String? cast;
  final String? director;
  final String? releaseDate;
  final String? backdropUrl;
}

class Season {
  const Season({
    required this.number,
    required this.episodes,
    this.name,
    this.posterUrl,
  });

  final int number;
  final String? name;
  final String? posterUrl;

  /// Ordenados por número de episodio.
  final List<Episode> episodes;

  String get label => name ?? 'Temporada $number';
}

class Episode {
  const Episode({
    required this.id,
    required this.season,
    required this.number,
    required this.title,
    this.plot,
    this.duration,
    this.imageUrl,
    this.containerExtension,
  });

  /// Id del episodio en el panel, o `m3u:<hash>`.
  final String id;
  final int season;
  final int number;
  final String title;
  final String? plot;
  final Duration? duration;
  final String? imageUrl;
  final String? containerExtension;

  @override
  bool operator ==(Object other) => other is Episode && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
