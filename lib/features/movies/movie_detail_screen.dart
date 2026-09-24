import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../core/utils/date_format.dart';
import '../../core/widgets/state_views.dart';
import '../../domain/entities/favorite.dart';
import '../../domain/entities/vod.dart';
import '../catalog/catalog_providers.dart';
import '../catalog/detail_layout.dart';
import '../favorites/favorite_button.dart';
import '../favorites/favorites.dart';
import '../player/vod_player_screen.dart';

/// Ficha de una película. Muestra enseguida lo que ya se sabe (póster y
/// nombre) y completa sinopsis, reparto y duración al llegar la ficha.
class MovieDetailScreen extends ConsumerWidget {
  const MovieDetailScreen({super.key, required this.movie});

  final VodItem movie;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(vodDetailProvider(movie));
    final data = detail.value;
    final item = data?.item ?? movie;

    void play() =>
        context.push(AppRoutes.vodPlayer, extra: MoviePlayable(item));

    return DetailLayout(
      title: item.name,
      posterUrl: item.posterUrl,
      backdropUrl: data?.backdropUrl,
      icon: Icons.movie_outlined,
      loading: detail.isLoading,
      meta: [
        if (item.year != null) '${item.year}',
        if (data?.duration != null) DateFormatEs.runtime(data!.duration!),
        if (data?.genre != null) data!.genre!,
        if (item.rating != null) '★ ${item.rating!.toStringAsFixed(1)}',
      ],
      plot: data?.plot,
      credits: [
        if (data?.director != null) ('Dirección', data!.director!),
        if (data?.cast != null) ('Reparto', data!.cast!),
        if (data?.country != null) ('País', data!.country!),
      ],
      actions: [
        FilledButton.icon(
          autofocus: true,
          onPressed: play,
          icon: const Icon(Icons.play_arrow_rounded),
          label: const Text('Reproducir'),
        ),
        FavoriteButton(
          isFavorite: ref
              .watch(favoriteIdsProvider(FavoriteKind.movie))
              .contains(item.id),
          onPressed: () => ref.read(favoritesServiceProvider).toggleMovie(item),
        ),
        // La ficha es informativa: si falla, se puede reproducir igual.
        if (detail.hasError)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              userMessageFor(detail.error!),
              style: const TextStyle(fontSize: 12),
            ),
          ),
      ],
    );
  }
}
