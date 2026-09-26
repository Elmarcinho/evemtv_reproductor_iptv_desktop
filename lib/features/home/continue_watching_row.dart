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
/// perfil activo (una tarjeta por serie, hasta 10). Un clic retoma donde
/// quedó. Si no entran todas, flechas ‹ › para desplazar la fila.
class ContinueWatchingRow extends ConsumerStatefulWidget {
  const ContinueWatchingRow({super.key, this.cardWidth = 150});

  /// Ancho de cada tarjeta (el póster es 2:3).
  final double cardWidth;

  /// Título, nombre y dos líneas de estado bajo el póster.
  static const double _titleHeight = 44;
  static const double _captionHeight = 78;

  /// Alto total de la fila (título incluido) para tarjetas de [cardWidth].
  static double heightFor(double cardWidth) =>
      _titleHeight + cardWidth * 3 / 2 + _captionHeight;

  @override
  ConsumerState<ContinueWatchingRow> createState() =>
      _ContinueWatchingRowState();
}

class _ContinueWatchingRowState extends ConsumerState<ContinueWatchingRow> {
  final _scroll = ScrollController();
  bool _canBack = false;
  bool _canForward = false;

  static const double _gap = 16;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_updateArrows);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _updateArrows() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    final back = pos.pixels > 0.5;
    final forward = pos.pixels < pos.maxScrollExtent - 0.5;
    if (back != _canBack || forward != _canForward) {
      setState(() {
        _canBack = back;
        _canForward = forward;
      });
    }
  }

  void _page(int direction) {
    final pos = _scroll.position;
    final step = (pos.viewportDimension - widget.cardWidth).clamp(
      widget.cardWidth + _gap,
      double.infinity,
    );
    _scroll.animateTo(
      (pos.pixels + direction * step).clamp(0.0, pos.maxScrollExtent),
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(continueWatchingProvider);
    if (items.isEmpty) return const SizedBox.shrink();
    // Tras cada cambio de tamaño o de contenido, revisar las flechas.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateArrows();
    });
    final posterHeight = widget.cardWidth * 3 / 2;
    return SizedBox(
      height: ContinueWatchingRow.heightFor(widget.cardWidth),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: ContinueWatchingRow._titleHeight,
            child: Text(
              'Seguir viendo',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          Expanded(
            child: NotificationListener<ScrollMetricsNotification>(
              onNotification: (_) {
                _updateArrows();
                return false;
              },
              child: Stack(
                children: [
                  ListView.separated(
                    controller: _scroll,
                    scrollDirection: Axis.horizontal,
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(width: _gap),
                    itemBuilder: (context, i) => _ProgressCard(
                      progress: items[i],
                      width: widget.cardWidth,
                    ),
                  ),
                  if (_canBack)
                    _Arrow(
                      top: posterHeight / 2 - 22,
                      left: 0,
                      icon: Icons.chevron_left_rounded,
                      tooltip: 'Anteriores',
                      onPressed: () => _page(-1),
                    ),
                  if (_canForward)
                    _Arrow(
                      top: posterHeight / 2 - 22,
                      right: 0,
                      icon: Icons.chevron_right_rounded,
                      tooltip: 'Más',
                      onPressed: () => _page(1),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Arrow extends StatelessWidget {
  const _Arrow({
    required this.top,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.left,
    this.right,
  });

  final double top;
  final double? left;
  final double? right;
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: top,
      left: left,
      right: right,
      child: IconButton.filledTonal(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon),
        style: IconButton.styleFrom(
          minimumSize: const Size(44, 44),
          backgroundColor: AppColors.surfaceHigh.withValues(alpha: 0.92),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
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
  const _ProgressCard({required this.progress, required this.width});

  final WatchProgress progress;
  final double width;

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
      width: widget.width,
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
                            .removeCard(
                              p,
                              ref.read(allWatchProgressProvider).value ??
                                  const [],
                            ),
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
