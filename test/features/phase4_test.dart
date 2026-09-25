// Fase 4: actualización del catálogo, seguir viendo, caché de imágenes,
// atajos y búsqueda. Datos ficticios.
import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:evemtv/core/images/image_disk_cache.dart';
import 'package:evemtv/core/logging/app_logger.dart';
import 'package:evemtv/core/router/app_router.dart';
import 'package:evemtv/core/theme/app_theme.dart';
import 'package:evemtv/core/widgets/keyboard_help.dart';
import 'package:evemtv/data/providers.dart';
import 'package:evemtv/data/storage/app_database.dart';
import 'package:evemtv/data/storage/drift_repositories.dart';
import 'package:evemtv/domain/entities/catalog.dart';
import 'package:evemtv/domain/entities/live.dart';
import 'package:evemtv/domain/entities/profile.dart';
import 'package:evemtv/domain/entities/vod.dart';
import 'package:evemtv/domain/entities/watch_progress.dart';
import 'package:evemtv/domain/repositories/content_source.dart';
import 'package:evemtv/features/auth/application/session.dart';
import 'package:evemtv/features/home/continue_watching_row.dart';
import 'package:evemtv/features/player/vod_player_screen.dart';
import 'package:evemtv/features/player/watch_progress.dart';
import 'package:evemtv/features/search/catalog_sync.dart';
import 'package:evemtv/features/search/search_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../helpers/fakes.dart';
import 'player/live_playback_controller_test.dart' show FakeSource;

/// Fuente con catálogo ficticio para la actualización y la búsqueda.
class _CatalogSource extends FakeSource {
  var downloads = 0;

  @override
  Future<List<ContentCategory>> liveCategories() async => const [
    ContentCategory(id: 'd', name: 'Deportes'),
  ];

  @override
  Future<List<LiveChannel>> liveChannels({String? categoryId}) async {
    downloads++;
    return const [
      LiveChannel(id: '1', name: 'Fútbol en Vivo', categoryId: 'd'),
      LiveChannel(id: '2', name: 'Noticias', categoryId: 'd'),
    ];
  }

  @override
  Future<List<ContentCategory>> vodCategories() async => const [];

  @override
  Future<List<VodItem>> vodItems({String? categoryId}) async => const [
    VodItem(id: '10', name: 'La Película del Fútbol', year: 2021),
  ];

  @override
  Future<List<ContentCategory>> seriesCategories() async => const [];

  @override
  Future<List<SeriesItem>> seriesItems({String? categoryId}) async => const [];
}

/// Catálogo cuyas películas esperan a [gate] (primera descarga lenta).
class _SlowMoviesSource extends _CatalogSource {
  final gate = Completer<void>();

  @override
  Future<List<VodItem>> vodItems({String? categoryId}) async {
    await gate.future;
    return super.vodItems(categoryId: categoryId);
  }
}

AppDatabase memoryDb() => AppDatabase(
  DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true),
);

void main() {
  late LogSink originalSink;
  setUp(() {
    originalSink = AppLogger.sink;
    AppLogger.sink = (_, _) {};
  });
  tearDown(() => AppLogger.sink = originalSink);

  group('actualización del catálogo', () {
    late AppDatabase db;
    late ProviderContainer c;
    late _CatalogSource source;

    setUp(() async {
      db = memoryDb();
      await DriftProfileRepository(db)
          .create(name: 'A', type: SourceType.xtream);
      source = _CatalogSource();
      c = ProviderContainer.test(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          sessionProvider.overrideWith(FixedSession.new),
          sessionContextProvider.overrideWithValue(testSessionContext()),
          contentSourceProvider.overrideWithValue(source),
        ],
      );
    });
    tearDown(() => db.close());

    test('descarga lo vencido, indexa y no repite si está al día', () async {
      final sync = c.read(catalogSyncProvider.notifier);
      await sync.sync();
      final state = c.read(catalogSyncProvider);
      expect(state.running, isFalse);
      expect(state.info.keys, containsAll(ContentKind.values));
      expect(state.info[ContentKind.live]!.itemCount, 2);

      final r = await c.read(catalogCacheProvider).search(1, 'futbol');
      expect(r.byKind[ContentKind.live], hasLength(1));
      expect(r.byKind[ContentKind.movie], hasLength(1));

      await sync.sync();
      expect(source.downloads, 1, reason: 'al día: no vuelve a descargar');
      await sync.sync(force: true);
      expect(source.downloads, 2);
    });

    test('al cambiar de cuenta, la nueva sesión sincroniza la suya', () async {
      final session = FixedSession().build()!;
      final a = sessionContainerFor(
        c,
        session,
        overrides: [contentSourceProvider.overrideWithValue(source)],
      );
      final old = a.read(catalogSyncProvider.notifier).sync();
      a.dispose();
      final b = sessionContainerFor(
        c,
        session,
        overrides: [contentSourceProvider.overrideWithValue(source)],
      );
      addTearDown(b.dispose);
      final fresh = b.read(catalogSyncProvider.notifier).sync();
      expect(identical(old, fresh), isFalse);
      await Future.wait([old, fresh]);
      expect(
        b.read(catalogSyncProvider).info.keys,
        containsAll(ContentKind.values),
      );
    });

    test('si la sesión termina a mitad de camino, no escribe', () async {
      final lifetime = SessionLifetime();
      final s = sessionContainerFor(
        c,
        FixedSession().build()!,
        lifetime: lifetime,
        overrides: [contentSourceProvider.overrideWithValue(source)],
      );
      final running = s.read(catalogSyncProvider.notifier).sync();
      lifetime.close();
      s.dispose();
      await running;
      final rows = await db.select(db.catalogItems).get();
      expect(rows, isEmpty);
    });
  });

  group('VodProgressTracker', () {
    late ProviderContainer c;
    late WatchProgressService service;
    late VodProgressTracker tracker;
    late AppDatabase db;

    const serie = SeriesItem(id: 's1', name: 'Serie Ficticia', categoryId: 'x');
    const e1 = Episode(id: 'e1', season: 1, number: 1, title: 'Piloto');
    const e2 = Episode(id: 'e2', season: 1, number: 2, title: 'Segundo');
    const peli = VodItem(id: 'm1', name: 'Película', categoryId: 'y');

    setUp(() async {
      db = memoryDb();
      await DriftProfileRepository(db)
          .create(name: 'A', type: SourceType.xtream);
      c = ProviderContainer.test(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          sessionProvider.overrideWith(FixedSession.new),
          sessionContextProvider.overrideWithValue(testSessionContext()),
        ],
      );
      service = c.read(watchProgressServiceProvider);
      tracker = VodProgressTracker(service);
    });
    tearDown(() => db.close());

    test('guarda, retoma 5 s antes y respeta "desde el principio"', () async {
      const target = MoviePlayable(peli);
      await tracker.save(
        target,
        position: const Duration(minutes: 37),
        duration: const Duration(hours: 2),
      );
      expect(
        await tracker.resumePosition(target),
        const Duration(minutes: 36, seconds: 55),
      );
      expect(
        await tracker.resumePosition(
          const MoviePlayable(peli, startOver: true),
        ),
        isNull,
      );
      final saved = await service.find(ProgressKind.movie, 'm1');
      expect(saved!.categoryId, 'y');
    });

    test('muy poco visto no se guarda; sin duración no se guarda', () async {
      await tracker.save(
        const MoviePlayable(peli),
        position: const Duration(seconds: 20),
        duration: const Duration(hours: 2),
      );
      await tracker.save(
        const MoviePlayable(peli),
        position: const Duration(minutes: 20),
        duration: Duration.zero,
      );
      expect(await service.find(ProgressKind.movie, 'm1'), isNull);
    });

    test(
      'al terminar un episodio se quita y queda listo el siguiente',
      () async {
        const target = EpisodePlayable(
          series: serie,
          episodes: [e1, e2],
          index: 0,
        );
        await tracker.save(
          target,
          position: const Duration(minutes: 20),
          duration: const Duration(minutes: 45),
        );
        expect(await service.find(ProgressKind.episode, 'e1'), isNotNull);
        await tracker.save(
          target,
          position: const Duration(minutes: 44, seconds: 30),
          duration: const Duration(minutes: 45),
        );
        expect(await service.find(ProgressKind.episode, 'e1'), isNull);
        final next = await service.find(ProgressKind.episode, 'e2');
        expect(next!.seriesId, 's1');
        expect(next.subtitle, 'T1 · E2 · Segundo');
        // El siguiente empieza de cero.
        expect(
          await tracker.resumePosition(
            const EpisodePlayable(series: serie, episodes: [e1, e2], index: 1),
          ),
          isNull,
        );
      },
    );
  });

  group('caché de imágenes en disco', () {
    late Directory dir;
    late FakeHttpAdapter http;
    late ImageDiskCache cache;
    const url =
        'http://img.example.com/movie/usuarioFicticio/claveFicticia/p.png';

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('evemtv_img_');
      http = FakeHttpAdapter((_) => ResponseBody.fromBytes(fakePng(1000), 200));
      cache = ImageDiskCache(
        directory: dir,
        key: List<int>.generate(32, (i) => i),
        dio: testDio(http),
        maxBytes: 3500,
        // La decodificación real se prueba aparte (necesita el motor).
        verifyDecodes: (_) async => true,
      );
    });
    tearDown(() => dir.delete(recursive: true));

    test('en disco no queda la URL: el nombre es un HMAC', () async {
      await cache.load(url);
      final files = dir.listSync().map((f) => f.uri.pathSegments.last).toList();
      expect(files, hasLength(1));
      expect(files.single, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(files.single, isNot(contains('claveFicticia')));
      expect(
        DiskCachedImage(url, cache).toString(),
        isNot(contains('claveFicticia')),
      );
    });

    test('la segunda carga sale del disco, sin red', () async {
      await cache.load(url);
      await cache.load(url);
      expect(http.requests, hasLength(1));
    });

    test('otra clave, otro nombre (no se puede adivinar la URL)', () {
      final other = ImageDiskCache(
        directory: dir,
        key: List<int>.filled(32, 1),
        dio: Dio(),
      );
      expect(other.fileNameFor(url), isNot(cache.fileNameFor(url)));
    });

    int diskBytes() => dir.listSync().whereType<File>().fold<int>(
      0,
      (a, f) => a + f.lengthSync(),
    );

    // Informe Codex Fase 4, punto 5: el tope se cumple en CADA escritura,
    // sin depender de una limpieza periódica (aquí nunca se llama a prune).
    test('el tope se cumple en cada escritura, sin llamar a prune', () async {
      String u(int i) => 'http://img.example.com/$i.png';
      for (var i = 0; i < 12; i++) {
        await cache.load(u(i));
        expect(diskBytes(), lessThanOrEqualTo(3500), reason: 'escritura $i');
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      // Se borraron las usadas hace más tiempo; la última sigue.
      final names = dir.listSync().map((f) => f.uri.pathSegments.last);
      expect(names, contains(cache.fileNameFor(u(11))));
      expect(names, isNot(contains(cache.fileNameFor(u(0)))));
    });

    test('prune deja una carpeta sobredimensionada en el 80 %', () async {
      for (var i = 0; i < 5; i++) {
        File('${dir.path}/viejo$i').writeAsBytesSync(fakePng(1000));
      }
      await cache.prune();
      expect(diskBytes(), lessThanOrEqualTo(3500 * 0.8));
    });

    test('imágenes enormes no se guardan', () async {
      http.handler = (_) =>
          ResponseBody.fromBytes(List<int>.filled(6 * 1024 * 1024, 1), 200);
      await expectLater(cache.load(url), throwsA(isA<FormatException>()));
      expect(dir.listSync(), isEmpty);
    });
  });

  group('ayuda de atajos', () {
    Future<void> pump(WidgetTester tester) => tester.pumpWidget(
      MaterialApp(
        home: ScreenShortcuts(
          title: 'Prueba',
          help: const [(keys: 'X', action: 'Acción de prueba')],
          child: const Scaffold(
            body: Column(
              children: [
                Focus(autofocus: true, child: Text('foco')),
                TextField(),
              ],
            ),
          ),
        ),
      ),
    );

    testWidgets('? y F1 muestran la ayuda', (tester) async {
      await pump(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.f1);
      await tester.pumpAndSettle();
      expect(find.text('Acción de prueba'), findsOneWidget);
      expect(find.text('Mostrar esta ayuda'), findsOneWidget);
      await tester.tap(find.text('Cerrar'));
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.slash, character: '?');
      await tester.pumpAndSettle();
      expect(find.text('Acción de prueba'), findsOneWidget);
    });

    testWidgets('mientras se escribe, ? no abre la ayuda', (tester) async {
      await pump(tester);
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.slash, character: '?');
      await tester.pumpAndSettle();
      expect(find.text('Acción de prueba'), findsNothing);
    });
  });

  group('pantallas', () {
    late AppDatabase db;
    Object? pushedExtra;
    String? pushedRoute;

    Future<void> pumpApp(
      WidgetTester tester,
      Widget home, {
      ContentSource? source,
      bool settle = true,
    }) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      pushedExtra = null;
      pushedRoute = null;
      Widget capture(String route, GoRouterState s) {
        pushedRoute = route;
        pushedExtra = s.extra;
        return Text('DESTINO $route');
      }

      final router = GoRouter(
        initialLocation: '/inicio',
        routes: [
          GoRoute(
            path: '/inicio',
            builder: (_, _) => Scaffold(body: home),
          ),
          GoRoute(path: AppRoutes.home, builder: (_, s) => capture('home', s)),
          GoRoute(
            path: AppRoutes.movieDetail,
            builder: (_, s) => capture('peli', s),
          ),
          GoRoute(
            path: AppRoutes.seriesDetail,
            builder: (_, s) => capture('serie', s),
          ),
          GoRoute(
            path: AppRoutes.livePlayer,
            builder: (_, s) => capture('vivo', s),
          ),
          GoRoute(
            path: AppRoutes.vodPlayer,
            builder: (_, s) => capture('play', s),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          retry: (_, _) => null,
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            sessionProvider.overrideWith(FixedSession.new),
            sessionContextProvider.overrideWithValue(testSessionContext()),
            contentSourceProvider.overrideWithValue(source ?? _CatalogSource()),
          ],
          child: MaterialApp.router(
            theme: AppTheme.dark(),
            routerConfig: router,
          ),
        ),
      );
      if (settle) await tester.pumpAndSettle();
    }

    setUp(() async {
      db = memoryDb();
    });

    Future<void> seed(WidgetTester tester) => tester.runAsync(() async {
      await DriftProfileRepository(db)
          .create(name: 'A', type: SourceType.xtream);
      final cache = DriftCatalogCache(db);
      await cache.replace(1, ContentKind.live, const [], const [
        CatalogEntry(kind: ContentKind.live, id: '1', name: 'Fútbol en Vivo'),
      ]);
      await cache.replace(1, ContentKind.movie, const [], const [
        CatalogEntry(
          kind: ContentKind.movie,
          id: '10',
          name: 'La Película del Fútbol',
          year: 2021,
        ),
      ]);
    });

    testWidgets('búsqueda: resultados agrupados y abre la ficha', (
      tester,
    ) async {
      await seed(tester);
      await pumpApp(tester, const SearchScreen());
      await tester.enterText(find.byType(TextField), 'futbol');
      await tester.pump(SearchScreenTiming.debounce);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      expect(find.text('En vivo (1)'), findsOneWidget);
      expect(find.text('Películas (1)'), findsOneWidget);

      await tester.tap(find.text('La Película del Fútbol'));
      await tester.pumpAndSettle();
      expect(pushedRoute, 'peli');
      expect((pushedExtra! as VodItem).id, '10');
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(db.close);
    });

    testWidgets('búsqueda: abre con el texto de "Buscar en todo el catálogo"', (
      tester,
    ) async {
      await seed(tester);
      await pumpApp(tester, const SearchScreen(initialQuery: 'futbol'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      expect(find.text('futbol'), findsOneWidget);
      expect(find.text('Películas (1)'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(db.close);
    });

    testWidgets(
      'búsqueda: en la primera descarga espera al catálogo completo',
      (tester) async {
        await tester.runAsync(
          () =>
              DriftProfileRepository(db)
                  .create(name: 'A', type: SourceType.xtream),
        );
        final source = _SlowMoviesSource();
        await pumpApp(
          tester,
          const SearchScreen(initialQuery: 'futbol'),
          source: source,
          settle: false,
        );
        await settleIo(tester);

        // En vivo ya está, películas se está descargando: no se busca.
        expect(find.text('Preparando la búsqueda'), findsOneWidget);
        expect(find.textContaining('Descargando películas'), findsOneWidget);
        expect(tester.widget<TextField>(find.byType(TextField)).enabled, false);
        expect(find.textContaining('Nada coincide'), findsNothing);
        expect(find.text('En vivo (1)'), findsNothing);

        // Al terminar, se busca lo que se había escrito.
        source.gate.complete();
        await settleIo(tester);
        await tester.pumpAndSettle();
        expect(tester.widget<TextField>(find.byType(TextField)).enabled, true);
        expect(find.text('En vivo (1)'), findsOneWidget);
        expect(find.text('Películas (1)'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(db.close);
      },
    );

    testWidgets('búsqueda: un canal abre el reproductor con ese canal', (
      tester,
    ) async {
      await seed(tester);
      await pumpApp(tester, const SearchScreen());
      await tester.enterText(find.byType(TextField), 'vivo');
      await tester.pump(SearchScreenTiming.debounce);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fútbol en Vivo'));
      await tester.pumpAndSettle();
      expect(pushedRoute, 'vivo');
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(db.close);
    });

    testWidgets('seguir viendo: tarjeta, retomar y quitar', (tester) async {
      await tester.runAsync(() async {
        await DriftProfileRepository(db)
            .create(name: 'A', type: SourceType.xtream);
        await DriftWatchProgressRepository(db).save(
          1,
          WatchProgress(
            kind: ProgressKind.movie,
            itemId: 'm1',
            title: 'Película a medias',
            position: const Duration(minutes: 30),
            duration: const Duration(hours: 2),
            updatedAt: DateTime(2026),
            containerExtension: 'mkv',
          ),
        );
      });
      await pumpApp(tester, const ContinueWatchingRow());
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Seguir viendo'), findsOneWidget);
      expect(find.text('Película a medias'), findsWidgets);
      expect(find.text('Quedan 1 h 30 min'), findsOneWidget);

      await tester.tap(find.text('Película a medias').last);
      await tester.pumpAndSettle();
      expect(pushedRoute, 'play');
      final playable = pushedExtra! as MoviePlayable;
      expect(playable.movie.containerExtension, 'mkv');
      expect(playable.startOver, isFalse);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(db.close);
    });
  });
}
