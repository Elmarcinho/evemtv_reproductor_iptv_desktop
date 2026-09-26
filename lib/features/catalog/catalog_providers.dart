import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../domain/entities/catalog.dart';
import '../../domain/entities/live.dart';
import '../../domain/entities/vod.dart';
import '../auth/application/session.dart';
import '../parental/parental.dart';
import '../search/catalog_sync.dart';
import 'category_cache.dart';

// Películas y series. Viven en el contenedor de la sesión (dependen de
// `contentSourceProvider`): se destruyen con ella y la siguiente sesión
// arranca sin ningún valor de la anterior.

/// Todas las categorías de películas del proveedor, sin filtrar.
final vodCategoriesAllProvider = FutureProvider<List<ContentCategory>>((
  ref,
) async {
  final source = ref.watch(contentSourceProvider);
  return source.vodCategories();
}, dependencies: [contentSourceProvider]);

/// Categorías de películas visibles (sin las ocultas por el control
/// parental mientras esté bloqueado).
final vodCategoriesProvider = FutureProvider<List<ContentCategory>>((
  ref,
) async {
  final all = await ref.watch(vodCategoriesAllProvider.future);
  return visibleCategories(ref.watch(parentalProvider), ContentKind.movie, all);
}, dependencies: [vodCategoriesAllProvider, parentalProvider]);

/// Películas de una categoría del proveedor (`null` = todas), sin filtrar.
/// En memoria solo las últimas categorías usadas (ver
/// [CategoryListCache]).
final vodItemsSourceProvider = FutureProvider.autoDispose
    .family<List<VodItem>, String?>((ref, categoryId) async {
      final source = ref.watch(contentSourceProvider);
      final items = await source.vodItems(categoryId: categoryId);
      if (ref.mounted) keepRecentCategory(ref, ('vod', categoryId));
      return items;
    }, dependencies: [contentSourceProvider, categoryListCacheProvider]);

/// Películas visibles de una categoría (`null` = todas): sin las de
/// adultos ni las de categorías ocultas mientras el control parental esté
/// bloqueado.
final vodItemsProvider = FutureProvider.autoDispose
    .family<List<VodItem>, String?>(
      (ref, categoryId) async {
        final items = await ref.watch(
          vodItemsSourceProvider(categoryId).future,
        );
        final parental = ref.watch(parentalProvider);
        if (parental.unlocked) return items;
        final hidden = await hiddenCategoryIdsOf(
          ref,
          parental,
          ContentKind.movie,
          vodCategoriesAllProvider,
        );
        if (categoryId != null && hidden.contains(categoryId)) return const [];
        return [
          for (final m in items)
            if (!m.adult && !hidden.contains(m.categoryId)) m,
        ];
      },
      dependencies: [
        vodItemsSourceProvider,
        vodCategoriesAllProvider,
        parentalProvider,
      ],
    );

final vodDetailProvider = FutureProvider.autoDispose.family<VodDetail, VodItem>(
  (ref, item) async {
    final source = ref.watch(contentSourceProvider);
    return source.vodDetail(item);
  },
  dependencies: [contentSourceProvider],
);

/// Todas las categorías de series del proveedor, sin filtrar.
final seriesCategoriesAllProvider = FutureProvider<List<ContentCategory>>((
  ref,
) async {
  final source = ref.watch(contentSourceProvider);
  return source.seriesCategories();
}, dependencies: [contentSourceProvider]);

/// Categorías de series visibles (sin las ocultas por el control parental
/// mientras esté bloqueado).
final seriesCategoriesProvider = FutureProvider<List<ContentCategory>>((
  ref,
) async {
  final all = await ref.watch(seriesCategoriesAllProvider.future);
  return visibleCategories(
    ref.watch(parentalProvider),
    ContentKind.series,
    all,
  );
}, dependencies: [seriesCategoriesAllProvider, parentalProvider]);

/// Series de una categoría del proveedor (`null` = todas), sin filtrar. En
/// memoria solo las últimas categorías usadas (ver [CategoryListCache]).
final seriesItemsSourceProvider = FutureProvider.autoDispose
    .family<List<SeriesItem>, String?>((ref, categoryId) async {
      final source = ref.watch(contentSourceProvider);
      final items = await source.seriesItems(categoryId: categoryId);
      if (ref.mounted) keepRecentCategory(ref, ('series', categoryId));
      return items;
    }, dependencies: [contentSourceProvider, categoryListCacheProvider]);

/// Series visibles de una categoría (`null` = todas): sin las de adultos ni
/// las de categorías ocultas mientras el control parental esté bloqueado.
final seriesItemsProvider = FutureProvider.autoDispose
    .family<List<SeriesItem>, String?>(
      (ref, categoryId) async {
        final items = await ref.watch(
          seriesItemsSourceProvider(categoryId).future,
        );
        final parental = ref.watch(parentalProvider);
        if (parental.unlocked) return items;
        final hidden = await hiddenCategoryIdsOf(
          ref,
          parental,
          ContentKind.series,
          seriesCategoriesAllProvider,
        );
        if (categoryId != null && hidden.contains(categoryId)) return const [];
        return [
          for (final s in items)
            if (!s.adult && !hidden.contains(s.categoryId)) s,
        ];
      },
      dependencies: [
        seriesItemsSourceProvider,
        seriesCategoriesAllProvider,
        parentalProvider,
      ],
    );

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
final recentMoviesProvider = FutureProvider<List<VodItem>>(
  (ref) async {
    final profileId = ref.watch(sessionContextProvider).profileId;
    ref.watch(catalogSyncProvider.select((s) => s.info[ContentKind.movie]));
    final hidden = await ref.watch(hiddenContentProvider.future);
    final entries = await ref
        .watch(catalogCacheProvider)
        .recentlyAdded(
          profileId,
          ContentKind.movie,
          limit: recentlyAddedLimit,
          hidden: hidden,
        );
    return [for (final e in entries) e.toMovie()];
  },
  dependencies: [
    sessionContextProvider,
    catalogSyncProvider,
    hiddenContentProvider,
  ],
);

/// Series recién agregadas o con episodios nuevos (catálogo local).
final recentSeriesProvider = FutureProvider<List<SeriesItem>>(
  (ref) async {
    final profileId = ref.watch(sessionContextProvider).profileId;
    ref.watch(catalogSyncProvider.select((s) => s.info[ContentKind.series]));
    final hidden = await ref.watch(hiddenContentProvider.future);
    final entries = await ref
        .watch(catalogCacheProvider)
        .recentlyAdded(
          profileId,
          ContentKind.series,
          limit: recentlyAddedLimit,
          hidden: hidden,
        );
    return [for (final e in entries) e.toSeries()];
  },
  dependencies: [
    sessionContextProvider,
    catalogSyncProvider,
    hiddenContentProvider,
  ],
);
