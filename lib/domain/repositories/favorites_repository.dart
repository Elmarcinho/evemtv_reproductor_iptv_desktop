import '../entities/favorite.dart';

/// Favoritos por perfil.
abstract interface class FavoritesRepository {
  /// Favoritos de un tipo, los más recientes primero.
  Stream<List<Favorite>> watch(int profileId, FavoriteKind kind);

  Future<void> add(int profileId, Favorite favorite);

  Future<void> remove(int profileId, FavoriteKind kind, String itemId);
}
