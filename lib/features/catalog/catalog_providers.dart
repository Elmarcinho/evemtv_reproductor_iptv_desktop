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
