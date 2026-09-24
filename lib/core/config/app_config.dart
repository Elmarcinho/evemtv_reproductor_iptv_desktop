import 'dart:ui';

/// Constantes generales de la app. No contiene servidores, listas ni
/// credenciales: la app es un reproductor vacío.
abstract final class AppConfig {
  static const String appName = 'EvemTv';

  /// Versión mostrada y enviada como User-Agent. Debe coincidir con
  /// `pubspec.yaml` (en la Fase 5 se lee con package_info_plus).
  static const String version = '0.1.0';

  /// User-Agent propio y neutral: no se imita a otros reproductores.
  static const String userAgent = 'EvemTv/$version';

  /// Versión de los términos de uso; si cambia, se vuelven a pedir.
  static const String termsVersion = '1';

  /// Repositorio público donde se publican las versiones (aviso de
  /// actualización, Fase 5).
  static const String githubRepo = 'Elmarcinho/evemtv_reproductor_iptv_desktop';

  static const Size initialWindowSize = Size(1280, 800);
  static const Size minWindowSize = Size(960, 600);
}
