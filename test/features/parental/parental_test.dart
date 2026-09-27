// Control parental (Fase 6). Catálogo ficticio; ninguna cuenta real.
import 'dart:convert';

import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:evemtv/core/logging/app_logger.dart';
import 'package:evemtv/data/providers.dart';
import 'package:evemtv/data/storage/app_database.dart';
import 'package:evemtv/data/storage/drift_repositories.dart';
import 'package:evemtv/data/xtream/xtream_live_parser.dart';
import 'package:evemtv/data/xtream/xtream_vod_parser.dart';
import 'package:evemtv/domain/entities/catalog.dart';
import 'package:evemtv/domain/entities/favorite.dart';
import 'package:evemtv/domain/entities/live.dart';
import 'package:evemtv/domain/entities/profile.dart';
import 'package:evemtv/domain/entities/source_credentials.dart';
import 'package:evemtv/domain/entities/vod.dart';
import 'package:evemtv/domain/entities/watch_progress.dart';
import 'package:evemtv/domain/parental/adult_content.dart';
import 'package:evemtv/domain/repositories/credential_store.dart';
import 'package:evemtv/domain/repositories/parental_repository.dart';
import 'package:evemtv/features/auth/application/session.dart';
import 'package:evemtv/features/catalog/catalog_providers.dart';
import 'package:evemtv/features/favorites/favorites.dart';
import 'package:evemtv/features/live/live_providers.dart';
import 'package:evemtv/features/parental/parental.dart';
import 'package:evemtv/features/parental/parental_widgets.dart';
import 'package:evemtv/features/parental/pin_hash.dart';
import 'package:evemtv/features/player/live_playback_controller.dart';
import 'package:evemtv/features/player/live_player_provider.dart';
import 'package:evemtv/features/player/watch_progress.dart';
import 'package:evemtv/features/search/catalog_sync.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fakes.dart';
import '../player/live_playback_controller_test.dart'
    show FakeEngine, FakeSource;

/// Catálogo ficticio con contenido de adultos por marca y por nombre.
class _AdultSource extends FakeSource {
  /// Sin conexión: el catálogo no se puede descargar.
  bool offline = false;

  void _check() {
    if (offline) throw StateError('sin conexión (simulado)');
  }

  static const liveCategories_ = [
    ContentCategory(id: 'c1', name: 'Deportes'),
    ContentCategory(id: 'c2', name: 'XXX Adultos'),
    ContentCategory(id: 'c3', name: 'Canales HOT'),
    ContentCategory(id: 'c4', name: 'Noticias'),
    ContentCategory(id: 'c5', name: 'Especial', adult: true),
  ];
  static const channels = [
    LiveChannel(id: '1', name: 'Fútbol Ficticio', categoryId: 'c1'),
    LiveChannel(id: '2', name: 'Adulto Uno', categoryId: 'c2'),
    LiveChannel(id: '3', name: 'Canal Marcado', categoryId: 'c1', adult: true),
    LiveChannel(id: '4', name: 'Noticias 24', categoryId: 'c4'),
    LiveChannel(id: '5', name: 'Especial Uno', categoryId: 'c5'),
    LiveChannel(id: '6', name: 'Picante Uno', categoryId: 'c3'),
  ];

  @override
  Future<List<ContentCategory>> liveCategories() async {
    _check();
    return liveCategories_;
  }

  @override
  Future<List<LiveChannel>> liveChannels({String? categoryId}) async {
    _check();
    return [
      for (final c in channels)
        if (categoryId == null || c.categoryId == categoryId) c,
    ];
  }

  @override
  Future<List<ContentCategory>> vodCategories() async {
    _check();
    return const [
      ContentCategory(id: 'm1', name: 'Estrenos'),
      ContentCategory(id: 'm2', name: 'Adultos +18'),
    ];
  }

  static final movies = [
    VodItem(
      id: '11',
      name: 'Película Familiar',
      categoryId: 'm1',
      added: DateTime.utc(2026, 9, 1),
    ),
    VodItem(
      id: '12',
      name: 'Película Adulta',
      categoryId: 'm2',
      added: DateTime.utc(2026, 9, 2),
    ),
    VodItem(
      id: '13',
      name: 'Película Marcada',
      categoryId: 'm1',
      adult: true,
      added: DateTime.utc(2026, 9, 3),
    ),
  ];

  @override
  Future<List<VodItem>> vodItems({String? categoryId}) async {
    _check();
    return [
      for (final m in movies)
        if (categoryId == null || m.categoryId == categoryId) m,
    ];
  }

  @override
  Future<List<ContentCategory>> seriesCategories() async {
    _check();
    return const [
      ContentCategory(id: 's1', name: 'Drama'),
      ContentCategory(id: 's2', name: 'Erótico'),
    ];
  }

  static const series = [
    SeriesItem(id: '21', name: 'Serie Familiar', categoryId: 's1'),
    SeriesItem(id: '22', name: 'Serie Adulta', categoryId: 's2'),
  ];

  @override
  Future<List<SeriesItem>> seriesItems({String? categoryId}) async {
    _check();
    return [
      for (final s in series)
        if (categoryId == null || s.categoryId == categoryId) s,
    ];
  }
}

/// Control parental en la base, con escrituras que pueden fallar.
class _FlakyRepository implements ParentalRepository {
  _FlakyRepository(this.inner);

  final ParentalRepository inner;
  bool failWrites = false;

  @override
  Future<ParentalRecord> read(int profileId) => inner.read(profileId);

  @override
  Future<void> write(int profileId, ParentalRecord record) {
    if (failWrites) throw StateError('disco lleno (simulado)');
    return inner.write(profileId, record);
  }
}

class _Credentials implements CredentialStore {
  _Credentials(this.value);

  final SourceCredentials value;

  @override
  Future<SourceCredentials?> read(int profileId) async => value;

  @override
  Future<void> write(int profileId, SourceCredentials credentials) async {}

  @override
  Future<void> delete(int profileId) async {}
}

void main() {
  late LogSink originalSink;
  late List<String> logs;
  setUp(() {
    originalSink = AppLogger.sink;
    logs = [];
    AppLogger.sink = (_, m) => logs.add(m);
  });
  tearDown(() => AppLogger.sink = originalSink);

  group('detección', () {
    test('por nombre de categoría: palabras completas, sin mayúsculas ni '
        'tildes', () {
      for (final name in [
        'XXX',
        '[XXX] VIP',
        'Adultos',
        'ADULT',
        'For Adults',
        '+18 Latino',
        'Cine 18+',
        'Porn',
        'Erótico',
        'EROTICO',
        'Hot',
        'Canales HOT',
        'VOD | Adultos',
      ]) {
        expect(AdultContent.isAdultName(name), isTrue, reason: name);
      }
      for (final name in [
        'Hotel',
        'Hotstar',
        'Deportes',
        'Series 2018',
        '18',
        'Top 18 Hits',
        'Adultez',
        'Photos',
        '',
      ]) {
        expect(AdultContent.isAdultName(name), isFalse, reason: name);
      }
    });

    test('por la marca del panel (is_adult), en cualquier formato', () {
      final categories = XtreamLiveParser.categories(
        jsonDecode(
          '[{"category_id":"1","category_name":"Especial","is_adult":"1"},'
          '{"category_id":"2","category_name":"Deportes","is_adult":0}]',
        ),
      );
      expect(categories.map((c) => c.adult), [true, false]);
      final channels = XtreamLiveParser.channels(
        jsonDecode(
          '[{"stream_id":1,"name":"A","is_adult":1},'
          '{"stream_id":2,"name":"B","is_adult":"true"},'
          '{"stream_id":3,"name":"C","is_adult":null},'
          '{"stream_id":4,"name":"D"}]',
        ),
      );
      expect(channels.map((c) => c.adult), [true, true, false, false]);
      expect(
        XtreamVodParser.movies(
          jsonDecode('[{"stream_id":1,"name":"P","is_adult":"1"}]'),
        ).single.adult,
        isTrue,
      );
      expect(
        XtreamVodParser.series(
          jsonDecode('[{"series_id":1,"name":"S","is_adult":1}]'),
        ).single.adult,
        isTrue,
      );
    });

    test('la categoría marcada por el panel o por nombre es automática', () {
      expect(
        ParentalState.isAutomatic(
          const ContentCategory(id: '1', name: 'Especial', adult: true),
        ),
        isTrue,
      );
      expect(
        ParentalState.isAutomatic(const ContentCategory(id: '1', name: 'XXX')),
        isTrue,
      );
      expect(
        ParentalState.isAutomatic(
          const ContentCategory(id: '1', name: 'Noticias'),
        ),
        isFalse,
      );
    });
  });

  test('PIN guardado como hash con sal', () {
    final a = PinHash.create('4821');
    final b = PinHash.create('4821');
    expect(a, isNot(contains('4821')));
    expect(a, isNot(b), reason: 'sal distinta');
    expect(PinHash.verify('4821', a), isTrue);
    expect(PinHash.verify('4822', a), isFalse);
    expect(PinHash.verify('4821', 'basura'), isFalse);
  });

  test('carruseles del inicio (novedades y mejor valoradas): la base no '
      'devuelve lo oculto', () async {
    final db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    addTearDown(db.close);
    await DriftProfileRepository(db).create(name: 'A', type: SourceType.xtream);
    final cache = DriftCatalogCache(db);
    await cache.replace(
      1,
      ContentKind.movie,
      const [
        ContentCategory(id: 'm1', name: 'Estrenos'),
        ContentCategory(id: 'm2', name: 'Adultos'),
      ],
      const [
        CatalogEntry(
          kind: ContentKind.movie,
          id: '1',
          name: 'Normal',
          categoryId: 'm1',
          year: 2026,
          rating: 7,
        ),
        CatalogEntry(
          kind: ContentKind.movie,
          id: '2',
          name: 'En categoría adulta',
          categoryId: 'm2',
          year: 2026,
          rating: 9,
        ),
        CatalogEntry(
          kind: ContentKind.movie,
          id: '3',
          name: 'Marcada',
          categoryId: 'm1',
          year: 2026,
          rating: 8,
          adult: true,
        ),
      ],
    );
    const hidden = HiddenContent(
      categories: {
        ContentKind.movie: {'m2'},
      },
    );
    List<String> ids(List<CatalogEntry> l) => [for (final e in l) e.id];
    expect(
      ids(
        await cache.recent(1, ContentKind.movie, minYear: 2026, hidden: hidden),
      ),
      ['1'],
    );
    expect(ids(await cache.topRated(1, ContentKind.movie, hidden: hidden)), [
      '1',
    ]);
    expect(
      ids(await cache.recentlyAdded(1, ContentKind.movie, hidden: hidden)),
      ['1'],
    );
    // Desbloqueado: todo.
    expect(await cache.topRated(1, ContentKind.movie), hasLength(3));
  });

  group('con una sesión', () {
    late AppDatabase db;
    late ProviderContainer root;
    late DateTime now;
    late _AdultSource source;
    late _FlakyRepository repo;

    setUp(() async {
      db = AppDatabase(
        DatabaseConnection(
          NativeDatabase.memory(),
          closeStreamsSynchronously: true,
        ),
      );
      await DriftProfileRepository(db)
          .create(name: 'Cuenta 1', type: SourceType.xtream);
      now = DateTime.utc(2026, 9, 26, 12);
      source = _AdultSource();
      repo = _FlakyRepository(DriftParentalRepository(db));
      root = ProviderContainer.test(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          parentalRepositoryProvider.overrideWithValue(repo),
          parentalClockProvider.overrideWithValue(() => now),
          credentialStoreProvider.overrideWithValue(
            _Credentials(
              XtreamCredentials(
                server: Uri.parse('http://panel.example.com'),
                username: 'usuarioDemo',
                password: 'claveDemo',
              ),
            ),
          ),
        ],
      );
      addTearDown(() async {
        root.dispose();
        await db.close();
      });
    });

    /// Contenedor de una sesión nueva del mismo perfil, con el catálogo
    /// local ya descargado.
    Future<ProviderContainer> session({
      bool sync = true,
      SessionLifetime? lifetime,
    }) async {
      final session = FixedSession().build()!;
      final c = sessionContainerFor(
        root,
        session,
        lifetime: lifetime,
        overrides: [contentSourceProvider.overrideWithValue(source)],
      );
      addTearDown(c.dispose);
      if (sync) await c.read(catalogSyncProvider.notifier).sync(force: true);
      // Lee lo guardado del control parental.
      c.read(parentalProvider);
      await Future<void>.delayed(Duration.zero);
      return c;
    }

    Future<List<String>> ids<T>(
      Future<List<T>> list,
      String Function(T) id,
    ) async => [for (final x in await list) id(x)];

    test('bloqueado por defecto: se oculta en categorías, listas, "todos", '
        'búsqueda, "Recién agregadas", "Seguir viendo" y favoritos; con el '
        'PIN aparece todo', () async {
      final c = await session();
      // Riverpod pausa lo que nadie escucha: como en la app, se escuchan.
      final sub = c.listen(continueWatchingProvider, (_, _) {});
      addTearDown(sub.close);
      final favSub = c.listen(favoritesProvider(FavoriteKind.live), (_, _) {});
      addTearDown(favSub.close);

      Future<void> expectLocked() async {
        expect(
          await ids(
            c.read(liveCategoriesProvider.future),
            (ContentCategory x) => x.id,
          ),
          ['c1', 'c4'],
          reason: 'XXX Adultos, Canales HOT y la marcada por el panel',
        );
        expect(
          await ids(
            c.read(liveChannelsProvider(null).future),
            (LiveChannel x) => x.id,
          ),
          ['1', '4'],
          reason: 'todos los canales, también para cambiar con las flechas',
        );
        expect(
          await ids(
            c.read(liveChannelsProvider('c1').future),
            (LiveChannel x) => x.id,
          ),
          ['1'],
          reason: 'canal marcado en una categoría normal',
        );
        expect(
          await ids(
            c.read(liveChannelsProvider('c2').future),
            (LiveChannel x) => x.id,
          ),
          isEmpty,
        );
        expect(
          await ids(
            c.read(vodCategoriesProvider.future),
            (ContentCategory x) => x.id,
          ),
          ['m1'],
        );
        expect(
          await ids(c.read(vodItemsProvider(null).future), (VodItem x) => x.id),
          ['11'],
        );
        expect(
          await ids(
            c.read(seriesCategoriesProvider.future),
            (ContentCategory x) => x.id,
          ),
          ['s1'],
        );
        expect(
          await ids(
            c.read(seriesItemsProvider(null).future),
            (SeriesItem x) => x.id,
          ),
          ['21'],
        );
        expect(
          await ids(c.read(recentMoviesProvider.future), (VodItem x) => x.id),
          ['11'],
        );
        expect(
          await ids(
            c.read(recentSeriesProvider.future),
            (SeriesItem x) => x.id,
          ),
          ['21'],
        );
        for (final query in ['adult', 'marcad', 'picante', 'especial']) {
          final results = await c.read(searchResultsProvider(query).future);
          expect(
            results.byKind.values.expand((e) => e),
            isEmpty,
            reason: 'búsqueda "$query"',
          );
        }
        final found = await c.read(searchResultsProvider('uno').future);
        expect(found.byKind.values.expand((e) => e), isEmpty);
      }

      // "Seguir viendo" y favoritos con contenido de adultos.
      final progress = DriftWatchProgressRepository(db);
      for (final p in [
        WatchProgress(
          kind: ProgressKind.movie,
          itemId: '11',
          title: 'Película Familiar',
          categoryId: 'm1',
          position: const Duration(minutes: 5),
          duration: const Duration(hours: 1),
          updatedAt: DateTime(2026, 9, 1),
        ),
        WatchProgress(
          kind: ProgressKind.movie,
          itemId: '12',
          title: 'Película Adulta',
          categoryId: 'm2',
          position: const Duration(minutes: 5),
          duration: const Duration(hours: 1),
          updatedAt: DateTime(2026, 9, 2),
        ),
        WatchProgress(
          kind: ProgressKind.movie,
          itemId: '13',
          title: 'Película Marcada',
          categoryId: 'm1',
          position: const Duration(minutes: 5),
          duration: const Duration(hours: 1),
          updatedAt: DateTime(2026, 9, 3),
        ),
        WatchProgress(
          kind: ProgressKind.episode,
          itemId: 'e1',
          title: 'Serie Adulta',
          categoryId: 's2',
          seriesId: '22',
          position: const Duration(minutes: 5),
          duration: const Duration(minutes: 40),
          updatedAt: DateTime(2026, 9, 4),
        ),
      ]) {
        await progress.save(1, p);
      }
      final favorites = DriftFavoritesRepository(db);
      for (final (id, cat) in [('1', 'c1'), ('2', 'c2'), ('3', 'c1')]) {
        await favorites.add(
          1,
          Favorite(
            kind: FavoriteKind.live,
            itemId: id,
            name: 'Canal $id',
            categoryId: cat,
            addedAt: DateTime(2026),
          ),
        );
      }

      await expectLocked();
      // Espera a que la lista de la base refleje lo guardado.
      for (var i = 0; i < 50; i++) {
        final all = c.read(allWatchProgressProvider).value ?? const [];
        if (all.length == 4) break;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      await c.read(hiddenContentProvider.future);
      expect(c.read(continueWatchingProvider).map((p) => p.itemId), ['11']);
      expect(
        (await c.read(favoritesProvider(FavoriteKind.live).future))
            .map((f) => f.itemId),
        ['1'],
      );

      // Con el PIN (0000 por defecto) aparece todo.
      final result = await c.read(parentalProvider.notifier).unlock('0000');
      expect(result, isA<ParentalOk>());
      expect(
        await ids(
          c.read(liveCategoriesProvider.future),
          (ContentCategory x) => x.id,
        ),
        ['c1', 'c2', 'c3', 'c4', 'c5'],
      );
      expect(
        await ids(
          c.read(liveChannelsProvider(null).future),
          (LiveChannel x) => x.id,
        ),
        ['1', '2', '3', '4', '5', '6'],
      );
      final all = await c.read(searchResultsProvider('uno').future);
      expect(all.byKind[ContentKind.live], hasLength(3));
      await c.read(hiddenContentProvider.future);
      expect(c.read(continueWatchingProvider), hasLength(4));
      expect(
        await c.read(favoritesProvider(FavoriteKind.live).future),
        hasLength(3),
      );

      // "Bloquear de nuevo": otra vez oculto.
      c.read(parentalProvider.notifier).lock();
      await expectLocked();
    });

    test('bloquear una categoría a mano la oculta; volver a mostrarla pide '
        'el PIN', () async {
      final c = await session();
      final parental = c.read(parentalProvider.notifier);
      await parental.blockCategory(ContentKind.live, 'c4');
      expect(
        await ids(
          c.read(liveCategoriesProvider.future),
          (ContentCategory x) => x.id,
        ),
        ['c1'],
      );
      expect(
        await ids(
          c.read(liveChannelsProvider(null).future),
          (LiveChannel x) => x.id,
        ),
        ['1'],
      );
      final found = await c.read(searchResultsProvider('noticias').future);
      expect(found.byKind.values.expand((e) => e), isEmpty);

      expect(
        await parental.unblockCategory(ContentKind.live, 'c4', '1234'),
        isA<ParentalWrong>(),
      );
      expect(c.read(parentalProvider).blocked, hasLength(1));
      expect(
        await parental.unblockCategory(ContentKind.live, 'c4', '0000'),
        isA<ParentalOk>(),
      );
      expect(
        await ids(
          c.read(liveCategoriesProvider.future),
          (ContentCategory x) => x.id,
        ),
        ['c1', 'c4'],
      );
      // Se guarda por perfil: una sesión nueva lo recuerda.
      await parental.blockCategory(ContentKind.movie, 'm1');
      final next = await session();
      expect(next.read(parentalProvider).blocked, {
        (kind: ContentKind.movie, id: 'm1'),
      });
    });

    test(
      'PIN por defecto 0000: sugiere cambiarlo una vez por sesión',
      () async {
        final c = await session();
        final parental = c.read(parentalProvider.notifier);
        expect(c.read(parentalProvider).defaultPin, isTrue);
        expect(
          await parental.unlock('0000'),
          isA<ParentalOk>().having((r) => r.suggestChangePin, 'sugiere', true),
        );
        parental
          ..lock()
          ..dismissSuggestion();
        expect(
          await parental.unlock('0000'),
          isA<ParentalOk>().having((r) => r.suggestChangePin, 'sugiere', false),
        );
      },
    );

    test('cambiar el PIN pide el actual; se guarda como hash y nunca en '
        'los logs', () async {
      final c = await session();
      final parental = c.read(parentalProvider.notifier);
      expect(await parental.changePin('1111', '4821'), isA<ParentalWrong>());
      expect(await parental.changePin('0000', '48'), isA<ParentalInvalidPin>());
      expect(
        await parental.changePin('0000', 'abcd'),
        isA<ParentalInvalidPin>(),
      );
      expect(await parental.changePin('0000', '4821'), isA<ParentalOk>());
      expect(c.read(parentalProvider).defaultPin, isFalse);

      expect(await parental.unlock('0000'), isA<ParentalWrong>());
      expect(
        await parental.unlock('4821'),
        isA<ParentalOk>().having((r) => r.suggestChangePin, 'sugiere', false),
      );
      final stored = await DriftParentalRepository(db).read(1);
      expect(stored.pinHash, isNot(contains('4821')));
      expect(PinHash.verify('4821', stored.pinHash!), isTrue);
      expect(logs.join('\n'), isNot(contains('4821')));
    });

    test(
      'olvidé mi PIN: con la contraseña de la cuenta vuelve a 0000',
      () async {
        final c = await session();
        final parental = c.read(parentalProvider.notifier);
        await parental.changePin('0000', '4821');
        expect(
          await parental.resetPinWithPassword('otraClave'),
          isA<ParentalWrong>(),
        );
        expect(
          await parental.resetPinWithPassword('claveDemo'),
          isA<ParentalOk>(),
        );
        expect(c.read(parentalProvider).defaultPin, isTrue);
        expect(await parental.unlock('4821'), isA<ParentalWrong>());
        expect(await parental.unlock('0000'), isA<ParentalOk>());
        expect(logs.join('\n'), isNot(contains('claveDemo')));
      },
    );

    test('la contraseña de una lista M3U', () {
      expect(
        ParentalController.accountPassword(
          M3uCredentials(
            playlist: Uri.parse(
              'http://lista.example.com/get.php?username=a&password=secreta',
            ),
          ),
        ),
        'secreta',
      );
      expect(
        ParentalController.accountPassword(
          M3uCredentials(playlist: Uri.parse('http://lista.example.com/a.m3u')),
        ),
        'http://lista.example.com/a.m3u',
      );
    });

    test('tras 5 intentos fallidos, 1 minuto de espera; si sigue fallando, '
        'más espera (también tras reabrir)', () async {
      final c = await session();
      final parental = c.read(parentalProvider.notifier);
      for (var left = 4; left >= 1; left--) {
        expect(
          await parental.unlock('9999'),
          isA<ParentalWrong>().having((r) => r.attemptsLeft, 'quedan', left),
        );
      }
      expect(
        await parental.unlock('9999'),
        isA<ParentalWait>().having(
          (r) => r.remaining,
          'espera',
          const Duration(minutes: 1),
        ),
      );
      // Durante la espera, ni el PIN correcto.
      now = now.add(const Duration(seconds: 30));
      expect(
        await parental.unlock('0000'),
        isA<ParentalWait>().having(
          (r) => r.remaining,
          'espera',
          const Duration(seconds: 30),
        ),
      );
      // Tampoco reabriendo la app.
      final reopened = await session();
      expect(
        await reopened.read(parentalProvider.notifier).unlock('0000'),
        isA<ParentalWait>(),
      );
      // Pasado el minuto, otro fallo: 2 minutos.
      now = now.add(const Duration(seconds: 31));
      expect(
        await parental.unlock('9999'),
        isA<ParentalWait>().having(
          (r) => r.remaining,
          'espera',
          const Duration(minutes: 2),
        ),
      );
      now = now.add(const Duration(minutes: 2));
      expect(await parental.unlock('0000'), isA<ParentalOk>());
      // Un acierto reinicia la cuenta.
      parental.lock();
      expect(
        await parental.unlock('9999'),
        isA<ParentalWrong>().having((r) => r.attemptsLeft, 'quedan', 4),
      );
    });

    test('el desbloqueo se pierde al cambiar de cuenta', () async {
      final a = await session();
      await a.read(parentalProvider.notifier).unlock('0000');
      expect(
        await ids(
          a.read(liveCategoriesProvider.future),
          (ContentCategory x) => x.id,
        ),
        hasLength(5),
      );
      // Otra sesión (cambiar de cuenta o volver a entrar): bloqueado.
      final b = await session();
      expect(b.read(parentalProvider).unlocked, isFalse);
      expect(
        await ids(
          b.read(liveCategoriesProvider.future),
          (ContentCategory x) => x.id,
        ),
        ['c1', 'c4'],
      );
    });

    testWidgets('"Contenido adulto" pide el PIN, sugiere cambiarlo y '
        '"Bloquear de nuevo" lo oculta', (tester) async {
      late ProviderContainer c;
      await tester.runAsync(() async => c = await session());
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) {
                  final categories =
                      ref.watch(liveCategoriesProvider).value ?? const [];
                  return Column(
                    children: [
                      for (final cat in categories) Text(cat.name),
                      const ParentalButton(),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      );
      Future<void> settle() async {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pumpAndSettle();
      }

      await settle();
      expect(find.text('Deportes'), findsOneWidget);
      expect(find.text('XXX Adultos'), findsNothing);

      await tester.tap(find.text('Contenido adulto'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '1234');
      await tester.tap(find.text('Aceptar'));
      await settle();
      expect(find.textContaining('PIN incorrecto'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '0000');
      await tester.tap(find.text('Aceptar'));
      await settle();
      // Sugerencia de cambiar el PIN de fábrica.
      expect(find.text('Cambia el PIN'), findsOneWidget);
      await tester.tap(find.text('Ahora no'));
      await settle();
      expect(find.text('XXX Adultos'), findsOneWidget);

      await tester.tap(find.text('Bloquear de nuevo'));
      await settle();
      expect(find.text('XXX Adultos'), findsNothing);
      expect(find.text('Contenido adulto'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    test('si no se puede guardar el PIN nuevo, se informa y queda el '
        'anterior (también al restablecer y al ocultar categorías)', () async {
      final c = await session();
      final parental = c.read(parentalProvider.notifier);
      expect(await parental.changePin('0000', '4821'), isA<ParentalOk>());

      repo.failWrites = true;
      final failed = await parental.changePin('4821', '1357');
      expect(failed, isA<ParentalSaveFailed>());
      expect(parentalErrorText(failed), contains('PIN anterior sigue vigente'));
      expect(
        await parental.resetPinWithPassword('claveDemo'),
        isA<ParentalSaveFailed>(),
      );
      expect(c.read(parentalProvider).defaultPin, isFalse);
      expect(await parental.blockCategory(ContentKind.live, 'c4'), isFalse);
      expect(c.read(parentalProvider).blocked, isEmpty);
      repo.failWrites = false;

      expect(await parental.unlock('1357'), isA<ParentalWrong>());
      expect(await parental.unlock('0000'), isA<ParentalWrong>());
      expect(await parental.unlock('4821'), isA<ParentalOk>());
    });

    test(
      'sin datos del catálogo local (antes de la primera descarga), '
      'favoritos y "Seguir viendo" se ocultan mientras esté bloqueado',
      () async {
        await DriftFavoritesRepository(db).add(
          1,
          Favorite(
            kind: FavoriteKind.live,
            itemId: '1',
            name: 'Fútbol Ficticio',
            categoryId: 'c1',
            addedAt: DateTime(2026),
          ),
        );
        await DriftWatchProgressRepository(db).save(
          1,
          WatchProgress(
            kind: ProgressKind.movie,
            itemId: '11',
            title: 'Película Familiar',
            categoryId: 'm1',
            position: const Duration(minutes: 5),
            duration: const Duration(hours: 1),
            updatedAt: DateTime(2026),
          ),
        );
        source.offline = true;
        final c = await session(sync: false);
        final subs = [
          c.listen(continueWatchingProvider, (_, _) {}),
          c.listen(favoritesProvider(FavoriteKind.live), (_, _) {}),
        ];
        addTearDown(() {
          for (final sub in subs) {
            sub.close();
          }
        });
        Future<void> settle() async {
          for (var i = 0; i < 50; i++) {
            if (c.read(allWatchProgressProvider).value?.isNotEmpty ?? false) {
              break;
            }
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
          await c.read(hiddenContentProvider.future);
        }

        await settle();
        expect(c.read(continueWatchingProvider), isEmpty);
        expect(
          await c.read(favoritesProvider(FavoriteKind.live).future),
          isEmpty,
        );
        // Desbloqueado se ven; tras descargar el catálogo, también bloqueado.
        await c.read(parentalProvider.notifier).unlock('0000');
        await settle();
        expect(c.read(continueWatchingProvider), hasLength(1));
        expect(
          await c.read(favoritesProvider(FavoriteKind.live).future),
          hasLength(1),
        );
        c.read(parentalProvider.notifier).lock();
        source.offline = false;
        await c.read(catalogSyncProvider.notifier).sync(force: true);
        await settle();
        expect(c.read(continueWatchingProvider), hasLength(1));
        expect(
          await c.read(favoritesProvider(FavoriteKind.live).future),
          hasLength(1),
        );
      },
    );

    test('una operación de una sesión que ya terminó no se aplica', () async {
      final lifetime = SessionLifetime();
      final c = await session(lifetime: lifetime);
      final parental = c.read(parentalProvider.notifier);
      lifetime.close();
      expect(
        await parental.changePin('0000', '4821'),
        isA<ParentalSessionClosed>(),
      );
      expect(await parental.unlock('0000'), isA<ParentalSessionClosed>());
      expect(
        await parental.resetPinWithPassword('claveDemo'),
        isA<ParentalSessionClosed>(),
      );
      expect(await parental.blockCategory(ContentKind.live, 'c4'), isFalse);
      final stored = await repo.read(1);
      expect(stored.pinHash, isNull);
      expect(stored.blocked, isEmpty);
      expect(stored.failedAttempts, 0);
    });

    testWidgets('los diálogos se abren sobre la app (fuera del contenedor '
        'de la sesión), actúan en esa sesión y se cierran si termina', (
      tester,
    ) async {
      final lifetime = SessionLifetime();
      late ProviderContainer c;
      await tester.runAsync(() async => c = await session(lifetime: lifetime));
      // Como en la app: el navegador (y los diálogos) están por encima del
      // contenedor de la sesión.
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: root,
          child: MaterialApp(
            home: UncontrolledProviderScope(
              container: c,
              child: Scaffold(
                body: Consumer(
                  builder: (context, ref, _) => Column(
                    children: [
                      TextButton(
                        onPressed: () => showChangePinDialog(context, ref),
                        child: const Text('abrir cambio'),
                      ),
                      TextButton(
                        onPressed: () => unlockAdultContent(context, ref),
                        child: const Text('abrir pin'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      Future<void> settle() async {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pumpAndSettle();
      }

      // Cambiar el PIN desde el diálogo funciona (usa el contenedor de la
      // sesión que lo abrió).
      await tester.tap(find.text('abrir cambio'));
      await tester.pumpAndSettle();
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), '0000');
      await tester.enterText(fields.at(1), '4821');
      await tester.enterText(fields.at(2), '4821');
      await tester.tap(find.text('Guardar'));
      await settle();
      expect(find.text('Cambiar PIN'), findsNothing);
      final stored = await tester.runAsync(() => repo.read(1));
      expect(PinHash.verify('4821', stored!.pinHash!), isTrue);

      // "Olvidé mi PIN" desde el diálogo del PIN también.
      await tester.tap(find.text('abrir pin'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Olvidé mi PIN'));
      await tester.pumpAndSettle();
      expect(find.text('Contraseña de la cuenta'), findsOneWidget);

      // Termina la sesión (cambio de cuenta): los dos diálogos se cierran.
      lifetime.close();
      await settle();
      expect(find.text('Contraseña de la cuenta'), findsNothing);
      expect(find.text('Contenido adulto'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  });

  test('al volver a bloquear, el reproductor quita los canales ocultos de '
      'las flechas y se detiene si el actual está oculto', () {
    LivePlaybackController player(int index) => LivePlaybackController(
      engine: FakeEngine(),
      source: FakeSource(),
      channels: _AdultSource.channels,
      initialIndex: index,
      allowedFormats: const [],
    );
    const locked = ParentalState(loaded: true);
    const categories = _AdultSource.liveCategories_;

    // Canal actual visible: sigue, y la lista solo tiene visibles.
    final a = player(0);
    expect(
      LivePlayerNotifier.keepPlayingAfterParental(locked, categories, a),
      isTrue,
    );
    expect(a.channels.map((c) => c.id), ['1', '4']);
    expect(a.channel.id, '1');
    expect(a.index, 0);

    // Canal actual oculto (categoría de adultos o marcado): se detiene.
    for (final i in [1, 2, 4, 5]) {
      expect(
        LivePlayerNotifier.keepPlayingAfterParental(
          locked,
          categories,
          player(i),
        ),
        isFalse,
        reason: _AdultSource.channels[i].name,
      );
    }
    // Categoría ocultada a mano mientras suena otro canal.
    final b = player(0);
    const manual = ParentalState(
      loaded: true,
      blocked: {(kind: ContentKind.live, id: 'c4')},
    );
    LivePlayerNotifier.keepPlayingAfterParental(manual, categories, b);
    expect(b.channels.map((c) => c.id), ['1']);
    // Sin las categorías no se puede saber: ante la duda, se detiene.
    expect(
      LivePlayerNotifier.keepPlayingAfterParental(locked, null, player(0)),
      isFalse,
    );
    // Desbloqueado: nada cambia.
    final d = player(1);
    expect(
      LivePlayerNotifier.keepPlayingAfterParental(
        const ParentalState(unlocked: true),
        categories,
        d,
      ),
      isTrue,
    );
    expect(d.channels, hasLength(6));
  });
}
