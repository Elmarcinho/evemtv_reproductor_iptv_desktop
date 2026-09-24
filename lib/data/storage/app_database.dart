import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../../domain/entities/favorite.dart';
import '../../domain/entities/profile.dart';

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

/// Favoritos por perfil. Sin URLs de stream ni credenciales: la imagen solo
/// se guarda si no revela el servidor (ver `FavoritesService`).
@DataClassName('FavoriteRow')
class Favorites extends Table {
  IntColumn get profileId =>
      integer().references(Profiles, #id, onDelete: KeyAction.cascade)();
  TextColumn get kind => textEnum<FavoriteKind>()();
  TextColumn get itemId => text()();
  TextColumn get name => text()();
  TextColumn get imageUrl => text().nullable()();
  IntColumn get number => integer().nullable()();
  TextColumn get containerExtension => text().nullable()();
  IntColumn get year => integer().nullable()();
  DateTimeColumn get addedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {profileId, kind, itemId};
}

/// Base de datos local. Las tablas de catálogo y EPG (Fases 2+) llevan
/// `profile_id` para poder borrar todo lo de un perfil al cerrar sesión.
@DriftDatabase(tables: [Profiles, AppSettings, Favorites])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _open());

  /// 1: perfiles y preferencias. 2: favoritos.
  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) await m.createTable(favorites);
    },
    // Necesario para que funcione el borrado en cascada por perfil.
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
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
