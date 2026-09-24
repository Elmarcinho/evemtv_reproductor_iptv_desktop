import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/category_list.dart';
import '../../core/widgets/poster.dart';
import '../../core/widgets/state_views.dart';
import '../../domain/entities/favorite.dart';
import '../../domain/entities/live.dart';
import '../favorites/favorite_button.dart';
import '../favorites/favorites.dart';

/// Cómo mostrar un elemento del catálogo en la grilla.
class CatalogItemView {
  const CatalogItemView({
    required this.name,
    this.posterUrl,
    this.rating,
    this.year,
  });

  final String name;
  final String? posterUrl;
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
    required this.filterHint,
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
    this.icon = Icons.movie_outlined,
  });

  final String title;
  final String allLabel;
  final String filterHint;
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
      body: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              context.go(AppRoutes.home),
        },
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 24, 12),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Volver (Esc)',
                      onPressed: () => context.go(AppRoutes.home),
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      widget.title,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const Spacer(),
                    SizedBox(
                      width: 320,
                      child: TextField(
                        controller: _filterController,
                        onChanged: (v) => setState(() => _filter = v),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: widget.filterHint,
                          prefixIcon: const Icon(Icons.search_rounded),
                        ),
                      ),
                    ),
                  ],
                ),
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
                              id: favoritesCategoryId,
                              name: 'Favoritos',
                              icon: Icons.star_rounded,
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
    final provider = widget.itemsProvider(categoryId);
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
        if (list.isEmpty) {
          return Center(
            child: Text(
              _filter.isEmpty
                  ? (isFavorites
                        ? widget.favoritesEmptyMessage
                        : widget.emptyMessage)
                  : 'Nada coincide con "$_filter".',
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
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Poster(
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
              style: text.bodySmall?.copyWith(color: AppColors.textSecondary),
            ),
        ],
      ),
    );
  }
}
