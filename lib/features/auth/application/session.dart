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

/// Sesión activa, o `null` si no hay ninguna.
///
/// Al iniciar una sesión se registran sus credenciales en el redactor de
/// logs; al terminarla se olvidan.
class SessionController extends Notifier<Session?> {
  @override
  Session? build() => null;

  void start(Session session) {
    Redactor.clearSecrets();
    session.credentials.secrets.forEach(Redactor.registerSecret);
    state = session;
  }

  void end() {
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
