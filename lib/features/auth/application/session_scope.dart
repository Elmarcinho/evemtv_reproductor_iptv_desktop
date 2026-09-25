import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers.dart';
import '../../../domain/entities/account_info.dart';
import '../../../domain/entities/profile.dart';
import '../../../domain/entities/source_credentials.dart';
import '../../../domain/repositories/content_source.dart';
import 'session.dart';

/// La sesión terminó: la operación que la usaba ya no debe continuar.
class SessionClosedException implements Exception {
  const SessionClosedException();

  @override
  String toString() => 'SessionClosedException';
}

/// Vida de una sesión. Se cierra al destruirse su contenedor (cambio de
/// perfil o cierre de sesión): cancela todas las peticiones hechas con
/// [cancelToken] y hace que [ensureActive] corte las operaciones en curso.
class SessionLifetime {
  final CancelToken cancelToken = CancelToken();
  bool _closed = false;

  bool get isActive => !_closed;

  /// Lanza [SessionClosedException] si la sesión ya terminó. Se llama entre
  /// pasos de una operación larga (p. ej. entre descargar categorías y
  /// elementos) para no iniciar trabajo nuevo con una sesión vieja.
  void ensureActive() {
    if (_closed) throw const SessionClosedException();
  }

  void close() {
    if (_closed) return;
    _closed = true;
    cancelToken.cancel('sesión cerrada');
  }
}

/// Todo lo que una sesión necesita, **fijo** durante su vida. Los servicios
/// de la sesión lo reciben al crearse y no vuelven a consultar el perfil
/// activo: una operación que empezó en el perfil A siempre escribe en A.
class SessionContext {
  const SessionContext({
    required this.profile,
    required this.credentials,
    required this.lifetime,
    this.initialAccountInfo,
  });

  factory SessionContext.fromSession(Session s, SessionLifetime lifetime) =>
      SessionContext(
        profile: s.profile,
        credentials: s.credentials,
        initialAccountInfo: s.initialAccountInfo,
        lifetime: lifetime,
      );

  final Profile profile;
  final SourceCredentials credentials;
  final AccountInfo? initialAccountInfo;
  final SessionLifetime lifetime;

  int get profileId => profile.id;
}

/// Contexto de la sesión actual. Solo existe dentro de [SessionScope]: los
/// providers de la sesión lo declaran en `dependencies`, así Riverpod los
/// crea en el contenedor de la sesión y los destruye con ella.
final sessionContextProvider = Provider<SessionContext>(
  (ref) => throw StateError('Se usó un dato de sesión fuera de SessionScope'),
  dependencies: const [],
);

/// Fuente de contenido de la sesión. Todas sus peticiones llevan el token
/// de la sesión: al cerrarse, las que están en curso se cancelan y las
/// nuevas fallan al instante.
final contentSourceProvider = Provider<ContentSource>((ref) {
  final ctx = ref.watch(sessionContextProvider);
  final source = ref
      .watch(contentSourceFactoryProvider)
      .create(ctx.credentials, cancelToken: ctx.lifetime.cancelToken);
  ref.onDispose(source.dispose);
  return source;
}, dependencies: [sessionContextProvider]);

/// Crea un contenedor de Riverpod NUEVO por cada sesión.
///
/// Al cambiar de perfil o cerrar sesión, el contenedor anterior se destruye
/// entero: se ejecutan los `onDispose` de todos los providers de la sesión
/// (descargas, temporizadores, reproductor, cachés) y la sesión nueva
/// arranca vacía, sin ver ningún valor de la anterior.
class SessionScope extends ConsumerStatefulWidget {
  const SessionScope({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<SessionScope> createState() => _SessionScopeState();
}

class _SessionScopeState extends ConsumerState<SessionScope> {
  Session? _session;
  SessionContext? _context;

  /// Contexto de [session]; si cambió, cierra el anterior y crea otro.
  SessionContext? _contextFor(Session? session) {
    if (identical(session, _session)) return _context;
    _context?.lifetime.close();
    _session = session;
    _context = session == null
        ? null
        : SessionContext.fromSession(session, SessionLifetime());
    return _context;
  }

  @override
  void dispose() {
    _context?.lifetime.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctx = _contextFor(ref.watch(sessionProvider));
    // Sin sesión (p. ej. durante la transición al cerrar sesión) no se
    // construye ninguna pantalla que necesite una.
    if (ctx == null) return const SizedBox.shrink();
    return ProviderScope(
      // Clave por sesión: otra sesión = otro contenedor.
      key: ObjectKey(ctx),
      overrides: [sessionContextProvider.overrideWithValue(ctx)],
      child: widget.child,
    );
  }
}
