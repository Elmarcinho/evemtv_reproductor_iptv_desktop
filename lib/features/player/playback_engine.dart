import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../core/config/app_config.dart';

/// Lo mínimo que el controlador de reproducción necesita del motor. Separado
/// de media_kit para probar la reconexión sin libmpv.
abstract interface class PlaybackEngine {
  Stream<bool> get playing;
  Stream<bool> get buffering;
  Stream<bool> get completed;

  /// Mensajes de error del motor. Pueden incluir la URL (con credenciales):
  /// nunca se muestran y solo se registran a través del logger.
  Stream<String> get error;

  /// Posición y duración (VOD). En vivo la duración suele ser cero.
  Stream<Duration> get position;
  Stream<Duration> get duration;

  Future<void> open(Uri url);
  Future<void> seek(Duration position);
  Future<void> dispose();
}

/// Motor real: media_kit (mpv).
class MediaKitEngine implements PlaybackEngine {
  MediaKitEngine._(this.player);

  final Player player;

  static Future<MediaKitEngine> create() async {
    final player = Player(
      configuration: const PlayerConfiguration(
        title: AppConfig.appName,
        // Solo errores: los mensajes de mpv incluyen URLs con credenciales.
        logLevel: MPVLogLevel.error,
      ),
    );
    final platform = player.platform;
    if (platform is NativePlayer) {
      // User-Agent propio y neutral, y cortes detectados en 15 s.
      await platform.setProperty('user-agent', AppConfig.userAgent);
      await platform.setProperty('network-timeout', '15');
    }
    return MediaKitEngine._(player);
  }

  @override
  Stream<bool> get playing => player.stream.playing;

  @override
  Stream<bool> get buffering => player.stream.buffering;

  @override
  Stream<bool> get completed => player.stream.completed;

  @override
  Stream<String> get error => player.stream.error;

  @override
  Stream<Duration> get position => player.stream.position;

  @override
  Stream<Duration> get duration => player.stream.duration;

  @override
  Future<void> open(Uri url) => player.open(Media(url.toString()));

  @override
  Future<void> seek(Duration position) => player.seek(position);

  @override
  Future<void> dispose() => player.dispose();
}

/// Salida de video. `hwdec: auto-safe` (recomendado por mpv): solo prueba
/// la decodificación por hardware que mpv considera estable y, si no hay,
/// sigue por software. Con `auto` (el valor por defecto de media_kit)
/// intenta todas, lo que genera avisos como "Could not open codec" en
/// equipos sin el controlador correspondiente.
VideoController createVideoController(Player player) => VideoController(
  player,
  configuration: const VideoControllerConfiguration(hwdec: 'auto-safe'),
);
