import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/date_format.dart';
import '../../core/widgets/category_list.dart';
import '../../core/widgets/state_views.dart';
import '../../domain/entities/favorite.dart';
import '../../domain/entities/live.dart';
import '../favorites/favorite_button.dart';
import '../favorites/favorites.dart';
import '../player/live_player_provider.dart';
import 'live_providers.dart';
import 'widgets/channel_logo.dart';
import 'widgets/mini_player.dart';

/// TV en vivo: categorías | canales | mini reproductor con EPG.
///
/// - Clic en un canal: lo reproduce en el mini reproductor.
/// - Doble clic, Enter o clic sobre el video: pantalla completa.
/// - ↑/↓ (Re Pág/Av Pág de a 10) recorren la lista; al detenerse medio
///   segundo en un canal, se reproduce en el mini reproductor.
/// - Esc vuelve al inicio.
abstract final class LiveScreenAutoplay {
  /// Espera antes de reproducir al recorrer la lista con el teclado: evita
  /// abrir un stream por cada canal que se pasa.
  static const Duration delay = Duration(milliseconds: 600);
}

class LiveScreen extends ConsumerStatefulWidget {
  const LiveScreen({super.key});

  @override
  ConsumerState<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends ConsumerState<LiveScreen> {
  /// `null` = todos los canales.
  String? _categoryId;
  bool _categoryChosen = false;
  int _selected = 0;
  String _filter = '';

  /// Lista visible en el último build, para sincronizar la selección con el
  /// canal que reproduce el reproductor (p. ej. tras cambiar de canal en
  /// pantalla completa).
  List<LiveChannel> _visibleChannels = const [];

  final _listController = ScrollController();
  final _listFocus = FocusNode(debugLabel: 'canales');
  final _filterController = TextEditingController();
  Timer? _autoplay;

  static const double _rowHeight = 64;
  static const double _categoriesWidth = 240;

  @override
  void dispose() {
    _autoplay?.cancel();
    _listController.dispose();
    _listFocus.dispose();
    _filterController.dispose();
    super.dispose();
  }

  void _selectCategory(String? id) {
    setState(() {
      _categoryId = id;
      _categoryChosen = true;
      _selected = 0;
    });
    if (_listController.hasClients) _listController.jumpTo(0);
    _listFocus.requestFocus();
  }

  List<LiveChannel> _visible(List<LiveChannel> channels) {
    final query = _filter.trim().toLowerCase();
    if (query.isEmpty) return channels;
    return [
      for (final c in channels)
        if (c.name.toLowerCase().contains(query)) c,
    ];
  }

  void _moveSelection(int delta, List<LiveChannel> channels) {
    if (channels.isEmpty) return;
    final next = (_selected + delta).clamp(0, channels.length - 1);
    setState(() => _selected = next);
    _ensureVisible(next);
    _autoplay?.cancel();
    _autoplay = Timer(LiveScreenAutoplay.delay, () => _preview(channels, next));
  }

  void _ensureVisible(int index) {
    if (!_listController.hasClients) return;
    final position = _listController.position;
    final top = index * _rowHeight;
    final bottom = top + _rowHeight;
    if (top < position.pixels) {
      _listController.jumpTo(top);
    } else if (bottom > position.pixels + position.viewportDimension) {
      _listController.jumpTo(bottom - position.viewportDimension);
    }
  }

  /// Reproduce en el mini reproductor.
  void _preview(List<LiveChannel> channels, int index) {
    if (channels.isEmpty || !mounted) return;
    unawaited(ref.read(livePlayerProvider.notifier).play(channels, index));
  }

  /// Reproduce y abre la pantalla completa.
  void _expand(List<LiveChannel> channels, int index) {
    if (channels.isEmpty) return;
    _autoplay?.cancel();
    _preview(channels, index);
    context.push(AppRoutes.livePlayer);
  }

  /// Si el reproductor cambió de canal (desde la pantalla completa), la
  /// lista acompaña la selección.
  void _followPlayer(LiveChannel playing) {
    final index = _visibleChannels.indexOf(playing);
    if (index < 0 || index == _selected) return;
    setState(() => _selected = index);
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureVisible(index));
  }

  KeyEventResult _onListKey(KeyEvent event, List<LiveChannel> channels) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      _moveSelection(1, channels);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      _moveSelection(-1, channels);
    } else if (key == LogicalKeyboardKey.pageDown) {
      _moveSelection(10, channels);
    } else if (key == LogicalKeyboardKey.pageUp) {
      _moveSelection(-10, channels);
    } else if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      _expand(channels, _selected);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    // Si el reproductor cambia de canal (desde la pantalla completa), la
    // lista acompaña la selección.
    ref.listen(playingLiveChannelProvider, (_, playing) {
      if (playing != null) _followPlayer(playing);
    });

    final categories = ref.watch(liveCategoriesProvider);
    // Con categorías cargadas y ninguna elegida, se abre la primera para no
    // descargar de entrada la lista completa (puede tener miles de canales).
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
              _Header(
                controller: _filterController,
                onFilter: (v) => setState(() {
                  _filter = v;
                  _selected = 0;
                }),
                onSubmitted: () => _listFocus.requestFocus(),
              ),
              const Divider(),
              Expanded(
                child: categories.when(
                  loading: () =>
                      const LoadingView(message: 'Cargando categorías…'),
                  error: (e, _) => ErrorView(
                    error: e,
                    onRetry: () => ref.invalidate(liveCategoriesProvider),
                  ),
                  data: (list) => LayoutBuilder(
                    builder: (context, constraints) {
                      // El panel del reproductor se lleva la mitad del
                      // espacio que dejan las categorías.
                      final detailWidth =
                          ((constraints.maxWidth - _categoriesWidth) * 0.5)
                              .clamp(380.0, 760.0);
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            width: _categoriesWidth,
                            child: CategoryList(
                              categories: list,
                              selectedId: categoryId,
                              onSelect: _selectCategory,
                              allLabel: 'Todos los canales',
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
                          Expanded(
                            child: _buildChannels(categoryId, detailWidth),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChannels(String? categoryId, double detailWidth) {
    final isFavorites = categoryId == favoritesCategoryId;
    final channels = isFavorites
        ? ref
              .watch(favoritesProvider(FavoriteKind.live))
              .whenData(
                (list) => preferResolved(
                  list,
                  ref.watch(resolvedLiveFavoritesProvider).value,
                  (c) => c.id,
                  (f) => f.toChannel(),
                ),
              )
        : ref.watch(liveChannelsProvider(categoryId));
    return channels.when(
      loading: () => const LoadingView(message: 'Cargando canales…'),
      error: (e, _) => ErrorView(
        error: e,
        onRetry: () => ref.invalidate(liveChannelsProvider(categoryId)),
      ),
      data: (all) {
        final list = _visible(all);
        _visibleChannels = list;
        if (list.isEmpty) {
          return Center(
            child: Text(
              _filter.isEmpty
                  ? (isFavorites
                        ? 'Todavía no tienes canales favoritos.\n'
                              'Márcalos con ★ en el panel del canal.'
                        : 'Esta categoría no tiene canales.')
                  : 'Ningún canal coincide con "$_filter".',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          );
        }
        final selected = _selected.clamp(0, list.length - 1);
        // Canal que suena: marca su fila y es el que muestra el panel.
        final playing = ref.watch(playingLiveChannelProvider);
        return _channelsAndDetail(list, selected, detailWidth, playing);
      },
    );
  }

  Widget _channelsAndDetail(
    List<LiveChannel> list,
    int selected,
    double detailWidth,
    LiveChannel? playing,
  ) {
    final favoriteIds = ref.watch(favoriteIdsProvider(FavoriteKind.live));
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Focus(
            focusNode: _listFocus,
            autofocus: true,
            onKeyEvent: (_, event) => _onListKey(event, list),
            child: ListView.builder(
              controller: _listController,
              itemExtent: _rowHeight,
              itemCount: list.length,
              itemBuilder: (context, i) => _ChannelRow(
                channel: list[i],
                selected: i == selected,
                playing: list[i] == playing,
                isFavorite: favoriteIds.contains(list[i].id),
                onTap: () {
                  _autoplay?.cancel();
                  setState(() => _selected = i);
                  _listFocus.requestFocus();
                  _preview(list, i);
                },
                onDoubleTap: () => _expand(list, i),
              ),
            ),
          ),
        ),
        const VerticalDivider(width: 1),
        SizedBox(
          width: detailWidth,
          // El panel muestra el canal que SE ESTÁ REPRODUCIENDO (no el
          // seleccionado): al cambiar de categoría, la selección pasa a
          // otra lista pero el video sigue con el canal anterior.
          child: _ChannelDetail(
            channel: playing ?? list[selected],
            onExpand: playing != null
                ? () => context.push(AppRoutes.livePlayer)
                : () => _expand(list, selected),
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.controller,
    required this.onFilter,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final ValueChanged<String> onFilter;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 24, 12),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Volver (Esc)',
            onPressed: () => context.go(AppRoutes.home),
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          const SizedBox(width: 8),
          Text('En vivo', style: Theme.of(context).textTheme.headlineSmall),
          const Spacer(),
          SizedBox(
            width: 320,
            child: TextField(
              controller: controller,
              onChanged: onFilter,
              onSubmitted: (_) => onSubmitted(),
              decoration: const InputDecoration(
                isDense: true,
                hintText: 'Filtrar canales de esta categoría',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChannelRow extends ConsumerWidget {
  const _ChannelRow({
    required this.channel,
    required this.selected,
    required this.playing,
    required this.isFavorite,
    required this.onTap,
    required this.onDoubleTap,
  });

  final LiveChannel channel;
  final bool selected;

  /// Es el canal que suena en el reproductor.
  final bool playing;

  /// Está en favoritos.
  final bool isFavorite;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // EPG corta bajo demanda: solo para las filas visibles.
    final epg = ref.watch(shortEpgProvider(channel)).value ?? const [];
    final now = nowAndNext(epg, DateTime.now()).now;
    final text = Theme.of(context).textTheme;
    return Material(
      color: selected
          ? AppColors.accent.withValues(alpha: 0.14)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onDoubleTap: onDoubleTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              SizedBox(
                width: 44,
                child: Text(
                  channel.number?.toString() ?? '',
                  style: text.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              ChannelLogo(url: channel.logoUrl),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      channel.name,
                      style: playing
                          ? text.titleSmall?.copyWith(color: AppColors.accent)
                          : text.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (now != null)
                      Text(
                        now.title,
                        style: text.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              if (isFavorite) const FavoriteBadge(),
              if (playing)
                const Tooltip(
                  message: 'Reproduciendo',
                  child: Icon(
                    Icons.graphic_eq_rounded,
                    size: 20,
                    color: AppColors.accent,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChannelDetail extends ConsumerWidget {
  const _ChannelDetail({required this.channel, required this.onExpand});

  final LiveChannel channel;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final epg = ref.watch(shortEpgProvider(channel));
    final text = Theme.of(context).textTheme;
    final now = DateTime.now();
    final program = nowAndNext(epg.value ?? const [], now);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MiniPlayer(onExpand: onExpand),
          const SizedBox(height: 16),
          Row(
            children: [
              ChannelLogo(url: channel.logoUrl, size: 48),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  channel.name,
                  style: text.titleLarge,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 12),
              FavoriteButton(
                compact: true,
                isFavorite: ref
                    .watch(favoriteIdsProvider(FavoriteKind.live))
                    .contains(channel.id),
                onPressed: () =>
                    ref.read(favoritesServiceProvider).toggleChannel(channel),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: onExpand,
                icon: const Icon(Icons.fullscreen_rounded),
                label: const Text('Pantalla completa'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (epg.isLoading)
            const LinearProgressIndicator()
          else if (program.now == null && program.next == null)
            const Text(
              'Sin información de programación.',
              style: TextStyle(color: AppColors.textSecondary),
            )
          else ...[
            if (program.now != null)
              _ProgramBlock(label: 'Ahora', entry: program.now!, now: now),
            if (program.next != null) ...[
              const SizedBox(height: 20),
              _ProgramBlock(label: 'A continuación', entry: program.next!),
            ],
          ],
        ],
      ),
    );
  }
}

class _ProgramBlock extends StatelessWidget {
  const _ProgramBlock({required this.label, required this.entry, this.now});

  final String label;
  final EpgEntry entry;

  /// Si se indica, se muestra la barra de avance.
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label · ${DateFormatEs.time(entry.start)}–${DateFormatEs.time(entry.end)}',
          style: text.labelMedium?.copyWith(color: AppColors.accent),
        ),
        const SizedBox(height: 6),
        Text(entry.title, style: text.titleSmall),
        if (now != null) ...[
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: entry.progressAt(now!),
            minHeight: 3,
            borderRadius: BorderRadius.circular(2),
          ),
        ],
        if (entry.description != null) ...[
          const SizedBox(height: 8),
          Text(
            entry.description!,
            style: text.bodySmall?.copyWith(color: AppColors.textSecondary),
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }
}
