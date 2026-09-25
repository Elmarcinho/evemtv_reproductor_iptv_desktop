import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../domain/entities/favorite.dart';
import '../../domain/entities/vod.dart';
import '../catalog/catalog_providers.dart';
import '../catalog/catalog_screen.dart';
import '../favorites/favorites.dart';

class SeriesScreen extends StatelessWidget {
  const SeriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return CatalogScreen<SeriesItem>(
      title: 'Series',
      allLabel: 'Todas las series',
      emptyMessage: 'Esta categoría no tiene series.',
      icon: Icons.video_library_outlined,
      categoriesProvider: seriesCategoriesProvider,
      itemsProvider: seriesItemsProvider.call,
      view: (s) => CatalogItemView(
        name: s.name,
        posterUrl: s.posterUrl,
        rating: s.rating,
        year: s.year,
      ),
      onOpen: (context, series) =>
          context.push(AppRoutes.seriesDetail, extra: series),
      favoriteKind: FavoriteKind.series,
      fromFavorite: (f) => f.toSeries(),
      resolvedFavoritesProvider: resolvedSeriesFavoritesProvider,
      idOf: (s) => s.id,
      favoritesEmptyMessage:
          'Todavía no tienes series favoritas.\n'
          'Márcalas con ★ en la ficha de la serie.',
    );
  }
}
