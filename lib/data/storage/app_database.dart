import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';

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

/// Base de datos local. Las tablas de catálogo y EPG (Fases 2+) llevan
/// `profile_id` para poder borrar todo lo de un perfil al cerrar sesión.
@DriftDatabase(tables: [Profiles, AppSettings])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _open());

  @override
  int get schemaVersion => 1;

  /// En la carpeta de soporte de la app (no en Documentos, que el usuario
  /// ve y sincroniza).
  static QueryExecutor _open() => driftDatabase(
    name: 'evemtv',
    native: const DriftNativeOptions(
      databaseDirectory: getApplicationSupportDirectory,
    ),
  );
}
