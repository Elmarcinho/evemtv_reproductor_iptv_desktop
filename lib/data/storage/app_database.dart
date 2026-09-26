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

  /// Marcada como de adultos por el panel (`is_adult`).
  BoolColumn get adult => boolean().withDefault(const Constant(false))();

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

  /// Cuándo se agregó al servidor (segundos Unix), si lo informa.
  IntColumn get added => integer().nullable()();
  IntColumn get position => integer()();

  /// Marcado como de adultos por el panel (`is_adult`).
  BoolColumn get adult => boolean().withDefault(const Constant(false))();

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

/// Control parental por perfil: PIN (hash con sal; sin fila o sin hash =
/// PIN por defecto `0000`), categorías que el usuario bloqueó a mano y
/// espera tras intentos fallidos. Se borra con el perfil.
@DataClassName('ParentalRow')
class ParentalSettings extends Table {
  IntColumn get profileId =>
      integer().references(Profiles, #id, onDelete: KeyAction.cascade)();

  /// `pbkdf2-sha256$<iteraciones>$<sal base64>$<hash base64>`.
  TextColumn get pinHash => text().nullable()();

  /// Categorías bloqueadas a mano: JSON `["live:12", "movie:7"]`.
  TextColumn get blockedCategories =>
      text().withDefault(const Constant('[]'))();

  IntColumn get failedAttempts => integer().withDefault(const Constant(0))();

  /// Hasta cuándo no se acepta otro intento (milisegundos Unix).
  IntColumn get lockedUntil => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {profileId};
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
    ParentalSettings,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _open());

  /// 1: perfiles y preferencias. 2: favoritos. 3: favoritos sin URL de
  /// imagen y con categoría (la imagen se resuelve desde el catálogo).
  /// 4: catálogo local con búsqueda FTS5 y "seguir viendo".
  /// 5: fecha de alta en el catálogo. 6: control parental (marca de
  /// adultos en el catálogo y tabla por perfil).
  @override
  int get schemaVersion => 6;

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
      } else {
        if (from < 5) {
          await m.addColumn(catalogItems, catalogItems.added);
        }
        if (from < 6) {
          await m.addColumn(catalogItems, catalogItems.adult);
          await m.addColumn(catalogCategories, catalogCategories.adult);
        }
        // El catálogo guardado no tiene los datos nuevos (fechas, marca de
        // adultos): se borra la marca de actualización para que se vuelva a
        // descargar al abrir la sesión.
        await customStatement('DELETE FROM catalog_sync');
      }
      if (from < 6) {
        await m.createTable(parentalSettings);
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
