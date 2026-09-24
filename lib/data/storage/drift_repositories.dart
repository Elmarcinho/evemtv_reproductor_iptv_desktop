import 'package:drift/drift.dart';

import '../../domain/entities/profile.dart';
import '../../domain/repositories/profile_repository.dart';
import '../../domain/repositories/settings_repository.dart';
import 'app_database.dart';

class DriftProfileRepository implements ProfileRepository {
  DriftProfileRepository(this._db, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final DateTime Function() _clock;

  static Profile _toEntity(ProfileRow row) => Profile(
    id: row.id,
    name: row.name,
    type: row.type,
    createdAt: row.createdAt,
    lastUsedAt: row.lastUsedAt,
  );

  @override
  Stream<List<Profile>> watchAll() {
    final query = _db.select(_db.profiles)
      ..orderBy([
        (t) => OrderingTerm(
          expression: t.lastUsedAt,
          mode: OrderingMode.desc,
          nulls: NullsOrder.last,
        ),
        (t) => OrderingTerm.desc(t.createdAt),
      ]);
    return query.watch().map((rows) => rows.map(_toEntity).toList());
  }

  @override
  Future<Profile> create({
    required String name,
    required SourceType type,
  }) async {
    final row = await _db
        .into(_db.profiles)
        .insertReturning(
          ProfilesCompanion.insert(name: name, type: type, createdAt: _clock()),
        );
    return _toEntity(row);
  }

  @override
  Future<void> markUsed(int id) async {
    await (_db.update(_db.profiles)..where((t) => t.id.equals(id))).write(
      ProfilesCompanion(lastUsedAt: Value(_clock())),
    );
  }

  @override
  Future<void> delete(int id) async {
    // En las fases siguientes, aquí se borran también catálogo, EPG,
    // favoritos y "seguir viendo" de este perfil, en la misma transacción.
    await _db.transaction(() async {
      await (_db.delete(_db.profiles)..where((t) => t.id.equals(id))).go();
    });
  }

  @override
  Future<int> count() async {
    final countExp = _db.profiles.id.count();
    final query = _db.selectOnly(_db.profiles)..addColumns([countExp]);
    return (await query.getSingle()).read(countExp) ?? 0;
  }
}

class DriftSettingsRepository implements SettingsRepository {
  DriftSettingsRepository(this._db);

  final AppDatabase _db;

  @override
  Future<String?> get(String key) async {
    final row = await (_db.select(
      _db.appSettings,
    )..where((t) => t.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  @override
  Future<void> set(String key, String value) async {
    await _db
        .into(_db.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(key: key, value: value),
        );
  }
}
