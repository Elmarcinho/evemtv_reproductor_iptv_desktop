import 'live.dart';
import 'vod.dart';

/// Tipo de contenido del catálogo.
enum ContentKind {
  live('En vivo'),
  movie('Películas'),
  series('Series');

  const ContentKind(this.label);
  final String label;
}

/// Elemento del catálogo guardado en la base local (para la búsqueda y la
/// carga rápida). **Sin URLs**: ni de stream ni de imagen.
class CatalogEntry {
  const CatalogEntry({
    required this.kind,
    required this.id,
    required this.name,
    this.categoryId,
    this.number,
    this.containerExtension,
    this.year,
    this.rating,
    this.added,
  });

  final ContentKind kind;
  final String id;
  final String name;
  final String? categoryId;
  final int? number;
  final String? containerExtension;
  final int? year;
  final double? rating;

  /// Cuándo se agregó al servidor, si lo informa.
  final DateTime? added;

  factory CatalogEntry.fromChannel(LiveChannel c) => CatalogEntry(
    kind: ContentKind.live,
    id: c.id,
    name: c.name,
    categoryId: c.categoryId,
    number: c.number,
  );

  factory CatalogEntry.fromMovie(VodItem m) => CatalogEntry(
    kind: ContentKind.movie,
    id: m.id,
    name: m.name,
    categoryId: m.categoryId,
    containerExtension: m.containerExtension,
    year: m.year,
    rating: m.rating,
    added: m.added,
  );

  factory CatalogEntry.fromSeries(SeriesItem s) => CatalogEntry(
    kind: ContentKind.series,
    id: s.id,
    name: s.name,
    categoryId: s.categoryId,
    year: s.year,
    rating: s.rating,
    added: s.added,
  );

  LiveChannel toChannel() =>
      LiveChannel(id: id, name: name, number: number, categoryId: categoryId);

  VodItem toMovie() => VodItem(
    id: id,
    name: name,
    categoryId: categoryId,
    containerExtension: containerExtension,
    year: year,
    rating: rating,
    added: added,
  );

  SeriesItem toSeries() => SeriesItem(
    id: id,
    name: name,
    categoryId: categoryId,
    year: year,
    rating: rating,
    added: added,
  );
}

/// Resultado de la búsqueda global, agrupado por tipo.
class SearchResults {
  const SearchResults(this.byKind);

  final Map<ContentKind, List<CatalogEntry>> byKind;

  static const empty = SearchResults({});

  bool get isEmpty => byKind.values.every((l) => l.isEmpty);
}

/// Estado del catálogo local de un tipo.
class CatalogSyncInfo {
  const CatalogSyncInfo({required this.syncedAt, required this.itemCount});

  final DateTime syncedAt;
  final int itemCount;
}
