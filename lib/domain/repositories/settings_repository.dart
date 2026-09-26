/// Preferencias no sensibles de la app (términos aceptados, ajustes).
abstract interface class SettingsRepository {
  Future<String?> get(String key);

  Future<void> set(String key, String value);
}

/// Claves de preferencias conocidas.
abstract final class SettingsKeys {
  static const String acceptedTermsVersion = 'accepted_terms_version';

  /// Id anónimo de esta instalación (UUID v4) para el conteo de uso.
  static const String installId = 'install_id';

  /// Día (UTC, aaaa-mm-dd) del último conteo de uso enviado.
  static const String usagePingDay = 'usage_ping_day';

  /// Día (UTC) del último conteo enviado con `account_hash`. Si el del día
  /// salió sin huella (app abierta sin cuenta), al abrir una cuenta ese
  /// mismo día se envía uno más, con ella.
  static const String usagePingHashDay = 'usage_ping_hash_day';
}
