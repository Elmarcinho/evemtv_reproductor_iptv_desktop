import '../entities/catalog.dart';

/// Datos guardados del control parental de un perfil.
class ParentalRecord {
  const ParentalRecord({
    this.pinHash,
    this.blocked = const {},
    this.failedAttempts = 0,
    this.lockedUntil,
  });

  /// Hash con sal del PIN; `null` = PIN por defecto (`0000`).
  final String? pinHash;

  /// Categorías bloqueadas a mano por el usuario.
  final Set<BlockedCategory> blocked;

  /// Intentos fallidos seguidos (PIN o contraseña).
  final int failedAttempts;

  /// Hasta cuándo hay que esperar para otro intento.
  final DateTime? lockedUntil;

  ParentalRecord copyWith({
    String? pinHash,
    bool clearPin = false,
    Set<BlockedCategory>? blocked,
    int? failedAttempts,
    DateTime? lockedUntil,
    bool clearLock = false,
  }) => ParentalRecord(
    pinHash: clearPin ? null : (pinHash ?? this.pinHash),
    blocked: blocked ?? this.blocked,
    failedAttempts: failedAttempts ?? this.failedAttempts,
    lockedUntil: clearLock ? null : (lockedUntil ?? this.lockedUntil),
  );
}

/// Categoría bloqueada a mano: tipo e id.
typedef BlockedCategory = ({ContentKind kind, String id});

/// Control parental por perfil (se borra con el perfil).
abstract interface class ParentalRepository {
  Future<ParentalRecord> read(int profileId);

  Future<void> write(int profileId, ParentalRecord record);
}
