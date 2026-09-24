import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/errors/app_failure.dart';
import '../../core/logging/app_logger.dart';
import 'playback_engine.dart';
import 'stream_probe.dart';

enum VodPlaybackStatus { connecting, playing, reconnecting, completed, failed }

/// Esperas entre reintentos de una película o episodio: 2, 4 y 8 s.
const List<Duration> vodReconnectDelays = [
  Duration(seconds: 2),
  Duration(seconds: 4),
  Duration(seconds: 8),
];

/// Reproducción de películas y episodios.
///
/// A diferencia del vivo, un corte no debe hacer perder lo que se vio: al
/// reconectar, se vuelve a la última posición conocida. Un "fin" que llega
/// lejos del final real ([cutTolerance]) se trata como corte, no como fin.
///
/// Los mensajes de error de mpv no siempre son fatales (p. ej. "Could not
/// open codec" cuando falla la decodificación por hardware y sigue por
/// software). Por eso un error solo provoca reconexión si durante
/// [errorGrace] el video no avanza. Si el archivo no llega a abrirse, se
/// consulta el código HTTP ([probe]): un 4xx significa que no existe en el
/// servidor y se informa enseguida, sin reintentos inútiles.
class VodPlaybackController extends ChangeNotifier {
  VodPlaybackController({
    required this.engine,
    this.probe,
    this.stallTimeout = const Duration(seconds: 30),
    this.cutTolerance = const Duration(seconds: 60),
    this.errorGrace = const Duration(seconds: 3),
  }) {
    _subscriptions.addAll([
      engine.playing.listen((playing) {
        _isPlaying = playing;
        _onPlaying(playing);
      }),
      engine.buffering.listen(_onBuffering),
      engine.position.listen((p) {
        if (p > Duration.zero) {
          _position = p;
          _markOpened();
        }
      }),
      engine.duration.listen((d) {
        // Al reabrir, media_kit emite duración 0: se ignora. La posición
        // pendiente se aplica solo con la duración válida de la apertura
        // actual (con la anterior, el salto se perdía antes de cargar).
        if (d <= Duration.zero) return;
        _duration = d;
        _markOpened();
        _maybeResume();
      }),
      engine.completed.listen((done) {
        if (done) _onCompleted();
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
  final StreamProbe? probe;
  final Duration stallTimeout;
  final Duration cutTolerance;
  final Duration errorGrace;
  Timer? _errorCheck;
  bool _isPlaying = false;

  /// Cambia con cada apertura: las comprobaciones pendientes de una apertura
  /// anterior se descartan.
  int _generation = 0;

  /// El archivo llegó a abrirse desde la última apertura (mpv informó
  /// duración o la posición avanzó). No alcanza con `playing`: media_kit lo
  /// pone en `true` apenas se pide reproducir, antes de abrir el archivo.
  bool _started = false;

  /// Llegó a reproducirse (abierto y en marcha). Solo entonces una pausa es
  /// del usuario.
  bool _hasPlayed = false;

  void _markOpened() {
    if (_started) return;
    _started = true;
    if (_isPlaying) _onPlaying(true);
  }

  final List<StreamSubscription<Object?>> _subscriptions = [];
  Timer? _retryTimer;
  Timer? _stallTimer;

  Uri? _url;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  /// Posición a la que volver cuando el stream esté listo (reanudar o
  /// reconectar).
  Duration? _pendingSeek;
  int _attempt = 0;
  bool _disposed = false;

  VodPlaybackStatus _status = VodPlaybackStatus.connecting;
  AppFailure? _failure;

  VodPlaybackStatus get status => _status;
  int get attempt => _attempt;
  int get maxAttempts => vodReconnectDelays.length;
  Duration get position => _position;
  Duration get duration => _duration;
  AppFailure? get failure => _failure;

  static const String unavailableMessage =
      'No se pudo reproducir el contenido. Puede no estar disponible en este '
      'momento.';

  /// Mensaje fijo para el estado `failed`.
  String get failureMessage => _failure is ContentUnavailableFailure
      ? _failure!.message
      : unavailableMessage;

  /// Abre [url] desde el inicio o desde [resumeAt].
  Future<void> open(Uri url, {Duration? resumeAt}) async {
    _url = url;
    _attempt = 0;
    _position = Duration.zero;
    _duration = Duration.zero;
    _failure = null;
    _pendingSeek = (resumeAt != null && resumeAt > Duration.zero)
        ? resumeAt
        : null;
    await _play();
  }

  Future<void> retry() {
    _attempt = 0;
    _failure = null;
    _pendingSeek ??= _position > Duration.zero ? _position : null;
    return _play();
  }

  Future<void> _play() async {
    final url = _url;
    if (_disposed || url == null) return;
    _cancelTimers();
    final generation = ++_generation;
    _started = false;
    _hasPlayed = false;
    // Duración de la apertura anterior: no sirve para esta.
    _duration = Duration.zero;
    _setStatus(
      _attempt == 0
          ? VodPlaybackStatus.connecting
          : VodPlaybackStatus.reconnecting,
    );
    AppLogger.event('player.open', {'kind': 'vod', 'attempt': _attempt});
    try {
      await engine.open(url);
    } on Object catch (e) {
      // Fallo tardío de una apertura anterior (p. ej. el episodio que ya se
      // cambió): no debe reconectar el contenido actual.
      if (generation != _generation) return;
      AppLogger.w('No se pudo abrir el video', e);
      _reconnect('open');
    }
  }

  /// La posición solo se puede fijar cuando el motor ya conoce la duración.
  void _maybeResume() {
    final target = _pendingSeek;
    if (target == null || _duration <= Duration.zero) return;
    _pendingSeek = null;
    // Si la posición guardada está pegada al final, se empieza de nuevo.
    if (target < _duration - const Duration(seconds: 5)) {
      unawaited(engine.seek(target));
      _position = target;
    }
  }

  void _onPlaying(bool playing) {
    if (!playing || !_started || _status == VodPlaybackStatus.failed) return;
    _hasPlayed = true;
    _stallTimer?.cancel();
    _setStatus(VodPlaybackStatus.playing);
  }

  /// Error de mpv: se espera [errorGrace] y solo se actúa si el video no
  /// avanzó (y no está en pausa por el usuario).
  void _onEngineError() {
    if (_disposed || _status == VodPlaybackStatus.failed) return;
    if (_errorCheck?.isActive ?? false) return;
    final generation = _generation;
    final before = _position;
    _errorCheck = Timer(errorGrace, () {
      if (generation != _generation || _disposed) return;
      final progressed = _position > before;
      final pausedByUser = _hasPlayed && !_isPlaying;
      if (progressed || pausedByUser) {
        AppLogger.event('player.error_ignored', {'kind': 'vod'});
        return;
      }
      unawaited(_onFatalError());
    });
  }

  Future<void> _onFatalError() async {
    // No llegó a abrirse: ¿existe en el servidor?
    final url = _url;
    if (!_started && _attempt == 0 && probe != null && url != null) {
      final generation = _generation;
      final status = await probe!(url);
      if (generation != _generation || _disposed) return;
      if (status != null && status >= 400 && status < 500) {
        _cancelTimers();
        _failure = ContentUnavailableFailure(detail: 'HTTP $status');
        AppLogger.e('Contenido no disponible', _failure);
        _setStatus(VodPlaybackStatus.failed);
        return;
      }
    }
    _reconnect('error');
  }

  void _onBuffering(bool buffering) {
    if (_status == VodPlaybackStatus.failed ||
        _status == VodPlaybackStatus.completed) {
      return;
    }
    _stallTimer?.cancel();
    if (buffering) {
      _stallTimer = Timer(stallTimeout, () => _reconnect('stall'));
    }
  }

  void _onCompleted() {
    // "Fin" lejos del final real = el stream se cortó.
    final known = _duration > Duration.zero;
    if (known && _position < _duration - cutTolerance) {
      _reconnect('cut');
      return;
    }
    _cancelTimers();
    _setStatus(VodPlaybackStatus.completed);
  }

  void _reconnect(String reason) {
    if (_disposed || _status == VodPlaybackStatus.failed) return;
    if (_retryTimer?.isActive ?? false) return;
    _cancelTimers();
    if (_attempt >= maxAttempts) {
      _failure = const ServerUnavailableFailure(detail: 'reconexión agotada');
      AppLogger.e('Reproducción fallida', _failure);
      _setStatus(VodPlaybackStatus.failed);
      return;
    }
    final delay = vodReconnectDelays[_attempt];
    _attempt++;
    // Se retoma donde se cortó.
    if (_position > Duration.zero) _pendingSeek = _position;
    AppLogger.event('player.reconnect', {
      'kind': 'vod',
      'reason': reason,
      'attempt': _attempt,
      'of': maxAttempts,
      'delay_s': delay.inSeconds,
    }, LogLevel.warning);
    _setStatus(VodPlaybackStatus.reconnecting);
    _retryTimer = Timer(delay, _play);
  }

  void _setStatus(VodPlaybackStatus status) {
    _status = status;
    if (!_disposed) notifyListeners();
  }

  void _cancelTimers() {
    _retryTimer?.cancel();
    _stallTimer?.cancel();
    _errorCheck?.cancel();
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
