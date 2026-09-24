import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Crea el almacén seguro con las opciones de cada plataforma.
///
/// macOS: se usa el Keychain clásico (`usesDataProtectionKeychain: false`).
/// El Keychain de protección de datos exige el entitlement
/// `keychain-access-groups` con un Team ID, que no existe con firma ad-hoc
/// (sin cuenta de desarrollador) y falla con errSecMissingEntitlement.
FlutterSecureStorage createSecureStorage() => const FlutterSecureStorage(
  mOptions: MacOsOptions(usesDataProtectionKeychain: false),
);
