import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/live.dart';
import '../../domain/entities/vod.dart';
import '../auth/application/session.dart';

// Películas y series. Viven en el contenedor de la sesión (dependen de
// `contentSourceProvider`): se destruyen con ella y la siguiente sesión
// arranca sin ningún valor de la anterior.

final vodCategoriesProvider = FutureProvider<List<ContentCategory>>((
  ref,
) async {
  final source = ref.watch(contentSourceProvider);
  return source.vodCategories();
}, dependencies: [contentSourceProvider]);

/// Películas de una categoría (`null` = todas), en memoria durante la sesión.
final vodItemsProvider = FutureProvider.family<List<VodItem>, String?>((
  ref,
  categoryId,
) async {
  final source = ref.watch(contentSourceProvider);
  return source.vodItems(categoryId: categoryId);
}, dependencies: [contentSourceProvider]);

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

/// Series de una categoría (`null` = todas), en memoria durante la sesión.
final seriesItemsProvider = FutureProvider.family<List<SeriesItem>, String?>((
  ref,
  categoryId,
) async {
  final source = ref.watch(contentSourceProvider);
  return source.seriesItems(categoryId: categoryId);
}, dependencies: [contentSourceProvider]);

final seriesDetailProvider = FutureProvider.autoDispose
    .family<SeriesDetail, SeriesItem>((ref, series) async {
      final source = ref.watch(contentSourceProvider);
      return source.seriesDetail(series);
    }, dependencies: [contentSourceProvider]);

/// Id de la categoría fija "Recién agregadas" en Películas y Series.
const String recentlyAddedCategoryId = '__recientes__';

/// Cuántos elementos muestra "Recién agregadas".
const int recentlyAddedLimit = 200;

/// Lo más nuevo primero según la fecha en que el servidor lo agregó. Los
/// que no tienen fecha van después; si ninguno la tiene (listas M3U), se
/// usa el orden inverso de la lista, que suele ir de lo más viejo a lo más
/// nuevo.
List<T> newestFirst<T>(List<T> items, DateTime? Function(T item) addedOf) {
  final reversed = items.reversed.toList();
  final dated = [
    for (final item in reversed)
      if (addedOf(item) != null) item,
  ];
  // sort no es estable: se desempata por la posición en la lista.
  final index = {for (final (i, item) in reversed.indexed) item: i};
  dated.sort((a, b) {
    final byDate = addedOf(b)!.compareTo(addedOf(a)!);
    return byDate != 0 ? byDate : index[a]!.compareTo(index[b]!);
  });
  return [
    ...dated,
    for (final item in reversed)
      if (addedOf(item) == null) item,
  ].take(recentlyAddedLimit).toList();
}

/// Películas recién agregadas (de la lista completa, en memoria).
final recentMoviesProvider = FutureProvider<List<VodItem>>(
  (ref) async => newestFirst(
    await ref.watch(vodItemsProvider(null).future),
    (m) => m.added,
  ),
  dependencies: [vodItemsProvider],
);

/// Series recién agregadas o con episodios nuevos (de la lista completa).
final recentSeriesProvider = FutureProvider<List<SeriesItem>>(
  (ref) async => newestFirst(
    await ref.watch(seriesItemsProvider(null).future),
    (s) => s.added,
  ),
  dependencies: [seriesItemsProvider],
);
