// Pantallas de películas y series con una fuente simulada y datos ficticios.
import 'package:evemtv/core/router/app_router.dart';
import 'package:evemtv/core/theme/app_theme.dart';
import 'package:evemtv/data/providers.dart';
import 'package:evemtv/domain/entities/live.dart';
import 'package:evemtv/domain/entities/vod.dart';
import 'package:evemtv/features/auth/application/session.dart';
import 'package:evemtv/features/catalog/related.dart';
import 'package:evemtv/features/home/promo_banner.dart';
import 'package:evemtv/features/movies/movie_detail_screen.dart';
import 'package:evemtv/features/movies/movies_screen.dart';
import 'package:evemtv/features/player/vod_player_screen.dart';
import 'package:evemtv/features/series/series_detail_screen.dart';
import 'package:evemtv/features/series/series_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../helpers/fakes.dart';
import '../player/live_playback_controller_test.dart' show FakeSource;

const serie = SeriesItem(id: '700', name: 'Serie Ficticia', year: 2019);

class _CatalogSource extends FakeSource {
  final requested = <String?>[];

  @override
  Future<List<ContentCategory>> vodCategories() async => const [
    ContentCategory(id: 'e', name: 'Estrenos'),
    ContentCategory(id: 'c', name: 'Clásicos'),
  ];

  @override
  Future<List<VodItem>> vodItems({String? categoryId}) async {
    requested.add(categoryId);
    return switch (categoryId) {
      'e' => const [
        VodItem(
          id: '1',
          name: 'Película Uno',
          year: 2022,
          rating: 7.5,
          categoryId: 'e',
        ),
        VodItem(
          id: '2',
          name: 'Película Dos',
          categoryId: 'e',
          posterUrl: 'http://img.example.com/2.jpg',
        ),
      ],
      'c' => const [VodItem(id: '3', name: 'Clásica Tres')],
      // Todas: con fechas de alta ficticias (la 3 es la última agregada).
      null => [
        VodItem(id: '1', name: 'Película Uno', added: DateTime.utc(2026, 1, 5)),
        const VodItem(id: '2', name: 'Película Dos'),
        VodItem(id: '3', name: 'Clásica Tres', added: DateTime.utc(2026, 9, 1)),
      ],
      _ => const [],
    };
  }

  @override
  Future<VodDetail> vodDetail(VodItem item) async => VodDetail(
    item: item,
    plot: 'Sinopsis ficticia de ${item.name}.',
    genre: 'Drama',
    director: 'Directora Inventada',
    duration: const Duration(minutes: 105),
  );

  @override
  Future<List<ContentCategory>> seriesCategories() async => const [
    ContentCategory(id: 's', name: 'Series'),
  ];

  @override
  Future<List<SeriesItem>> seriesItems({String? categoryId}) async => const [
    serie,
  ];

  @override
  Future<SeriesDetail> seriesDetail(SeriesItem series) async =>
      const SeriesDetail(
        series: serie,
        plot: 'Trama ficticia.',
        seasons: [
          Season(
            number: 1,
            episodes: [
              Episode(id: 'a', season: 1, number: 1, title: 'Piloto'),
              Episode(id: 'b', season: 1, number: 2, title: 'Segundo'),
            ],
          ),
          Season(
            number: 2,
            name: 'Temporada final',
            episodes: [
              Episode(id: 'c', season: 2, number: 1, title: 'Regreso'),
            ],
          ),
        ],
      );
}

void main() {
  late _CatalogSource source;
  Object? played;

  Future<void> pump(
    WidgetTester tester,
    String initial, {
    Object? extra,
  }) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    source = _CatalogSource();
    played = null;
    final router = GoRouter(
      initialLocation: initial,
      initialExtra: extra,
      routes: [
        GoRoute(path: AppRoutes.home, builder: (_, _) => const Text('INICIO')),
        GoRoute(
          path: AppRoutes.movies,
          builder: (_, _) => const MoviesScreen(),
          routes: [
            GoRoute(
              path: 'detail',
              builder: (_, s) => MovieDetailScreen(movie: s.extra! as VodItem),
            ),
          ],
        ),
        GoRoute(
          path: AppRoutes.seriesDetail,
          builder: (_, s) => SeriesDetailScreen(series: s.extra! as SeriesItem),
        ),
        GoRoute(
          path: AppRoutes.series,
          builder: (_, _) => const SeriesScreen(),
        ),
        GoRoute(
          path: AppRoutes.vodPlayer,
          builder: (_, s) {
            played = s.extra;
            return const Text('REPRODUCTOR');
          },
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          contentSourceProvider.overrideWithValue(source),
          sessionProvider.overrideWith(FixedSession.new),
          sessionContextProvider.overrideWithValue(testSessionContext()),
          favoritesRepositoryProvider.overrideWithValue(
            InMemoryFavoritesRepository(),
          ),
        ],
        child: MaterialApp.router(theme: AppTheme.dark(), routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('películas: primera categoría, grilla y cambio de categoría', (
    tester,
  ) async {
    await pump(tester, AppRoutes.movies);
    expect(source.requested, ['e']);
    // Anuncio discreto en el encabezado, como en el inicio.
    expect(find.byType(PromoChip), findsOneWidget);
    expect(find.text('Película Uno'), findsWidgets);
    expect(find.text('2022  ·  ★ 7.5'), findsOneWidget);

    await tester.tap(find.text('Clásicos'));
    await tester.pumpAndSettle();
    expect(find.text('Clásica Tres'), findsWidgets);
    expect(find.text('Película Uno'), findsNothing);
  });

  testWidgets('películas: "Recién agregadas", lo último primero', (
    tester,
  ) async {
    await pump(tester, AppRoutes.movies);
    await tester.tap(find.text('Recién agregadas'));
    await tester.pumpAndSettle();
    expect(source.requested, contains(null));
    final titles = [
      for (final t in ['Clásica Tres', 'Película Uno', 'Película Dos'])
        tester.getTopLeft(find.text(t).first),
    ];
    // Grilla: primero la más nueva, después la otra con fecha y al final
    // la que no la tiene.
    expect(titles[0].dx, lessThan(titles[1].dx));
    expect(titles[1].dx, lessThan(titles[2].dx));
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Buscar en Recién agregadas'), findsOneWidget);
  });

  testWidgets('películas: filtro', (tester) async {
    await pump(tester, AppRoutes.movies);
    await tester.enterText(find.byType(TextField), 'dos');
    await tester.pumpAndSettle();
    expect(find.text('Película Dos'), findsWidgets);
    expect(find.text('Película Uno'), findsNothing);
  });

  testWidgets('ficha de película: "Más de" su categoría, sin ella misma', (
    tester,
  ) async {
    await pump(tester, AppRoutes.movies);
    await tester.tap(find.text('Película Uno').first);
    await tester.pumpAndSettle();
    expect(find.text('Más de Estrenos'), findsOneWidget);
    // Ficha corta: la fila va al pie de la pantalla (se ve el fondo).
    expect(
      tester.getBottomLeft(find.byType(RelatedRow<VodItem>)).dy,
      closeTo(1000 - 32, 1),
    );
    // Película Dos (misma categoría, con póster) se recomienda.
    final related = find.descendant(
      of: find.byType(RelatedRow<VodItem>),
      matching: find.text('Película Dos'),
    );
    // Título debajo del póster (y el de respaldo del póster, sin imagen).
    expect(related, findsWidgets);
    await tester.ensureVisible(related.last);
    await tester.pumpAndSettle();
    await tester.tap(related.last);
    await tester.pumpAndSettle();
    expect(find.text('Sinopsis ficticia de Película Dos.'), findsOneWidget);
  });

  testWidgets('ficha de película y reproducir', (tester) async {
    await pump(tester, AppRoutes.movies);
    await tester.tap(find.text('Película Uno').first);
    await tester.pumpAndSettle();
    expect(find.text('Sinopsis ficticia de Película Uno.'), findsOneWidget);
    expect(find.textContaining('1 h 45 min'), findsOneWidget);
    expect(find.textContaining('Directora Inventada'), findsOneWidget);

    await tester.tap(find.text('Reproducir'));
    await tester.pumpAndSettle();
    expect(played, isA<MoviePlayable>());
    expect((played! as MoviePlayable).movie.id, '1');
  });

  testWidgets('ficha de serie: temporadas y episodio con lista completa', (
    tester,
  ) async {
    await pump(tester, AppRoutes.seriesDetail, extra: serie);
    expect(find.text('Trama ficticia.'), findsOneWidget);
    expect(find.text('Temporada 1 (2)'), findsOneWidget);
    expect(find.text('Temporada final (1)'), findsOneWidget);
    expect(find.text('Piloto'), findsOneWidget);
    expect(find.text('Regreso'), findsNothing);

    await tester.tap(find.text('Temporada final (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Regreso'), findsOneWidget);

    await tester.tap(find.text('Regreso'));
    await tester.pumpAndSettle();
    final playable = played! as EpisodePlayable;
    // Lista plana en orden, para pasar al siguiente entre temporadas.
    expect(playable.episodes.map((e) => e.id), ['a', 'b', 'c']);
    expect(playable.index, 2);
    expect(playable.next, isNull);
    expect(playable.subtitle, 'T2 · E1 · Regreso');
  });

  testWidgets('"Ver desde el principio" abre el primer episodio', (
    tester,
  ) async {
    await pump(tester, AppRoutes.seriesDetail, extra: serie);
    await tester.tap(find.text('Ver desde el principio'));
    await tester.pumpAndSettle();
    final playable = played! as EpisodePlayable;
    expect(playable.index, 0);
    expect(playable.next?.episode.id, 'b');
  });

  testWidgets('favoritos de películas: marcar en la ficha y ver en la grilla', (
    tester,
  ) async {
    await pump(tester, AppRoutes.movies);
    await tester.tap(find.text('Película Dos').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Agregar a favoritos'));
    await tester.pumpAndSettle();
    expect(find.text('En favoritos'), findsOneWidget);

    await tester.tap(find.byTooltip('Volver (Esc)'));
    await tester.pumpAndSettle();
    // Marca ★ en el póster.
    expect(find.byTooltip('En favoritos'), findsOneWidget);

    await tester.tap(find.text('Favoritos'));
    await tester.pumpAndSettle();
    expect(find.text('Película Dos'), findsWidgets);
    expect(find.text('Película Uno'), findsNothing);
  });

  testWidgets('favoritos de series: marcar en la ficha', (tester) async {
    await pump(tester, AppRoutes.seriesDetail, extra: serie);
    await tester.tap(find.text('Agregar a favoritos'));
    await tester.pumpAndSettle();
    expect(find.text('En favoritos'), findsOneWidget);
  });
}
