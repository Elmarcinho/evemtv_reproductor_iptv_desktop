import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../core/config/app_config.dart';
import 'tls_ca_bundle.dart';

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

  /// Propiedades de mpv que se fijan al crear el reproductor.
  ///
  /// - `tls-verify=yes`: mpv trae la verificación de certificados
  ///   DESACTIVADA por defecto. Sin esto, un intermediario con un
  ///   certificado falso recibiría las URLs con credenciales. La validación
  ///   de Dio no cubre las conexiones de mpv.
  /// - User-Agent propio y neutral; cortes detectados en 15 s.
  static Map<String, String> mpvProperties({String? caFile}) => {
    'tls-verify': 'yes',
    'tls-ca-file': ?caFile,
    'user-agent': AppConfig.userAgent,
    'network-timeout': '15',
  };

  /// Certificados raíz para mpv, si la plataforma los necesita (ver
  /// [TlsCaBundle]). Se prepara una vez, al crear el primer reproductor.
  static String? caFile;

  static Future<MediaKitEngine> create() async {
    caFile ??= await TlsCaBundle.ensure();
    final player = Player(
      configuration: const PlayerConfiguration(
        title: AppConfig.appName,
        // Solo errores: los mensajes de mpv incluyen URLs con credenciales.
        logLevel: MPVLogLevel.error,
      ),
    );
    final platform = player.platform;
    if (platform is! NativePlayer) {
      await player.dispose();
      throw StateError('Plataforma no soportada');
    }
    for (final entry in mpvProperties(caFile: caFile).entries) {
      await platform.setProperty(entry.key, entry.value);
    }
    // Comprobación: si mpv no aceptó la verificación TLS, no se reproduce.
    final verify = await platform.getProperty('tls-verify');
    if (verify != 'yes') {
      await player.dispose();
      throw StateError('mpv no activó la verificación TLS');
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

  /// Abre [url] SIN `player.open`: media_kit 1.2.6 escribe la lista de
  /// reproducción (con la URL completa, credenciales incluidas) en un
  /// archivo temporal y lo borra 5 s después. Aquí la URL va directo a mpv
  /// como argumento de `loadfile`, sin tocar el disco. `stop()` y `play()`
  /// mantienen el estado interno de media_kit igual que `open`.
  @override
  Future<void> open(Uri url) async {
    await player.stop();
    await (player.platform! as NativePlayer).command([
      'loadfile',
      url.toString(),
      'replace',
    ]);
    await player.play();
  }

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
