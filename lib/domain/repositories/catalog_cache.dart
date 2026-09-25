import '../entities/catalog.dart';
import '../entities/live.dart';

/// Catálogo guardado en la base local, por perfil.
abstract interface class CatalogCache {
  /// Reemplaza todo el catálogo de un tipo (categorías, elementos e índice
  /// de búsqueda) en una sola transacción.
  Future<void> replace(
    int profileId,
    ContentKind kind,
    List<ContentCategory> categories,
    List<CatalogEntry> items,
  );

  Future<CatalogSyncInfo?> syncInfo(int profileId, ContentKind kind);

  /// Búsqueda por nombre (sin tildes, por prefijo de cada palabra).
  Future<SearchResults> search(
    int profileId,
    String query, {
    int limitPerKind = 30,
  });

  /// Nombre de cada categoría de un tipo, para mostrar en los resultados.
  Future<Map<String, String>> categoryNames(int profileId, ContentKind kind);
}
