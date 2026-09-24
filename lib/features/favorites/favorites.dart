import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logging/app_logger.dart';
import '../../data/providers.dart';
import '../../domain/entities/favorite.dart';
import '../../domain/entities/live.dart';
import '../../domain/entities/vod.dart';
import '../auth/application/session.dart';
import '../catalog/catalog_providers.dart';
import '../live/live_providers.dart';

/// Id de la categoría virtual "Favoritos" en En vivo, Películas y Series.
const String favoritesCategoryId = '__favoritos__';

/// Favoritos de un tipo en el perfil activo, en tiempo real.
final favoritesProvider = StreamProvider.family<List<Favorite>, FavoriteKind>((
  ref,
  kind,
) {
  final profileId = ref.watch(sessionProvider.select((s) => s?.profile.id));
  if (profileId == null) return Stream.value(const []);
  return ref.watch(favoritesRepositoryProvider).watch(profileId, kind);
});

/// Ids favoritos de un tipo, para marcar filas y pósters.
final favoriteIdsProvider = Provider.family<Set<String>, FavoriteKind>((
  ref,
  kind,
) {
  final list = ref.watch(favoritesProvider(kind)).value ?? const [];
  return {for (final f in list) f.itemId};
});

/// Completa los favoritos con los datos del catálogo (logo, póster,
/// puntaje), buscándolos en la lista de su categoría. Esas listas ya quedan
/// en memoria durante la sesión, así que no se repiten descargas. Si algo
/// no se encuentra, se usa el favorito tal cual (sin imagen).
Future<List<T>> _resolve<T>(
  Ref ref,
  List<Favorite> favorites,
  Future<List<T>> Function(String categoryId) loadCategory,
  String Function(T item) idOf,
  T Function(Favorite favorite) fallback,
) async {
  final byId = <String, T>{};
  final categories = {for (final f in favorites) ?f.categoryId};
  for (final categoryId in categories) {
    try {
      for (final item in await loadCategory(categoryId)) {
        byId[idOf(item)] = item;
      }
    } on Object catch (e) {
      // La imagen es opcional: una categoría que falla no bloquea la lista.
      AppLogger.w('No se pudieron completar favoritos', e);
    }
  }
  return [for (final f in favorites) byId[f.itemId] ?? fallback(f)];
}

final resolvedLiveFavoritesProvider =
    FutureProvider.autoDispose<List<LiveChannel>>((ref) async {
      final favorites = await ref.watch(
        favoritesProvider(FavoriteKind.live).future,
      );
      return _resolve(
        ref,
        favorites,
        (id) => ref.watch(liveChannelsProvider(id).future),
        (c) => c.id,
        (f) => f.toChannel(),
      );
    });

final resolvedMovieFavoritesProvider =
    FutureProvider.autoDispose<List<VodItem>>((ref) async {
      final favorites = await ref.watch(
        favoritesProvider(FavoriteKind.movie).future,
      );
      return _resolve(
        ref,
        favorites,
        (id) => ref.watch(vodItemsProvider(id).future),
        (m) => m.id,
        (f) => f.toMovie(),
      );
    });

final resolvedSeriesFavoritesProvider =
    FutureProvider.autoDispose<List<SeriesItem>>((ref) async {
      final favorites = await ref.watch(
        favoritesProvider(FavoriteKind.series).future,
      );
      return _resolve(
        ref,
        favorites,
        (id) => ref.watch(seriesItemsProvider(id).future),
        (s) => s.id,
        (f) => f.toSeries(),
      );
    });

/// Agregar y quitar favoritos del perfil activo. No se guarda ninguna URL.
class FavoritesService {
  FavoritesService(this._ref);

  final Ref _ref;

  Future<void> toggleChannel(LiveChannel c) => _toggle(
    FavoriteKind.live,
    c.id,
    () => Favorite(
      kind: FavoriteKind.live,
      itemId: c.id,
      name: c.name,
      categoryId: c.categoryId,
      number: c.number,
      addedAt: DateTime.now(),
    ),
  );

  Future<void> toggleMovie(VodItem m) => _toggle(
    FavoriteKind.movie,
    m.id,
    () => Favorite(
      kind: FavoriteKind.movie,
      itemId: m.id,
      name: m.name,
      categoryId: m.categoryId,
      containerExtension: m.containerExtension,
      year: m.year,
      addedAt: DateTime.now(),
    ),
  );

  Future<void> toggleSeries(SeriesItem s) => _toggle(
    FavoriteKind.series,
    s.id,
    () => Favorite(
      kind: FavoriteKind.series,
      itemId: s.id,
      name: s.name,
      categoryId: s.categoryId,
      year: s.year,
      addedAt: DateTime.now(),
    ),
  );

  Future<void> _toggle(
    FavoriteKind kind,
    String itemId,
    Favorite Function() build,
  ) async {
    final profileId = _ref.read(sessionProvider)?.profile.id;
    if (profileId == null) return;
    final repo = _ref.read(favoritesRepositoryProvider);
    final isFavorite = _ref.read(favoriteIdsProvider(kind)).contains(itemId);
    if (isFavorite) {
      await repo.remove(profileId, kind, itemId);
    } else {
      await repo.add(profileId, build());
    }
    AppLogger.event('favorite.toggle', {'kind': kind, 'added': !isFavorite});
  }
}

final favoritesServiceProvider = Provider<FavoritesService>(
  FavoritesService.new,
);

/// Lista a mostrar: la versión completada con el catálogo si ya está lista
/// y corresponde a los mismos favoritos; si no, la básica al instante.
List<T> preferResolved<T>(
  List<Favorite> favorites,
  List<T>? resolved,
  String Function(T item) idOf,
  T Function(Favorite favorite) fallback,
) {
  if (resolved != null &&
      resolved.length == favorites.length &&
      Iterable<int>.generate(favorites.length)
          .every((i) => idOf(resolved[i]) == favorites[i].itemId)) {
    return resolved;
  }
  return [for (final f in favorites) fallback(f)];
}
