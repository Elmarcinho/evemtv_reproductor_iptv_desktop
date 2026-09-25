import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/category_list.dart';
import '../../core/widgets/keyboard_help.dart';
import '../../core/widgets/state_views.dart';
import '../../domain/entities/favorite.dart';
import '../../domain/entities/live.dart';
import '../favorites/favorite_button.dart';
import '../favorites/favorites.dart';
import '../images/poster.dart';
import '../search/section_header.dart';
import 'catalog_images.dart';
import 'catalog_providers.dart';

/// Cómo mostrar un elemento del catálogo en la grilla.
class CatalogItemView {
  const CatalogItemView({
    required this.name,
    this.posterUrl,
    this.rating,
    this.year,
    this.imageKey,
  });

  final String name;
  final String? posterUrl;

  /// Sin [posterUrl] (p. ej. "Recién agregadas", que sale de la base local
  /// sin URLs): el póster se busca en memoria solo cuando la celda se ve.
  final CatalogImageKey? imageKey;
  final double? rating;
  final int? year;
}

/// Catálogo de películas o series: categorías | grilla de pósters.
///
/// Carga progresiva: primero las categorías; los elementos se piden por
/// categoría (se abre la primera). La grilla es perezosa, así que miles de
/// pósters no traban la interfaz.
class CatalogScreen<T> extends ConsumerStatefulWidget {
  const CatalogScreen({
    super.key,
    required this.title,
    required this.allLabel,
    required this.emptyMessage,
    required this.categoriesProvider,
    required this.itemsProvider,
    required this.view,
    required this.onOpen,
    required this.favoriteKind,
    required this.fromFavorite,
    required this.resolvedFavoritesProvider,
    required this.idOf,
    required this.favoritesEmptyMessage,
    required this.recentProvider,
    this.icon = Icons.movie_outlined,
  });

  /// Categoría fija "Recién agregadas": lo último que agregó el servidor.
  final FutureProvider<List<T>> recentProvider;

  final String title;
  final String allLabel;
  final String emptyMessage;
  final FutureProvider<List<ContentCategory>> categoriesProvider;
  final FutureProvider<List<T>> Function(String? categoryId) itemsProvider;
  final CatalogItemView Function(T item) view;
  final void Function(BuildContext context, T item) onOpen;
  final IconData icon;

  /// Favoritos: categoría fija "Favoritos" y marca ★ en los pósters.
  final FavoriteKind favoriteKind;
  final T Function(Favorite favorite) fromFavorite;

  /// Favoritos completados con el catálogo (imágenes, puntaje).
  final ProviderListenable<AsyncValue<List<T>>> resolvedFavoritesProvider;
  final String Function(T item) idOf;
  final String favoritesEmptyMessage;

  @override
  ConsumerState<CatalogScreen<T>> createState() => _CatalogScreenState<T>();
}

class _CatalogScreenState<T> extends ConsumerState<CatalogScreen<T>> {
  String? _categoryId;
  bool _categoryChosen = false;
  String _filter = '';
  final _filterController = TextEditingController();
  final _gridController = ScrollController();

  @override
  void dispose() {
    _filterController.dispose();
    _gridController.dispose();
    super.dispose();
  }

  void _selectCategory(String? id) {
    setState(() {
      _categoryId = id;
      _categoryChosen = true;
    });
    if (_gridController.hasClients) _gridController.jumpTo(0);
  }

  /// Nombre de la selección actual, para el filtro ("Buscar en …").
  String _scopeLabel(String? categoryId, List<ContentCategory>? categories) {
    if (categoryId == null) return widget.allLabel.toLowerCase();
    if (categoryId == favoritesCategoryId) return 'Favoritos';
    if (categoryId == recentlyAddedCategoryId) return 'Recién agregadas';
    return categories?.where((c) => c.id == categoryId).firstOrNull?.name ??
        'esta categoría';
  }

  List<T> _visible(List<T> items) {
    final query = _filter.trim().toLowerCase();
    if (query.isEmpty) return items;
    return [
      for (final item in items)
        if (widget.view(item).name.toLowerCase().contains(query)) item,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(widget.categoriesProvider);
    final firstCategory = categories.value?.firstOrNull?.id;
    final categoryId = _categoryChosen ? _categoryId : firstCategory;

    return Scaffold(
      body: ScreenShortcuts(
        title: widget.title,
        help: ShortcutCatalog.catalog,
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              context.go(AppRoutes.home),
          const SingleActivator(LogicalKeyboardKey.keyF, control: true): () =>
              context.push(AppRoutes.search),
        },
        child: SafeArea(
          child: Column(
            children: [
              SectionHeader(
                title: widget.title,
                scopeLabel: _scopeLabel(categoryId, categories.value),
                controller: _filterController,
                onFilter: (v) => setState(() => _filter = v),
              ),
              const Divider(),
              Expanded(
                child: categories.when(
                  loading: () =>
                      const LoadingView(message: 'Cargando categorías…'),
                  error: (e, _) => ErrorView(
                    error: e,
                    onRetry: () => ref.invalidate(widget.categoriesProvider),
                  ),
                  data: (list) => Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: 240,
                        child: CategoryList(
                          categories: list,
                          selectedId: categoryId,
                          onSelect: _selectCategory,
                          allLabel: widget.allLabel,
                          pinned: const [
                            (
                              id: recentlyAddedCategoryId,
                              name: 'Recién agregadas',
                              icon: Icons.new_releases_outlined,
                              color: AppColors.accent,
                            ),
                            (
                              id: favoritesCategoryId,
                              name: 'Favoritos',
                              icon: Icons.star_rounded,
                              color: null,
                            ),
                          ],
                        ),
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(child: _buildGrid(categoryId)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGrid(String? categoryId) {
    final isFavorites = categoryId == favoritesCategoryId;
    final provider = categoryId == recentlyAddedCategoryId
        ? widget.recentProvider
        : widget.itemsProvider(categoryId);
    final items = isFavorites
        ? ref
              .watch(favoritesProvider(widget.favoriteKind))
              .whenData(
                (list) => preferResolved(
                  list,
                  ref.watch(widget.resolvedFavoritesProvider).value,
                  widget.idOf,
                  widget.fromFavorite,
                ),
              )
        : ref.watch(provider);
    final favoriteIds = ref.watch(favoriteIdsProvider(widget.favoriteKind));
    return items.when(
      loading: () => const LoadingView(message: 'Cargando…'),
      error: (e, _) =>
          ErrorView(error: e, onRetry: () => ref.invalidate(provider)),
      data: (all) {
        final list = _visible(all);
        if (list.isEmpty && _filter.trim().isNotEmpty) {
          return NoMatchesInScope(
            query: _filter.trim(),
            scopeLabel: _scopeLabel(
              categoryId,
              ref.read(widget.categoriesProvider).value,
            ),
          );
        }
        if (list.isEmpty) {
          return Center(
            child: Text(
              isFavorites ? widget.favoritesEmptyMessage : widget.emptyMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          );
        }
        return GridView.builder(
          controller: _gridController,
          padding: const EdgeInsets.all(20),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 180,
            // Póster 2:3 más dos líneas de texto.
            childAspectRatio: 0.52,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
          ),
          itemCount: list.length,
          itemBuilder: (context, i) => _PosterTile(
            view: widget.view(list[i]),
            icon: widget.icon,
            isFavorite: favoriteIds.contains(widget.idOf(list[i])),
            autofocus: i == 0,
            onTap: () => widget.onOpen(context, list[i]),
          ),
        );
      },
    );
  }
}

class _PosterTile extends StatelessWidget {
  const _PosterTile({
    required this.view,
    required this.icon,
    required this.onTap,
    required this.isFavorite,
    this.autofocus = false,
  });

  final bool isFavorite;
  final CatalogItemView view;
  final IconData icon;
  final VoidCallback onTap;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final meta = [
      if (view.year != null) '${view.year}',
      if (view.rating != null) '★ ${view.rating!.toStringAsFixed(1)}',
    ].join('  ·  ');
    return InkWell(
      autofocus: autofocus,
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // El póster toma lo que deja el texto: la celda nunca desborda,
          // sea cual sea su ancho.
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: view.posterUrl == null && view.imageKey != null
                      ? Consumer(
                          builder: (context, ref, _) => Poster(
                            url: ref
                                .watch(catalogImageProvider(view.imageKey!))
                                .value,
                            title: view.name,
                            icon: icon,
                          ),
                        )
                      : Poster(
                          url: view.posterUrl,
                          title: view.name,
                          icon: icon,
                        ),
                ),
                if (isFavorite)
                  const Positioned(
                    top: 6,
                    right: 6,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      child: Padding(
                        padding: EdgeInsets.all(4),
                        child: FavoriteBadge(),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            view.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: text.bodyMedium,
          ),
          if (meta.isNotEmpty)
            Text(
              meta,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.bodySmall?.copyWith(color: AppColors.textSecondary),
            ),
        ],
      ),
    );
  }
}
