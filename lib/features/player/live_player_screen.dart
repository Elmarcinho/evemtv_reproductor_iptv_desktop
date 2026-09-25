import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/date_format.dart';
import '../../core/widgets/keyboard_help.dart';
import '../../core/widgets/state_views.dart';
import '../../domain/entities/live.dart';
import '../live/live_providers.dart';
import '../live/widgets/channel_logo.dart';
import 'live_playback_controller.dart';
import 'live_player_provider.dart';
import 'widgets/playback_status_view.dart';
import 'widgets/player_bar.dart';

/// Canales con los que abrir el reproductor.
class LiveStart {
  const LiveStart({required this.channels, this.index = 0});

  final List<LiveChannel> channels;
  final int index;
}

/// Reproductor de TV en vivo a pantalla grande. Usa el mismo reproductor
/// que el mini reproductor de En vivo ([livePlayerProvider]): entrar y salir
/// no corta el stream.
///
/// Teclado: Espacio pausa, F pantalla completa, Esc cierra la lista, sale
/// de pantalla completa o vuelve, ↑/↓ cambian de canal, ←/→ volumen,
/// M silencio, L lista de canales.
class LivePlayerScreen extends ConsumerStatefulWidget {
  const LivePlayerScreen({super.key, this.start});

  /// Canales para empezar a reproducir al abrir (p. ej. desde la búsqueda).
  /// Sin esto, se usa lo que ya suena en el reproductor compartido.
  final LiveStart? start;

  @override
  ConsumerState<LivePlayerScreen> createState() => _LivePlayerScreenState();
}

class _LivePlayerScreenState extends ConsumerState<LivePlayerScreen> {
  bool _overlayVisible = true;
  bool _channelListOpen = false;
  bool _fullscreen = false;
  Timer? _hideTimer;
  final FocusNode _focus = FocusNode(debugLabel: 'reproductor');

  @override
  void initState() {
    super.initState();
    _bumpOverlay();
    final start = widget.start;
    if (start != null) {
      // Después del primer frame: la pantalla ya escucha el proveedor y el
      // reproductor compartido no se libera antes de tiempo.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(
          ref
              .read(livePlayerProvider.notifier)
              .play(start.channels, start.index),
        );
      });
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _focus.dispose();
    if (_fullscreen) unawaited(windowManager.setFullScreen(false));
    super.dispose();
  }

  LivePlayerHandle? get _handle => ref.read(livePlayerProvider).handle;

  void _bumpOverlay() {
    if (!mounted) return;
    setState(() => _overlayVisible = true);
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      // Con la lista de canales abierta, los controles no se ocultan.
      if (mounted && !_channelListOpen) {
        setState(() => _overlayVisible = false);
      }
    });
  }

  Future<void> _toggleFullscreen() async {
    final next = !_fullscreen;
    await windowManager.setFullScreen(next);
    if (mounted) setState(() => _fullscreen = next);
  }

  Future<void> _escape() async {
    if (_channelListOpen) {
      _toggleChannelList();
    } else if (_fullscreen) {
      await _toggleFullscreen();
    } else if (mounted) {
      await Navigator.of(context).maybePop();
    }
  }

  void _toggleChannelList() {
    setState(() => _channelListOpen = !_channelListOpen);
    _bumpOverlay();
    _focus.requestFocus();
  }

  void _changeVolume(double delta) {
    final player = _handle?.engine.player;
    if (player == null) return;
    unawaited(
      player.setVolume((player.state.volume + delta).clamp(0.0, 100.0)),
    );
    _bumpOverlay();
  }

  void _switchChannel(bool next) {
    final playback = _handle?.playback;
    if (playback == null) return;
    unawaited(next ? playback.nextChannel() : playback.previousChannel());
    _bumpOverlay();
  }

  void _playAt(int index) {
    final playback = _handle?.playback;
    if (playback == null) return;
    unawaited(playback.playChannel(playback.channels, index));
    _bumpOverlay();
  }

  Map<ShortcutActivator, VoidCallback> get _shortcuts => {
    const SingleActivator(LogicalKeyboardKey.space): () {
      unawaited(_handle?.engine.player.playOrPause());
      _bumpOverlay();
    },
    const SingleActivator(LogicalKeyboardKey.keyF): _toggleFullscreen,
    const SingleActivator(LogicalKeyboardKey.escape): _escape,
    const SingleActivator(LogicalKeyboardKey.keyL): _toggleChannelList,
    const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
        _switchChannel(false),
    const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
        _switchChannel(true),
    const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
        _changeVolume(-5),
    const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
        _changeVolume(5),
    const SingleActivator(LogicalKeyboardKey.keyM): () {
      final player = _handle?.engine.player;
      if (player == null) return;
      unawaited(player.setVolume(player.state.volume > 0 ? 0 : 100));
      _bumpOverlay();
    },
  };

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(livePlayerProvider);
    final handle = state.handle;
    if (handle == null) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.black),
        body: state.error != null
            ? ErrorView(error: state.error!)
            : const LoadingView(message: 'Conectando…'),
      );
    }
    final playback = handle.playback;
    return Scaffold(
      backgroundColor: Colors.black,
      body: ScreenShortcuts(
        title: 'Reproductor en vivo',
        help: ShortcutCatalog.livePlayer,
        bindings: _shortcuts,
        child: Focus(
          focusNode: _focus,
          autofocus: true,
          child: MouseRegion(
            cursor: _overlayVisible
                ? SystemMouseCursors.basic
                : SystemMouseCursors.none,
            onHover: (_) => _bumpOverlay(),
            child: Stack(
              fit: StackFit.expand,
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _bumpOverlay,
                  onDoubleTap: _toggleFullscreen,
                  child: Video(
                    controller: handle.video,
                    // Sin controles de media_kit: se usan los propios.
                    controls: null,
                  ),
                ),
                PlaybackStatusView(playback: playback),
                AnimatedOpacity(
                  opacity: _overlayVisible ? 1 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: IgnorePointer(
                    ignoring: !_overlayVisible,
                    child: ListenableBuilder(
                      listenable: playback,
                      builder: (context, _) => _Controls(
                        playback: playback,
                        player: handle.engine.player,
                        fullscreen: _fullscreen,
                        channelListOpen: _channelListOpen,
                        onBack: _escape,
                        onFullscreen: _toggleFullscreen,
                        onChannelList: _toggleChannelList,
                      ),
                    ),
                  ),
                ),
                // Clic fuera de la lista: la cierra.
                if (_channelListOpen)
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _toggleChannelList,
                    ),
                  ),
                if (_channelListOpen)
                  Positioned(
                    top: 0,
                    right: 0,
                    bottom: 0,
                    width: _ChannelListPanel.width,
                    child: ListenableBuilder(
                      listenable: playback,
                      builder: (context, _) => _ChannelListPanel(
                        channels: playback.channels,
                        current: playback.index,
                        onSelect: _playAt,
                        onClose: _toggleChannelList,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Controls extends ConsumerWidget {
  const _Controls({
    required this.playback,
    required this.player,
    required this.fullscreen,
    required this.channelListOpen,
    required this.onBack,
    required this.onFullscreen,
    required this.onChannelList,
  });

  final LivePlaybackController playback;
  final Player player;
  final bool fullscreen;
  final bool channelListOpen;
  final VoidCallback onBack;
  final VoidCallback onFullscreen;
  final VoidCallback onChannelList;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final channel = playback.channel;
    final epg = ref.watch(shortEpgProvider(channel)).value ?? const [];
    final now = nowAndNext(epg, DateTime.now()).now;
    final text = Theme.of(context).textTheme;
    // Con la lista abierta, las barras dejan libre su espacio a la derecha.
    final rightInset = channelListOpen ? _ChannelListPanel.width + 16 : 16.0;

    return Column(
      children: [
        // Barra superior: volver, canal y programa actual.
        DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xCC000000), Color(0x00000000)],
            ),
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 16, rightInset, 40),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Volver (Esc)',
                  onPressed: onBack,
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
                const SizedBox(width: 8),
                ChannelLogo(url: channel.logoUrl, size: 44),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        [
                          if (channel.number != null) '${channel.number}',
                          channel.name,
                        ].join('  '),
                        style: text.titleLarge,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (now != null)
                        Text(
                          '${DateFormatEs.time(now.start)}–'
                          '${DateFormatEs.time(now.end)}  ${now.title}',
                          style: text.bodyMedium?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const Spacer(),
        // Barra inferior: pausa, canal, volumen, lista, pistas y pantalla
        // completa.
        DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [Color(0xCC000000), Color(0x00000000)],
            ),
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 40, rightInset, 16),
            // Mismo color y tamaño para todos los íconos, incluido el menú
            // de audio y subtítulos (PopupMenuButton usa otro estilo por
            // defecto).
            child: IconButtonTheme(
              data: IconButtonThemeData(style: barButtonStyle),
              child: Row(
                children: [
                  StreamBuilder<bool>(
                    stream: player.stream.playing,
                    initialData: player.state.playing,
                    builder: (context, snap) => IconButton(
                      tooltip: 'Pausa (Espacio)',
                      onPressed: player.playOrPause,
                      icon: Icon(
                        snap.data == true
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                      ),
                    ),
                  ),
                  VolumeControl(player: player),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Lista de canales (L)',
                    // Resaltado mientras la lista está abierta.
                    style: channelListOpen
                        ? IconButton.styleFrom(
                            foregroundColor: AppColors.accent,
                            iconSize: barIconSize,
                          )
                        : null,
                    onPressed: onChannelList,
                    icon: const Icon(Icons.format_list_bulleted_rounded),
                  ),
                  TracksMenu(player: player),
                  IconButton(
                    tooltip: fullscreen
                        ? 'Salir de pantalla completa (F / Esc)'
                        : 'Pantalla completa (F)',
                    onPressed: onFullscreen,
                    icon: Icon(
                      fullscreen
                          ? Icons.fullscreen_exit_rounded
                          : Icons.fullscreen_rounded,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Lista de canales sobre el video: muestra dónde está el canal actual y
/// permite saltar a cualquiera con un clic.
class _ChannelListPanel extends StatefulWidget {
  const _ChannelListPanel({
    required this.channels,
    required this.current,
    required this.onSelect,
    required this.onClose,
  });

  static const double width = 360;

  final List<LiveChannel> channels;
  final int current;
  final ValueChanged<int> onSelect;
  final VoidCallback onClose;

  @override
  State<_ChannelListPanel> createState() => _ChannelListPanelState();
}

class _ChannelListPanelState extends State<_ChannelListPanel> {
  static const double _rowHeight = 56;

  // Abre con el canal actual a la vista, algo por debajo del borde superior.
  late final ScrollController _scroll = ScrollController(
    initialScrollOffset: ((widget.current - 3) * _rowHeight).clamp(
      0,
      double.infinity,
    ),
  );

  @override
  void didUpdateWidget(_ChannelListPanel old) {
    super.didUpdateWidget(old);
    if (old.current != widget.current) _ensureVisible(widget.current);
  }

  void _ensureVisible(int index) {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    final top = index * _rowHeight;
    if (top < position.pixels ||
        top + _rowHeight > position.pixels + position.viewportDimension) {
      _scroll.jumpTo(
        (top - position.viewportDimension / 2 + _rowHeight / 2).clamp(
          0,
          position.maxScrollExtent,
        ),
      );
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Material(
      color: const Color(0xEE0D1117),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
            child: Row(
              children: [
                Expanded(child: Text('Canales', style: text.titleMedium)),
                IconButton(
                  tooltip: 'Cerrar (L / Esc)',
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              itemExtent: _rowHeight,
              itemCount: widget.channels.length,
              itemBuilder: (context, i) {
                final channel = widget.channels[i];
                final current = i == widget.current;
                return Material(
                  color: current
                      ? AppColors.accent.withValues(alpha: 0.22)
                      : Colors.transparent,
                  child: InkWell(
                    onTap: () => widget.onSelect(i),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 36,
                            child: Text(
                              channel.number?.toString() ?? '',
                              style: text.bodySmall?.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                          ChannelLogo(url: channel.logoUrl, size: 36),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              channel.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: current
                                  ? text.titleSmall?.copyWith(
                                      color: AppColors.accent,
                                    )
                                  : text.bodyMedium,
                            ),
                          ),
                          if (current)
                            const Icon(
                              Icons.play_arrow_rounded,
                              size: 18,
                              color: AppColors.accent,
                            ),
                        ],
                      ),
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
