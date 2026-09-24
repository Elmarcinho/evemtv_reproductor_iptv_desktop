import 'package:media_kit/media_kit.dart';

import '../../core/errors/app_failure.dart';
import '../../core/logging/app_logger.dart';

/// Inicialización diferida del motor de video (libmpv vía media_kit).
///
/// No se llama en `main()`: si libmpv falta o está rota, `MediaKit` lanza una
/// excepción y la app entera no arrancaría. Así, login, perfiles y catálogo
/// funcionan igual y el error aparece solo al intentar reproducir.
class MediaEngine {
  MediaEngine({void Function()? initializer})
    : _initializer = initializer ?? MediaKit.ensureInitialized;

  final void Function() _initializer;

  bool _ready = false;
  PlayerUnavailableFailure? _failure;

  bool get isReady => _ready;

  /// Inicializa el motor una sola vez. Lanza [PlayerUnavailableFailure] si
  /// no está disponible; el fallo se recuerda para no reintentar en cada
  /// reproducción (hace falta reiniciar la app tras instalar libmpv).
  void ensureReady() {
    if (_ready) return;
    if (_failure != null) throw _failure!;
    try {
      _initializer();
      _ready = true;
    } catch (error, stack) {
      _failure = PlayerUnavailableFailure(
        detail: 'MediaKit.ensureInitialized',
        cause: error,
      );
      AppLogger.e('No se pudo iniciar el motor de video', _failure, stack);
      throw _failure!;
    }
  }
}
