import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/errors/app_failure.dart';
import '../../core/logging/app_logger.dart';
import '../../domain/entities/live.dart';
import '../../domain/repositories/content_source.dart';
import 'playback_engine.dart';

enum LivePlaybackStatus { connecting, playing, reconnecting, failed }

/// Esperas entre reintentos de reconexión: 1, 2, 4, 8 y 15 s.
const List<Duration> reconnectDelays = [
  Duration(seconds: 1),
  Duration(seconds: 2),
  Duration(seconds: 4),
  Duration(seconds: 8),
  Duration(seconds: 15),
];

/// Reproducción de TV en vivo con reconexión automática.
///
/// - Si el stream da error, termina (un canal en vivo no debería terminar)
///   o se queda cargando más de [stallTimeout], reconecta con espera
///   progresiva y alterna entre las URLs candidatas (`.m3u8` ↔ `.ts`).
/// - Tras [stableAfter] reproduciendo sin cortes, el contador de intentos
///   vuelve a cero.
/// - Tras [reconnectDelays].length intentos seguidos, se rinde y muestra un
///   error con opción de reintentar.
class LivePlaybackController extends ChangeNotifier {
  LivePlaybackController({
    required this.engine,
    required this.source,
    required List<LiveChannel> channels,
    required int initialIndex,
    this._allowedFormats = const [],
    this.stallTimeout = const Duration(seconds: 20),
    this.stableAfter = const Duration(seconds: 30),
  }) : _channels = List.unmodifiable(channels),
       _index = initialIndex.clamp(0, channels.length - 1) {
    _subscriptions.addAll([
      engine.playing.listen(_onPlaying),
      engine.buffering.listen(_onBuffering),
      engine.completed.listen((done) {
        if (done) _reconnect('completed');
      }),
      engine.error.listen((message) {
        // El mensaje de mpv puede incluir la URL: el logger lo reduce al
        // tipo en release y lo redacta en debug.
        AppLogger.w('Error del reproductor', message);
        _reconnect('error');
      }),
    ]);
  }

  final PlaybackEngine engine;
  final ContentSource source;
  List<LiveChannel> _channels;
  List<String> _allowedFormats;
  final Duration stallTimeout;
  final Duration stableAfter;

  final List<StreamSubscription<Object?>> _subscriptions = [];
  Timer? _retryTimer;
  Timer? _stallTimer;
  Timer? _stableTimer;

  int _index;
  List<Uri> _candidates = const [];
  int _candidate = 0;
  int _attempt = 0;
  bool _disposed = false;

  /// Cambia con cada canal abierto: los eventos del motor que llegan tarde
  /// de un canal anterior no deben disparar reconexiones del nuevo.
  int _generation = 0;

  LivePlaybackStatus _status = LivePlaybackStatus.connecting;
  AppFailure? _failure;

  LivePlaybackStatus get status => _status;
  int get attempt => _attempt;
  int get maxAttempts => reconnectDelays.length;
  AppFailure? get failure => _failure;
  int get index => _index;

  /// Lista por la que se navega con canal anterior/siguiente.
  List<LiveChannel> get channels => _channels;
  LiveChannel get channel => _channels[_index];

  /// Abre el canal actual desde cero.
  Future<void> start() => _openChannel(_index);

  /// Reproduce [channels][index] y adopta esa lista para navegar. Si ese
  /// canal ya se está reproduciendo (p. ej. un segundo clic), no lo reabre.
  Future<void> playChannel(
    List<LiveChannel> channels,
    int index, {
    List<String>? allowedFormats,
  }) {
    if (channels.isEmpty) return Future.value();
    final target = channels[index.clamp(0, channels.length - 1)];
    // Se compara con el canal actual ANTES de reemplazar la lista.
    final sameChannel = target == channel;
    _channels = List.unmodifiable(channels);
    if (allowedFormats != null) _allowedFormats = allowedFormats;
    _index = index.clamp(0, channels.length - 1);
    if (sameChannel && _status != LivePlaybackStatus.failed) {
      notifyListeners();
      return Future.value();
    }
    return _openChannel(_index);
  }

  Future<void> nextChannel() => _openChannel((_index + 1) % channels.length);

  Future<void> previousChannel() =>
      _openChannel((_index - 1 + channels.length) % channels.length);

  Future<void> retry() {
    _attempt = 0;
    return _play();
  }

  Future<void> _openChannel(int index) async {
    _index = index;
    _attempt = 0;
    _candidate = 0;
    _failure = null;
    try {
      _candidates = source
          .liveStream(channel, allowedFormats: _allowedFormats)
          .urls;
    } on AppFailure catch (e) {
      _fail(e);
      return;
    }
    await _play();
  }

  Future<void> _play() async {
    if (_disposed) return;
    _cancelTimers();
    final generation = ++_generation;
    _setStatus(
      _attempt == 0
          ? LivePlaybackStatus.connecting
          : LivePlaybackStatus.reconnecting,
    );
    final url = _candidates[_candidate];
    AppLogger.event('player.open', {
      'kind': 'live',
      'channel': channel.id,
      'format': _formatOf(url),
      'attempt': _attempt,
    });
    try {
      await engine.open(url);
    } on Object catch (e) {
      if (generation != _generation) return;
      AppLogger.w('No se pudo abrir el stream', e);
      _reconnect('open');
    }
  }

  void _onPlaying(bool playing) {
    if (!playing || _status == LivePlaybackStatus.failed) return;
    _stallTimer?.cancel();
    _setStatus(LivePlaybackStatus.playing);
    _stableTimer?.cancel();
    _stableTimer = Timer(stableAfter, () => _attempt = 0);
  }

  void _onBuffering(bool buffering) {
    if (_status == LivePlaybackStatus.failed) return;
    _stallTimer?.cancel();
    if (buffering) {
      final generation = _generation;
      _stallTimer = Timer(stallTimeout, () {
        if (generation == _generation) _reconnect('stall');
      });
    }
  }

  void _reconnect(String reason) {
    if (_disposed || _status == LivePlaybackStatus.failed) return;
    // Ya hay una reconexión programada: no se acumulan.
    if (_retryTimer?.isActive ?? false) return;
    _cancelTimers();
    if (_attempt >= maxAttempts) {
      _fail(
        const ServerUnavailableFailure(detail: 'reconexión agotada'),
        message: channelUnavailableMessage,
      );
      return;
    }
    final delay = reconnectDelays[_attempt];
    _attempt++;
    // Alterna formato (m3u8 ↔ ts) en cada intento.
    _candidate = (_candidate + 1) % _candidates.length;
    AppLogger.event('player.reconnect', {
      'reason': reason,
      'attempt': _attempt,
      'of': maxAttempts,
      'delay_s': delay.inSeconds,
    }, LogLevel.warning);
    _setStatus(LivePlaybackStatus.reconnecting);
    _retryTimer = Timer(delay, _play);
  }

  static const String channelUnavailableMessage =
      'No se pudo reproducir el canal. Puede estar caído o no disponible en '
      'este momento.';

  String? _failureMessage;

  /// Mensaje fijo para mostrar cuando [status] es `failed`.
  String? get failureMessage => _failureMessage ?? _failure?.message;

  void _fail(AppFailure failure, {String? message}) {
    _cancelTimers();
    _failure = failure;
    _failureMessage = message;
    AppLogger.e('Reproducción fallida', failure);
    _setStatus(LivePlaybackStatus.failed);
  }

  static String _formatOf(Uri url) {
    final path = url.path;
    final dot = path.lastIndexOf('.');
    return dot < 0 ? 'otro' : path.substring(dot + 1);
  }

  void _setStatus(LivePlaybackStatus status) {
    if (status != LivePlaybackStatus.failed) _failureMessage = null;
    _status = status;
    if (!_disposed) notifyListeners();
  }

  void _cancelTimers() {
    _retryTimer?.cancel();
    _stallTimer?.cancel();
    _stableTimer?.cancel();
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelTimers();
    for (final s in _subscriptions) {
      unawaited(s.cancel());
    }
    super.dispose();
  }
}
