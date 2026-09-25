// Carrusel de novedades del inicio. Datos ficticios.
import 'dart:async';

import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:evemtv/core/logging/app_logger.dart';
import 'package:evemtv/core/theme/app_theme.dart';
import 'package:evemtv/data/providers.dart';
import 'package:evemtv/data/storage/app_database.dart';
import 'package:evemtv/data/storage/drift_repositories.dart';
import 'package:evemtv/data/xtream/xtream_vod_parser.dart';
import 'package:evemtv/domain/entities/catalog.dart';
import 'package:evemtv/domain/entities/live.dart';
import 'package:evemtv/domain/entities/profile.dart';
import 'package:evemtv/domain/entities/vod.dart';
import 'package:evemtv/features/auth/application/session.dart';
import 'package:evemtv/features/home/featured.dart';
import 'package:evemtv/features/home/featured_carousel.dart';
import 'package:evemtv/features/search/catalog_sync.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fakes.dart';
import '../player/live_playback_controller_test.dart' show FakeSource;

/// Catálogo ya leído y sin descargas en curso.
class _LoadedSync extends CatalogSyncController {
  @override
  CatalogSyncState build() => const CatalogSyncState(loaded: true);
}

/// Listas por categoría con pósters ficticios (algunas sin póster).
class _PosterSource extends FakeSource {
  @override
  Future<List<VodItem>> vodItems({String? categoryId}) async => [
    for (var i = 0; i < 10; i++)
      VodItem(
        id: 'm$i',
        name: 'Película $i',
        categoryId: categoryId,
        posterUrl: i == 3 ? null : 'http://img.example.com/m$i.jpg',
      ),
  ];

  @override
  Future<List<SeriesItem>> seriesItems({String? categoryId}) async => [
    for (var i = 0; i < 10; i++)
      SeriesItem(
        id: 's$i',
        name: 'Serie $i',
        categoryId: categoryId,
        posterUrl: 'http://img.example.com/s$i.jpg',
      ),
  ];

  @override
  Future<List<LiveChannel>> liveChannels({String? categoryId}) async =>
      const [];
}

CatalogEntry _movie(int i, int? year) => CatalogEntry(
  kind: ContentKind.movie,
  id: 'm$i',
  name: 'Película $i',
  categoryId: 'c',
  year: year,
);

CatalogEntry _series(int i, int? year) => CatalogEntry(
  kind: ContentKind.series,
  id: 's$i',
  name: 'Serie $i',
  categoryId: 'c',
  year: year,
);

void main() {
  late LogSink originalSink;
  setUp(() {
    originalSink = AppLogger.sink;
    AppLogger.sink = (_, _) {};
    FeaturedRules.clock = () => DateTime(2026, 9, 25);
  });
  tearDown(() {
    AppLogger.sink = originalSink;
    FeaturedRules.clock = DateTime.now;
  });

  test('fecha de alta del servidor (segundos Unix)', () {
    final movies = XtreamVodParser.movies([
      {'stream_id': 1, 'name': 'A', 'added': '1767225600'},
      {'stream_id': 2, 'name': 'B', 'added': '0'},
      {'stream_id': 3, 'name': 'C', 'added': 'basura'},
    ]);
    expect(movies.first.added, DateTime.utc(2026));
    expect(movies[1].added, isNull);
    expect(movies[2].added, isNull);
    final series = XtreamVodParser.series([
      {'series_id': 5, 'name': 'S', 'last_modified': 1767225600},
    ]);
    expect(series.single.added, DateTime.utc(2026));
  });

  group('año en el nombre', () {
    test('entre paréntesis, corchetes o tras un guion', () {
      expect(XtreamVodParser.yearInName('Película (2026)'), 2026);
      expect(XtreamVodParser.yearInName('Película [2025] 4K'), 2025);
      expect(XtreamVodParser.yearInName('Película - 2026'), 2026);
      expect(XtreamVodParser.yearInName('Blade Runner 2049'), isNull);
      expect(XtreamVodParser.yearInName('Película (1800)'), isNull);
      expect(XtreamVodParser.yearInName(null), isNull);
    });

    test('se usa si el panel no llena el campo del año', () {
      final movies = XtreamVodParser.movies([
        {'stream_id': 1, 'name': 'Estreno (2026)'},
        {'stream_id': 2, 'name': 'Otra (2026)', 'year': '2024'},
      ]);
      expect(movies.map((m) => m.year), [2026, 2024]);
      final series = XtreamVodParser.series([
        {'series_id': 5, 'name': 'Serie Nueva [2026]'},
      ]);
      expect(series.single.year, 2026);
    });
  });

  group('novedades desde el catálogo local', () {
    late AppDatabase db;
    late ProviderContainer c;

    setUp(() async {
      db = AppDatabase(
        DatabaseConnection(
          NativeDatabase.memory(),
          closeStreamsSynchronously: true,
        ),
      );
      await DriftProfileRepository(db)
          .create(name: 'A', type: SourceType.xtream);
      c = ProviderContainer.test(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          sessionContextProvider.overrideWithValue(testSessionContext()),
          contentSourceProvider.overrideWithValue(_PosterSource()),
        ],
      );
    });
    tearDown(() => db.close());

    /// Como en el inicio: con alguien escuchando (el carrusel).
    Future<List<FeaturedItem>> featured(ContentKind kind) {
      c.listen(featuredProvider(kind), (_, _) {});
      return c.read(featuredProvider(kind).future);
    }

    test(
      'recent: del año pedido en adelante, los más nuevos primero',
      () async {
        final cache = DriftCatalogCache(db);
        await cache.replace(1, ContentKind.movie, const [], [
          _movie(0, 2026),
          _movie(1, 2024),
          _movie(2, 2026),
          _movie(3, null),
          _movie(4, 2025),
        ]);
        final r = await cache.recent(1, ContentKind.movie, minYear: 2025);
        // 2026 primero (el último de la lista del servidor antes), luego 2025.
        expect(r.map((e) => e.id), ['m2', 'm0', 'm4']);
      },
    );

    test('estrenos recién agregados: primero lo último que subió el '
        'servidor, sin películas viejas', () async {
      CatalogEntry dated(String id, int year, int month) => CatalogEntry(
        kind: ContentKind.movie,
        id: id,
        name: id,
        categoryId: 'c',
        year: year,
        added: DateTime.utc(2026, month),
      );
      final cache = DriftCatalogCache(db);
      await cache.replace(1, ContentKind.movie, const [], [
        dated('enero', 2026, 1),
        dated('septiembre', 2026, 9),
        dated('agosto-2025', 2025, 8),
        // Vieja subida hace poco: no es un estreno.
        dated('vieja', 1995, 9),
        _movie(7, 2026), // sin fecha de alta: al final
      ]);
      final r = await cache.recent(1, ContentKind.movie, minYear: 2025);
      expect(r.map((e) => e.id), ['septiembre', 'agosto-2025', 'enero', 'm7']);
    });

    test('películas y series por separado, del año y con póster', () async {
      final cache = DriftCatalogCache(db);
      await cache.replace(1, ContentKind.movie, const [], [
        for (var i = 0; i < 5; i++) _movie(i, 2026),
        _movie(8, 2020),
      ]);
      await cache.replace(1, ContentKind.series, const [], [
        for (var i = 0; i < 3; i++) _series(i, 2026),
      ]);
      final movies = await featured(ContentKind.movie);
      // Más nuevas primero; m3 (sin póster) y la de 2020 quedan fuera.
      expect(movies.map((i) => i.entry.id), ['m4', 'm2', 'm1', 'm0']);
      expect(movies.every((i) => i.posterUrl.startsWith('http://')), isTrue);
      final series = await featured(ContentKind.series);
      expect(series.map((i) => i.entry.id), ['s2', 's1', 's0']);
    });

    test('a principios de año, sin nada del año ni del anterior, las de '
        'mejor puntaje', () async {
      FeaturedRules.clock = () => DateTime(2027, 1, 1);
      final cache = DriftCatalogCache(db);
      await cache.replace(1, ContentKind.movie, const [], [
        _movie(0, 2026),
        const CatalogEntry(
          kind: ContentKind.movie,
          id: 'm1',
          name: 'Clásica',
          categoryId: 'c',
          year: 1999,
          rating: 9.1,
        ),
        const CatalogEntry(
          kind: ContentKind.movie,
          id: 'm2',
          name: 'Buena',
          categoryId: 'c',
          rating: 7.5,
        ),
        _movie(4, 2010),
      ]);
      final items = await featured(ContentKind.movie);
      // Primero la de 2026 (año anterior), después por puntaje.
      expect(items.map((i) => i.entry.id), ['m0', 'm1', 'm2']);
      expect(FeaturedRules.title('Películas', items), 'Películas destacadas');
    });

    test('mejor valoradas: de los últimos años, intercaladas y por '
        'puntaje', () async {
      CatalogEntry rated(ContentKind kind, String id, int year, double r) =>
          CatalogEntry(
            kind: kind,
            id: id,
            name: id,
            categoryId: 'c',
            year: year,
            rating: r,
          );
      final cache = DriftCatalogCache(db);
      await cache.replace(1, ContentKind.movie, const [], [
        rated(ContentKind.movie, 'm1', 2024, 8.0),
        rated(ContentKind.movie, 'm2', 2025, 9.0),
        // Clásico muy bien puntuado, pero fuera de los últimos 5 años.
        rated(ContentKind.movie, 'm3', 1990, 9.9),
        rated(ContentKind.movie, 'm4', 2026, 7.0),
      ]);
      await cache.replace(1, ContentKind.series, const [], [
        rated(ContentKind.series, 's1', 2023, 8.5),
        rated(ContentKind.series, 's2', 2026, 6.0),
        rated(ContentKind.series, 's3', 2022, 7.5),
      ]);
      c.listen(topRatedProvider, (_, _) {});
      final items = await c.read(topRatedProvider.future);
      expect(items.map((i) => i.entry.id), [
        'm2',
        's1',
        'm1',
        's3',
        'm4',
        's2',
      ]);
    });

    test('el título sigue al año del reloj', () {
      FeaturedItem item(int? year) =>
          (entry: _movie(0, year), posterUrl: 'http://img.example.com/0.jpg');
      FeaturedRules.clock = () => DateTime(2027, 1, 1);
      expect(
        FeaturedRules.title('Películas', [item(2027)]),
        'Películas nuevas 2027',
      );
      expect(
        FeaturedRules.title('Series', [item(2027), item(2026)]),
        'Series recientes',
      );
      expect(
        FeaturedRules.title('Series', [item(2027), item(null)]),
        'Series destacadas',
      );
    });

    test('con pocas del año se suman las del anterior', () async {
      final cache = DriftCatalogCache(db);
      await cache.replace(1, ContentKind.movie, const [], [
        _movie(0, 2026),
        _movie(1, 2025),
        _movie(2, 2025),
        _movie(4, 2025),
        _movie(5, 2025),
        _movie(6, 2025),
      ]);
      final items = await featured(ContentKind.movie);
      expect(items.first.entry.id, 'm0');
      expect(items.map((i) => i.entry.year).toSet(), {2026, 2025});
    });
  });

  group('carrusel apilado', () {
    final items = <FeaturedItem>[
      for (var i = 0; i < 4; i++)
        (entry: _movie(i, 2026), posterUrl: 'http://img.example.com/$i.jpg'),
    ];

    /// La barra de avance se anima sin parar: en lugar de pumpAndSettle,
    /// se deja terminar la animación de las tarjetas (420 ms).
    Future<void> settle(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }

    Future<List<CatalogEntry>> pump(WidgetTester tester) async {
      final opened = <CatalogEntry>[];
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: Scaffold(
              body: Center(
                child: StackedCarousel(
                  items: items,
                  cardHeight: 300,
                  onOpen: opened.add,
                ),
              ),
            ),
          ),
        ),
      );
      await settle(tester);
      return opened;
    }

    /// Título visible (el de la tarjeta del frente, con opacidad 1).
    String frontTitle(WidgetTester tester) {
      for (final i in items) {
        final title = find.text(i.entry.name);
        // Todas las tarjetas visibles tienen el título, pero solo la del
        // frente lo muestra (su opacidad y la de la tarjeta valen 1).
        final opacities = tester
            .widgetList<AnimatedOpacity>(
              find.ancestor(of: title, matching: find.byType(AnimatedOpacity)),
            )
            .map((o) => o.opacity);
        if (opacities.every((o) => o == 1)) return i.entry.name;
      }
      return '';
    }

    testWidgets('barra de avance, clic atrás y clic en la del frente', (
      tester,
    ) async {
      final opened = await pump(tester);
      expect(frontTitle(tester), 'Película 0');
      expect(find.text('1 / 4'), findsOneWidget);

      // Sin flechas: la barra lleva a esa parte de la lista.
      expect(find.byTooltip('Siguiente'), findsNothing);
      expect(find.byTooltip('Anterior'), findsNothing);
      final bar = tester.getRect(find.byKey(const ValueKey('barra-novedades')));
      await tester.tapAt(Offset(bar.left + bar.width * 0.9, bar.center.dy));
      await settle(tester);
      expect(frontTitle(tester), 'Película 3');
      expect(find.text('4 / 4'), findsOneWidget);

      await tester.tapAt(
        tester.getCenter(find.byType(StackedCarousel)) + const Offset(40, -40),
      );
      await settle(tester);
      expect(opened.single.id, 'm3');

      // Un clic en lo que asoma de la última de atrás la trae al frente.
      final box = tester.getRect(find.byType(StackedCarousel));
      await tester.tapAt(Offset(box.left + 10, box.top + 150));
      await settle(tester);
      expect(frontTitle(tester), 'Película 1');
      expect(opened, hasLength(1));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('si la lista se acorta vuelve a la primera y lo avisa', (
      tester,
    ) async {
      final changes = <int>[];
      Widget carousel(List<FeaturedItem> list) => ProviderScope(
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: Center(
              child: StackedCarousel(
                items: list,
                cardHeight: 300,
                onOpen: (_) {},
                onChanged: changes.add,
              ),
            ),
          ),
        ),
      );
      await tester.pumpWidget(carousel(items));
      await settle(tester);
      final bar = tester.getRect(find.byKey(const ValueKey('barra-novedades')));
      await tester.tapAt(Offset(bar.left + bar.width * 0.9, bar.center.dy));
      await settle(tester);
      expect(changes.last, 3);

      await tester.pumpWidget(carousel(items.take(2).toList()));
      await settle(tester);
      expect(changes.last, 0);
      expect(frontTitle(tester), 'Película 0');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('avanza solo cada 3 s y se detiene con el mouse encima', (
      tester,
    ) async {
      expect(FeaturedCarousel.interval, const Duration(seconds: 3));
      await pump(tester);
      await tester.pump(FeaturedCarousel.interval);
      await settle(tester);
      expect(frontTitle(tester), 'Película 1');

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(
        location: tester.getCenter(find.byType(StackedCarousel)),
      );
      await tester.pump();
      await tester.pump(FeaturedCarousel.interval * 2);
      await settle(tester);
      expect(frontTitle(tester), 'Película 1');
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('sin redibujado continuo; en pausa con la ventana inactiva', (
      tester,
    ) async {
      await pump(tester);
      // Entre un avance y otro no queda ningún cuadro pendiente.
      expect(tester.binding.hasScheduledFrame, isFalse);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump(FeaturedCarousel.interval * 3);
      await settle(tester);
      expect(frontTitle(tester), 'Película 0');

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(FeaturedCarousel.interval);
      await settle(tester);
      expect(frontTitle(tester), 'Película 1');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('mientras carga se ven tarjetas de muestra', (tester) async {
      final loading = Completer<List<FeaturedItem>>();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionContextProvider.overrideWithValue(testSessionContext()),
            catalogSyncProvider.overrideWith(_LoadedSync.new),
            featuredProvider.overrideWith((ref, kind) => loading.future),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const Scaffold(
              body: FeaturedCarousel(kind: ContentKind.series),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(CarouselSkeleton), findsOneWidget);
      expect(find.text('Series nuevas'), findsOneWidget);

      loading.complete([
        (entry: _series(1, 2026), posterUrl: 'http://img.example.com/1.jpg'),
      ]);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(CarouselSkeleton), findsNothing);
      expect(find.text('Series nuevas 2026'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
