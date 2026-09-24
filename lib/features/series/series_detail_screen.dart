import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/date_format.dart';
import '../../core/widgets/state_views.dart';
import '../../domain/entities/favorite.dart';
import '../../domain/entities/vod.dart';
import '../catalog/catalog_providers.dart';
import '../catalog/detail_layout.dart';
import '../favorites/favorite_button.dart';
import '../favorites/favorites.dart';
import '../player/vod_player_screen.dart';

/// Ficha de una serie con selector de temporada y lista de episodios.
class SeriesDetailScreen extends ConsumerStatefulWidget {
  const SeriesDetailScreen({super.key, required this.series});

  final SeriesItem series;

  @override
  ConsumerState<SeriesDetailScreen> createState() => _SeriesDetailScreenState();
}

class _SeriesDetailScreenState extends ConsumerState<SeriesDetailScreen> {
  int? _seasonNumber;

  void _play(SeriesDetail detail, Episode episode) {
    // Lista plana en orden para poder pasar al siguiente episodio, incluso
    // de una temporada a la otra.
    final all = [for (final s in detail.seasons) ...s.episodes];
    final index = all.indexOf(episode);
    if (index < 0) return;
    context.push(
      AppRoutes.vodPlayer,
      extra: EpisodePlayable(
        series: widget.series,
        episodes: all,
        index: index,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(seriesDetailProvider(widget.series));
    final data = detail.value;
    final series = widget.series;

    final seasons = data?.seasons ?? const <Season>[];
    final season = seasons.isEmpty
        ? null
        : seasons.firstWhere(
            (s) => s.number == _seasonNumber,
            orElse: () => seasons.first,
          );

    return DetailLayout(
      title: series.name,
      posterUrl: series.posterUrl,
      backdropUrl: data?.backdropUrl,
      icon: Icons.video_library_outlined,
      loading: detail.isLoading,
      meta: [
        if (series.year != null) '${series.year}',
        if (seasons.isNotEmpty)
          seasons.length == 1 ? '1 temporada' : '${seasons.length} temporadas',
        if (data?.genre != null) data!.genre!,
        if (series.rating != null) '★ ${series.rating!.toStringAsFixed(1)}',
      ],
      plot: data?.plot,
      credits: [
        if (data?.director != null) ('Dirección', data!.director!),
        if (data?.cast != null) ('Reparto', data!.cast!),
      ],
      actions: [
        if (data != null && season != null && season.episodes.isNotEmpty)
          FilledButton.icon(
            autofocus: true,
            onPressed: () => _play(data, seasons.first.episodes.first),
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Ver desde el principio'),
          ),
        FavoriteButton(
          isFavorite: ref
              .watch(favoriteIdsProvider(FavoriteKind.series))
              .contains(series.id),
          onPressed: () =>
              ref.read(favoritesServiceProvider).toggleSeries(series),
        ),
      ],
      below: detail.hasError
          ? SliverToBoxAdapter(
              child: ErrorView(
                error: detail.error!,
                onRetry: () =>
                    ref.invalidate(seriesDetailProvider(widget.series)),
              ),
            )
          : data == null
          ? const SliverToBoxAdapter(child: SizedBox.shrink())
          : season == null
          ? const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(48),
                child: Text(
                  'Esta serie no tiene episodios disponibles.',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            )
          : SliverPadding(
              padding: const EdgeInsets.fromLTRB(48, 0, 48, 48),
              sliver: SliverMainAxisGroup(
                slivers: [
                  SliverToBoxAdapter(
                    child: _SeasonSelector(
                      seasons: seasons,
                      selected: season,
                      onSelect: (s) => setState(() => _seasonNumber = s.number),
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 12)),
                  SliverList.separated(
                    itemCount: season.episodes.length,
                    separatorBuilder: (_, _) => const Divider(),
                    itemBuilder: (context, i) => _EpisodeTile(
                      episode: season.episodes[i],
                      onPlay: () => _play(data, season.episodes[i]),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _SeasonSelector extends StatelessWidget {
  const _SeasonSelector({
    required this.seasons,
    required this.selected,
    required this.onSelect,
  });

  final List<Season> seasons;
  final Season selected;
  final ValueChanged<Season> onSelect;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final s in seasons)
          ChoiceChip(
            label: Text('${s.label} (${s.episodes.length})'),
            selected: s.number == selected.number,
            onSelected: (_) => onSelect(s),
          ),
      ],
    );
  }
}

class _EpisodeTile extends StatelessWidget {
  const _EpisodeTile({required this.episode, required this.onPlay});

  final Episode episode;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return InkWell(
      onTap: onPlay,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 44,
              child: Text(
                '${episode.number}',
                style: text.titleMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            if (episode.imageUrl != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.network(
                  episode.imageUrl!,
                  width: 160,
                  height: 90,
                  fit: BoxFit.cover,
                  cacheWidth: 320,
                  errorBuilder: (_, _, _) => const SizedBox(width: 160),
                ),
              ),
              const SizedBox(width: 16),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(episode.title, style: text.titleSmall),
                  if (episode.duration != null)
                    Text(
                      DateFormatEs.runtime(episode.duration!),
                      style: text.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  if (episode.plot != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      episode.plot!,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Icon(Icons.play_circle_outline_rounded),
          ],
        ),
      ),
    );
  }
}
