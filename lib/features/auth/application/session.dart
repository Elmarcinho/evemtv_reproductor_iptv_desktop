import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/logging/redactor.dart';
import '../../../data/providers.dart';
import '../../../domain/entities/account_info.dart';
import '../../../domain/entities/profile.dart';
import '../../../domain/entities/source_credentials.dart';
import '../../../domain/repositories/content_source.dart';

/// Sesión activa: perfil elegido y sus credenciales (solo en memoria).
class Session {
  const Session({
    required this.profile,
    required this.credentials,
    this.initialAccountInfo,
  });

  final Profile profile;
  final SourceCredentials credentials;

  /// Datos de cuenta obtenidos al validar el login, para no repetir la
  /// petición al entrar al inicio.
  final AccountInfo? initialAccountInfo;
}

/// Marca de la época en que empezó una operación asíncrona.
///
/// Mecanismo común para descartar resultados obsoletos: toda operación que
/// dependa de la sesión o de un perfil toma un [SessionToken] al empezar y,
/// después de cada `await`, comprueba [SessionController.isCurrent] antes de
/// aplicar su resultado. La época cambia al abrir o terminar una sesión y al
/// eliminar un perfil, así que cualquier resultado pendiente de "antes" queda
/// invalidado de una sola vez.
extension type const SessionToken._(int epoch) {}

/// Sesión activa, o `null` si no hay ninguna.
///
/// Al iniciar una sesión se registran sus credenciales en el redactor de
/// logs; al terminarla se olvidan.
class SessionController extends Notifier<Session?> {
  int _epoch = 0;

  @override
  Session? build() => null;

  /// Token de la época actual, para operaciones que empiezan ahora.
  SessionToken get token => SessionToken._(_epoch);

  /// `true` si no hubo cambios de sesión ni eliminaciones desde [token].
  bool isCurrent(SessionToken token) => token.epoch == _epoch;

  /// Invalida todas las operaciones pendientes sin tocar la sesión (p. ej.
  /// al empezar a eliminar un perfil).
  void invalidatePending() => _epoch++;

  void start(Session session) {
    _epoch++;
    Redactor.clearSecrets();
    session.credentials.secrets.forEach(Redactor.registerSecret);
    state = session;
  }

  void end() {
    _epoch++;
    Redactor.clearSecrets();
    state = null;
  }
}

final sessionProvider = NotifierProvider<SessionController, Session?>(
  SessionController.new,
);

/// Fuente de contenido de la sesión activa.
final contentSourceProvider = Provider<ContentSource?>((ref) {
  final session = ref.watch(sessionProvider);
  if (session == null) return null;
  return ref.watch(contentSourceFactoryProvider).create(session.credentials);
});
