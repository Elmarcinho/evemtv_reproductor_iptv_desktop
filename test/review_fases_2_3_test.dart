// Casos reproducidos en la revisión de las Fases 2 y 3 (datos ficticios).
import 'dart:async';
import 'dart:convert';

import 'package:evemtv/core/logging/app_logger.dart';
import 'package:evemtv/core/utils/task_pool.dart';
import 'package:evemtv/data/m3u/m3u_catalog.dart';
import 'package:evemtv/data/m3u/m3u_parser.dart';
import 'package:evemtv/data/xtream/xtream_client.dart';
import 'package:evemtv/data/xtream/xtream_source.dart';
import 'package:evemtv/data/xtream/xtream_vod_parser.dart';
import 'package:evemtv/domain/entities/live.dart';
import 'package:evemtv/domain/entities/source_credentials.dart';
import 'package:evemtv/domain/entities/vod.dart';
import 'package:evemtv/features/player/live_playback_controller.dart';
import 'package:evemtv/features/player/vod_playback_controller.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'features/player/live_playback_controller_test.dart'
    show FakeEngine, FakeSource;
import 'helpers/fakes.dart';

/// Motor cuyas aperturas se completan a mano (para solapar aperturas).
class ManualOpenEngine extends FakeEngine {
  final pendingOpens = <Completer<void>>[];

  @override
  Future<void> open(Uri url) {
    opened.add(url);
    final c = Completer<void>();
    pendingOpens.add(c);
    return c.future;
  }
}

/// Fuente de vivo que devuelve una URL "rara" con credenciales en la ruta.
class _OddUrlSource extends FakeSource {
  @override
  PlaybackCandidates liveStream(
    LiveChannel channel, {
    List<String> allowedFormats = const [],
  }) => PlaybackCandidates([
    Uri.parse('http://s.example.com/auth.php/usuarioFicticio/claveFicticia'),
  ]);
}

void main() {
  late LogSink originalSink;
  late List<String> logs;
  setUp(() {
    logs = [];
    originalSink = AppLogger.sink;
    AppLogger.sink = (_, m) => logs.add(m);
  });
  tearDown(() => AppLogger.sink = originalSink);

  group('2. formato del log desde un conjunto cerrado', () {
    test('formatLabel', () {
      String f(String url) =>
          LivePlaybackController.formatLabel(Uri.parse(url));
      expect(
        f('http://s.example.com/auth.php/usuarioFicticio/claveFicticia'),
        'otro',
      );
      expect(f('http://s.example.com/live/u/p/1.m3u8'), 'm3u8');
      expect(f('http://s.example.com/live/u/p/1.TS'), 'ts');
      expect(f('http://s.example.com/x.php?a=b.m3u8'), 'otro');
      expect(f('http://s.example.com/canal'), 'otro');
    });

    test('el log de apertura no contiene la ruta', () {
      fakeAsync((async) {
        final c = LivePlaybackController(
          engine: FakeEngine(),
          source: _OddUrlSource(),
          channels: const [LiveChannel(id: '1', name: 'x')],
          initialIndex: 0,
        )..start();
        async.flushMicrotasks();
        c.dispose();
      });
      final all = logs.join('\n');
      expect(all, contains('format=otro'));
      expect(all, isNot(contains('usuarioFicticio')));
      expect(all, isNot(contains('claveFicticia')));
    });
  });

  group('3. entradas M3U sin título: nombre genérico, nada de la URL', () {
    test('vivo, película y serie', () {
      final list = M3uParser.parse('''
#EXTM3U
#EXTINF:-1,
https://cdn.example.org/tokenFicticio
#EXTINF:-1,
https://cdn.example.org/otroTokenFicticio.mp4
https://cdn.example.org/series/u/p/tercerToken.mkv
''').entries;
      expect(list.map((e) => e.name), [
        'Canal sin nombre',
        'Película sin título',
        'Serie sin título',
      ]);
      for (final e in list) {
        expect(e.name.toLowerCase(), isNot(contains('token')));
      }
    });
  });

  group('5. reconexión VOD: la posición se aplica con la duración nueva', () {
    test('el 0 que emite media_kit al reabrir no consume el salto', () {
      fakeAsync((async) {
        final engine = FakeEngine();
        final c = VodPlaybackController(engine: engine)
          ..open(Uri.parse('http://s.example.com/movie/u/p/1.mkv'));
        async.flushMicrotasks();
        engine.durationCtrl.add(const Duration(hours: 2));
        engine.playingCtrl.add(true);
        engine.positionCtrl.add(const Duration(seconds: 37));

        engine.errorCtrl.add('corte');
        async.elapse(const Duration(seconds: 3 + 2)); // gracia + espera
        expect(engine.opened, hasLength(2));

        // Al reabrir, media_kit emite duración 0 antes de cargar.
        engine.durationCtrl.add(Duration.zero);
        expect(engine.seeks, isEmpty, reason: 'aún no hay archivo cargado');
        engine.durationCtrl.add(const Duration(hours: 2));
        expect(engine.seeks, [const Duration(seconds: 37)]);
        c.dispose();
      });
    });
  });

  group('6. un fallo tardío de la apertura anterior no reinicia la actual', () {
    test('A falla después de pedir B', () {
      fakeAsync((async) {
        final engine = ManualOpenEngine();
        final c = VodPlaybackController(engine: engine);
        c.open(Uri.parse('http://s.example.com/series/u/p/A.mkv'));
        c.open(Uri.parse('http://s.example.com/series/u/p/B.mkv'));
        async.flushMicrotasks();
        expect(engine.opened, hasLength(2));

        engine.pendingOpens.first.completeError(StateError('A falló'));
        async.elapse(const Duration(seconds: 20));
        expect(engine.opened, hasLength(2), reason: 'sin reaperturas de B');
        expect(c.status, VodPlaybackStatus.connecting);
        c.dispose();
      });
    });
  });

  group('7. vivo: estable = 30 s de reproducción continua', () {
    test('15 s bien + 15 s trabado no reinicia el contador', () {
      fakeAsync((async) {
        final engine = FakeEngine();
        final c = LivePlaybackController(
          engine: engine,
          source: FakeSource(),
          channels: const [LiveChannel(id: '1', name: 'x')],
          initialIndex: 0,
        )..start();
        async.flushMicrotasks();
        // Un error real para que haya un intento contado.
        engine.errorCtrl.add('x');
        async.elapse(const Duration(seconds: 3 + 1));
        expect(c.attempt, 1);

        for (var i = 0; i < 3; i++) {
          engine.playingCtrl.add(true);
          engine.positionCtrl.add(Duration(seconds: 1 + i * 30));
          engine.bufferingCtrl.add(false);
          async.elapse(const Duration(seconds: 15));
          engine.bufferingCtrl.add(true);
          async.elapse(const Duration(seconds: 15));
        }
        expect(c.attempt, 1, reason: 'nunca hubo 30 s seguidos');

        engine.bufferingCtrl.add(false);
        async.elapse(const Duration(seconds: 30));
        expect(c.attempt, 0);
        c.dispose();
      });
    });

    test('la pausa también corta la cuenta', () {
      fakeAsync((async) {
        final engine = FakeEngine();
        final c = LivePlaybackController(
          engine: engine,
          source: FakeSource(),
          channels: const [LiveChannel(id: '1', name: 'x')],
          initialIndex: 0,
        )..start();
        async.flushMicrotasks();
        engine.errorCtrl.add('x');
        async.elapse(const Duration(seconds: 4));
        engine.playingCtrl.add(true);
        engine.positionCtrl.add(const Duration(seconds: 1));
        async.elapse(const Duration(seconds: 20));
        engine.playingCtrl.add(false);
        async.elapse(const Duration(seconds: 20));
        expect(c.attempt, 1);
        c.dispose();
      });
    });
  });

  group('8. la cola de EPG no sigue trabajando tras abandonar la sesión', () {
    test('TaskPool.cancelAll descarta lo pendiente', () async {
      final pool = TaskPool(4);
      final gate = Completer<void>();
      var ran = 0;
      final futures = [
        for (var i = 0; i < 100; i++)
          pool.run(() async {
            ran++;
            await gate.future;
          }),
      ];
      await Future<void>.delayed(Duration.zero);
      expect(ran, 4);
      expect(pool.pending, 96);
      pool.cancelAll();
      gate.complete();
      final results = await Future.wait(
        futures.map((f) => f.then((_) => 'ok', onError: (Object e) => '$e')),
      );
      expect(ran, 4);
      expect(
        results.where((r) => r == 'TaskCancelledException'),
        hasLength(96),
      );
      await expectLater(
        pool.run(() async {}),
        throwsA(isA<TaskCancelledException>()),
      );
    });

    test('isCancelled: una fila que ya no se ve no hace la petición', () async {
      final pool = TaskPool(1);
      final gate = Completer<void>();
      final first = pool.run(() => gate.future);
      var ran = false;
      final second = pool.run(() async => ran = true, isCancelled: () => true);
      gate.complete();
      await first;
      await expectLater(second, throwsA(isA<TaskCancelledException>()));
      expect(ran, isFalse);
    });

    test(
      'XtreamSource.dispose: 100 EPG pedidas, solo 4 llegan al panel',
      () async {
        final gate = Completer<void>();
        final adapter = FakeHttpAdapter((_) async {
          await gate.future;
          return jsonBody('{"epg_listings": []}');
        });
        final source = XtreamSource(
          XtreamClient(
            testDio(adapter, maxRetries: 0),
            XtreamCredentials(
              server: Uri.parse('http://panel.example.com'),
              username: 'u',
              password: 'p',
            ),
          ),
        );
        final pending = [
          for (var i = 0; i < 100; i++)
            source
                .shortEpg(LiveChannel(id: '$i', name: 'c'))
                .then((_) => 'ok', onError: (Object _) => 'cancelada'),
        ];
        await Future<void>.delayed(const Duration(milliseconds: 10));
        source.dispose();
        gate.complete();
        final results = await Future.wait(pending);
        expect(adapter.requests, hasLength(4));
        expect(results.where((r) => r == 'cancelada'), hasLength(96));
      },
    );
  });

  group('9. series M3U reconocidas por el nombre', () {
    test('guessKind', () {
      expect(
        M3uParser.guessKind(
          Uri.parse('http://s.example.com/42.mp4'),
          'Serie Ficticia S01E02',
        ),
        M3uKind.series,
      );
      expect(
        M3uParser.guessKind(Uri.parse('http://s.example.com/42'), 'Serie 1x03'),
        M3uKind.series,
      );
      // Un canal en vivo con un nombre parecido sigue siendo vivo.
      expect(
        M3uParser.guessKind(
          Uri.parse('http://s.example.com/live/u/p/7.m3u8'),
          'Maratón S01E01',
        ),
        M3uKind.live,
      );
      expect(
        M3uParser.guessKind(
          Uri.parse('http://s.example.com/peli.mp4'),
          'Película',
        ),
        M3uKind.movie,
      );
    });

    test('se agrupan en temporadas con siguiente episodio', () {
      final catalog = M3uCatalog.build(
        M3uParser.parse('''
#EXTM3U
#EXTINF:-1 group-title="Series",Serie Ficticia S01E02
http://s.example.com/42.mp4
#EXTINF:-1 group-title="Series",Serie Ficticia S01E01
http://s.example.com/41.mp4
#EXTINF:-1 group-title="Series",Serie Ficticia S02E01
http://s.example.com/43.mp4
'''),
      );
      expect(catalog.movies, isEmpty);
      final detail = catalog.seriesDetails[catalog.series.single.id]!;
      expect(detail.seasons.map((s) => s.number), [1, 2]);
      expect(detail.seasons.first.episodes.map((e) => e.number), [1, 2]);
    });
  });

  group('10. lista de listas sin "season": no mezcla temporadas', () {
    const series = SeriesItem(id: '1', name: 'X');

    test('usa las temporadas declaradas', () {
      final d = XtreamVodParser.seriesDetail(
        series,
        jsonDecode('''
{
  "seasons": [{"season_number": 1}, {"season_number": 2}],
  "episodes": [
    [{"id": 11, "episode_num": 1, "title": "T1E1"}, {"id": 12, "episode_num": 2, "title": "T1E2"}],
    [{"id": 21, "episode_num": 1, "title": "T2E1"}]
  ]
}'''),
      );
      expect(d.seasons.map((s) => s.number), [1, 2]);
      expect(d.seasons.first.episodes.map((e) => e.title), ['T1E1', 'T1E2']);
      expect(d.seasons.last.episodes.single.title, 'T2E1');
    });

    test('sin temporadas declaradas usa la posición', () {
      final d = XtreamVodParser.seriesDetail(
        series,
        jsonDecode(
          '''
{"episodes": [[{"id": 1, "episode_num": 1}], [{"id": 2, "episode_num": 1}], [{"id": 3, "episode_num": 1}]]}''',
        ),
      );
      expect(d.seasons.map((s) => s.number), [1, 2, 3]);
    });

    test('un "season" explícito sigue teniendo prioridad', () {
      final d = XtreamVodParser.seriesDetail(
        series,
        jsonDecode('''
{"seasons": [{"season_number": 1}],
 "episodes": [[{"id": 1, "episode_num": 1, "season": 5}]]}'''),
      );
      expect(d.seasons.single.number, 5);
    });
  });
}
