import 'dart:ui';

/// Constantes generales de la app. No contiene servidores, listas ni
/// credenciales: la app es un reproductor vacío.
abstract final class AppConfig {
  static const String appName = 'EvemTv';

  /// Repositorio público donde se publican las versiones (aviso de
  /// actualización, Fase 5).
  static const String githubRepo = 'Elmarcinho/evemtv_reproductor_iptv_desktop';

  static const Size initialWindowSize = Size(1280, 800);
  static const Size minWindowSize = Size(960, 600);
}
