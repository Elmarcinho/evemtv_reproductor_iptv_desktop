// Reconexión del reproductor en vivo con motor simulado y reloj falso.
import 'dart:async';

import 'package:evemtv/core/errors/app_failure.dart';
import 'package:evemtv/core/logging/app_logger.dart';
import 'package:evemtv/domain/entities/account_info.dart';
import 'package:evemtv/domain/entities/live.dart';
import 'package:evemtv/domain/entities/profile.dart';
import 'package:evemtv/domain/entities/vod.dart';
import 'package:evemtv/domain/repositories/content_source.dart';
import 'package:evemtv/features/player/live_playback_controller.dart';
import 'package:evemtv/features/player/playback_engine.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeEngine implements PlaybackEngine {
  final playingCtrl = StreamController<bool>.broadcast(sync: true);
  final bufferingCtrl = StreamController<bool>.broadcast(sync: true);
  final completedCtrl = StreamController<bool>.broadcast(sync: true);
  final errorCtrl = StreamController<String>.broadcast(sync: true);
  final positionCtrl = StreamController<Duration>.broadcast(sync: true);
  final durationCtrl = StreamController<Duration>.broadcast(sync: true);
  final opened = <Uri>[];
  final seeks = <Duration>[];

  @override
  Stream<bool> get playing => playingCtrl.stream;
  @override
  Stream<bool> get buffering => bufferingCtrl.stream;
  @override
  Stream<bool> get completed => completedCtrl.stream;
  @override
  Stream<String> get error => errorCtrl.stream;
  @override
  Stream<Duration> get position => positionCtrl.stream;
  @override
  Stream<Duration> get duration => durationCtrl.stream;

  @override
  Future<void> seek(Duration position) async => seeks.add(position);

  @override
  Future<void> open(Uri url) async => opened.add(url);

  @override
  Future<void> dispose() async {
    await Future.wait([
      playingCtrl.close(),
      bufferingCtrl.close(),
      completedCtrl.close(),
      errorCtrl.close(),
      positionCtrl.close(),
      durationCtrl.close(),
    ]);
  }
}

/// Fuente mínima: solo arma URLs de reproducción ficticias.
class FakeSource implements ContentSource {
  List<String>? lastFormats;

  @override
  PlaybackCandidates liveStream(
    LiveChannel channel, {
    List<String> allowedFormats = const [],
  }) {
    lastFormats = allowedFormats;
    return PlaybackCandidates([
      Uri.parse('http://s.example.com/live/u/p/${channel.id}.m3u8'),
      Uri.parse('http://s.example.com/live/u/p/${channel.id}.ts'),
    ]);
  }

  @override
  SourceType get type => SourceType.xtream;
  @override
  Future<AccountInfo?> verify() => throw UnimplementedError();
  @override
  Future<AccountInfo?> fetchAccountInfo() => throw UnimplementedError();
  @override
  Future<List<ContentCategory>> liveCategories() => throw UnimplementedError();
  @override
  Future<List<LiveChannel>> liveChannels({String? categoryId}) =>
      throw UnimplementedError();
  @override
  Future<List<EpgEntry>> shortEpg(LiveChannel channel, {int limit = 4}) =>
      throw UnimplementedError();

  @override
  Future<List<ContentCategory>> vodCategories() => throw UnimplementedError();
  @override
  Future<List<VodItem>> vodItems({String? categoryId}) =>
      throw UnimplementedError();
  @override
  Future<VodDetail> vodDetail(VodItem item) => throw UnimplementedError();
  @override
  PlaybackCandidates movieStream(VodItem item) => PlaybackCandidates([
    Uri.parse('http://s.example.com/movie/u/p/${item.id}.mp4'),
  ]);
  @override
  Future<List<ContentCategory>> seriesCategories() =>
      throw UnimplementedError();
  @override
  Future<List<SeriesItem>> seriesItems({String? categoryId}) =>
      throw UnimplementedError();
  @override
  Future<SeriesDetail> seriesDetail(SeriesItem series) =>
      throw UnimplementedError();
  @override
  PlaybackCandidates episodeStream(Episode episode) => PlaybackCandidates([
    Uri.parse('http://s.example.com/series/u/p/${episode.id}.mkv'),
  ]);
}

const channels = [
  LiveChannel(id: '1', name: 'Uno'),
  LiveChannel(id: '2', name: 'Dos'),
  LiveChannel(id: '3', name: 'Tres'),
];

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
    void Function(FakeAsync async, FakeEngine engine, LivePlaybackController c)
    body, {
    int index = 0,
    List<String> formats = const ['m3u8', 'ts'],
  }) {
    fakeAsync((async) {
      final engine = FakeEngine();
      final controller = LivePlaybackController(
        engine: engine,
        source: FakeSource(),
        channels: channels,
        initialIndex: index,
        allowedFormats: formats,
      );
      controller.start();
      async.flushMicrotasks();
      body(async, engine, controller);
      controller.dispose();
    });
  }

  String fileOf(Uri u) => u.pathSegments.last;

  /// Error de mpv que sí es fatal: el video no avanza durante la gracia.
  void fatal(FakeAsync async, FakeEngine engine, [String message = 'x']) {
    engine.errorCtrl.add(message);
    async.elapse(const Duration(seconds: 3));
  }

  test('conecta y pasa a reproduciendo', () {
    run((async, engine, c) {
      expect(c.status, LivePlaybackStatus.connecting);
      expect(engine.opened.map(fileOf), ['1.m3u8']);
      engine.playingCtrl.add(true);
      engine.positionCtrl.add(const Duration(seconds: 1));
      expect(c.status, LivePlaybackStatus.playing);
    });
  });

  test('ante un error reconecta con espera progresiva alternando formato', () {
    run((async, engine, c) {
      engine.playingCtrl.add(true);
      engine.positionCtrl.add(const Duration(seconds: 1));
      fatal(async, engine, 'fallo http://s.example.com/live/u/p/1.m3u8');
      expect(c.status, LivePlaybackStatus.reconnecting);
      expect(c.attempt, 1);

      async.elapse(const Duration(milliseconds: 999));
      expect(engine.opened, hasLength(1), reason: 'espera 1 s');
      async.elapse(const Duration(milliseconds: 1));
      expect(engine.opened.map(fileOf), ['1.m3u8', '1.ts']);

      fatal(async, engine, 'otra vez');
      async.elapse(const Duration(seconds: 2));
      expect(engine.opened.map(fileOf).last, '1.m3u8');
      expect(c.attempt, 2);
    });
  });

  test('un canal en vivo que "termina" también reconecta', () {
    run((async, engine, c) {
      engine.completedCtrl.add(true);
      expect(c.status, LivePlaybackStatus.reconnecting);
    });
  });

  test('carga trabada más de 20 s = reconexión', () {
    run((async, engine, c) {
      engine.playingCtrl.add(true);
      engine.positionCtrl.add(const Duration(seconds: 1));
      engine.bufferingCtrl.add(true);
      async.elapse(const Duration(seconds: 19));
      expect(c.status, LivePlaybackStatus.playing);
      async.elapse(const Duration(seconds: 1));
      expect(c.status, LivePlaybackStatus.reconnecting);

      // Si la carga termina a tiempo, no reconecta.
      async.elapse(const Duration(seconds: 1));
      engine.playingCtrl.add(true);
      engine.positionCtrl.add(const Duration(seconds: 1));
      engine.bufferingCtrl.add(true);
      async.elapse(const Duration(seconds: 5));
      engine.bufferingCtrl.add(false);
      async.elapse(const Duration(seconds: 30));
      expect(c.status, LivePlaybackStatus.playing);
    });
  });

  test('se rinde tras 5 intentos y "Reintentar" vuelve a empezar', () {
    run((async, engine, c) {
      for (var i = 0; i < 5; i++) {
        fatal(async, engine);
        async.elapse(const Duration(seconds: 15));
      }
      fatal(async, engine);
      expect(c.status, LivePlaybackStatus.failed);
      expect(
        c.failureMessage,
        LivePlaybackController.channelUnavailableMessage,
      );
      final opened = engine.opened.length;

      // Ya rendido, más errores no programan reconexiones.
      fatal(async, engine);
      async.elapse(const Duration(minutes: 1));
      expect(engine.opened, hasLength(opened));

      c.retry();
      async.flushMicrotasks();
      expect(c.status, LivePlaybackStatus.connecting);
      expect(c.attempt, 0);
      expect(engine.opened, hasLength(opened + 1));
    });
  });

  test('30 s estable reinicia el contador de intentos', () {
    run((async, engine, c) {
      fatal(async, engine);
      async.elapse(const Duration(seconds: 1));
      engine.playingCtrl.add(true);
      engine.positionCtrl.add(const Duration(seconds: 1));
      expect(c.attempt, 1);
      async.elapse(const Duration(seconds: 30));
      expect(c.attempt, 0);
    });
  });

  test('errores repetidos no acumulan reconexiones', () {
    run((async, engine, c) {
      engine.errorCtrl.add('a');
      engine.errorCtrl.add('b');
      engine.completedCtrl.add(true);
      expect(c.attempt, 1);
      async.elapse(const Duration(seconds: 3));
      expect(c.attempt, 1, reason: 'la reconexión ya estaba programada');
      async.elapse(const Duration(seconds: 1));
      expect(engine.opened, hasLength(2));
    });
  });

  test('cambio de canal con vuelta al inicio y al final', () {
    run((async, engine, c) {
      c.previousChannel();
      async.flushMicrotasks();
      expect(c.channel.id, '3');
      c.nextChannel();
      async.flushMicrotasks();
      expect(c.channel.id, '1');
      c.nextChannel();
      async.flushMicrotasks();
      expect(engine.opened.map(fileOf).last, '2.m3u8');
      expect(c.attempt, 0);
    });
  });

  test('cambiar de canal cancela la reconexión pendiente del anterior', () {
    run((async, engine, c) {
      engine.errorCtrl.add('x');
      c.nextChannel();
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 20));
      expect(engine.opened.map(fileOf), ['1.m3u8', '2.m3u8']);
    });
  });

  test('pasa los formatos permitidos a la fuente', () {
    fakeAsync((async) {
      final source = FakeSource();
      final c = LivePlaybackController(
        engine: FakeEngine(),
        source: source,
        channels: channels,
        initialIndex: 0,
        allowedFormats: const ['ts'],
      )..start();
      async.flushMicrotasks();
      expect(source.lastFormats, ['ts']);
      c.dispose();
    });
  });

  test('los logs no contienen URLs ni el mensaje de mpv', () {
    run((async, engine, c) {
      fatal(
        async,
        engine,
        'fallo http://s.example.com/live/usuarioX/claveY/1.m3u8',
      );
      async.elapse(const Duration(seconds: 1));
    });
    final all = logs.join('\n');
    expect(all, contains('player.reconnect'));
    expect(all, isNot(contains('usuarioX')));
    expect(all, isNot(contains('claveY')));
  });

  test('fallo de la fuente al armar la URL = error claro', () {
    fakeAsync((async) {
      final c = LivePlaybackController(
        engine: FakeEngine(),
        source: _ThrowingSource(),
        channels: channels,
        initialIndex: 0,
      )..start();
      async.flushMicrotasks();
      expect(c.status, LivePlaybackStatus.failed);
      expect(c.failureMessage, const InvalidPlaylistFailure().message);
      c.dispose();
    });
  });

  test('playChannel: un segundo clic en el mismo canal no lo reabre', () {
    run((async, engine, c) {
      engine.playingCtrl.add(true);
      engine.positionCtrl.add(const Duration(seconds: 1));
      c.playChannel(channels, 0);
      async.flushMicrotasks();
      expect(engine.opened, hasLength(1));
      expect(c.status, LivePlaybackStatus.playing);
    });
  });

  test('playChannel: adopta otra lista y abre el canal pedido', () {
    run((async, engine, c) {
      const otra = [
        LiveChannel(id: '8', name: 'Ocho'),
        LiveChannel(id: '9', name: 'Nueve'),
      ];
      c.playChannel(otra, 1);
      async.flushMicrotasks();
      expect(c.channel.id, '9');
      expect(c.channels, otra);
      expect(engine.opened.map(fileOf).last, '9.m3u8');
      // Siguiente navega dentro de la lista nueva.
      c.nextChannel();
      async.flushMicrotasks();
      expect(c.channel.id, '8');
    });
  });

  test('playChannel: mismo canal pero fallido sí reintenta', () {
    run((async, engine, c) {
      for (var i = 0; i <= 5; i++) {
        fatal(async, engine);
        async.elapse(const Duration(seconds: 15));
      }
      expect(c.status, LivePlaybackStatus.failed);
      final opened = engine.opened.length;
      c.playChannel(channels, 0);
      async.flushMicrotasks();
      expect(engine.opened, hasLength(opened + 1));
    });
  });

  test('imagen: un aviso de mpv con el video avanzando no reconecta', () {
    run((async, engine, c) {
      engine.playingCtrl.add(true);
      engine.positionCtrl.add(const Duration(seconds: 1));
      engine.positionCtrl.add(const Duration(seconds: 10));
      engine.errorCtrl.add('Could not open codec.');
      engine.positionCtrl.add(const Duration(seconds: 12));
      async.elapse(const Duration(seconds: 5));
      expect(c.status, LivePlaybackStatus.playing);
      expect(engine.opened, hasLength(1));
      expect(logs.join('\n'), contains('player.error_ignored'));
    });
  });

  test('un aviso de mpv en pausa no reconecta', () {
    run((async, engine, c) {
      engine.playingCtrl.add(true);
      engine.positionCtrl.add(const Duration(seconds: 1));
      engine.playingCtrl.add(false);
      engine.errorCtrl.add('Could not open codec.');
      async.elapse(const Duration(seconds: 5));
      expect(engine.opened, hasLength(1));
    });
  });
}

class _ThrowingSource extends FakeSource {
  @override
  PlaybackCandidates liveStream(
    LiveChannel channel, {
    List<String> allowedFormats = const [],
  }) => throw const InvalidPlaylistFailure();
}
