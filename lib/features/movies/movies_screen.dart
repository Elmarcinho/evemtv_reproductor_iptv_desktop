import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../domain/entities/favorite.dart';
import '../../domain/entities/vod.dart';
import '../catalog/catalog_providers.dart';
import '../catalog/catalog_screen.dart';
import '../favorites/favorites.dart';

class MoviesScreen extends StatelessWidget {
  const MoviesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return CatalogScreen<VodItem>(
      title: 'Películas',
      allLabel: 'Todas las películas',
      filterHint: 'Filtrar películas de esta categoría',
      emptyMessage: 'Esta categoría no tiene películas.',
      categoriesProvider: vodCategoriesProvider,
      itemsProvider: vodItemsProvider.call,
      view: (m) => CatalogItemView(
        name: m.name,
        posterUrl: m.posterUrl,
        rating: m.rating,
        year: m.year,
      ),
      onOpen: (context, movie) =>
          context.push(AppRoutes.movieDetail, extra: movie),
      favoriteKind: FavoriteKind.movie,
      fromFavorite: (f) => f.toMovie(),
      resolvedFavoritesProvider: resolvedMovieFavoritesProvider,
      idOf: (m) => m.id,
      favoritesEmptyMessage:
          'Todavía no tienes películas favoritas.\n'
          'Márcalas con ★ en la ficha de la película.',
    );
  }
}
