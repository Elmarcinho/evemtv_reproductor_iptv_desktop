import 'package:drift/drift.dart';

import '../../domain/entities/catalog.dart';
import '../../domain/entities/favorite.dart';
import '../../domain/entities/live.dart';
import '../../domain/entities/profile.dart';
import '../../domain/entities/watch_progress.dart';
import '../../domain/repositories/catalog_cache.dart';
import '../../domain/repositories/favorites_repository.dart';
import '../../domain/repositories/profile_repository.dart';
import '../../domain/repositories/settings_repository.dart';
import '../../domain/repositories/watch_progress_repository.dart';
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
      for (final table in <TableInfo<Table, Object?>>[
        _db.favorites,
        _db.catalogCategories,
        _db.catalogItems,
        _db.catalogSync,
        _db.watchProgressEntries,
      ]) {
        await _db.customStatement(
          'DELETE FROM ${table.actualTableName} WHERE profile_id = ?',
          [id],
        );
      }
      // El índice de búsqueda no tiene claves foráneas.
      await _db.customStatement(
        'DELETE FROM catalog_search WHERE profile_id = ?',
        [id],
      );
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

class DriftCatalogCache implements CatalogCache {
  DriftCatalogCache(this._db, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final DateTime Function() _clock;

  @override
  Future<void> replace(
    int profileId,
    ContentKind kind,
    List<ContentCategory> categories,
    List<CatalogEntry> items,
  ) async {
    await _db.transaction(() async {
      await (_db.delete(_db.catalogCategories)..where(
            (t) => t.profileId.equals(profileId) & t.kind.equalsValue(kind),
          ))
          .go();
      await (_db.delete(_db.catalogItems)..where(
            (t) => t.profileId.equals(profileId) & t.kind.equalsValue(kind),
          ))
          .go();
      await _db.customStatement(
        'DELETE FROM catalog_search WHERE profile_id = ? AND kind = ?',
        [profileId, kind.name],
      );
      await _db.batch((b) {
        b.insertAll(_db.catalogCategories, [
          for (final (i, c) in categories.indexed)
            CatalogCategoriesCompanion.insert(
              profileId: profileId,
              kind: kind,
              categoryId: c.id,
              name: c.name,
              position: i,
            ),
        ], mode: InsertMode.insertOrReplace);
        final seen = <String>{};
        for (final (i, e) in items.indexed) {
          // Un mismo elemento puede venir repetido: se guarda una vez.
          if (!seen.add(e.id)) continue;
          b.insert(
            _db.catalogItems,
            CatalogItemsCompanion.insert(
              profileId: profileId,
              kind: kind,
              itemId: e.id,
              name: e.name,
              categoryId: Value(e.categoryId),
              number: Value(e.number),
              containerExtension: Value(e.containerExtension),
              year: Value(e.year),
              rating: Value(e.rating),
              position: i,
            ),
          );
          b.customStatement(
            'INSERT INTO catalog_search (name, profile_id, kind, item_id) '
            'VALUES (?, ?, ?, ?)',
            [e.name, profileId, kind.name, e.id],
          );
        }
      });
      await _db
          .into(_db.catalogSync)
          .insertOnConflictUpdate(
            CatalogSyncCompanion.insert(
              profileId: profileId,
              kind: kind,
              syncedAt: _clock(),
              itemCount: items.length,
            ),
          );
    });
  }

  @override
  Future<CatalogSyncInfo?> syncInfo(int profileId, ContentKind kind) async {
    final row =
        await (_db.select(_db.catalogSync)..where(
              (t) => t.profileId.equals(profileId) & t.kind.equalsValue(kind),
            ))
            .getSingleOrNull();
    return row == null
        ? null
        : CatalogSyncInfo(syncedAt: row.syncedAt, itemCount: row.itemCount);
  }

  /// Convierte lo que escribe el usuario en una consulta FTS5 segura: cada
  /// palabra entre comillas (sin operadores del usuario) y como prefijo.
  /// "fut arg" → `"fut"* "arg"*` (todas las palabras deben aparecer).
  static String? ftsQuery(String input) {
    final words = input
        .split(RegExp(r'\s+'))
        .map((w) => w.replaceAll('"', '').trim())
        .where((w) => w.isNotEmpty)
        .take(8)
        .toList();
    if (words.isEmpty) return null;
    return words.map((w) => '"$w"*').join(' ');
  }

  @override
  Future<SearchResults> search(
    int profileId,
    String query, {
    int limitPerKind = 30,
  }) async {
    final fts = ftsQuery(query);
    if (fts == null) return SearchResults.empty;
    final byKind = <ContentKind, List<CatalogEntry>>{};
    for (final kind in ContentKind.values) {
      final rows = await _db
          .customSelect(
            'SELECT i.* FROM catalog_search s '
            'JOIN catalog_items i ON i.profile_id = s.profile_id '
            'AND i.kind = s.kind AND i.item_id = s.item_id '
            'WHERE catalog_search MATCH ? AND s.profile_id = ? AND s.kind = ? '
            'ORDER BY s.rank LIMIT ?',
            variables: [
              Variable.withString(fts),
              Variable.withInt(profileId),
              Variable.withString(kind.name),
              Variable.withInt(limitPerKind),
            ],
            readsFrom: {_db.catalogItems},
          )
          .get();
      byKind[kind] = [
        for (final r in rows)
          CatalogEntry(
            kind: kind,
            id: r.read<String>('item_id'),
            name: r.read<String>('name'),
            categoryId: r.readNullable<String>('category_id'),
            number: r.readNullable<int>('number'),
            containerExtension: r.readNullable<String>('container_extension'),
            year: r.readNullable<int>('year'),
            rating: r.readNullable<double>('rating'),
          ),
      ];
    }
    return SearchResults(byKind);
  }

  @override
  Future<Map<String, String>> categoryNames(
    int profileId,
    ContentKind kind,
  ) async {
    final rows =
        await (_db.select(_db.catalogCategories)..where(
              (t) => t.profileId.equals(profileId) & t.kind.equalsValue(kind),
            ))
            .get();
    return {for (final r in rows) r.categoryId: r.name};
  }
}

class DriftWatchProgressRepository implements WatchProgressRepository {
  DriftWatchProgressRepository(this._db);

  final AppDatabase _db;

  static WatchProgress _toEntity(WatchProgressRow r) => WatchProgress(
    kind: r.kind,
    itemId: r.itemId,
    title: r.title,
    position: Duration(milliseconds: r.positionMs),
    duration: Duration(milliseconds: r.durationMs),
    updatedAt: r.updatedAt,
    categoryId: r.categoryId,
    containerExtension: r.containerExtension,
    seriesId: r.seriesId,
    season: r.season,
    episode: r.episode,
    episodeTitle: r.episodeTitle,
  );

  @override
  Stream<List<WatchProgress>> watchRecent(int profileId, {int limit = 20}) {
    final query = _db.select(_db.watchProgressEntries)
      ..where((t) => t.profileId.equals(profileId))
      ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)])
      ..limit(limit);
    return query.watch().map((rows) => rows.map(_toEntity).toList());
  }

  @override
  Future<WatchProgress?> get(
    int profileId,
    ProgressKind kind,
    String itemId,
  ) async {
    final row =
        await (_db.select(_db.watchProgressEntries)..where(
              (t) =>
                  t.profileId.equals(profileId) &
                  t.kind.equalsValue(kind) &
                  t.itemId.equals(itemId),
            ))
            .getSingleOrNull();
    return row == null ? null : _toEntity(row);
  }

  @override
  Future<void> save(int profileId, WatchProgress p) async {
    await _db
        .into(_db.watchProgressEntries)
        .insertOnConflictUpdate(
          WatchProgressEntriesCompanion.insert(
            profileId: profileId,
            kind: p.kind,
            itemId: p.itemId,
            title: p.title,
            categoryId: Value(p.categoryId),
            containerExtension: Value(p.containerExtension),
            seriesId: Value(p.seriesId),
            season: Value(p.season),
            episode: Value(p.episode),
            episodeTitle: Value(p.episodeTitle),
            positionMs: p.position.inMilliseconds,
            durationMs: p.duration.inMilliseconds,
            updatedAt: p.updatedAt,
          ),
        );
  }

  @override
  Future<void> remove(int profileId, ProgressKind kind, String itemId) async {
    await (_db.delete(_db.watchProgressEntries)..where(
          (t) =>
              t.profileId.equals(profileId) &
              t.kind.equalsValue(kind) &
              t.itemId.equals(itemId),
        ))
        .go();
  }
}
