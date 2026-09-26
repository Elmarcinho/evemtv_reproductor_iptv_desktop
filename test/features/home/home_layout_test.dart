// Inicio: arreglo según haya o no "Seguir viendo". Datos ficticios.
import 'dart:async';

import 'package:evemtv/core/logging/app_logger.dart';
import 'package:evemtv/core/theme/app_theme.dart';
import 'package:evemtv/core/utils/text_format.dart';
import 'package:evemtv/data/providers.dart';
import 'package:evemtv/domain/entities/catalog.dart';
import 'package:evemtv/domain/entities/watch_progress.dart';
import 'package:evemtv/domain/repositories/settings_repository.dart';
import 'package:evemtv/features/auth/application/session.dart';
import 'package:evemtv/features/home/continue_watching_row.dart';
import 'package:evemtv/features/home/featured.dart';
import 'package:evemtv/features/home/featured_carousel.dart';
import 'package:evemtv/features/home/home_screen.dart';
import 'package:evemtv/features/home/promo_banner.dart';
import 'package:evemtv/features/player/watch_progress.dart';
import 'package:evemtv/features/search/catalog_sync.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fakes.dart';
import '../player/live_playback_controller_test.dart' show FakeSource;

class _MemorySettings implements SettingsRepository {
  final values = <String, String>{};

  @override
  Future<String?> get(String key) async => values[key];

  @override
  Future<void> set(String key, String value) async => values[key] = value;
}

/// Catálogo local ya descargado, con cantidades.
class _SyncedCatalog extends CatalogSyncController {
  @override
  CatalogSyncState build() => CatalogSyncState(
    loaded: true,
    info: {
      ContentKind.live: CatalogSyncInfo(
        syncedAt: DateTime(2026),
        itemCount: 1240,
      ),
      ContentKind.movie: CatalogSyncInfo(
        syncedAt: DateTime(2026),
        itemCount: 8300,
      ),
      ContentKind.series: CatalogSyncInfo(
        syncedAt: DateTime(2026),
        itemCount: 1,
      ),
    },
  );
}

void main() {
  late LogSink originalSink;
  setUp(() {
    originalSink = AppLogger.sink;
    AppLogger.sink = (_, _) {};
  });
  tearDown(() => AppLogger.sink = originalSink);

  test('nombres sin el año del final y miles con punto', () {
    expect(TextFormat.withoutYear('Película (2026)'), 'Película');
    expect(TextFormat.withoutYear('Serie [2025]'), 'Serie');
    expect(TextFormat.withoutYear('Otra - 2026'), 'Otra');
    expect(TextFormat.withoutYear('Blade Runner 2049'), 'Blade Runner 2049');
    expect(TextFormat.withoutYear('(2026)'), '(2026)');
    expect(
      TextFormat.displayName(
        'La muerte de Robin Hood - The Death of Robin Hood (2026) FHD Latino',
      ),
      'La muerte de Robin Hood - The Death of Robin Hood',
    );
    expect(TextFormat.displayName('BTS EL REGRESO FHD'), 'BTS EL REGRESO');
    expect(TextFormat.displayName('Avatar 4K'), 'Avatar');
    expect(TextFormat.displayName('Lalka - La Muñeca'), 'Lalka - La Muñeca');
    expect(TextFormat.displayName('HD'), 'HD');
    expect(TextFormat.thousands(1240), '1.240');
    expect(TextFormat.thousands(1234567), '1.234.567');
    expect(TextFormat.thousands(999), '999');
  });

  Future<StreamController<List<WatchProgress>>> pumpHome(
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final progress = StreamController<List<WatchProgress>>();
    addTearDown(progress.close);
    FeaturedItem item(ContentKind kind, int i) => (
      entry: CatalogEntry(
        kind: kind,
        id: '${kind.name}$i',
        name: '${kind == ContentKind.movie ? 'Película' : 'Serie'} $i (2026)',
        categoryId: 'c',
        year: 2026,
      ),
      posterUrl: 'http://img.example.com/$i.jpg',
    );
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          ...parentalTestOverrides(),
          sessionContextProvider.overrideWithValue(testSessionContext()),
          contentSourceProvider.overrideWithValue(FakeSource()),
          catalogSyncProvider.overrideWith(_SyncedCatalog.new),
          settingsRepositoryProvider.overrideWithValue(_MemorySettings()),
          allWatchProgressProvider.overrideWith((ref) => progress.stream),
          featuredProvider.overrideWith(
            (ref, kind) async => [for (var i = 0; i < 3; i++) item(kind, i)],
          ),
          topRatedProvider.overrideWith(
            (ref) async => [
              item(ContentKind.movie, 7),
              item(ContentKind.series, 8),
            ],
          ),
        ],
        child: MaterialApp(theme: AppTheme.dark(), home: const HomeScreen()),
      ),
    );
    await tester.pump();
    return progress;
  }

  testWidgets(
    'sin "Seguir viendo": novedades grandes con su ficha; con algo a medio '
    'ver, "Seguir viendo" entre las secciones y los carruseles',
    (tester) async {
      // Se cierra en pumpHome (addTearDown).
      // ignore: close_sinks
      final progress = await pumpHome(tester);
      // Hasta saber si hay algo a medio ver, solo las secciones.
      expect(find.byType(FeaturedHero), findsNothing);
      expect(find.byType(FeaturedCarousel), findsNothing);

      progress.add(const []);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      // Tres carruseles, uno por columna: películas, series y mejor
      // valoradas.
      expect(find.byType(FeaturedHero), findsNWidgets(3));
      expect(find.text('Mejor valoradas'), findsOneWidget);
      // Cada carrusel alineado bajo su sección.
      for (final (i, section) in ['En vivo', 'Películas', 'Series'].indexed) {
        final tile = tester.getRect(
          find.ancestor(of: find.text(section), matching: find.byType(Card)),
        );
        final hero = tester.getRect(find.byType(FeaturedHero).at(i));
        expect(hero.left, closeTo(tile.left, 1), reason: section);
        expect(hero.right, closeTo(tile.right, 1), reason: section);
      }
      // Con espacio de sobra, el conjunto baja (no queda pegado arriba):
      // lo que sobra se reparte arriba y abajo.
      final searchBottom = tester
          .getRect(find.text('Buscar canales, películas y series'))
          .bottom;
      final tilesTop = tester
          .getRect(
            find.ancestor(
              of: find.text('En vivo'),
              matching: find.byType(Card),
            ),
          )
          .top;
      final heroBottom = tester.getRect(find.byType(FeaturedHero).first).bottom;
      final creditTop = tester
          .getRect(find.text('Desarrollado por Godebol'))
          .top;
      final above = tilesTop - searchBottom;
      final below = creditTop - heroBottom;
      expect(above, greaterThan(60));
      expect((above - below).abs(), lessThan(60));
      // Título de la sección centrado en su columna.
      final column = tester.getRect(find.byType(FeaturedHero).first);
      expect(
        tester.getCenter(find.text('Películas nuevas 2026')).dx,
        closeTo(column.center.dx, 2),
      );
      expect(find.text('Películas nuevas 2026'), findsOneWidget);
      expect(find.text('Series nuevas 2026'), findsOneWidget);
      // Sin botón: la ficha se abre con un clic en la tarjeta.
      expect(find.text('Ver ficha'), findsNothing);
      // El año no se repite en el título.
      expect(find.text('Película 0'), findsWidgets);
      // El título de la novedad va debajo de la pila, no al lado.
      final carousel = tester.getRect(find.byType(StackedCarousel).first);
      final title = tester.getTopLeft(
        find
            .descendant(
              of: find.byType(FeaturedHero).first,
              matching: find.text('Película 0'),
            )
            .last,
      );
      expect(title.dy, greaterThan(carousel.bottom - 1));
      expect(title.dx, lessThan(carousel.right));
      expect(find.text('Película 0 (2026)'), findsNothing);
      expect(find.text('Seguir viendo'), findsNothing);
      // Cantidades del catálogo en las secciones.
      expect(find.text('1.240 canales'), findsOneWidget);
      expect(find.text('8.300 películas'), findsOneWidget);
      expect(find.text('1 serie'), findsOneWidget);
      // Anuncio discreto en la barra superior, no en el contenido.
      expect(find.byType(PromoChip), findsOneWidget);
      expect(find.byType(PromoBanner), findsNothing);
      expect(
        tester.getCenter(find.byType(PromoChip)).dy,
        lessThan(tester.getTopLeft(find.text('En vivo')).dy),
      );
      // Firma al pie.
      expect(find.text('Desarrollado por Godebol'), findsOneWidget);

      progress.add([
        WatchProgress(
          kind: ProgressKind.movie,
          itemId: 'm9',
          title: 'Película a medias',
          position: const Duration(minutes: 30),
          duration: const Duration(hours: 2),
          updatedAt: DateTime(2026),
        ),
      ]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Seguir viendo'), findsOneWidget);
      // Mismo arreglo: los tres carruseles siguen alineados bajo las
      // secciones, sin columna a la derecha.
      expect(find.byType(FeaturedCarousel), findsNothing);
      expect(find.byType(FeaturedHero), findsNWidgets(3));
      for (final (i, section) in ['En vivo', 'Películas', 'Series'].indexed) {
        final tile = tester.getRect(
          find.ancestor(of: find.text(section), matching: find.byType(Card)),
        );
        final hero = tester.getRect(find.byType(FeaturedHero).at(i));
        expect(hero.left, closeTo(tile.left, 1), reason: section);
        expect(hero.right, closeTo(tile.right, 1), reason: section);
      }
      // "Seguir viendo" entre las secciones y los carruseles, y todo
      // entra en 1920×1080 sin desplazar (sobre la firma del pie).
      final continueTop = tester.getRect(find.text('Seguir viendo')).top;
      final tilesBottom = tester
          .getRect(
            find.ancestor(
              of: find.text('En vivo'),
              matching: find.byType(Card),
            ),
          )
          .bottom;
      expect(continueTop, greaterThan(tilesBottom));
      expect(
        tester.getRect(find.byType(FeaturedHero).first).top,
        greaterThan(continueTop),
      );
      expect(
        tester.getRect(find.byType(FeaturedHero).first).bottom,
        lessThanOrEqualTo(
          tester.getRect(find.text('Desarrollado por Godebol')).top,
        ),
      );

      // Tope de 10 tarjetas; si no entran todas, flechas para desplazar.
      progress.add([
        for (var i = 0; i < 14; i++)
          WatchProgress(
            kind: ProgressKind.movie,
            itemId: 'm$i',
            title: 'Película a medias $i',
            position: const Duration(minutes: 30),
            duration: const Duration(hours: 2),
            updatedAt: DateTime(2026, 1, 1, 0, 59 - i),
          ),
      ]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      final row = find.byType(ContinueWatchingRow);
      final list = tester.widget<ListView>(
        find.descendant(of: row, matching: find.byType(ListView)),
      );
      expect(list.childrenDelegate.estimatedChildCount, 19, reason: '10 + 9');
      // En 1920 de ancho entran las 10: sin flechas.
      expect(find.byTooltip('Más'), findsNothing);
      tester.view.physicalSize = const Size(1280, 800);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byTooltip('Anteriores'), findsNothing);
      expect(find.byTooltip('Más'), findsOneWidget);
      await tester.tap(find.byTooltip('Más'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Anteriores'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('con "Seguir viendo" el inicio no se desplaza: si falta alto, '
      'se compacta', (tester) async {
    // Se cierra en pumpHome (addTearDown).
    // ignore: close_sinks
    final progress = await pumpHome(tester);
    progress.add([
      WatchProgress(
        kind: ProgressKind.movie,
        itemId: 'm9',
        title: 'Película a medias',
        position: const Duration(minutes: 30),
        duration: const Duration(hours: 2),
        updatedAt: DateTime(2026),
      ),
    ]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    double tilesHeight() => tester
        .getRect(
          find.ancestor(of: find.text('En vivo'), matching: find.byType(Card)),
        )
        .height;
    ScrollPhysics? physics() => tester
        .widget<ListView>(
          find
              .ancestor(
                of: find.byType(ContinueWatchingRow),
                matching: find.byType(ListView),
              )
              .last,
        )
        .physics;

    void expectAllVisible(Size size) => expect(
      tester.getRect(find.byType(FeaturedHero).first).bottom,
      lessThanOrEqualTo(
        tester.getRect(find.text('Desarrollado por Godebol')).top,
      ),
      reason: '$size: todo a la vista, sobre la firma del pie',
    );

    // Pantalla 1080p sin barra de título, y ventana maximizada en 1080p
    // con la barra de título de Linux (la del usuario): nunca se desplaza;
    // en la segunda las secciones se compactan un poco.
    for (final (size, tiles) in [
      (const Size(1920, 1080), 150.0),
      (const Size(1920, 1032), 130.0),
    ]) {
      tester.view.physicalSize = size;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(physics(), isA<NeverScrollableScrollPhysics>(), reason: '$size');
      expect(tilesHeight(), closeTo(tiles, 1), reason: '$size');
      expectAllVisible(size);
    }
    // Ventana muy baja (1280×720): ni compactado entra; solo ahí se
    // desplaza, con todo al mínimo.
    const small = Size(1280, 720);
    tester.view.physicalSize = small;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(physics(), isNot(isA<NeverScrollableScrollPhysics>()));
    expect(tilesHeight(), closeTo(110, 1));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('nada arranca resaltado; una flecha entra con el teclado', (
    tester,
  ) async {
    // Se cierra en pumpHome (addTearDown).
    // ignore: close_sinks
    final progress = await pumpHome(tester);
    progress.add(const []);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    // El foco está en la pantalla, no en una sección.
    final before = FocusManager.instance.primaryFocus;
    expect(before?.context?.widget, isNot(isA<InkWell>()));
    expect(
      find.ancestor(
        of: find.text('En vivo'),
        matching: find.byWidgetPredicate(
          (w) => w is Focus && (w.focusNode?.hasPrimaryFocus ?? false),
        ),
      ),
      findsNothing,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus, isNot(before));
    await tester.pumpWidget(const SizedBox());
  });
}
