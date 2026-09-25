import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../domain/entities/catalog.dart';
import '../../domain/entities/live.dart';
import '../../domain/entities/vod.dart';
import '../auth/application/session.dart';
import '../search/catalog_sync.dart';
import 'category_cache.dart';

// Películas y series. Viven en el contenedor de la sesión (dependen de
// `contentSourceProvider`): se destruyen con ella y la siguiente sesión
// arranca sin ningún valor de la anterior.

final vodCategoriesProvider = FutureProvider<List<ContentCategory>>((
  ref,
) async {
  final source = ref.watch(contentSourceProvider);
  return source.vodCategories();
}, dependencies: [contentSourceProvider]);

/// Películas de una categoría (`null` = todas). En memoria solo las últimas
/// categorías usadas (ver [CategoryListCache]).
final vodItemsProvider = FutureProvider.autoDispose
    .family<List<VodItem>, String?>((ref, categoryId) async {
      final source = ref.watch(contentSourceProvider);
      final items = await source.vodItems(categoryId: categoryId);
      if (ref.mounted) keepRecentCategory(ref, ('vod', categoryId));
      return items;
    }, dependencies: [contentSourceProvider, categoryListCacheProvider]);

final vodDetailProvider = FutureProvider.autoDispose.family<VodDetail, VodItem>(
  (ref, item) async {
    final source = ref.watch(contentSourceProvider);
    return source.vodDetail(item);
  },
  dependencies: [contentSourceProvider],
);

final seriesCategoriesProvider = FutureProvider<List<ContentCategory>>((
  ref,
) async {
  final source = ref.watch(contentSourceProvider);
  return source.seriesCategories();
}, dependencies: [contentSourceProvider]);

/// Series de una categoría (`null` = todas). En memoria solo las últimas
/// categorías usadas (ver [CategoryListCache]).
final seriesItemsProvider = FutureProvider.autoDispose
    .family<List<SeriesItem>, String?>((ref, categoryId) async {
      final source = ref.watch(contentSourceProvider);
      final items = await source.seriesItems(categoryId: categoryId);
      if (ref.mounted) keepRecentCategory(ref, ('series', categoryId));
      return items;
    }, dependencies: [contentSourceProvider, categoryListCacheProvider]);

final seriesDetailProvider = FutureProvider.autoDispose
    .family<SeriesDetail, SeriesItem>((ref, series) async {
      final source = ref.watch(contentSourceProvider);
      return source.seriesDetail(series);
    }, dependencies: [contentSourceProvider]);

/// Id de la categoría fija "Recién agregadas" en Películas y Series.
const String recentlyAddedCategoryId = '__recientes__';

/// Cuántos elementos muestra "Recién agregadas".
const int recentlyAddedLimit = 50;

/// Películas recién agregadas: las últimas [recentlyAddedLimit] según el
/// catálogo local (fecha de alta del servidor). Se consultan a la base, sin
/// cargar la lista completa del servidor; los pósters se resuelven solo
/// para las filas visibles (ver [CatalogItemView.imageKey]).
final recentMoviesProvider = FutureProvider<List<VodItem>>((ref) async {
  final profileId = ref.watch(sessionContextProvider).profileId;
  ref.watch(catalogSyncProvider.select((s) => s.info[ContentKind.movie]));
  final entries = await ref
      .watch(catalogCacheProvider)
      .recentlyAdded(profileId, ContentKind.movie, limit: recentlyAddedLimit);
  return [for (final e in entries) e.toMovie()];
}, dependencies: [sessionContextProvider, catalogSyncProvider]);

/// Series recién agregadas o con episodios nuevos (catálogo local).
final recentSeriesProvider = FutureProvider<List<SeriesItem>>((ref) async {
  final profileId = ref.watch(sessionContextProvider).profileId;
  ref.watch(catalogSyncProvider.select((s) => s.info[ContentKind.series]));
  final entries = await ref
      .watch(catalogCacheProvider)
      .recentlyAdded(profileId, ContentKind.series, limit: recentlyAddedLimit);
  return [for (final e in entries) e.toSeries()];
}, dependencies: [sessionContextProvider, catalogSyncProvider]);
