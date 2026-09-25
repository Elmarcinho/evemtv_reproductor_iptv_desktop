import 'package:dio/dio.dart';

/// Token propio de una petición que además se cancela cuando se cancela
/// cualquiera de [parents] (p. ej. el de la sesión y el de la pantalla).
/// Si alguno ya estaba cancelado, nace cancelado.
CancelToken linkedCancelToken(Iterable<CancelToken?> parents) {
  final token = CancelToken();
  for (final parent in parents) {
    if (parent == null) continue;
    if (parent.isCancelled) {
      token.cancel();
      break;
    }
    parent.whenCancel.then((_) {
      if (!token.isCancelled) token.cancel();
    });
  }
  return token;
}
