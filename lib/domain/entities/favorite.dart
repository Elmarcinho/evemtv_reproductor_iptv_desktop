import 'live.dart';
import 'vod.dart';

enum FavoriteKind { live, movie, series }

/// Elemento marcado como favorito en un perfil.
///
/// Guarda lo mínimo para mostrarlo y reproducirlo sin volver a descargar el
/// catálogo. [imageUrl] se omite si revela el servidor o las credenciales
/// (ver `FavoritesService`).
class Favorite {
  const Favorite({
    required this.kind,
    required this.itemId,
    required this.name,
    required this.addedAt,
    this.imageUrl,
    this.number,
    this.containerExtension,
    this.year,
  });

  final FavoriteKind kind;
  final String itemId;
  final String name;
  final DateTime addedAt;
  final String? imageUrl;

  /// Número de canal (vivo).
  final int? number;

  /// Extensión del archivo (películas), necesaria para la URL Xtream.
  final String? containerExtension;
  final int? year;

  LiveChannel toChannel() =>
      LiveChannel(id: itemId, name: name, number: number, logoUrl: imageUrl);

  VodItem toMovie() => VodItem(
    id: itemId,
    name: name,
    posterUrl: imageUrl,
    containerExtension: containerExtension,
    year: year,
  );

  SeriesItem toSeries() =>
      SeriesItem(id: itemId, name: name, posterUrl: imageUrl, year: year);
}
