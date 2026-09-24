// TV en vivo: parsers y fuentes Xtream/M3U con datos ficticios.
import 'dart:convert';

import 'package:evemtv/core/errors/app_failure.dart';
import 'package:evemtv/core/logging/app_logger.dart';
import 'package:evemtv/core/utils/stable_id.dart';
import 'package:evemtv/core/utils/task_pool.dart';
import 'package:evemtv/data/m3u/m3u_parser.dart';
import 'package:evemtv/data/m3u/m3u_source.dart';
import 'package:evemtv/data/xtream/xtream_client.dart';
import 'package:evemtv/data/xtream/xtream_live_parser.dart';
import 'package:evemtv/data/xtream/xtream_source.dart';
import 'package:evemtv/domain/entities/live.dart';
import 'package:evemtv/domain/entities/source_credentials.dart';
import 'package:evemtv/features/live/live_providers.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/live_fixtures.dart';
import '../helpers/fakes.dart';

final xtreamCredentials = XtreamCredentials(
  server: Uri.parse('http://panel.example.com:8080'),
  username: 'usu ario/1',
  password: 'cl@ve?#',
);

void main() {
  late LogSink originalSink;
  late List<String> logs;
  setUp(() {
    logs = [];
    originalSink = AppLogger.sink;
    AppLogger.sink = (_, m) => logs.add(m);
  });
  tearDown(() => AppLogger.sink = originalSink);

  group('XtreamLiveParser', () {
    test('categorías tolerantes', () {
      final list = XtreamLiveParser.categories(jsonDecode(liveCategoriesJson));
      expect(list.map((c) => (c.id, c.name)), [
        ('1', 'Noticias'),
        ('2', 'Sin nombre'),
      ]);
      expect(XtreamLiveParser.categories({}), isEmpty);
      expect(XtreamLiveParser.categories(null), isEmpty);
    });

    test('canales tolerantes', () {
      final list = XtreamLiveParser.channels(jsonDecode(liveStreamsJson));
      expect(list.map((c) => c.id), ['101', '102', '103']);
      final uno = list[0];
      expect(uno.number, 1);
      expect(uno.logoUrl, 'http://img.example.com/1.png');
      expect(uno.epgChannelId, 'uno.example');
      expect(uno.categoryId, '1');
      expect(uno.hasArchive, isTrue);
      expect(list[1].number, 2);
      expect(list[1].logoUrl, isNull);
      expect(list[1].hasArchive, isFalse);
      // Nombre vacío → genérico; logo con esquema no http → ignorado.
      expect(list[2].name, 'Canal 103');
      expect(list[2].logoUrl, isNull);
    });

    test('EPG corta: base64, orden, horarios inválidos descartados', () {
      final epg = XtreamLiveParser.shortEpg(jsonDecode(shortEpgJson()));
      expect(epg.map((e) => e.title), [
        'Noticiero Ficticio',
        'Programa Siguiente',
        'Texto sin base64',
      ]);
      expect(epg.first.description, 'Resumen del día');
      expect(epg.first.start, DateTime.utc(2026, 1, 1));
      expect(XtreamLiveParser.shortEpg([]), isEmpty);
      expect(
        XtreamLiveParser.shortEpg({'epg_listings': <String, Object?>{}}),
        isEmpty,
      );
    });

    test('decodeText no confunde texto normal con base64', () {
      expect(XtreamLiveParser.decodeText('Noticias'), 'Noticias');
      expect(XtreamLiveParser.decodeText(b64('Fútbol')), 'Fútbol');
      expect(XtreamLiveParser.decodeText('###'), '###');
    });
  });

  group('XtreamSource en vivo', () {
    test('formatos según allowed_output_formats', () {
      expect(XtreamSource.liveExtensions([]), ['m3u8', 'ts']);
      expect(XtreamSource.liveExtensions(['ts']), ['ts']);
      expect(XtreamSource.liveExtensions(['M3U8', 'ts', 'rtmp']), [
        'm3u8',
        'ts',
      ]);
      expect(XtreamSource.liveExtensions(['rtmp']), ['m3u8', 'ts']);
    });

    test('URL de vivo con credenciales codificadas como segmentos', () {
      final source = XtreamSource(
        XtreamClient(
          testDio(FakeHttpAdapter((_) => jsonBody('[]'))),
          xtreamCredentials,
        ),
      );
      const channel = LiveChannel(id: '101', name: 'Canal Uno');
      final urls = source
          .liveStream(channel, allowedFormats: ['ts', 'm3u8'])
          .urls;
      expect(urls, hasLength(2));
      expect(urls.first.pathSegments, [
        'live',
        'usu ario/1',
        'cl@ve?#',
        '101.m3u8',
      ]);
      expect(urls.last.pathSegments.last, '101.ts');
      expect(urls.first.port, 8080);
      // Los caracteres especiales no rompen la ruta.
      expect(urls.first.toString(), isNot(contains('?#')));
    });

    test('pide categorías y canales por categoría', () async {
      final adapter = FakeHttpAdapter((o) {
        final action = o.uri.queryParameters['action'];
        return jsonBody(
          action == 'get_live_categories'
              ? liveCategoriesJson
              : liveStreamsJson,
        );
      });
      final source = XtreamSource(
        XtreamClient(testDio(adapter), xtreamCredentials),
      );
      expect(await source.liveCategories(), hasLength(2));
      expect(await source.liveChannels(categoryId: '1'), hasLength(3));
      expect(adapter.requests.last.uri.queryParameters['category_id'], '1');
      await source.liveChannels();
      expect(
        adapter.requests.last.uri.queryParameters.containsKey('category_id'),
        isFalse,
      );
    });

    test('respuestas grandes se decodifican fuera del hilo de UI', () async {
      final big = jsonEncode([
        for (var i = 0; i < 6000; i++)
          {
            'stream_id': i,
            'name': 'Canal ficticio número $i',
            'category_id': '1',
          },
      ]);
      expect(big.length, greaterThan(XtreamClient.isolateDecodeThreshold));
      final source = XtreamSource(
        XtreamClient(
          testDio(FakeHttpAdapter((_) => jsonBody(big))),
          xtreamCredentials,
        ),
      );
      expect(await source.liveChannels(), hasLength(6000));
    });

    test('la EPG corta no registra títulos ni credenciales', () async {
      final source = XtreamSource(
        XtreamClient(
          testDio(FakeHttpAdapter((_) => jsonBody(shortEpgJson()))),
          xtreamCredentials,
        ),
      );
      final epg = await source.shortEpg(
        const LiveChannel(id: '101', name: 'x'),
      );
      expect(epg, hasLength(3));
      final all = logs.join('\n');
      expect(all, contains('get_short_epg'));
      expect(all, isNot(contains('Noticiero')));
      expect(all, isNot(contains('cl@ve')));
    });
  });

  group('M3uParser', () {
    late M3uPlaylist playlist;
    setUp(() => playlist = M3uParser.parse(m3uFull));

    test('cabecera: guía XMLTV', () {
      expect(playlist.epgUrl.toString(), 'http://epg.example.com/guia.xml');
    });

    test('entradas, atributos, comas entre comillas y nombres', () {
      final names = playlist.entries.map((e) => e.name).toList();
      expect(names, [
        'Canal Uno',
        'Canal Dos, con coma',
        'Nombre por atributo',
        'Canal con EXTGRP',
        'sin-extinf',
        'Película Ficticia',
        'Episodio Ficticio',
        'Canal Uno repetido',
      ]);
      final uno = playlist.entries[0];
      expect(uno.group, 'Noticias');
      expect(uno.tvgId, 'uno.example');
      expect(uno.channelNumber, 1);
      expect(uno.logoUrl, 'http://img.example.com/1.png');
      final dos = playlist.entries[1];
      expect(dos.group, 'Deportes, Fútbol');
      expect(dos.logoUrl, isNull, reason: 'logo data: ignorado');
      expect(playlist.entries[3].group, 'Música');
      expect(playlist.entries[4].group, isNull);
    });

    test('tipo deducido por la URL', () {
      expect(playlist.entries[0].kind, M3uKind.live);
      expect(playlist.entries[5].kind, M3uKind.movie);
      expect(playlist.entries[6].kind, M3uKind.series);
      expect(
        M3uParser.guessKind(Uri.parse('http://x.example.com/peli.MP4')),
        M3uKind.movie,
      );
    });

    test('nunca lanza con entradas rotas', () {
      expect(M3uParser.parse('').entries, isEmpty);
      expect(M3uParser.parse('#EXTM3U\n#EXTINF:-1,\n\n').entries, isEmpty);
      expect(
        M3uParser.parse(
          '#EXTINF:-1 "sin cerrar,Nombre\nhttp://x.example.com/%FF',
        ).entries,
        hasLength(1),
      );
    });
  });

  group('M3uSource en vivo', () {
    final m3uCredentials = M3uCredentials(
      playlist: Uri.parse(
        'http://lista.example.com/get.php?username=a&password=b',
      ),
    );

    test('categorías por group-title, sin VOD ni duplicados', () async {
      final adapter = FakeHttpAdapter((_) => textBody(m3uFull));
      final source = M3uSource(testDio(adapter), m3uCredentials);
      final categories = await source.liveCategories();
      expect(categories.map((c) => c.name), [
        'Noticias',
        'Deportes, Fútbol',
        'Sin categoría',
        'Música',
      ]);
      final all = await source.liveChannels();
      expect(all.map((c) => c.name), [
        'Canal Uno',
        'Canal Dos, con coma',
        'Nombre por atributo',
        'Canal con EXTGRP',
        'sin-extinf',
      ]);
      expect(await source.liveChannels(categoryId: 'Noticias'), hasLength(1));
      // La lista se descarga una sola vez por sesión.
      expect(adapter.requests, hasLength(1));
    });

    test('ids estables sin credenciales y URL para reproducir', () async {
      final source = M3uSource(
        testDio(FakeHttpAdapter((_) => textBody(m3uFull))),
        m3uCredentials,
      );
      final uno = (await source.liveChannels()).first;
      expect(
        uno.id,
        'm3u:${stableHash('http://stream.example.com/live/u/p/1.ts')}',
      );
      expect(uno.id, isNot(contains('stream.example.com')));
      expect(
        source.liveStream(uno).urls.single.toString(),
        'http://stream.example.com/live/u/p/1.ts',
      );
      expect(
        () => source.liveStream(const LiveChannel(id: 'm3u:otro', name: 'x')),
        throwsA(isA<InvalidPlaylistFailure>()),
      );
    });

    test(
      'lista vacía o error: mensaje claro y se reintenta la descarga',
      () async {
        var calls = 0;
        final adapter = FakeHttpAdapter(
          (_) => ++calls == 1 ? textBody('#EXTM3U\n') : textBody(m3uFull),
        );
        final source = M3uSource(testDio(adapter), m3uCredentials);
        await expectLater(
          source.liveCategories(),
          throwsA(isA<InvalidPlaylistFailure>()),
        );
        expect(await source.liveCategories(), isNotEmpty);
        expect(calls, 2);
      },
    );

    test('las listas no traen EPG corta', () async {
      final source = M3uSource(
        testDio(FakeHttpAdapter((_) => textBody(m3uFull))),
        m3uCredentials,
      );
      expect(
        await source.shortEpg(const LiveChannel(id: 'x', name: 'x')),
        isEmpty,
      );
    });
  });

  group('utilidades', () {
    test('stableHash: FNV-1a 64 con vectores conocidos', () {
      expect(stableHash(''), 'cbf29ce484222325');
      expect(stableHash('a'), 'af63dc4c8601ec8c');
      expect(stableHash('foobar'), '85944171f73967e8');
    });

    test('TaskPool no supera el máximo de tareas simultáneas', () async {
      final pool = TaskPool(2);
      var running = 0;
      var peak = 0;
      Future<void> task() => pool.run(() async {
        running++;
        peak = running > peak ? running : peak;
        await Future<void>.delayed(const Duration(milliseconds: 5));
        running--;
      });
      await Future.wait([for (var i = 0; i < 8; i++) task()]);
      expect(peak, 2);
    });

    test('nowAndNext', () {
      final e1 = EpgEntry(
        title: 'A',
        start: DateTime.utc(2026, 1, 1, 10),
        end: DateTime.utc(2026, 1, 1, 11),
      );
      final e2 = EpgEntry(
        title: 'B',
        start: DateTime.utc(2026, 1, 1, 11),
        end: DateTime.utc(2026, 1, 1, 12),
      );
      final at = DateTime.utc(2026, 1, 1, 10, 30);
      expect(nowAndNext([e1, e2], at), (now: e1, next: e2));
      expect(nowAndNext([e2], at), (now: null, next: e2));
      expect(nowAndNext([], at), (now: null, next: null));
      expect(e1.progressAt(at), 0.5);
    });
  });
}
