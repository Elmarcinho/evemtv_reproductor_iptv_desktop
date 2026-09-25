import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/text_format.dart';
import '../../domain/entities/live.dart';
import '../../domain/entities/vod.dart';
import '../images/poster.dart';
import 'catalog_providers.dart';

/// Recomendaciones para una ficha: [title] ("Más de Terror") y los
/// elementos, los más relacionados primero.
typedef Related<T> = ({String title, List<T> items});

/// Elige los elementos más relacionados con [item] entre [candidates]
/// (los de su misma categoría). Los paneles no informan géneros ni
/// relaciones en las listas, así que se usa lo que hay:
///
/// 1. Palabras del título en común: agrupa sagas y secuelas ("Resident
///    Evil", "Rápidos y furiosos 3").
/// 2. Año cercano.
/// 3. Puntaje.
///
/// Sin póster no entran (la fila es visual). Nunca incluye a [item].
List<T> relatedTo<T>(
  T item,
  List<T> candidates, {
  required String Function(T) idOf,
  required String Function(T) nameOf,
  required int? Function(T) yearOf,
  required double? Function(T) ratingOf,
  required String? Function(T) posterOf,
  int limit = 20,
}) {
  final words = titleWords(nameOf(item));
  final year = yearOf(item);
  double score(T c) {
    final shared = titleWords(nameOf(c)).intersection(words).length;
    final y = yearOf(c);
    final yearScore = (year == null || y == null)
        ? 0
        : 3 - (y - year).abs().clamp(0, 3);
    return shared * 10 + yearScore + (ratingOf(c) ?? 0) / 10;
  }

  final id = idOf(item);
  final pool = [
    for (final c in candidates)
      if (idOf(c) != id && posterOf(c) != null) (c, score(c)),
  ];
  // sort no es estable: se desempata por el orden original de la lista.
  final order = {for (final (i, p) in pool.indexed) p.$1: i};
  pool.sort((a, b) {
    final byScore = b.$2.compareTo(a.$2);
    return byScore != 0 ? byScore : order[a.$1]!.compareTo(order[b.$1]!);
  });
  return [for (final p in pool.take(limit)) p.$1];
}

/// Palabras significativas de un título: en minúsculas, sin tildes, sin el
/// año ni palabras vacías ("el", "de", "the"…).
Set<String> titleWords(String name) {
  const accents = {
    'á': 'a',
    'é': 'e',
    'í': 'i',
    'ó': 'o',
    'ú': 'u',
    'ü': 'u',
    'ñ': 'n',
  };
  final clean = TextFormat.withoutYear(name)
      .toLowerCase()
      .split('')
      .map((c) => accents[c] ?? c)
      .join();
  return {
    for (final w in clean.split(RegExp(r'[^a-z0-9]+')))
      if (w.length >= 3 && !_stopWords.contains(w) && int.tryParse(w) == null)
        w,
  };
}

const _stopWords = {
  'the',
  'and',
  'los',
  'las',
  'del',
  'una',
  'uno',
  'con',
  'por',
  'para',
  'que',
  'sin',
  'sus',
  'mas',
  'from',
  'with',
  'for',
  'you',
  'your',
  'our',
  'movie',
  'pelicula',
  'serie',
  'temporada',
  'season',
  'latino',
  'castellano',
  'subtitulado',
  'sub',
  'dual',
  'hd',
  'fhd',
  'uhd',
};

String _titleFor(
  List<ContentCategory>? categories,
  String? categoryId,
  String fallback,
) {
  final name = categories?.where((c) => c.id == categoryId).firstOrNull?.name;
  return name == null ? fallback : 'Más de $name';
}

/// Películas relacionadas: de su misma categoría (lista en memoria).
final relatedMoviesProvider = FutureProvider.autoDispose
    .family<Related<VodItem>, VodItem>((ref, movie) async {
      final categoryId = movie.categoryId;
      if (categoryId == null) return (title: '', items: const <VodItem>[]);
      final list = await ref.watch(vodItemsProvider(categoryId).future);
      final categories = ref.watch(vodCategoriesProvider).value;
      return (
        title: _titleFor(categories, categoryId, 'Te puede interesar'),
        items: relatedTo(
          movie,
          list,
          idOf: (m) => m.id,
          nameOf: (m) => m.name,
          yearOf: (m) => m.year,
          ratingOf: (m) => m.rating,
          posterOf: (m) => m.posterUrl,
        ),
      );
    }, dependencies: [vodItemsProvider, vodCategoriesProvider]);

/// Series relacionadas: de su misma categoría (lista en memoria).
final relatedSeriesProvider = FutureProvider.autoDispose
    .family<Related<SeriesItem>, SeriesItem>((ref, series) async {
      final categoryId = series.categoryId;
      if (categoryId == null) return (title: '', items: const <SeriesItem>[]);
      final list = await ref.watch(seriesItemsProvider(categoryId).future);
      final categories = ref.watch(seriesCategoriesProvider).value;
      return (
        title: _titleFor(categories, categoryId, 'Te puede interesar'),
        items: relatedTo(
          series,
          list,
          idOf: (s) => s.id,
          nameOf: (s) => s.name,
          yearOf: (s) => s.year,
          ratingOf: (s) => s.rating,
          posterOf: (s) => s.posterUrl,
        ),
      );
    }, dependencies: [seriesItemsProvider, seriesCategoriesProvider]);

/// Fila de recomendaciones al pie de una ficha. No aparece si no hay nada
/// que recomendar o si falla (es opcional).
class RelatedRow<T> extends StatelessWidget {
  const RelatedRow({
    super.key,
    required this.related,
    required this.nameOf,
    required this.posterOf,
    required this.yearOf,
    required this.onOpen,
    required this.icon,
  });

  final AsyncValue<Related<T>> related;
  final String Function(T) nameOf;
  final String? Function(T) posterOf;
  final int? Function(T) yearOf;
  final void Function(BuildContext context, T item) onOpen;
  final IconData icon;

  static const double tileWidth = 150;

  @override
  Widget build(BuildContext context) {
    final data = related.value;
    if (data == null || data.items.isEmpty) return const SizedBox.shrink();
    final text = Theme.of(context).textTheme;
    return Padding(
      // Separada de la ficha: es otra sección.
      padding: const EdgeInsets.fromLTRB(48, 40, 48, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(data.title, style: text.titleLarge),
          const SizedBox(height: 12),
          SizedBox(
            height: tileWidth * 1.5 + 52,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: data.items.length,
              separatorBuilder: (_, _) => const SizedBox(width: 16),
              itemBuilder: (context, i) {
                final item = data.items[i];
                final year = yearOf(item);
                return SizedBox(
                  width: tileWidth,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => onOpen(context, item),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Poster(
                            url: posterOf(item),
                            title: nameOf(item),
                            width: tileWidth,
                            icon: icon,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          TextFormat.displayName(nameOf(item)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodyMedium,
                        ),
                        if (year != null)
                          Text(
                            '$year',
                            style: text.bodySmall?.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Fila de películas relacionadas para la ficha de [movie].
class RelatedMovies extends ConsumerWidget {
  const RelatedMovies({super.key, required this.movie});

  final VodItem movie;

  @override
  Widget build(BuildContext context, WidgetRef ref) => RelatedRow<VodItem>(
    related: ref.watch(relatedMoviesProvider(movie)),
    nameOf: (m) => m.name,
    posterOf: (m) => m.posterUrl,
    yearOf: (m) => m.year,
    icon: Icons.movie_outlined,
    onOpen: (context, m) => context.push(AppRoutes.movieDetail, extra: m),
  );
}

/// Fila de series relacionadas para la ficha de [series].
class RelatedSeries extends ConsumerWidget {
  const RelatedSeries({super.key, required this.series});

  final SeriesItem series;

  @override
  Widget build(BuildContext context, WidgetRef ref) => RelatedRow<SeriesItem>(
    related: ref.watch(relatedSeriesProvider(series)),
    nameOf: (s) => s.name,
    posterOf: (s) => s.posterUrl,
    yearOf: (s) => s.year,
    icon: Icons.video_library_outlined,
    onOpen: (context, s) => context.push(AppRoutes.seriesDetail, extra: s),
  );
}
