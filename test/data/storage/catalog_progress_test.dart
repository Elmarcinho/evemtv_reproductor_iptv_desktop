// Catálogo local, búsqueda FTS5 y "seguir viendo" (datos ficticios).
import 'dart:io';

import 'package:drift/drift.dart' show Table, TableInfo, Variable;
import 'package:drift/native.dart';
import 'package:evemtv/data/storage/app_database.dart';
import 'package:evemtv/data/storage/drift_repositories.dart';
import 'package:evemtv/domain/entities/catalog.dart';
import 'package:evemtv/domain/entities/live.dart';
import 'package:evemtv/domain/entities/profile.dart';
import 'package:evemtv/domain/entities/watch_progress.dart';
import 'package:flutter_test/flutter_test.dart';

CatalogEntry movie(String id, String name, {String? category}) => CatalogEntry(
  kind: ContentKind.movie,
  id: id,
  name: name,
  categoryId: category,
);

void main() {
  late AppDatabase db;
  late DriftProfileRepository profiles;
  late DriftCatalogCache cache;
  late int a;
  late int b;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    profiles = DriftProfileRepository(db);
    cache = DriftCatalogCache(db, clock: () => DateTime(2026, 1, 1));
    a = (await profiles.create(name: 'A', type: SourceType.xtream)).id;
    b = (await profiles.create(name: 'B', type: SourceType.xtream)).id;
  });
  tearDown(() => db.close());

  group('catálogo local y búsqueda', () {
    setUp(() async {
      await cache.replace(
        a,
        ContentKind.live,
        const [ContentCategory(id: 'd', name: 'Deportes')],
        const [
          CatalogEntry(
            kind: ContentKind.live,
            id: '1',
            name: 'Fútbol en Vivo',
            categoryId: 'd',
            number: 7,
          ),
          CatalogEntry(
            kind: ContentKind.live,
            id: '2',
            name: 'Noticias 24h',
            categoryId: 'd',
          ),
        ],
      );
      await cache.replace(a, ContentKind.movie, const [], [
        movie('10', 'La Película del Fútbol', category: 'e'),
        movie('11', 'Otra historia'),
        movie('11', 'Repetida'),
      ]);
      await cache.replace(b, ContentKind.live, const [], const [
        CatalogEntry(kind: ContentKind.live, id: '99', name: 'Fútbol de B'),
      ]);
    });

    test(
      'sin tildes, sin mayúsculas, por prefijo y agrupado por tipo',
      () async {
        final r = await cache.search(a, 'FUTB');
        expect(r.byKind[ContentKind.live]!.map((e) => e.id), ['1']);
        expect(r.byKind[ContentKind.movie]!.map((e) => e.id), ['10']);
        expect(r.byKind[ContentKind.series], isEmpty);
        final canal = r.byKind[ContentKind.live]!.single;
        expect(canal.number, 7);
        expect(canal.categoryId, 'd');
      },
    );

    test('todas las palabras deben aparecer', () async {
      expect(
        (await cache.search(a, 'pel futbol')).byKind[ContentKind.movie],
        hasLength(1),
      );
      expect((await cache.search(a, 'pel noticias')).isEmpty, isTrue);
    });

    test('cada perfil ve solo su catálogo', () async {
      final r = await cache.search(b, 'futbol');
      expect(r.byKind[ContentKind.live]!.map((e) => e.id), ['99']);
      expect(r.byKind[ContentKind.movie], isEmpty);
    });

    test('la sintaxis FTS del usuario no rompe la consulta', () async {
      for (final q in [
        '"',
        'fut*',
        'NOT futbol',
        'a OR b',
        'NEAR(x y)',
        '(',
        '^',
        ':',
      ]) {
        await cache.search(a, q); // no lanza
      }
      expect(DriftCatalogCache.ftsQuery('  fut   "arg" '), '"fut"* "arg"*');
      expect(DriftCatalogCache.ftsQuery('   '), isNull);
    });

    test('recién agregadas: solo las últimas 50, por fecha de alta', () async {
      await cache.replace(a, ContentKind.movie, const [], [
        for (var i = 0; i < 80; i++)
          CatalogEntry(
            kind: ContentKind.movie,
            id: 'm$i',
            name: 'Película $i',
            added: DateTime.utc(2026).add(Duration(hours: i)),
          ),
      ]);
      final r = await cache.recentlyAdded(a, ContentKind.movie);
      expect(r, hasLength(50));
      expect(r.first.id, 'm79');
      expect(r.last.id, 'm30');
    });

    // Informe Codex Fase 4, punto 7.
    test('NUL y otros caracteres de control no rompen la búsqueda', () async {
      expect(DriftCatalogCache.ftsQuery('\u0000'), isNull);
      expect(DriftCatalogCache.ftsQuery('a\u0000b'), '"a"* "b"*');
      expect(DriftCatalogCache.ftsQuery('fut\u0007\u009Fbol'), '"fut"* "bol"*');
      for (final q in ['\u0000', 'a\u0000b', 'fut\u0000', '\u007F\u0085']) {
        await cache.search(a, q); // no lanza
      }
      expect(
        (await cache.search(a, 'futbol\u0000')).byKind[ContentKind.movie],
        hasLength(1),
      );
    });

    test(
      'reemplazar un tipo borra lo anterior de ese tipo solamente',
      () async {
        await cache.replace(a, ContentKind.live, const [], const [
          CatalogEntry(kind: ContentKind.live, id: '3', name: 'Canal Nuevo'),
        ]);
        expect(
          (await cache.search(a, 'futbol')).byKind[ContentKind.live],
          isEmpty,
        );
        expect(
          (await cache.search(a, 'nuevo')).byKind[ContentKind.live],
          hasLength(1),
        );
        expect(
          (await cache.search(a, 'futbol')).byKind[ContentKind.movie],
          hasLength(1),
        );
      },
    );

    test('estado de la sincronización y nombres de categorías', () async {
      final info = await cache.syncInfo(a, ContentKind.movie);
      expect(info!.itemCount, 3);
      expect(info.syncedAt, DateTime(2026, 1, 1));
      expect(await cache.syncInfo(a, ContentKind.series), isNull);
      expect(await cache.categoryNames(a, ContentKind.live), {'d': 'Deportes'});
    });

    test('eliminar el perfil borra su catálogo e índice', () async {
      await profiles.delete(a);
      final rows = await db
          .customSelect(
            'SELECT COUNT(*) c FROM catalog_search WHERE profile_id = ?',
            variables: [Variable.withInt(a)],
          )
          .getSingle();
      expect(rows.read<int>('c'), 0);
      expect(
        await db.select(db.catalogItems).get(),
        hasLength(1),
        reason: 'queda el de B',
      );
    });

    test('ninguna tabla del catálogo tiene columnas de URL', () {
      for (final table in <TableInfo<Table, Object?>>[
        db.catalogItems,
        db.catalogCategories,
        db.watchProgressEntries,
      ]) {
        for (final c in table.$columns) {
          expect(
            c.name,
            isNot(contains('url')),
            reason: '${table.actualTableName}.${c.name}',
          );
        }
      }
    });
  });

  group('seguir viendo', () {
    late DriftWatchProgressRepository progress;
    setUp(() => progress = DriftWatchProgressRepository(db));

    WatchProgress p(String id, int minute, {DateTime? at}) => WatchProgress(
      kind: ProgressKind.movie,
      itemId: id,
      title: 'Película $id',
      position: Duration(minutes: minute),
      duration: const Duration(hours: 2),
      updatedAt: at ?? DateTime(2026, 1, 1),
    );

    test('guarda, actualiza, ordena y quita', () async {
      await progress.save(a, p('1', 10, at: DateTime(2026, 1, 1)));
      await progress.save(a, p('2', 20, at: DateTime(2026, 1, 2)));
      await progress.save(a, p('1', 30, at: DateTime(2026, 1, 3)));
      final list = await progress.watchRecent(a).first;
      expect(list.map((e) => e.itemId), ['1', '2']);
      expect(list.first.position, const Duration(minutes: 30));
      expect(
        (await progress.get(a, ProgressKind.movie, '2'))!.fraction,
        closeTo(1 / 6, 0.001),
      );
      await progress.remove(a, ProgressKind.movie, '1');
      expect(await progress.get(a, ProgressKind.movie, '1'), isNull);
      expect(await progress.watchRecent(b).first, isEmpty);
    });

    test('reglas de terminado y de muy poco visto', () {
      const h2 = Duration(hours: 2);
      expect(
        WatchProgress.isFinished(const Duration(minutes: 115), h2),
        isTrue,
      );
      expect(
        WatchProgress.isFinished(const Duration(minutes: 119), h2),
        isTrue,
      );
      expect(
        WatchProgress.isFinished(const Duration(minutes: 60), h2),
        isFalse,
      );
      expect(
        WatchProgress.isFinished(const Duration(minutes: 60), Duration.zero),
        isFalse,
      );
      expect(WatchProgress.isTooEarly(const Duration(seconds: 29)), isTrue);
    });
  });

  test(
    'migración v3 → v4: conserva perfiles y favoritos, crea las tablas nuevas',
    () async {
      final old = AppDatabase(
        NativeDatabase.memory(
          setup: (raw) {
            raw.execute(
              'CREATE TABLE profiles (id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
              'name TEXT NOT NULL, type TEXT NOT NULL, created_at INTEGER NOT NULL, '
              'last_used_at INTEGER NULL);',
            );
            raw.execute(
              'CREATE TABLE app_settings (key TEXT NOT NULL, value TEXT NOT NULL, PRIMARY KEY (key));',
            );
            raw.execute(
              'CREATE TABLE favorites (profile_id INTEGER NOT NULL REFERENCES profiles (id) '
              'ON DELETE CASCADE, kind TEXT NOT NULL, item_id TEXT NOT NULL, name TEXT NOT NULL, '
              'category_id TEXT NULL, number INTEGER NULL, container_extension TEXT NULL, '
              'year INTEGER NULL, added_at INTEGER NOT NULL, PRIMARY KEY (profile_id, kind, item_id));',
            );
            raw.execute(
              "INSERT INTO profiles (name, type, created_at) VALUES ('Vieja', 'xtream', 0);",
            );
            raw.execute(
              "INSERT INTO favorites VALUES (1, 'live', '5', 'Canal', NULL, NULL, NULL, NULL, 0);",
            );
            raw.execute('PRAGMA user_version = 3;');
          },
        ),
      );
      addTearDown(old.close);
      expect((await old.select(old.profiles).get()).single.name, 'Vieja');
      expect(await old.select(old.favorites).get(), hasLength(1));
      await DriftCatalogCache(
        old,
      ).replace(1, ContentKind.series, const [], const [
        CatalogEntry(kind: ContentKind.series, id: '7', name: 'Serie Ficticia'),
      ]);
      expect(
        (await DriftCatalogCache(
          old,
        ).search(1, 'serie')).byKind[ContentKind.series],
        hasLength(1),
      );
      final v = await old.customSelect('PRAGMA user_version').getSingle();
      expect(v.data.values.single, 5);
    },
  );

  test('migración v4 → v5: agrega la fecha de alta y fuerza a descargar el '
      'catálogo de nuevo', () async {
    final dir = Directory.systemTemp.createTempSync('evemtv_db_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/db.sqlite');

    // Base v5 con catálogo, convertida a v4 (sin la columna added).
    final v5 = AppDatabase(NativeDatabase(file));
    await DriftProfileRepository(v5).create(name: 'A', type: SourceType.xtream);
    await DriftCatalogCache(v5).replace(1, ContentKind.movie, const [], const [
      CatalogEntry(kind: ContentKind.movie, id: '1', name: 'Película'),
    ]);
    await v5.close();
    // Al reabrir, antes de migrar, se deja como una base v4.
    final migrated = AppDatabase(
      NativeDatabase(
        file,
        setup: (raw) {
          raw.execute('ALTER TABLE catalog_items DROP COLUMN added;');
          raw.execute('PRAGMA user_version = 4;');
        },
      ),
    );
    addTearDown(migrated.close);
    final cache = DriftCatalogCache(migrated);
    // Se conserva lo guardado (la búsqueda sigue funcionando)…
    expect(
      (await cache.search(1, 'pelicula')).byKind[ContentKind.movie],
      hasLength(1),
    );
    // …pero la marca de actualización se borra: se descarga de nuevo.
    expect(await cache.syncInfo(1, ContentKind.movie), isNull);
    // Y la fecha de alta ya se guarda.
    await cache.replace(1, ContentKind.movie, const [], [
      CatalogEntry(
        kind: ContentKind.movie,
        id: '2',
        name: 'Nueva',
        year: 2026,
        added: DateTime.utc(2026, 9, 1),
      ),
    ]);
    final recent = await cache.recent(1, ContentKind.movie, minYear: 2026);
    expect(recent.single.added, DateTime.utc(2026, 9, 1));
  });
}
