import '../entities/catalog.dart';
import '../entities/live.dart';
import '../parental/adult_content.dart';

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

  // Las consultas reciben [HiddenContent]: lo oculto por el control
  // parental no sale de la base (así los límites se cumplen igual).

  /// Búsqueda por nombre (sin tildes, por prefijo de cada palabra).
  Future<SearchResults> search(
    int profileId,
    String query, {
    int limitPerKind = 30,
    HiddenContent hidden = HiddenContent.none,
  });

  /// Elementos de [kind] de [minYear] en adelante: primero los últimos que
  /// agregó el servidor (fecha de alta) y, sin fecha, los de año más nuevo.
  Future<List<CatalogEntry>> recent(
    int profileId,
    ContentKind kind, {
    required int minYear,
    int limit = 20,
    HiddenContent hidden = HiddenContent.none,
  });

  /// Los últimos [limit] elementos de [kind] que agregó el servidor (fecha
  /// de alta; sin fecha, los últimos de su lista).
  Future<List<CatalogEntry>> recentlyAdded(
    int profileId,
    ContentKind kind, {
    int limit = 50,
    HiddenContent hidden = HiddenContent.none,
  });

  /// Elementos de [kind] con mejor puntaje del servidor (los que no tienen
  /// puntaje no entran). Con [minYear], solo de ese año en adelante.
  Future<List<CatalogEntry>> topRated(
    int profileId,
    ContentKind kind, {
    int limit = 20,
    int? minYear,
    HiddenContent hidden = HiddenContent.none,
  });

  /// Nombre de cada categoría de un tipo, para mostrar en los resultados.
  Future<Map<String, String>> categoryNames(int profileId, ContentKind kind);

  /// Categorías guardadas de un tipo (con la marca de adultos del panel).
  Future<List<ContentCategory>> categories(int profileId, ContentKind kind);

  /// Ids de los elementos de [kind] que el panel marcó como de adultos.
  Future<Set<String>> adultItemIds(int profileId, ContentKind kind);

  /// Ids de todos los elementos de [kind] guardados.
  Future<Set<String>> itemIds(int profileId, ContentKind kind);
}
