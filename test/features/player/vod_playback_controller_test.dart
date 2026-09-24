// Reproducción de películas/episodios con motor simulado y reloj falso.
import 'package:evemtv/core/errors/app_failure.dart';
import 'package:evemtv/core/logging/app_logger.dart';
import 'package:evemtv/features/player/stream_probe.dart';
import 'package:evemtv/features/player/vod_playback_controller.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'live_playback_controller_test.dart' show FakeEngine;

final url = Uri.parse('http://s.example.com/movie/u/p/1.mkv');

/// Error de mpv fatal: el video no avanza durante la gracia (3 s).
void fatal(FakeAsync async, FakeEngine engine, [String message = 'x']) {
  engine.errorCtrl.add(message);
  async.elapse(const Duration(seconds: 3));
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

  void run(
    void Function(FakeAsync async, FakeEngine engine, VodPlaybackController c)
    body, {
    Duration? resumeAt,
    StreamProbe? probe,
  }) {
    fakeAsync((async) {
      final engine = FakeEngine();
      final c = VodPlaybackController(engine: engine, probe: probe);
      c.open(url, resumeAt: resumeAt);
      async.flushMicrotasks();
      body(async, engine, c);
      c.dispose();
    });
  }

  test('abre y reproduce', () {
    run((async, engine, c) {
      expect(engine.opened, [url]);
      expect(c.status, VodPlaybackStatus.connecting);
      engine.playingCtrl.add(true);
      engine.positionCtrl.add(const Duration(seconds: 1));
      expect(c.status, VodPlaybackStatus.playing);
    });
  });

  test('reanuda en la posición pedida cuando se conoce la duración', () {
    run(resumeAt: const Duration(minutes: 20), (async, engine, c) {
      expect(engine.seeks, isEmpty, reason: 'sin duración todavía');
      engine.durationCtrl.add(const Duration(hours: 2));
      expect(engine.seeks, [const Duration(minutes: 20)]);
      engine.durationCtrl.add(const Duration(hours: 2));
      expect(engine.seeks, hasLength(1), reason: 'solo una vez');
    });
  });

  test('una posición pegada al final empieza de nuevo', () {
    run(resumeAt: const Duration(minutes: 119, seconds: 58), (
      async,
      engine,
      c,
    ) {
      engine.durationCtrl.add(const Duration(hours: 2));
      expect(engine.seeks, isEmpty);
    });
  });

  test('un corte reconecta y vuelve a donde estaba', () {
    run((async, engine, c) {
      engine.durationCtrl.add(const Duration(hours: 2));
      engine.playingCtrl.add(true);
      engine.positionCtrl.add(const Duration(seconds: 1));
      engine.positionCtrl.add(const Duration(minutes: 37));
      fatal(
        async,
        engine,
        'fallo http://s.example.com/movie/usuarioX/claveY/1.mkv',
      );
      expect(c.status, VodPlaybackStatus.reconnecting);

      async.elapse(const Duration(seconds: 2));
      expect(engine.opened, hasLength(2));
      engine.durationCtrl.add(const Duration(hours: 2));
      expect(engine.seeks.last, const Duration(minutes: 37));
      expect(logs.join('\n'), isNot(contains('claveY')));
    });
  });

  test('un "fin" lejos del final real es un corte', () {
    run((async, engine, c) {
      engine.durationCtrl.add(const Duration(hours: 2));
      engine.positionCtrl.add(const Duration(minutes: 10));
      engine.completedCtrl.add(true);
      expect(c.status, VodPlaybackStatus.reconnecting);
    });
  });

  test('el fin real se informa como terminado, sin reconectar', () {
    run((async, engine, c) {
      engine.durationCtrl.add(const Duration(hours: 2));
      engine.positionCtrl.add(
        const Duration(hours: 1, minutes: 59, seconds: 50),
      );
      engine.completedCtrl.add(true);
      expect(c.status, VodPlaybackStatus.completed);
      async.elapse(const Duration(minutes: 1));
      expect(engine.opened, hasLength(1));
      // Tras terminar, una carga trabada no dispara reconexiones.
      engine.bufferingCtrl.add(true);
      async.elapse(const Duration(minutes: 1));
      expect(c.status, VodPlaybackStatus.completed);
    });
  });

  test('se rinde tras 3 intentos; Reintentar retoma la posición', () {
    run((async, engine, c) {
      engine.durationCtrl.add(const Duration(hours: 2));
      engine.positionCtrl.add(const Duration(minutes: 5));
      for (var i = 0; i < 3; i++) {
        fatal(async, engine);
        async.elapse(const Duration(seconds: 8));
      }
      fatal(async, engine);
      expect(c.status, VodPlaybackStatus.failed);

      c.retry();
      async.flushMicrotasks();
      expect(c.status, VodPlaybackStatus.connecting);
      engine.durationCtrl.add(const Duration(hours: 2));
      expect(engine.seeks.last, const Duration(minutes: 5));
    });
  });

  test('carga trabada 30 s = reconexión', () {
    run((async, engine, c) {
      engine.playingCtrl.add(true);
      engine.positionCtrl.add(const Duration(seconds: 1));
      engine.bufferingCtrl.add(true);
      async.elapse(const Duration(seconds: 29));
      expect(c.status, VodPlaybackStatus.playing);
      async.elapse(const Duration(seconds: 1));
      expect(c.status, VodPlaybackStatus.reconnecting);
    });
  });

  // Casos de los logs reales (datos ficticios).
  test(
    '"Could not open codec" con el video avanzando no corta la película',
    () {
      run((async, engine, c) {
        engine.durationCtrl.add(const Duration(hours: 1, minutes: 46));
        engine.playingCtrl.add(true);
        engine.positionCtrl.add(const Duration(seconds: 1));
        engine.positionCtrl.add(const Duration(seconds: 1));
        engine.errorCtrl.add('Could not open codec.');
        engine.positionCtrl.add(const Duration(seconds: 3));
        async.elapse(const Duration(seconds: 10));
        expect(c.status, VodPlaybackStatus.playing);
        expect(engine.opened, hasLength(1), reason: 'sin reinicios');
      });
    },
  );

  test('un aviso en pausa no reconecta', () {
    run((async, engine, c) {
      engine.playingCtrl.add(true);
      engine.positionCtrl.add(const Duration(seconds: 1));
      engine.positionCtrl.add(const Duration(minutes: 2));
      engine.playingCtrl.add(false);
      engine.errorCtrl.add('Could not open codec.');
      async.elapse(const Duration(seconds: 10));
      expect(engine.opened, hasLength(1));
    });
  });

  test('"Failed to open" + HTTP 404: no disponible, sin reintentos', () {
    final probed = <Uri>[];
    run(
      probe: (u) async {
        probed.add(u);
        return 404;
      },
      (async, engine, c) {
        fatal(
          async,
          engine,
          'Failed to open http://s.example.com/movie/u/p/1.mkv.',
        );
        async.flushMicrotasks();
        expect(probed, [url]);
        expect(c.status, VodPlaybackStatus.failed);
        expect(c.failure, isA<ContentUnavailableFailure>());
        expect(c.failureMessage, const ContentUnavailableFailure().message);
        async.elapse(const Duration(minutes: 1));
        expect(engine.opened, hasLength(1));
      },
    );
  });

  test('"Failed to open" con el servidor respondiendo bien: reintenta', () {
    run(probe: (_) async => 206, (async, engine, c) {
      fatal(async, engine);
      async.flushMicrotasks();
      expect(c.status, VodPlaybackStatus.reconnecting);
      expect(c.failureMessage, VodPlaybackController.unavailableMessage);
    });
  });

  test('la consulta HTTP solo se hace si nunca llegó a reproducir', () {
    var probes = 0;
    run(
      probe: (_) async {
        probes++;
        return 404;
      },
      (async, engine, c) {
        engine.playingCtrl.add(true);
        engine.positionCtrl.add(const Duration(seconds: 1));
        engine.durationCtrl.add(const Duration(hours: 1));
        engine.positionCtrl.add(const Duration(minutes: 3));
        fatal(async, engine);
        async.flushMicrotasks();
        expect(probes, 0);
        expect(c.status, VodPlaybackStatus.reconnecting);
      },
    );
  });

  test('orden real de mpv ante un 404: playing=true antes de abrir', () {
    // Secuencia registrada con libmpv al abrir un archivo inexistente.
    run(probe: (_) async => 404, (async, engine, c) {
      engine.playingCtrl.add(false);
      engine.completedCtrl.add(false);
      engine.durationCtrl.add(Duration.zero);
      engine.bufferingCtrl.add(false);
      engine.playingCtrl.add(true);
      engine.bufferingCtrl.add(true);
      expect(
        c.status,
        VodPlaybackStatus.connecting,
        reason: 'playing=true sin archivo abierto no es reproducir',
      );
      fatal(async, engine, 'Failed to open http://s.example.com/x.mp4.');
      async.flushMicrotasks();
      expect(c.status, VodPlaybackStatus.failed);
      expect(c.failure, isA<ContentUnavailableFailure>());
    });
  });
}
