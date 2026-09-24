import 'package:drift/drift.dart';

import '../../domain/entities/favorite.dart';
import '../../domain/entities/profile.dart';
import '../../domain/repositories/favorites_repository.dart';
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
  Future<bool> markUsed(int id) async {
    final updated =
        await (_db.update(_db.profiles)..where((t) => t.id.equals(id))).write(
          ProfilesCompanion(lastUsedAt: Value(_clock())),
        );
    return updated > 0;
  }

  @override
  Future<void> delete(int id) async {
    // Todo lo del perfil se borra en la misma transacción. Los favoritos
    // también tienen borrado en cascada; se borran explícitamente por si
    // las claves foráneas estuvieran desactivadas.
    await _db.transaction(() async {
      await (_db.delete(
        _db.favorites,
      )..where((t) => t.profileId.equals(id))).go();
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

class DriftFavoritesRepository implements FavoritesRepository {
  DriftFavoritesRepository(this._db);

  final AppDatabase _db;

  static Favorite _toEntity(FavoriteRow r) => Favorite(
    kind: r.kind,
    itemId: r.itemId,
    name: r.name,
    addedAt: r.addedAt,
    categoryId: r.categoryId,
    number: r.number,
    containerExtension: r.containerExtension,
    year: r.year,
  );

  @override
  Stream<List<Favorite>> watch(int profileId, FavoriteKind kind) {
    final query = _db.select(_db.favorites)
      ..where((t) => t.profileId.equals(profileId) & t.kind.equalsValue(kind))
      ..orderBy([(t) => OrderingTerm.desc(t.addedAt)]);
    return query.watch().map((rows) => rows.map(_toEntity).toList());
  }

  @override
  Future<void> add(int profileId, Favorite f) async {
    await _db
        .into(_db.favorites)
        .insertOnConflictUpdate(
          FavoritesCompanion.insert(
            profileId: profileId,
            kind: f.kind,
            itemId: f.itemId,
            name: f.name,
            categoryId: Value(f.categoryId),
            number: Value(f.number),
            containerExtension: Value(f.containerExtension),
            year: Value(f.year),
            addedAt: f.addedAt,
          ),
        );
  }

  @override
  Future<void> remove(int profileId, FavoriteKind kind, String itemId) async {
    await (_db.delete(_db.favorites)..where(
          (t) =>
              t.profileId.equals(profileId) &
              t.kind.equalsValue(kind) &
              t.itemId.equals(itemId),
        ))
        .go();
  }
}
