import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../domain/entities/live.dart';
import '../auth/application/session.dart';
import '../home/account_info_controller.dart';
import 'live_playback_controller.dart';
import 'media_engine_provider.dart';
import 'playback_engine.dart';

/// Reproductor de TV en vivo compartido entre el mini reproductor de la
/// pantalla En vivo y la pantalla completa: pasar de uno a otro no corta
/// ni reconecta el stream.
class LivePlayerHandle {
  const LivePlayerHandle({
    required this.engine,
    required this.video,
    required this.playback,
  });

  final MediaKitEngine engine;
  final VideoController video;
  final LivePlaybackController playback;

  Future<void> dispose() async {
    playback.dispose();
    await engine.dispose();
  }
}

class LivePlayerState {
  const LivePlayerState({this.handle, this.error});

  /// `null` hasta que se reproduce el primer canal.
  final LivePlayerHandle? handle;

  /// Error al crear el reproductor (p. ej. libmpv no disponible).
  final Object? error;
}

/// Se crea al reproducir el primer canal y se libera al salir de En vivo
/// (autoDispose) o al cambiar de sesión.
class LivePlayerNotifier extends Notifier<LivePlayerState> {
  Future<LivePlayerHandle>? _creating;

  @override
  LivePlayerState build() {
    ref.watch(sessionProvider);
    ref.onDispose(() {
      final creating = _creating;
      _creating = null;
      if (creating != null) {
        unawaited(creating.then((h) => h.dispose(), onError: (_) {}));
      }
    });
    return const LivePlayerState();
  }

  /// Reproduce [channels][index] en el reproductor compartido.
  Future<void> play(List<LiveChannel> channels, int index) async {
    if (channels.isEmpty) return;
    final formats =
        ref.read(accountInfoProvider).value?.allowedOutputFormats ??
        const <String>[];
    try {
      final existing = state.handle;
      if (existing != null) {
        await existing.playback.playChannel(
          channels,
          index,
          allowedFormats: formats,
        );
        return;
      }
      final handle = await (_creating ??= _create(channels, index, formats));
      if (!ref.mounted) return;
      if (state.handle == null) {
        state = LivePlayerState(handle: handle);
        await handle.playback.start();
      } else {
        await handle.playback.playChannel(
          channels,
          index,
          allowedFormats: formats,
        );
      }
    } on Object catch (e) {
      _creating = null;
      if (ref.mounted) state = LivePlayerState(error: e);
    }
  }

  Future<LivePlayerHandle> _create(
    List<LiveChannel> channels,
    int index,
    List<String> formats,
  ) async {
    // Lanza PlayerUnavailableFailure si libmpv no está disponible.
    ref.read(mediaEngineProvider).ensureReady();
    final source = ref.read(contentSourceProvider);
    if (source == null) throw StateError('sin sesión');
    final engine = await MediaKitEngine.create();
    return LivePlayerHandle(
      engine: engine,
      video: createVideoController(engine.player),
      playback: LivePlaybackController(
        engine: engine,
        source: source,
        channels: channels,
        initialIndex: index,
        allowedFormats: formats,
      ),
    );
  }
}

final livePlayerProvider =
    NotifierProvider.autoDispose<LivePlayerNotifier, LivePlayerState>(
      LivePlayerNotifier.new,
    );

/// Canal que suena en el reproductor compartido, o `null` si todavía no se
/// reprodujo nada. Se actualiza al cambiar de canal (también desde la
/// pantalla completa).
class PlayingChannelNotifier extends Notifier<LiveChannel?> {
  @override
  LiveChannel? build() {
    final playback = ref.watch(livePlayerProvider).handle?.playback;
    if (playback == null) return null;
    void update() => state = playback.channel;
    playback.addListener(update);
    ref.onDispose(() => playback.removeListener(update));
    return playback.channel;
  }
}

final playingLiveChannelProvider =
    NotifierProvider.autoDispose<PlayingChannelNotifier, LiveChannel?>(
      PlayingChannelNotifier.new,
    );
