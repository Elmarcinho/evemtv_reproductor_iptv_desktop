import 'package:media_kit/media_kit.dart';

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

  Future<void> open(Uri url);
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
  Future<void> open(Uri url) => player.open(Media(url.toString()));

  @override
  Future<void> dispose() => player.dispose();
}
