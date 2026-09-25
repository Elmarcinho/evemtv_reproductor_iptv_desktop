import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/errors/app_failure.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/date_format.dart';
import '../../core/widgets/keyboard_help.dart';
import '../../core/widgets/state_views.dart';
import '../../data/providers.dart';
import '../../domain/entities/live.dart';
import '../../domain/entities/vod.dart';
import '../../domain/entities/watch_progress.dart';
import '../../domain/repositories/content_source.dart';
import '../auth/application/session.dart';
import 'media_engine_provider.dart';
import 'playback_engine.dart';
import 'stream_probe.dart';
import 'vod_playback_controller.dart';
import 'watch_progress.dart';
import 'widgets/player_bar.dart';

/// Qué reproducir: una película o un episodio (con la lista de episodios
/// para pasar al siguiente).
sealed class VodPlayable implements ProgressTarget {
  const VodPlayable({this.startOver = false});

  /// Empezar desde el principio aunque haya una posición guardada.
  @override
  final bool startOver;

  String get title;
  String? get subtitle;
  PlaybackCandidates candidates(ContentSource source);

  /// Clave de "seguir viendo".
  @override
  ({ProgressKind kind, String id}) get progressKey;

  /// Registro de "seguir viendo" en [position] (sin URLs).
  @override
  WatchProgress progressAt(Duration position, Duration duration);
}

class MoviePlayable extends VodPlayable {
  const MoviePlayable(this.movie, {super.startOver});

  final VodItem movie;

  @override
  String get title => movie.name;

  @override
  String? get subtitle => movie.year?.toString();

  @override
  PlaybackCandidates candidates(ContentSource source) =>
      source.movieStream(movie);

  @override
  ProgressTarget? get nextTarget => null;

  @override
  ({ProgressKind kind, String id}) get progressKey =>
      (kind: ProgressKind.movie, id: movie.id);

  @override
  WatchProgress progressAt(Duration position, Duration duration) =>
      WatchProgressService.forMovie(
        movie,
        position: position,
        duration: duration,
      );
}

class EpisodePlayable extends VodPlayable {
  const EpisodePlayable({
    required this.series,
    required this.episodes,
    required this.index,
    super.startOver,
  });

  final SeriesItem series;

  /// Todos los episodios en orden (temporada, número), para "siguiente".
  final List<Episode> episodes;
  final int index;

  Episode get episode => episodes[index];

  EpisodePlayable? get next => index + 1 < episodes.length
      ? EpisodePlayable(series: series, episodes: episodes, index: index + 1)
      : null;

  @override
  String get title => series.name;

  @override
  String? get subtitle =>
      'T${episode.season} · E${episode.number} · ${episode.title}';

  @override
  PlaybackCandidates candidates(ContentSource source) =>
      source.episodeStream(episode);

  @override
  ProgressTarget? get nextTarget => next;

  @override
  ({ProgressKind kind, String id}) get progressKey =>
      (kind: ProgressKind.episode, id: episode.id);

  @override
  WatchProgress progressAt(Duration position, Duration duration) =>
      WatchProgressService.forEpisode(
        series,
        episode,
        position: position,
        duration: duration,
      );
}

/// Reproductor de películas y episodios con barra de progreso.
///
/// Teclado: Espacio pausa, F pantalla completa, Esc sale de pantalla
/// completa o vuelve, ←/→ retrocede/adelanta 10 s, ↑/↓ volumen,
/// M silencio, N siguiente episodio.
class VodPlayerScreen extends ConsumerStatefulWidget {
  const VodPlayerScreen({super.key, required this.playable});

  final VodPlayable playable;

  @override
  ConsumerState<VodPlayerScreen> createState() => _VodPlayerScreenState();
}

class _VodPlayerScreenState extends ConsumerState<VodPlayerScreen> {
  MediaKitEngine? _engine;
  VideoController? _video;
  VodPlaybackController? _playback;
  Object? _startError;
  late VodPlayable _current = widget.playable;

  bool _overlayVisible = true;
  bool _fullscreen = false;
  Timer? _hideTimer;

  /// Cuenta regresiva para el siguiente episodio (segundos restantes).
  int? _nextCountdown;
  Timer? _countdownTimer;
  static const int _nextEpisodeDelay = 10;

  final FocusNode _focus = FocusNode(debugLabel: 'reproductor-vod');

  /// "Seguir viendo": se guarda cada [_saveEvery], al cambiar de episodio y
  /// al salir. El servicio se toma al iniciar para poder usarlo en dispose.
  late final VodProgressTracker _progress = VodProgressTracker(
    ref.read(watchProgressServiceProvider),
  );
  Timer? _saveTimer;
  static const Duration _saveEvery = Duration(seconds: 10);

  /// Posición desde la que se reanudó (para el aviso "Desde el principio").
  Duration? _resumedAt;
  Timer? _resumedTimer;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    try {
      // Lanza PlayerUnavailableFailure si libmpv no está disponible.
      ref.read(mediaEngineProvider).ensureReady();
      final engine = await MediaKitEngine.create();
      if (!mounted) {
        await engine.dispose();
        return;
      }
      final playback = VodPlaybackController(
        engine: engine,
        probe: httpStreamProbe(ref.read(dioProvider)),
      )..addListener(_onPlaybackChanged);
      setState(() {
        _engine = engine;
        _video = createVideoController(engine.player);
        _playback = playback;
      });
      await _openCurrent();
      _bumpOverlay();
    } on Object catch (e) {
      if (mounted) setState(() => _startError = e);
    }
  }

  Future<void> _openCurrent() async {
    final source = ref.read(contentSourceProvider);
    final playback = _playback;
    if (playback == null) return;
    try {
      final url = _current.candidates(source).urls.first;
      final resumeAt = await _resumePosition(_current);
      if (!mounted) return;
      await playback.open(url, resumeAt: resumeAt);
      _showResumed(resumeAt);
      _saveTimer?.cancel();
      _saveTimer = Timer.periodic(_saveEvery, (_) => _saveProgress());
    } on Object catch (e) {
      if (mounted) setState(() => _startError = e);
    }
  }

  Future<Duration?> _resumePosition(VodPlayable playable) =>
      _progress.resumePosition(playable);

  void _showResumed(Duration? at) {
    _resumedTimer?.cancel();
    setState(() => _resumedAt = at);
    if (at == null) return;
    _resumedTimer = Timer(const Duration(seconds: 8), () {
      if (mounted) setState(() => _resumedAt = null);
    });
  }

  void _startOver() {
    _resumedTimer?.cancel();
    setState(() => _resumedAt = null);
    unawaited(_engine?.player.seek(Duration.zero));
  }

  /// Guarda la posición actual (ver [VodProgressTracker.save]).
  void _saveProgress({bool completed = false}) {
    final playback = _playback;
    if (playback == null) return;
    unawaited(
      _progress.save(
        _current,
        position: playback.position,
        duration: playback.duration,
        completed: completed,
      ),
    );
  }

  void _onPlaybackChanged() {
    final playback = _playback;
    if (playback == null || !mounted) return;
    if (playback.status == VodPlaybackStatus.completed) {
      _saveTimer?.cancel();
      _saveProgress(completed: true);
    }
    if (playback.status == VodPlaybackStatus.completed &&
        _nextEpisode != null &&
        _nextCountdown == null) {
      _startNextCountdown();
    }
    // Al terminar, se muestran los controles.
    if (playback.status == VodPlaybackStatus.completed) _bumpOverlay();
  }

  EpisodePlayable? get _nextEpisode => switch (_current) {
    final EpisodePlayable e => e.next,
    MoviePlayable() => null,
  };

  void _startNextCountdown() {
    setState(() => _nextCountdown = _nextEpisodeDelay);
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      final left = (_nextCountdown ?? 0) - 1;
      if (left <= 0) {
        t.cancel();
        unawaited(_playNext());
      } else {
        setState(() => _nextCountdown = left);
      }
    });
  }

  void _cancelNextCountdown() {
    _countdownTimer?.cancel();
    setState(() => _nextCountdown = null);
  }

  Future<void> _playNext() async {
    final next = _nextEpisode;
    if (next == null) return;
    _countdownTimer?.cancel();
    // Si se salta a mitad del episodio, se guarda dónde quedó.
    if (_playback?.status != VodPlaybackStatus.completed) _saveProgress();
    setState(() {
      _current = next;
      _nextCountdown = null;
    });
    await _openCurrent();
    _bumpOverlay();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _resumedTimer?.cancel();
    if (_playback?.status != VodPlaybackStatus.completed) _saveProgress();
    _hideTimer?.cancel();
    _countdownTimer?.cancel();
    _focus.dispose();
    _playback
      ?..removeListener(_onPlaybackChanged)
      ..dispose();
    unawaited(_engine?.dispose());
    if (_fullscreen) unawaited(windowManager.setFullScreen(false));
    super.dispose();
  }

  void _bumpOverlay() {
    if (!mounted) return;
    setState(() => _overlayVisible = true);
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      final done = _playback?.status == VodPlaybackStatus.completed;
      if (mounted && !done) setState(() => _overlayVisible = false);
    });
  }

  Future<void> _toggleFullscreen() async {
    final next = !_fullscreen;
    await windowManager.setFullScreen(next);
    if (mounted) setState(() => _fullscreen = next);
  }

  Future<void> _escape() async {
    if (_fullscreen) {
      await _toggleFullscreen();
    } else if (mounted) {
      await Navigator.of(context).maybePop();
    }
  }

  void _seekBy(Duration delta) {
    final player = _engine?.player;
    if (player == null) return;
    final target = player.state.position + delta;
    final max = player.state.duration;
    unawaited(
      player.seek(
        target < Duration.zero
            ? Duration.zero
            : (max > Duration.zero && target > max ? max : target),
      ),
    );
    _bumpOverlay();
  }

  void _changeVolume(double delta) {
    final player = _engine?.player;
    if (player == null) return;
    unawaited(
      player.setVolume((player.state.volume + delta).clamp(0.0, 100.0)),
    );
    _bumpOverlay();
  }

  Map<ShortcutActivator, VoidCallback> get _shortcuts => {
    const SingleActivator(LogicalKeyboardKey.space): () {
      unawaited(_engine?.player.playOrPause());
      _bumpOverlay();
    },
    const SingleActivator(LogicalKeyboardKey.keyF): _toggleFullscreen,
    const SingleActivator(LogicalKeyboardKey.escape): _escape,
    const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
        _seekBy(const Duration(seconds: -10)),
    const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
        _seekBy(const Duration(seconds: 10)),
    const SingleActivator(LogicalKeyboardKey.arrowUp): () => _changeVolume(5),
    const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
        _changeVolume(-5),
    const SingleActivator(LogicalKeyboardKey.keyM): () {
      final player = _engine?.player;
      if (player == null) return;
      unawaited(player.setVolume(player.state.volume > 0 ? 0 : 100));
      _bumpOverlay();
    },
    const SingleActivator(LogicalKeyboardKey.keyN): () {
      if (_nextEpisode != null) unawaited(_playNext());
    },
  };

  @override
  Widget build(BuildContext context) {
    if (_startError != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.black),
        body: ErrorView(error: _startError!),
      );
    }
    final playback = _playback;
    final video = _video;
    final engine = _engine;
    if (playback == null || video == null || engine == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: LoadingView(message: 'Conectando…'),
      );
    }
    return Scaffold(
      backgroundColor: Colors.black,
      body: ScreenShortcuts(
        title: 'Reproductor',
        help: ShortcutCatalog.vodPlayer,
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
                    controller: video,
                    // Sin controles de media_kit: se usan los propios.
                    controls: null,
                  ),
                ),
                ListenableBuilder(
                  listenable: playback,
                  builder: (context, _) => _StatusOverlay(
                    playback: playback,
                    nextEpisode: _nextEpisode,
                    countdown: _nextCountdown,
                    onPlayNext: _playNext,
                    onCancelNext: _cancelNextCountdown,
                    onReplay: () => engine.player
                        .seek(Duration.zero)
                        .then((_) => engine.player.play()),
                    onBack: () => Navigator.of(context).maybePop(),
                  ),
                ),
                // Aviso de reanudación, con opción de empezar de nuevo.
                if (_resumedAt != null)
                  Positioned(
                    left: 24,
                    bottom: 120,
                    child: Material(
                      color: const Color(0xE6151B23),
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.history_rounded, size: 20),
                            const SizedBox(width: 10),
                            Text(
                              'Continuando desde '
                              '${DateFormatEs.clock(_resumedAt!)}',
                            ),
                            const SizedBox(width: 12),
                            TextButton(
                              onPressed: _startOver,
                              child: const Text('Desde el principio'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                AnimatedOpacity(
                  opacity: _overlayVisible ? 1 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: IgnorePointer(
                    ignoring: !_overlayVisible,
                    child: _Controls(
                      playable: _current,
                      player: engine.player,
                      fullscreen: _fullscreen,
                      hasNext: _nextEpisode != null,
                      onBack: _escape,
                      onFullscreen: _toggleFullscreen,
                      onNext: _playNext,
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

/// Conectando / reconectando / error / fin (con siguiente episodio).
class _StatusOverlay extends StatelessWidget {
  const _StatusOverlay({
    required this.playback,
    required this.nextEpisode,
    required this.countdown,
    required this.onPlayNext,
    required this.onCancelNext,
    required this.onReplay,
    required this.onBack,
  });

  final VodPlaybackController playback;
  final EpisodePlayable? nextEpisode;
  final int? countdown;
  final VoidCallback onPlayNext;
  final VoidCallback onCancelNext;
  final VoidCallback onReplay;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    switch (playback.status) {
      case VodPlaybackStatus.playing:
        return const SizedBox.shrink();
      case VodPlaybackStatus.connecting:
        return const LoadingView(message: 'Cargando…');
      case VodPlaybackStatus.reconnecting:
        return LoadingView(
          message:
              'Reconectando… (intento ${playback.attempt} de '
              '${playback.maxAttempts})',
        );
      case VodPlaybackStatus.failed:
        return _Card(
          // Ícono según la causa: el archivo no existe en el servidor, o
          // se cortó y no pudo reconectar (típicamente la conexión).
          icon: playback.failure is ContentUnavailableFailure
              ? Icons.videocam_off_rounded
              : Icons.signal_wifi_bad_rounded,
          iconColor: AppColors.error,
          message: playback.failureMessage,
          actions: [
            TextButton(onPressed: onBack, child: const Text('Volver')),
            FilledButton.icon(
              onPressed: playback.retry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Reintentar'),
            ),
          ],
        );
      case VodPlaybackStatus.completed:
        final next = nextEpisode;
        if (next != null && countdown != null) {
          return _Card(
            icon: Icons.skip_next_rounded,
            message:
                'Siguiente: T${next.episode.season} · E${next.episode.number} · '
                '${next.episode.title}\nEmpieza en $countdown s',
            actions: [
              TextButton(
                onPressed: onCancelNext,
                child: const Text('Cancelar'),
              ),
              FilledButton.icon(
                autofocus: true,
                onPressed: onPlayNext,
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Ver ahora'),
              ),
            ],
          );
        }
        return _Card(
          icon: Icons.check_circle_outline_rounded,
          message: 'Terminó la reproducción.',
          actions: [
            TextButton(onPressed: onBack, child: const Text('Volver')),
            FilledButton.icon(
              onPressed: onReplay,
              icon: const Icon(Icons.replay_rounded),
              label: const Text('Ver de nuevo'),
            ),
          ],
        );
    }
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.icon,
    required this.message,
    required this.actions,
    this.iconColor = AppColors.accent,
  });

  final IconData icon;
  final Color iconColor;
  final String message;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black54,
      child: Center(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 40, color: iconColor),
                  const SizedBox(height: 12),
                  Text(message, textAlign: TextAlign.center),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    spacing: 12,
                    children: actions,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.playable,
    required this.player,
    required this.fullscreen,
    required this.hasNext,
    required this.onBack,
    required this.onFullscreen,
    required this.onNext,
  });

  final VodPlayable playable;
  final Player player;
  final bool fullscreen;
  final bool hasNext;
  final VoidCallback onBack;
  final VoidCallback onFullscreen;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      children: [
        DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xCC000000), Color(0x00000000)],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 24, 40),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Volver (Esc)',
                  onPressed: onBack,
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        playable.title,
                        style: text.titleLarge,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (playable.subtitle != null)
                        Text(
                          playable.subtitle!,
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
        DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [Color(0xCC000000), Color(0x00000000)],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 40, 16, 12),
            child: IconButtonTheme(
              data: IconButtonThemeData(style: barButtonStyle),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ProgressBar(player: player),
                  Row(
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
                      if (hasNext)
                        IconButton(
                          tooltip: 'Siguiente episodio (N)',
                          onPressed: onNext,
                          icon: const Icon(Icons.skip_next_rounded),
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
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Barra de progreso con tiempo transcurrido y total. Mientras se arrastra
/// no salta con la posición real; al soltar, busca.
class _ProgressBar extends StatefulWidget {
  const _ProgressBar({required this.player});

  final Player player;

  @override
  State<_ProgressBar> createState() => _ProgressBarState();
}

class _ProgressBarState extends State<_ProgressBar> {
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    final player = widget.player;
    return StreamBuilder<Duration>(
      stream: player.stream.position,
      initialData: player.state.position,
      builder: (context, snap) {
        final duration = player.state.duration;
        final position = snap.data ?? Duration.zero;
        final max = duration.inMilliseconds.toDouble();
        final value = (_dragging ?? position.inMilliseconds.toDouble()).clamp(
          0.0,
          max <= 0 ? 0.0 : max,
        );
        final label = TextStyle(
          color: AppColors.textSecondary,
          fontFeatures: const [FontFeature.tabularFigures()],
        );
        return Row(
          children: [
            SizedBox(
              width: 72,
              child: Text(
                DateFormatEs.clock(Duration(milliseconds: value.round())),
                textAlign: TextAlign.right,
                style: label,
              ),
            ),
            Expanded(
              child: Slider(
                value: value,
                max: max <= 0 ? 1 : max,
                onChanged: max <= 0
                    ? null
                    : (v) => setState(() => _dragging = v),
                onChangeEnd: (v) {
                  setState(() => _dragging = null);
                  unawaited(player.seek(Duration(milliseconds: v.round())));
                },
              ),
            ),
            SizedBox(
              width: 72,
              child: Text(DateFormatEs.clock(duration), style: label),
            ),
          ],
        );
      },
    );
  }
}
