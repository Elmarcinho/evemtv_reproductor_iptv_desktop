// Pantalla En vivo con una fuente simulada y datos ficticios.
import 'package:evemtv/core/router/app_router.dart';
import 'package:evemtv/core/theme/app_theme.dart';
import 'package:evemtv/data/providers.dart';
import 'package:evemtv/domain/entities/live.dart';
import 'package:evemtv/features/auth/application/session.dart';
import 'package:evemtv/features/live/live_screen.dart';
import 'package:evemtv/features/player/live_player_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../helpers/fakes.dart';
import '../player/live_playback_controller_test.dart' show FakeSource;

class _LiveSource extends FakeSource {
  final requestedCategories = <String?>[];

  @override
  Future<List<ContentCategory>> liveCategories() async => const [
    ContentCategory(id: 'n', name: 'Noticias'),
    ContentCategory(id: 'd', name: 'Deportes'),
  ];

  @override
  Future<List<LiveChannel>> liveChannels({String? categoryId}) async {
    requestedCategories.add(categoryId);
    return switch (categoryId) {
      'n' => const [
        LiveChannel(id: '1', name: 'Noticias Uno', number: 1),
        LiveChannel(id: '2', name: 'Noticias Dos', number: 2),
        LiveChannel(id: '3', name: 'Otro Canal', number: 3),
      ],
      'd' => const [LiveChannel(id: '9', name: 'Deportes Nueve')],
      _ => const [],
    };
  }

  @override
  Future<List<EpgEntry>> shortEpg(LiveChannel channel, {int limit = 4}) async {
    final now = DateTime.now();
    return [
      EpgEntry(
        title: 'Programa de ${channel.name}',
        start: now.subtract(const Duration(minutes: 10)),
        end: now.add(const Duration(minutes: 20)),
      ),
      EpgEntry(
        title: 'Después en ${channel.name}',
        start: now.add(const Duration(minutes: 20)),
        end: now.add(const Duration(minutes: 50)),
      ),
    ];
  }
}

/// Reproductor compartido falso: registra qué se pidió reproducir.
class _FakePlayer extends LivePlayerNotifier {
  static final calls = <(String, int)>[];

  @override
  LivePlayerState build() => const LivePlayerState();

  @override
  Future<void> play(List<LiveChannel> channels, int index) async {
    calls.add((channels.map((c) => c.id).join(','), index));
  }
}

/// Simula que el reproductor está sonando con "Noticias Dos".
class _PlayingNoticiasDos extends PlayingChannelNotifier {
  @override
  LiveChannel? build() =>
      const LiveChannel(id: '2', name: 'Noticias Dos', number: 2);
}

void main() {
  late _LiveSource source;
  var openedPlayer = false;

  Future<void> pumpLive(
    WidgetTester tester, {
    bool playingNoticiasDos = false,
  }) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    source = _LiveSource();
    openedPlayer = false;
    _FakePlayer.calls.clear();
    final router = GoRouter(
      initialLocation: AppRoutes.live,
      routes: [
        GoRoute(path: AppRoutes.home, builder: (_, _) => const Text('INICIO')),
        GoRoute(
          path: AppRoutes.live,
          builder: (_, _) => const LiveScreen(),
          routes: [
            GoRoute(
              path: 'player',
              builder: (_, _) {
                openedPlayer = true;
                return const Text('REPRODUCTOR');
              },
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          contentSourceProvider.overrideWithValue(source),
          livePlayerProvider.overrideWith(_FakePlayer.new),
          sessionProvider.overrideWith(FixedSession.new),
          favoritesRepositoryProvider.overrideWithValue(
            InMemoryFavoritesRepository(),
          ),
          if (playingNoticiasDos)
            playingLiveChannelProvider.overrideWith(_PlayingNoticiasDos.new),
        ],
        child: MaterialApp.router(theme: AppTheme.dark(), routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('abre la primera categoría, no la lista completa', (
    tester,
  ) async {
    await pumpLive(tester);
    expect(find.text('Noticias Uno'), findsWidgets);
    expect(source.requestedCategories, ['n']);
  });

  testWidgets('detalle con programa actual y siguiente', (tester) async {
    await pumpLive(tester);
    expect(find.textContaining('Ahora ·'), findsOneWidget);
    expect(find.text('Programa de Noticias Uno'), findsWidgets);
    expect(find.text('Después en Noticias Uno'), findsOneWidget);
  });

  testWidgets('mini reproductor: vacío al entrar, un clic reproduce el canal', (
    tester,
  ) async {
    await pumpLive(tester);
    expect(find.text('Selecciona un canal para verlo aquí'), findsOneWidget);
    expect(_FakePlayer.calls, isEmpty);

    await tester.tap(find.text('Noticias Dos').first);
    // La fila también detecta doble clic: el clic simple se confirma tras
    // el tiempo de espera del doble clic.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(_FakePlayer.calls.single, ('1,2,3', 1));
    expect(openedPlayer, isFalse, reason: 'un clic no abre pantalla completa');
  });

  testWidgets('flechas: reproduce al detenerse, no en cada canal', (
    tester,
  ) async {
    await pumpLive(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump(const Duration(milliseconds: 200));
    expect(_FakePlayer.calls, isEmpty);

    await tester.pump(LiveScreenAutoplay.delay);
    expect(_FakePlayer.calls.single, ('1,2,3', 2));
    expect(find.text('Después en Otro Canal'), findsOneWidget);
  });

  testWidgets('Enter reproduce y abre la pantalla completa', (tester) async {
    await pumpLive(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(openedPlayer, isTrue);
    expect(_FakePlayer.calls.last, ('1,2,3', 1));
  });

  testWidgets('doble clic abre la pantalla completa', (tester) async {
    await pumpLive(tester);
    final row = find.text('Otro Canal').first;
    await tester.tap(row);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(openedPlayer, isTrue);
  });

  testWidgets('cambiar de categoría y filtrar', (tester) async {
    await pumpLive(tester);
    await tester.tap(find.text('Deportes'));
    await tester.pumpAndSettle();
    expect(find.text('Deportes Nueve'), findsWidgets);
    expect(find.text('Noticias Uno'), findsNothing);

    await tester.tap(find.text('Noticias'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'otro');
    await tester.pumpAndSettle();
    expect(find.text('Otro Canal'), findsWidgets);
    expect(find.text('Noticias Dos'), findsNothing);

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('Ningún canal coincide con "zzz".'), findsOneWidget);
  });

  testWidgets('Esc vuelve al inicio', (tester) async {
    await pumpLive(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('INICIO'), findsOneWidget);
  });

  testWidgets(
    'imagen 3: al cambiar de categoría, el panel sigue mostrando el canal que suena',
    (tester) async {
      await pumpLive(tester, playingNoticiasDos: true);
      // La fila que suena queda marcada.
      expect(find.byIcon(Icons.graphic_eq_rounded), findsOneWidget);
      expect(find.text('Después en Noticias Dos'), findsOneWidget);

      // Otra categoría: la selección pasa a "Deportes Nueve", pero el video
      // sigue siendo "Noticias Dos" y el panel lo dice.
      await tester.tap(find.text('Deportes'));
      await tester.pumpAndSettle();
      expect(
        find.text('Deportes Nueve'),
        findsOneWidget,
        reason: 'solo en la lista',
      );
      expect(find.text('Noticias Dos'), findsOneWidget, reason: 'en el panel');
      expect(find.text('Después en Noticias Dos'), findsOneWidget);
      expect(find.byIcon(Icons.graphic_eq_rounded), findsNothing);
    },
  );

  testWidgets('favoritos: vacío, marcar con ★ y aparece en la categoría', (
    tester,
  ) async {
    await pumpLive(tester);
    await tester.tap(find.text('Favoritos'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Todavía no tienes canales favoritos'),
      findsOneWidget,
    );

    await tester.tap(find.text('Noticias'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Agregar a favoritos'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Quitar de favoritos'), findsOneWidget);
    expect(find.byIcon(Icons.star_rounded), findsWidgets);

    await tester.tap(find.text('Favoritos'));
    await tester.pumpAndSettle();
    expect(find.text('Noticias Uno'), findsWidgets);
    expect(find.text('Noticias Dos'), findsNothing);

    // Quitar desde el panel lo saca de la lista.
    await tester.tap(find.byTooltip('Quitar de favoritos'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Todavía no tienes canales favoritos'),
      findsOneWidget,
    );
  });
}
