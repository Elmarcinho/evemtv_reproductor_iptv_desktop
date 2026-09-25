// Favoritos: repositorio drift, migración, filtro de imágenes y servicio.
import 'package:drift/native.dart';
import 'package:evemtv/core/logging/app_logger.dart';
import 'package:evemtv/data/providers.dart';
import 'package:evemtv/data/storage/app_database.dart';
import 'package:evemtv/data/storage/drift_repositories.dart';
import 'package:evemtv/domain/entities/favorite.dart';
import 'package:evemtv/domain/entities/live.dart';
import 'package:evemtv/domain/entities/profile.dart';
import 'package:evemtv/domain/entities/vod.dart';
import 'package:evemtv/features/auth/application/session.dart';
import 'package:evemtv/features/favorites/favorites.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fakes.dart';
import '../player/live_playback_controller_test.dart' show FakeSource;

Favorite fav(FavoriteKind kind, String id, {DateTime? at}) => Favorite(
  kind: kind,
  itemId: id,
  name: 'Elemento $id',
  addedAt: at ?? DateTime(2026),
);

void main() {
  late LogSink originalSink;
  setUp(() {
    originalSink = AppLogger.sink;
    AppLogger.sink = (_, _) {};
  });
  tearDown(() => AppLogger.sink = originalSink);

  group('DriftFavoritesRepository', () {
    late AppDatabase db;
    late DriftProfileRepository profiles;
    late DriftFavoritesRepository favorites;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      profiles = DriftProfileRepository(db);
      favorites = DriftFavoritesRepository(db);
    });
    tearDown(() => db.close());

    test('por perfil y por tipo, los más recientes primero', () async {
      final a = await profiles.create(name: 'A', type: SourceType.xtream);
      final b = await profiles.create(name: 'B', type: SourceType.m3u);
      await favorites.add(
        a.id,
        fav(FavoriteKind.live, '1', at: DateTime(2026, 1, 1)),
      );
      await favorites.add(
        a.id,
        fav(FavoriteKind.live, '2', at: DateTime(2026, 1, 2)),
      );
      await favorites.add(a.id, fav(FavoriteKind.movie, '9'));
      await favorites.add(b.id, fav(FavoriteKind.live, '1'));

      final live = await favorites.watch(a.id, FavoriteKind.live).first;
      expect(live.map((f) => f.itemId), ['2', '1']);
      expect(
        await favorites.watch(a.id, FavoriteKind.movie).first,
        hasLength(1),
      );
      expect(
        await favorites.watch(b.id, FavoriteKind.live).first,
        hasLength(1),
      );

      // Agregar de nuevo no duplica.
      await favorites.add(a.id, fav(FavoriteKind.live, '1'));
      expect(
        await favorites.watch(a.id, FavoriteKind.live).first,
        hasLength(2),
      );

      await favorites.remove(a.id, FavoriteKind.live, '2');
      expect(
        (await favorites.watch(a.id, FavoriteKind.live).first).map(
          (f) => f.itemId,
        ),
        ['1'],
      );
    });

    test('eliminar el perfil borra sus favoritos y no los de otros', () async {
      final a = await profiles.create(name: 'A', type: SourceType.xtream);
      final b = await profiles.create(name: 'B', type: SourceType.xtream);
      await favorites.add(a.id, fav(FavoriteKind.series, '7'));
      await favorites.add(b.id, fav(FavoriteKind.series, '7'));
      await profiles.delete(a.id);
      final rows = await db.select(db.favorites).get();
      expect(rows.map((r) => r.profileId), [b.id]);
    });

    test('la tabla no tiene columnas de URL de stream ni credenciales', () {
      final columns = db.favorites.$columns.map((c) => c.name).toSet();
      expect(columns, {
        'profile_id',
        'kind',
        'item_id',
        'name',
        'category_id',
        'number',
        'container_extension',
        'year',
        'added_at',
      });
    });
  });

  test('migración: una base v1 existente gana la tabla de favoritos (v3)', () async {
    final executor = NativeDatabase.memory(
      setup: (raw) {
        // Esquema tal como lo dejaba la versión 1.
        raw.execute(
          'CREATE TABLE profiles (id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
          'name TEXT NOT NULL, type TEXT NOT NULL, created_at INTEGER NOT NULL, '
          'last_used_at INTEGER NULL);',
        );
        raw.execute(
          'CREATE TABLE app_settings (key TEXT NOT NULL, value TEXT NOT NULL, '
          'PRIMARY KEY (key));',
        );
        raw.execute(
          "INSERT INTO profiles (name, type, created_at) VALUES ('Vieja', 'xtream', 0);",
        );
        raw.execute(
          "INSERT INTO app_settings VALUES ('accepted_terms_version', '1');",
        );
        raw.execute('PRAGMA user_version = 1;');
      },
    );
    final db = AppDatabase(executor);
    addTearDown(db.close);
    final profile = (await db.select(db.profiles).get()).single;
    expect(profile.name, 'Vieja', reason: 'los datos se conservan');
    await DriftFavoritesRepository(db)
        .add(profile.id, fav(FavoriteKind.live, '1'));
    expect(await db.select(db.favorites).get(), hasLength(1));
    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(
      version.data.values.single,
      AppDatabase(NativeDatabase.memory()).schemaVersion,
    );
  });

  test('migración v2 → v3: descarta las URLs de imagen y conserva los favoritos', () async {
    final executor = NativeDatabase.memory(
      setup: (raw) {
        raw.execute(
          'CREATE TABLE profiles (id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
          'name TEXT NOT NULL, type TEXT NOT NULL, created_at INTEGER NOT NULL, '
          'last_used_at INTEGER NULL);',
        );
        raw.execute(
          'CREATE TABLE app_settings (key TEXT NOT NULL, value TEXT NOT NULL, '
          'PRIMARY KEY (key));',
        );
        // Tabla de favoritos tal como la dejaba la versión 2.
        raw.execute(
          'CREATE TABLE favorites (profile_id INTEGER NOT NULL REFERENCES '
          'profiles (id) ON DELETE CASCADE, kind TEXT NOT NULL, item_id TEXT '
          'NOT NULL, name TEXT NOT NULL, image_url TEXT NULL, number INTEGER '
          'NULL, container_extension TEXT NULL, year INTEGER NULL, added_at '
          'INTEGER NOT NULL, PRIMARY KEY (profile_id, kind, item_id));',
        );
        raw.execute(
          "INSERT INTO profiles (name, type, created_at) VALUES ('A', 'xtream', 0);",
        );
        raw.execute(
          "INSERT INTO favorites VALUES (1, 'movie', '501', 'Película', "
          "'http://img.example.org/p.jpg?password=claveDemo', NULL, 'mkv', 2021, 0);",
        );
        raw.execute('PRAGMA user_version = 2;');
      },
    );
    final db = AppDatabase(executor);
    addTearDown(db.close);
    final rows = await db.select(db.favorites).get();
    expect(rows.single.itemId, '501');
    expect(rows.single.containerExtension, 'mkv');
    expect(rows.single.categoryId, isNull);
    final columns = await db
        .customSelect("SELECT name FROM pragma_table_info('favorites')")
        .get();
    expect(
      columns.map((r) => r.data['name']),
      isNot(contains('image_url')),
      reason: 'la columna (y sus URLs) se descarta',
    );
  });

  group('FavoritesService', () {
    late ProviderContainer c;
    late _CatalogSource source;

    setUp(() {
      source = _CatalogSource();
      c = ProviderContainer.test(
        overrides: [
          sessionProvider.overrideWith(FixedSession.new),
          favoritesRepositoryProvider.overrideWithValue(
            InMemoryFavoritesRepository(),
          ),
          contentSourceProvider.overrideWithValue(source),
        ],
      );
    });

    test('guarda categoría y datos para reproducir, ninguna URL', () async {
      final sub = c.listen(favoritesProvider(FavoriteKind.movie), (_, _) {});
      addTearDown(sub.close);
      const movie = VodItem(
        id: '501',
        name: 'Película Ficticia',
        categoryId: 'e',
        containerExtension: 'mkv',
        year: 2021,
        posterUrl: 'http://img.example.org/p.jpg?password=claveDemo',
      );
      await c.read(favoritesServiceProvider).toggleMovie(movie);
      await Future<void>.delayed(Duration.zero);
      final saved = c.read(favoritesProvider(FavoriteKind.movie)).value!.single;
      expect(saved.categoryId, 'e');
      expect(saved.containerExtension, 'mkv');
      expect(saved.toMovie().posterUrl, isNull);

      await c.read(favoritesServiceProvider).toggleMovie(movie);
      await Future<void>.delayed(Duration.zero);
      expect(c.read(favoritesProvider(FavoriteKind.movie)).value, isEmpty);
    });

    test('las imágenes se resuelven desde el catálogo en memoria', () async {
      final sub = c.listen(resolvedLiveFavoritesProvider, (_, _) {});
      addTearDown(sub.close);
      await c
          .read(favoritesServiceProvider)
          .toggleChannel(
            const LiveChannel(id: '1', name: 'Uno', categoryId: 'n'),
          );
      await c
          .read(favoritesServiceProvider)
          .toggleChannel(
            const LiveChannel(id: '404', name: 'Ya no está', categoryId: 'n'),
          );
      // Espera a que la lista resuelta incluya los dos favoritos.
      var resolved = <LiveChannel>[];
      for (var i = 0; i < 50 && resolved.length < 2; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        resolved = await c.read(resolvedLiveFavoritesProvider.future);
      }
      final byId = {for (final ch in resolved) ch.id: ch};
      expect(byId['1']!.logoUrl, 'http://img.example.org/uno.png');
      expect(byId['404']!.logoUrl, isNull, reason: 'sin catálogo: sin imagen');
      expect(source.requested, ['n'], reason: 'una descarga por categoría');
    });

    test('preferResolved usa la versión completa solo si coincide', () {
      final favorites = [
        fav(FavoriteKind.live, 'a'),
        fav(FavoriteKind.live, 'b'),
      ];
      const full = [
        LiveChannel(
          id: 'a',
          name: 'A',
          logoUrl: 'http://img.example.org/a.png',
        ),
        LiveChannel(id: 'b', name: 'B'),
      ];
      expect(
        preferResolved(favorites, full, (c) => c.id, (f) => f.toChannel()),
        same(full),
      );
      expect(
        preferResolved(
          favorites,
          full.sublist(0, 1),
          (c) => c.id,
          (f) => f.toChannel(),
        ).map((c) => c.logoUrl),
        [null, null],
      );
    });
  });
}

class _CatalogSource extends FakeSource {
  final requested = <String?>[];

  @override
  Future<List<LiveChannel>> liveChannels({String? categoryId}) async {
    requested.add(categoryId);
    return const [
      LiveChannel(
        id: '1',
        name: 'Uno',
        logoUrl: 'http://img.example.org/uno.png',
      ),
      LiveChannel(id: '2', name: 'Dos'),
    ];
  }
}
