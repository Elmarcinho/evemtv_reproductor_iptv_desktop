/// Preferencias no sensibles de la app (términos aceptados, ajustes).
abstract interface class SettingsRepository {
  Future<String?> get(String key);

  Future<void> set(String key, String value);
}

/// Claves de preferencias conocidas.
abstract final class SettingsKeys {
  static const String acceptedTermsVersion = 'accepted_terms_version';
}
