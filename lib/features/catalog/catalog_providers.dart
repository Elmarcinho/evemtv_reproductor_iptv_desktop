import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/live.dart';
import '../../domain/entities/vod.dart';
import '../auth/application/session.dart';

// Películas y series. Igual que En vivo: dependen de `contentSourceProvider`,
// así que al cambiar de sesión se recalculan y los resultados tardíos de la
// sesión anterior se descartan.

final vodCategoriesProvider = FutureProvider<List<ContentCategory>>((
  ref,
) async {
  final source = ref.watch(contentSourceProvider);
  if (source == null) return const [];
  return source.vodCategories();
});

/// Películas de una categoría (`null` = todas), en memoria durante la sesión.
final vodItemsProvider = FutureProvider.family<List<VodItem>, String?>((
  ref,
  categoryId,
) async {
  final source = ref.watch(contentSourceProvider);
  if (source == null) return const [];
  return source.vodItems(categoryId: categoryId);
});

final vodDetailProvider = FutureProvider.autoDispose.family<VodDetail, VodItem>(
  (ref, item) async {
    final source = ref.watch(contentSourceProvider);
    if (source == null) return VodDetail(item: item);
    return source.vodDetail(item);
  },
);

final seriesCategoriesProvider = FutureProvider<List<ContentCategory>>((
  ref,
) async {
  final source = ref.watch(contentSourceProvider);
  if (source == null) return const [];
  return source.seriesCategories();
});

/// Series de una categoría (`null` = todas), en memoria durante la sesión.
final seriesItemsProvider = FutureProvider.family<List<SeriesItem>, String?>((
  ref,
  categoryId,
) async {
  final source = ref.watch(contentSourceProvider);
  if (source == null) return const [];
  return source.seriesItems(categoryId: categoryId);
});

final seriesDetailProvider = FutureProvider.autoDispose
    .family<SeriesDetail, SeriesItem>((ref, series) async {
      final source = ref.watch(contentSourceProvider);
      if (source == null) {
        return SeriesDetail(series: series, seasons: const []);
      }
      return source.seriesDetail(series);
    });
