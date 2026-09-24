// Favoritos: repositorio drift, migración, filtro de imágenes y servicio.
import 'package:drift/native.dart';
import 'package:evemtv/core/logging/app_logger.dart';
import 'package:evemtv/data/providers.dart';
import 'package:evemtv/data/storage/app_database.dart';
import 'package:evemtv/data/storage/drift_repositories.dart';
import 'package:evemtv/domain/entities/favorite.dart';
import 'package:evemtv/domain/entities/live.dart';
import 'package:evemtv/domain/entities/profile.dart';
import 'package:evemtv/domain/entities/source_credentials.dart';
import 'package:evemtv/domain/entities/vod.dart';
import 'package:evemtv/features/auth/application/session.dart';
import 'package:evemtv/features/favorites/favorites.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fakes.dart';

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
        'image_url',
        'number',
        'container_extension',
        'year',
        'added_at',
      });
    });
  });

  test('migración: una base v1 existente gana la tabla de favoritos', () async {
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
    expect(version.data.values.single, 2);
  });

  group('FavoritesService', () {
    ProviderContainer container(SourceCredentials credentials) {
      final c = ProviderContainer.test(
        overrides: [
          sessionProvider.overrideWith(() => FixedSession(credentials)),
          favoritesRepositoryProvider.overrideWithValue(
            InMemoryFavoritesRepository(),
          ),
        ],
      );
      return c;
    }

    final xtream = XtreamCredentials(
      server: Uri.parse('http://panel.example.com:8080'),
      username: 'usuarioDemo',
      password: 'claveDemo',
    );

    test('imágenes: no se guardan si revelan el servidor o credenciales', () {
      final service = container(xtream).read(favoritesServiceProvider);
      expect(
        service.safeImageUrl('http://img.example.org/logo.png'),
        'http://img.example.org/logo.png',
      );
      expect(
        service.safeImageUrl('http://panel.example.com:8080/i/1.png'),
        isNull,
      );
      expect(service.safeImageUrl('http://PANEL.example.com/i/1.png'), isNull);
      expect(
        service.safeImageUrl('http://img.example.org/usuarioDemo/logo.png'),
        isNull,
      );
      expect(service.safeImageUrl(null), isNull);

      final m3u = container(
        M3uCredentials(
          playlist: Uri.parse('http://lista.example.net/get.php?token=abc123'),
        ),
      ).read(favoritesServiceProvider);
      expect(m3u.safeImageUrl('http://lista.example.net/logo.png'), isNull);
      expect(m3u.safeImageUrl('http://cdn.example.org/x.png?t=abc123'), isNull);
      expect(m3u.safeImageUrl('http://cdn.example.org/x.png'), isNotNull);
    });

    test('alternar agrega y quita, con los datos para reproducir', () async {
      final c = container(xtream);
      final sub = c.listen(favoriteIdsProvider(FavoriteKind.movie), (_, _) {});
      final subLive = c.listen(favoritesProvider(FavoriteKind.live), (_, _) {});
      addTearDown(sub.close);
      addTearDown(subLive.close);
      final service = c.read(favoritesServiceProvider);
      const movie = VodItem(
        id: '501',
        name: 'Película Ficticia',
        containerExtension: 'mkv',
        year: 2021,
        posterUrl: 'http://panel.example.com:8080/p.jpg',
      );
      await service.toggleMovie(movie);
      await c.read(favoritesProvider(FavoriteKind.movie).future);
      await Future<void>.delayed(Duration.zero);
      final saved = c.read(favoritesProvider(FavoriteKind.movie)).value!.single;
      expect(saved.containerExtension, 'mkv');
      expect(saved.year, 2021);
      expect(saved.imageUrl, isNull, reason: 'apuntaba al servidor');
      expect(saved.toMovie().containerExtension, 'mkv');
      expect(c.read(favoriteIdsProvider(FavoriteKind.movie)), {'501'});

      await service.toggleMovie(movie);
      await Future<void>.delayed(Duration.zero);
      expect(c.read(favoriteIdsProvider(FavoriteKind.movie)), isEmpty);

      await service.toggleChannel(
        const LiveChannel(id: '101', name: 'Canal', number: 7),
      );
      await Future<void>.delayed(Duration.zero);
      final channel = c
          .read(favoritesProvider(FavoriteKind.live))
          .value!
          .single;
      expect(channel.toChannel().number, 7);
    });
  });
}
