import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/date_format.dart';
import '../../core/widgets/state_views.dart';
import '../../domain/entities/catalog.dart';
import '../../domain/entities/watch_progress.dart';
import '../catalog/catalog_images.dart';
import '../catalog/catalog_providers.dart';
import '../images/poster.dart';
import '../player/vod_player_screen.dart';
import '../player/watch_progress.dart';

/// Fila "Seguir viendo" del inicio: películas y episodios a medio ver del
/// perfil activo. Un clic retoma donde quedó.
class ContinueWatchingRow extends ConsumerWidget {
  const ContinueWatchingRow({super.key});

  static const double cardWidth = 150;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(continueWatchingProvider);
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Seguir viendo', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        SizedBox(
          height: 300,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 16),
            itemBuilder: (context, i) => _ProgressCard(progress: items[i]),
          ),
        ),
      ],
    );
  }
}

/// Retoma un elemento de "Seguir viendo". Para episodios carga la serie,
/// así el reproductor puede pasar al siguiente.
Future<void> resumeProgress(
  BuildContext context,
  WidgetRef ref,
  WatchProgress p,
) async {
  switch (p.kind) {
    case ProgressKind.movie:
      await context.push(
        AppRoutes.vodPlayer,
        extra: MoviePlayable(p.toMovie()),
      );
    case ProgressKind.episode:
      final episode = p.toEpisode();
      var episodes = [episode];
      var index = 0;
      try {
        final detail = await ref.read(
          seriesDetailProvider(p.toSeries()).future,
        );
        final all = [for (final s in detail.seasons) ...s.episodes];
        final found = all.indexOf(episode);
        if (found >= 0) {
          episodes = all;
          index = found;
        }
      } on Object {
        // Sin la ficha de la serie se reproduce solo este episodio.
      }
      if (!context.mounted) return;
      await context.push(
        AppRoutes.vodPlayer,
        extra: EpisodePlayable(
          series: p.toSeries(),
          episodes: episodes,
          index: index,
        ),
      );
  }
}

class _ProgressCard extends ConsumerStatefulWidget {
  const _ProgressCard({required this.progress});

  final WatchProgress progress;

  @override
  ConsumerState<_ProgressCard> createState() => _ProgressCardState();
}

class _ProgressCardState extends ConsumerState<_ProgressCard> {
  bool _opening = false;

  Future<void> _open() async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      await resumeProgress(context, ref, widget.progress);
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(userMessageFor(e))));
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.progress;
    final isEpisode = p.kind == ProgressKind.episode;
    final image = ref
        .watch(
          catalogImageProvider((
            kind: isEpisode ? ContentKind.series : ContentKind.movie,
            categoryId: p.categoryId,
            id: isEpisode ? (p.seriesId ?? '') : p.itemId,
          )),
        )
        .value;
    final text = Theme.of(context).textTheme;
    final remaining = p.duration - p.position;
    final status = p.duration <= Duration.zero
        ? 'Siguiente episodio'
        : 'Quedan ${DateFormatEs.runtime(remaining < const Duration(minutes: 1) ? const Duration(minutes: 1) : remaining)}';

    return SizedBox(
      width: ContinueWatchingRow.cardWidth,
      child: InkWell(
        onTap: _open,
        borderRadius: BorderRadius.circular(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Poster(
                    url: image,
                    title: p.title,
                    icon: isEpisode
                        ? Icons.video_library_outlined
                        : Icons.movie_outlined,
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: LinearProgressIndicator(
                    value: p.fraction,
                    minHeight: 4,
                    backgroundColor: Colors.black54,
                  ),
                ),
                if (_opening)
                  const Positioned.fill(
                    child: ColoredBox(
                      color: Colors.black45,
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  ),
                Positioned(
                  top: 2,
                  right: 2,
                  child: PopupMenuButton<void>(
                    tooltip: 'Opciones',
                    iconColor: Colors.white,
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        onTap: () => ref
                            .read(watchProgressServiceProvider)
                            .remove(p.kind, p.itemId),
                        child: const Text('Quitar de Seguir viendo'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              p.title,
              style: text.bodyMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              p.subtitle ?? status,
              style: text.bodySmall?.copyWith(color: AppColors.textSecondary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (p.subtitle != null)
              Text(
                status,
                style: text.bodySmall?.copyWith(color: AppColors.textSecondary),
              ),
          ],
        ),
      ),
    );
  }
}
