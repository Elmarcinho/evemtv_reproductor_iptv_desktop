import '../entities/source_credentials.dart';

/// Almacén de credenciales por perfil. La implementación usa el almacén
/// seguro del sistema; nunca archivos planos ni la base de datos.
abstract interface class CredentialStore {
  /// Lanza `StorageFailure` si el llavero no está disponible.
  Future<SourceCredentials?> read(int profileId);

  Future<void> write(int profileId, SourceCredentials credentials);

  Future<void> delete(int profileId);
}
