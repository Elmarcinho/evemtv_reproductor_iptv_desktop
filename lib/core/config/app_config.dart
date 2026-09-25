import 'dart:ui';

/// Constantes generales de la app. No contiene servidores, listas ni
/// credenciales: la app es un reproductor vacío.
abstract final class AppConfig {
  static const String appName = 'EvemTv';

  /// Firma del desarrollador (pie de las pantallas principales).
  static const String developer = 'Godebol';

  /// Anuncio propio del desarrollador en el inicio (excepción a la
  /// neutralidad aprobada por el dueño del proyecto; ver CLAUDE.md §8).
  static const String promoTitle = '¿Buscas un servicio de IPTV?';
  static const String promoSubtitle =
      'Fútbol nacional e internacional, últimas películas y series del año.';

  /// Número visible en el anuncio (para quien lo ve en otra pantalla y
  /// quiere anotarlo). Debe coincidir con el de [promoUrl].
  static const String promoPhone = '+591 33217668';

  /// Abre WhatsApp con el mensaje ya escrito ("vi el anuncio en EvemTv"),
  /// así se sabe qué contactos llegaron por la app sin rastrear a nadie.
  static final Uri promoUrl = Uri.parse(
    'https://wa.me/59133217668?text=Hola,%20vi%20el%20anuncio%20en%20EvemTv'
    '%20y%20quiero%20informaci%C3%B3n',
  );

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
