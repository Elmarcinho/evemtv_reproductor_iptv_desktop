import 'live.dart';
import 'vod.dart';

enum FavoriteKind { live, movie, series }

/// Elemento marcado como favorito en un perfil.
///
/// Guarda lo mínimo para listarlo y reproducirlo: id, nombre, categoría,
/// número de canal, extensión y año. **Ninguna URL** (ni de stream ni de
/// imagen): las imágenes pueden estar en el servidor del panel o llevar
/// tokens. El logo o póster se resuelve en memoria desde la lista de su
/// [categoryId].
class Favorite {
  const Favorite({
    required this.kind,
    required this.itemId,
    required this.name,
    required this.addedAt,
    this.categoryId,
    this.number,
    this.containerExtension,
    this.year,
  });

  final FavoriteKind kind;
  final String itemId;
  final String name;
  final DateTime addedAt;
  final String? categoryId;

  /// Número de canal (vivo).
  final int? number;

  /// Extensión del archivo (películas), necesaria para la URL Xtream.
  final String? containerExtension;
  final int? year;

  LiveChannel toChannel() => LiveChannel(
    id: itemId,
    name: name,
    number: number,
    categoryId: categoryId,
  );

  VodItem toMovie() => VodItem(
    id: itemId,
    name: name,
    categoryId: categoryId,
    containerExtension: containerExtension,
    year: year,
  );

  SeriesItem toSeries() =>
      SeriesItem(id: itemId, name: name, categoryId: categoryId, year: year);
}
