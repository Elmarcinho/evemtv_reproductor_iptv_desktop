import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/logging/redactor.dart';
import '../../../domain/entities/account_info.dart';
import '../../../domain/entities/profile.dart';
import '../../../domain/entities/source_credentials.dart';

export 'session_scope.dart';

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
/// Solo para lo que ocurre **fuera** de una sesión (abrir un perfil desde el
/// selector): lo que pasa dentro de una sesión vive en su contenedor
/// ([SessionScope]) y se descarta al destruirlo. La época cambia al abrir o
/// terminar una sesión y al eliminar un perfil, así que una apertura
/// pendiente de "antes" queda invalidada.
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
