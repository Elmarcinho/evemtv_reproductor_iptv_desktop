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
    this.errorGrace = const Duration(seconds: 3),
  }) : _channels = List.unmodifiable(channels),
       _index = initialIndex.clamp(0, channels.length - 1) {
    _subscriptions.addAll([
      engine.playing.listen((playing) {
        _isPlaying = playing;
        if (!playing) _stableTimer?.cancel();
        _onPlaying(playing);
      }),
      engine.position.listen((p) {
        _position = p;
        if (p > Duration.zero && !_opened) {
          _opened = true;
          if (_isPlaying) _onPlaying(true);
        }
      }),
      engine.buffering.listen(_onBuffering),
      engine.completed.listen((done) {
        if (done) _reconnect('completed');
      }),
      engine.error.listen((message) {
        // El mensaje de mpv puede incluir la URL: el logger lo reduce al
        // tipo en release y lo redacta en debug.
        AppLogger.w('Error del reproductor', message);
        _onEngineError();
      }),
    ]);
  }

  final PlaybackEngine engine;
  final ContentSource source;
  List<LiveChannel> _channels;
  List<String> _allowedFormats;
  final Duration stallTimeout;
  final Duration stableAfter;

  /// Los errores de mpv no siempre son fatales (p. ej. "Could not open
  /// codec" al fallar la decodificación por hardware, que sigue por
  /// software): solo se reconecta si en este lapso el video no avanzó.
  final Duration errorGrace;
  Timer? _errorCheck;
  Duration _position = Duration.zero;
  bool _isPlaying = false;

  /// El stream llegó a abrirse (la posición avanzó). No alcanza con
  /// `playing`: media_kit lo pone en `true` apenas se pide reproducir.
  bool _opened = false;

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
    _opened = false;
    _position = Duration.zero;
    _setStatus(
      _attempt == 0
          ? LivePlaybackStatus.connecting
          : LivePlaybackStatus.reconnecting,
    );
    final url = _candidates[_candidate];
    AppLogger.event('player.open', {
      'kind': 'live',
      'channel': channel.id,
      'format': formatLabel(url),
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
    if (!playing || !_opened || _status == LivePlaybackStatus.failed) return;
    _stallTimer?.cancel();
    _setStatus(LivePlaybackStatus.playing);
    _armStable();
  }

  /// El contador de intentos vuelve a cero solo tras [stableAfter] de
  /// reproducción EFECTIVA y continua: cualquier carga o pausa lo reinicia.
  /// Así, un canal que alterna 15 s bien y 15 s trabado no puede reintentar
  /// indefinidamente.
  void _armStable() {
    _stableTimer?.cancel();
    if (!_isPlaying || _isBuffering || !_opened) return;
    _stableTimer = Timer(stableAfter, () => _attempt = 0);
  }

  bool _isBuffering = false;

  void _onBuffering(bool buffering) {
    _isBuffering = buffering;
    if (_status == LivePlaybackStatus.failed) return;
    _stallTimer?.cancel();
    if (buffering) {
      _stableTimer?.cancel();
      final generation = _generation;
      _stallTimer = Timer(stallTimeout, () {
        if (generation == _generation) _reconnect('stall');
      });
    } else if (_status == LivePlaybackStatus.playing) {
      _armStable();
    }
  }

  void _onEngineError() {
    if (_disposed || _status == LivePlaybackStatus.failed) return;
    if (_errorCheck?.isActive ?? false) return;
    final generation = _generation;
    final before = _position;
    _errorCheck = Timer(errorGrace, () {
      if (generation != _generation || _disposed) return;
      // Avanzó, o está en pausa por el usuario: el error no era fatal.
      final pausedByUser = _status == LivePlaybackStatus.playing && !_isPlaying;
      if (_position > before || pausedByUser) {
        AppLogger.event('player.error_ignored', {'kind': 'live'});
        return;
      }
      _reconnect('error');
    });
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

  /// Formatos que se registran en los logs. Conjunto CERRADO: nada que
  /// venga de la URL (p. ej. `auth.php/usuario/clave`) puede llegar al log.
  static const Set<String> _knownFormats = {
    'm3u8', 'ts', 'mp4', 'mkv', 'avi', 'mov', 'webm', 'flv', 'mpd', //
  };

  /// Formato del stream para el log: la extensión del último segmento si es
  /// uno de [_knownFormats]; si no, `otro`.
  @visibleForTesting
  static String formatLabel(Uri url) {
    final path = url.path;
    final last = path.substring(path.lastIndexOf('/') + 1).toLowerCase();
    final dot = last.lastIndexOf('.');
    final ext = dot < 0 ? '' : last.substring(dot + 1);
    return _knownFormats.contains(ext) ? ext : 'otro';
  }

  void _setStatus(LivePlaybackStatus status) {
    if (status != LivePlaybackStatus.failed) _failureMessage = null;
    _status = status;
    if (!_disposed) notifyListeners();
  }

  void _cancelTimers() {
    _errorCheck?.cancel();
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
