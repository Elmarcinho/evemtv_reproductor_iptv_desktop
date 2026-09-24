/// Errores de la app.
///
/// Reglas:
/// - [message] es siempre un texto **fijo** en español, definido en este
///   archivo. Nunca incluye URLs, datos ingresados ni texto del servidor.
/// - [detail] es un resumen técnico corto que arma nuestro código (p. ej.
///   `"HTTP 401"` o `"connectionTimeout"`), solo para el logger, que lo
///   redacta. Nunca un cuerpo de respuesta ni una excepción completa.
/// - [cause] conserva el error original para depurar en memoria, pero ni
///   [toString] ni el logger lo imprimen: solo su tipo.
sealed class AppFailure implements Exception {
  const AppFailure(this.message, {this.detail, this.cause});

  final String message;
  final String? detail;
  final Object? cause;

  /// Descripción para el logger (se redacta igualmente al registrarse).
  String get logDescription {
    final parts = <String>[
      '$runtimeType',
      ?detail,
      if (cause != null) 'causa: ${cause.runtimeType}',
    ];
    return parts.join(' | ');
  }

  @override
  String toString() => logDescription;
}

class NoConnectionFailure extends AppFailure {
  const NoConnectionFailure({super.detail, super.cause})
    : super('Sin conexión a internet. Revisa tu red e intenta de nuevo.');
}

class ServerUnavailableFailure extends AppFailure {
  const ServerUnavailableFailure({super.detail, super.cause})
    : super(
        'El servidor no responde. Puede estar caído o la URL es incorrecta.',
      );
}

class TimeoutFailure extends AppFailure {
  const TimeoutFailure({super.detail, super.cause})
    : super('El servidor tardó demasiado en responder.');
}

class InvalidCredentialsFailure extends AppFailure {
  const InvalidCredentialsFailure({super.detail, super.cause})
    : super('Usuario o contraseña incorrectos.');
}

class AccountExpiredFailure extends AppFailure {
  const AccountExpiredFailure({super.detail, super.cause})
    : super('La cuenta está vencida o inactiva.');
}

enum InvalidUrlReason {
  empty('Ingresa la URL del servidor.'),
  containsSpaces('La URL no puede contener espacios.'),
  unsupportedScheme('La URL debe empezar con http:// o https://.'),
  malformed('La URL no tiene un formato válido.'),
  embeddedCredentials(
    'No incluyas usuario ni contraseña en la URL: usa los campos de abajo.',
  );

  const InvalidUrlReason(this.message);
  final String message;
}

class InvalidUrlFailure extends AppFailure {
  InvalidUrlFailure(this.reason) : super(reason.message, detail: reason.name);

  final InvalidUrlReason reason;
}

class CertificateFailure extends AppFailure {
  const CertificateFailure({super.detail, super.cause})
    : super(
        'El certificado de seguridad del servidor no es válido. '
        'Prueba con http:// si tu proveedor no usa HTTPS.',
      );
}

class ResourceNotFoundFailure extends AppFailure {
  const ResourceNotFoundFailure({super.detail, super.cause})
    : super('No se encontró nada en esa dirección. Revisa la URL.');
}

class InvalidPlaylistFailure extends AppFailure {
  const InvalidPlaylistFailure({super.detail, super.cause})
    : super('La URL no devolvió una lista M3U válida.');
}

class InvalidResponseFailure extends AppFailure {
  const InvalidResponseFailure({super.detail, super.cause})
    : super(
        'El servidor devolvió una respuesta no reconocida. '
        'Verifica que sea un servidor compatible con Xtream Codes.',
      );
}

enum StorageFailureKind {
  keyringUnavailable(
    'No se encontró un llavero del sistema para guardar las credenciales. '
    'En Linux instala y activa GNOME Keyring o KWallet.',
  ),
  readWrite('No se pudieron leer o guardar los datos locales.');

  const StorageFailureKind(this.message);
  final String message;
}

class StorageFailure extends AppFailure {
  StorageFailure(this.kind, {super.cause})
    : super(kind.message, detail: kind.name);

  final StorageFailureKind kind;
}

class PlayerUnavailableFailure extends AppFailure {
  const PlayerUnavailableFailure({super.detail, super.cause})
    : super(
        'El motor de video no está disponible. En Linux instala libmpv '
        '(paquete libmpv2) y vuelve a abrir la app.',
      );
}

class UnknownFailure extends AppFailure {
  const UnknownFailure({super.detail, super.cause})
    : super('Ocurrió un error inesperado.');
}
