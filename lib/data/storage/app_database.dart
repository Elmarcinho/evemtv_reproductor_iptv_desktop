import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../../domain/entities/catalog.dart';
import '../../domain/entities/favorite.dart';
import '../../domain/entities/profile.dart';
import '../../domain/entities/watch_progress.dart';

part 'app_database.g.dart';

/// Perfiles: solo id, nombre, tipo y fechas. Sin URLs ni credenciales.
@DataClassName('ProfileRow')
class Profiles extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 60)();
  TextColumn get type => textEnum<SourceType>()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get lastUsedAt => dateTime().nullable()();
}

/// Preferencias no sensibles (clave/valor).
@DataClassName('SettingRow')
class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

/// Favoritos por perfil. Sin ninguna URL (ni de stream ni de imagen).
@DataClassName('FavoriteRow')
class Favorites extends Table {
  IntColumn get profileId =>
      integer().references(Profiles, #id, onDelete: KeyAction.cascade)();
  TextColumn get kind => textEnum<FavoriteKind>()();
  TextColumn get itemId => text()();
  TextColumn get name => text()();
  TextColumn get categoryId => text().nullable()();
  IntColumn get number => integer().nullable()();
  TextColumn get containerExtension => text().nullable()();
  IntColumn get year => integer().nullable()();
  DateTimeColumn get addedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {profileId, kind, itemId};
}

/// Categorías del catálogo por perfil (para la búsqueda y la carga rápida).
@DataClassName('CatalogCategoryRow')
class CatalogCategories extends Table {
  IntColumn get profileId =>
      integer().references(Profiles, #id, onDelete: KeyAction.cascade)();
  TextColumn get kind => textEnum<ContentKind>()();
  TextColumn get categoryId => text()();
  TextColumn get name => text()();
  IntColumn get position => integer()();

  @override
  Set<Column<Object>> get primaryKey => {profileId, kind, categoryId};
}

/// Elementos del catálogo por perfil. **Sin URLs** (ni stream ni imagen).
@DataClassName('CatalogItemRow')
class CatalogItems extends Table {
  IntColumn get profileId =>
      integer().references(Profiles, #id, onDelete: KeyAction.cascade)();
  TextColumn get kind => textEnum<ContentKind>()();
  TextColumn get itemId => text()();
  TextColumn get name => text()();
  TextColumn get categoryId => text().nullable()();
  IntColumn get number => integer().nullable()();
  TextColumn get containerExtension => text().nullable()();
  IntColumn get year => integer().nullable()();
  RealColumn get rating => real().nullable()();
  IntColumn get position => integer()();

  @override
  Set<Column<Object>> get primaryKey => {profileId, kind, itemId};
}

/// Última actualización del catálogo local por perfil y tipo.
@DataClassName('CatalogSyncRow')
class CatalogSync extends Table {
  IntColumn get profileId =>
      integer().references(Profiles, #id, onDelete: KeyAction.cascade)();
  TextColumn get kind => textEnum<ContentKind>()();
  DateTimeColumn get syncedAt => dateTime()();
  IntColumn get itemCount => integer()();

  @override
  Set<Column<Object>> get primaryKey => {profileId, kind};
}

/// "Seguir viendo": posición por película o episodio. **Sin URLs.**
@DataClassName('WatchProgressRow')
class WatchProgressEntries extends Table {
  @override
  String get tableName => 'watch_progress';

  IntColumn get profileId =>
      integer().references(Profiles, #id, onDelete: KeyAction.cascade)();
  TextColumn get kind => textEnum<ProgressKind>()();
  TextColumn get itemId => text()();
  TextColumn get title => text()();
  TextColumn get categoryId => text().nullable()();
  TextColumn get containerExtension => text().nullable()();
  TextColumn get seriesId => text().nullable()();
  IntColumn get season => integer().nullable()();
  IntColumn get episode => integer().nullable()();
  TextColumn get episodeTitle => text().nullable()();
  IntColumn get positionMs => integer()();
  IntColumn get durationMs => integer()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {profileId, kind, itemId};
}

/// Base de datos local. Las tablas de catálogo y EPG (Fases 2+) llevan
/// `profile_id` para poder borrar todo lo de un perfil al cerrar sesión.
@DriftDatabase(
  tables: [
    Profiles,
    AppSettings,
    Favorites,
    CatalogCategories,
    CatalogItems,
    CatalogSync,
    WatchProgressEntries,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _open());

  /// 1: perfiles y preferencias. 2: favoritos. 3: favoritos sin URL de
  /// imagen y con categoría (la imagen se resuelve desde el catálogo).
  /// 4: catálogo local con búsqueda FTS5 y "seguir viendo".
  @override
  int get schemaVersion => 4;

  /// Índice de búsqueda FTS5: sin tildes ni mayúsculas ("futbol" encuentra
  /// "Fútbol"). Tabla independiente: se escribe junto con `catalog_items`
  /// y se borra por perfil (no tiene claves foráneas).
  static const String createSearchIndex =
      'CREATE VIRTUAL TABLE IF NOT EXISTS catalog_search USING fts5('
      'name, profile_id UNINDEXED, kind UNINDEXED, item_id UNINDEXED, '
      "tokenize='unicode61 remove_diacritics 2')";

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.createTable(favorites);
      } else if (from < 3) {
        // Recrea la tabla: se descarta la columna image_url (y sus URLs) y
        // se agrega category_id. Los favoritos se conservan.
        await m.alterTable(
          TableMigration(favorites, newColumns: [favorites.categoryId]),
        );
      }
      if (from < 4) {
        await m.createTable(catalogCategories);
        await m.createTable(catalogItems);
        await m.createTable(catalogSync);
        await m.createTable(watchProgressEntries);
      }
    },
    // Necesario para que funcione el borrado en cascada por perfil.
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
      await customStatement(createSearchIndex);
    },
  );

  /// En la carpeta de soporte de la app (no en Documentos, que el usuario
  /// ve y sincroniza).
  static QueryExecutor _open() => driftDatabase(
    name: 'evemtv',
    native: const DriftNativeOptions(
      databaseDirectory: getApplicationSupportDirectory,
    ),
  );
}
