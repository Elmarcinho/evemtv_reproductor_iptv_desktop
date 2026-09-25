import '../entities/watch_progress.dart';

/// "Seguir viendo" por perfil.
abstract interface class WatchProgressRepository {
  /// Los más recientes primero.
  Stream<List<WatchProgress>> watchRecent(int profileId, {int limit = 20});

  Future<WatchProgress?> get(int profileId, ProgressKind kind, String itemId);

  Future<void> save(int profileId, WatchProgress progress);

  Future<void> remove(int profileId, ProgressKind kind, String itemId);
}
