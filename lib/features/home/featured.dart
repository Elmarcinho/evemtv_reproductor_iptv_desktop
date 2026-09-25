import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../domain/entities/catalog.dart';
import '../auth/application/session.dart';
import '../catalog/catalog_images.dart';
import '../search/catalog_sync.dart';

/// Un elemento del carrusel de novedades, con su póster ya resuelto.
typedef FeaturedItem = ({CatalogEntry entry, String posterUrl});

/// Novedades de un tipo (películas o series) para su carrusel del inicio:
/// las del año en curso, según el catálogo local del perfil. El año sale
/// del reloj: el 1 de enero pasa solo al año nuevo.
///
/// - Si hay pocas del año (p. ej. a principios de enero), se completa con
///   las del año anterior.
/// - Si aun así faltan (o el panel no informa años), se completa con las
///   de mejor puntaje. Los paneles no informan qué es lo más visto: el
///   puntaje es lo más cercano que dan.
/// - Solo entran las que tienen póster (se resuelve en memoria desde la
///   lista de su categoría; la base no guarda URLs).
/// - Se recalcula cuando termina una actualización de ese tipo.
final featuredProvider = FutureProvider.family<List<FeaturedItem>, ContentKind>(
  (ref, kind) async {
    final profileId = ref.watch(sessionContextProvider).profileId;
    ref.watch(catalogSyncProvider.select((s) => s.info[kind]));
    final cache = ref.watch(catalogCacheProvider);
    final year = FeaturedRules.clock().year;

    Future<List<CatalogEntry>> pick(int minYear) => cache.recent(
      profileId,
      kind,
      minYear: minYear,
      limit: FeaturedRules.candidates,
    );

    var candidates = await pick(year);
    if (candidates.length < FeaturedRules.minItems) {
      candidates = await pick(year - 1);
    }
    if (candidates.length < FeaturedRules.minItems) {
      final ids = {for (final c in candidates) c.id};
      final best = await cache.topRated(
        profileId,
        kind,
        limit: FeaturedRules.candidates,
      );
      candidates = [
        ...candidates,
        for (final b in best)
          if (!ids.contains(b.id)) b,
      ].take(FeaturedRules.candidates).toList();
    }

    return _withPosters(ref, candidates);
  },
  dependencies: [
    sessionContextProvider,
    catalogSyncProvider,
    catalogImageProvider,
  ],
);

/// Resuelve el póster de cada candidato (en memoria, desde la lista de su
/// categoría) y deja solo los que tienen, hasta [FeaturedRules.maxItems].
Future<List<FeaturedItem>> _withPosters(
  Ref ref,
  List<CatalogEntry> candidates,
) async {
  // En paralelo: cada categoría se pide una sola vez aunque la compartan
  // varios candidatos.
  final posters = await Future.wait([
    for (final entry in candidates)
      ref.watch(
        catalogImageProvider((
          kind: entry.kind,
          categoryId: entry.categoryId,
          id: entry.id,
        )).future,
      ),
  ]);
  final result = <FeaturedItem>[
    for (final (i, entry) in candidates.indexed)
      if (posters[i] case final poster?) (entry: entry, posterUrl: poster),
  ];
  return result.length > FeaturedRules.maxItems
      ? result.sublist(0, FeaturedRules.maxItems)
      : result;
}

/// "Mejor valoradas": películas y series intercaladas, por puntaje del
/// servidor. Primero las de los últimos [FeaturedRules.topRatedYears] años
/// (para que no sean siempre los mismos clásicos); si hay pocas, de
/// cualquier año.
final topRatedProvider = FutureProvider<List<FeaturedItem>>(
  (ref) async {
    final profileId = ref.watch(sessionContextProvider).profileId;
    ref.watch(
      catalogSyncProvider.select(
        (s) => (s.info[ContentKind.movie], s.info[ContentKind.series]),
      ),
    );
    final cache = ref.watch(catalogCacheProvider);
    final minYear = FeaturedRules.clock().year - FeaturedRules.topRatedYears;

    Future<List<CatalogEntry>> pick(ContentKind kind, {int? since}) =>
        cache.topRated(
          profileId,
          kind,
          limit: FeaturedRules.candidates ~/ 2,
          minYear: since,
        );

    var movies = await pick(ContentKind.movie, since: minYear);
    var series = await pick(ContentKind.series, since: minYear);
    if (movies.length + series.length < FeaturedRules.minItems) {
      movies = await pick(ContentKind.movie);
      series = await pick(ContentKind.series);
    }
    return _withPosters(ref, FeaturedRules.interleave(movies, series));
  },
  dependencies: [
    sessionContextProvider,
    catalogSyncProvider,
    catalogImageProvider,
  ],
);

/// Reglas del carrusel, separadas para poder probarlas.
abstract final class FeaturedRules {
  /// Máximo de tarjetas en el carrusel.
  static const int maxItems = 12;

  /// Con menos novedades del año, se suman las del año anterior.
  static const int minItems = 6;

  /// Candidatos (algunos se descartan por no tener póster).
  static const int candidates = 20;

  /// "Mejor valoradas" prefiere las de estos últimos años.
  static const int topRatedYears = 5;

  /// Película, serie, película…; lo que sobra de uno va al final.
  static List<T> interleave<T>(List<T> a, List<T> b) => [
    for (var i = 0; i < a.length || i < b.length; i++) ...[
      if (i < a.length) a[i],
      if (i < b.length) b[i],
    ],
  ];

  /// Reloj (los tests fijan la fecha).
  static DateTime Function() clock = DateTime.now;

  /// Título del carrusel según lo que muestra: todas del año
  /// ("Películas nuevas 2027"), del año y el anterior ("Películas
  /// recientes") o completadas con las de mejor puntaje ("Películas
  /// destacadas").
  static String title(
    String noun,
    List<({CatalogEntry entry, String posterUrl})> items,
  ) {
    final year = clock().year;
    final years = items.map((i) => i.entry.year);
    if (years.every((y) => y == year)) return '$noun nuevas $year';
    if (years.every((y) => y != null && y >= year - 1)) {
      return '$noun recientes';
    }
    return '$noun destacadas';
  }
}
