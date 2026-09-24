import '../entities/profile.dart';

/// Perfiles guardados (solo datos no sensibles).
abstract interface class ProfileRepository {
  /// Perfiles ordenados por último uso, los más recientes primero.
  Stream<List<Profile>> watchAll();

  Future<Profile> create({required String name, required SourceType type});

  Future<void> markUsed(int id);

  /// Borra el perfil y todos sus datos locales (catálogo, EPG, favoritos…).
  Future<void> delete(int id);

  /// Cantidad de perfiles, para sugerir nombres por defecto.
  Future<int> count();
}
