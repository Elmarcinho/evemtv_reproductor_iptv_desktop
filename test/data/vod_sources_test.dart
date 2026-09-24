// Películas y series: parsers y fuentes Xtream/M3U con datos ficticios.
import 'dart:convert';

import 'package:evemtv/core/errors/app_failure.dart';
import 'package:evemtv/core/logging/app_logger.dart';
import 'package:evemtv/data/m3u/m3u_catalog.dart';
import 'package:evemtv/data/m3u/m3u_source.dart';
import 'package:evemtv/data/xtream/xtream_client.dart';
import 'package:evemtv/data/xtream/xtream_source.dart';
import 'package:evemtv/data/xtream/xtream_vod_parser.dart';
import 'package:evemtv/domain/entities/source_credentials.dart';
import 'package:evemtv/domain/entities/vod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/vod_fixtures.dart';
import '../helpers/fakes.dart';

final credentials = XtreamCredentials(
  server: Uri.parse('http://panel.example.com:8080'),
  username: 'usu ario',
  password: 'cl@ve/1',
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

  group('XtreamVodParser películas', () {
    test('lista tolerante', () {
      final list = XtreamVodParser.movies(jsonDecode(vodStreamsJson));
      expect(list.map((m) => m.id), ['501', '502', '503']);
      final uno = list[0];
      expect(uno.rating, 7.4);
      expect(uno.year, 2021);
      expect(uno.containerExtension, 'mkv');
      expect(uno.posterUrl, 'http://img.example.com/p1.jpg');
      expect(list[1].rating, isNull, reason: 'rating 0 = sin puntaje');
      expect(list[1].containerExtension, 'mp4');
      expect(list[1].posterUrl, isNull);
      // Extensión con barras: se descarta para no alterar la URL.
      expect(list[2].containerExtension, isNull);
      expect(list[2].rating, isNull, reason: 'fuera de rango');
    });

    test('ficha completa', () {
      const item = VodItem(id: '501', name: 'Película Ficticia Uno');
      final d = XtreamVodParser.movieDetail(item, jsonDecode(vodInfoJson));
      expect(d.plot, 'Una historia inventada para las pruebas.');
      expect(d.genre, 'Drama');
      expect(d.cast, 'Actriz Uno, Actor Dos');
      expect(d.director, 'Directora Ficticia');
      expect(d.duration, const Duration(minutes: 105));
      expect(d.backdropUrl, 'http://img.example.com/fondo.jpg');
      expect(d.country, 'País Imaginario');
      // Completa lo que faltaba en el elemento de la grilla.
      expect(d.item.posterUrl, 'http://img.example.com/p1-grande.jpg');
      expect(d.item.containerExtension, 'mkv');
      expect(d.item.year, 2021);
    });

    test('ficha sin metadatos = ficha mínima, sin errores', () {
      const item = VodItem(id: '9', name: 'X', containerExtension: 'avi');
      final d = XtreamVodParser.movieDetail(item, jsonDecode(vodInfoEmptyJson));
      expect(d.plot, isNull);
      expect(d.item.containerExtension, 'avi');
      expect(XtreamVodParser.movieDetail(item, null).item.name, 'X');
    });

    test('duraciones', () {
      expect(
        XtreamVodParser.duration(null, '1:02:03'),
        const Duration(seconds: 3723),
      );
      expect(
        XtreamVodParser.duration(null, '45:00'),
        const Duration(minutes: 45),
      );
      expect(XtreamVodParser.duration('0', 'x'), isNull);
      expect(XtreamVodParser.duration('-5', '1:-2'), isNull);
    });
  });

  group('XtreamVodParser series', () {
    test('lista tolerante', () {
      final list = XtreamVodParser.series(jsonDecode(seriesJson));
      expect(list.map((s) => s.id), ['700', '701']);
      expect(list.first.rating, 8.2, reason: 'acepta coma decimal');
      expect(list.first.year, 2019);
    });

    test('temporadas ordenadas, episodios ordenados y sin repetidos', () {
      const series = SeriesItem(id: '700', name: 'Serie Ficticia');
      final d = XtreamVodParser.seriesDetail(
        series,
        jsonDecode(seriesInfoMapJson),
      );
      expect(d.seasons.map((s) => s.number), [1, 2]);
      expect(d.seasons.first.label, 'Temporada Uno');
      expect(d.seasons.last.label, 'Temporada 2');
      expect(d.seasons.first.posterUrl, 'http://img.example.com/t1.jpg');
      final t1 = d.seasons.first.episodes;
      expect(t1.map((e) => e.number), [1, 2]);
      expect(t1.map((e) => e.id), ['9001', '9002']);
      expect(t1[1].duration, const Duration(minutes: 45));
      expect(t1[1].plot, 'Sinopsis dos');
      expect(t1[1].containerExtension, 'mkv');
      expect(
        d.seasons.last.episodes.single.duration,
        const Duration(minutes: 45),
      );
      expect(d.plot, 'Trama ficticia.');
      expect(d.backdropUrl, 'http://img.example.com/fondo-serie.jpg');
    });

    test('episodios como lista de listas', () {
      const series = SeriesItem(id: '1', name: 'X');
      final d = XtreamVodParser.seriesDetail(
        series,
        jsonDecode(seriesInfoListJson),
      );
      expect(d.seasons.map((s) => s.number), [1, 2]);
      expect(d.seasons.last.episodes.single.title, 'B');
    });

    test('respuesta vacía = sin temporadas', () {
      const series = SeriesItem(id: '1', name: 'X');
      expect(XtreamVodParser.seriesDetail(series, []).seasons, isEmpty);
    });
  });

  group('XtreamSource películas y series', () {
    XtreamSource source(FakeHttpAdapter adapter) =>
        XtreamSource(XtreamClient(testDio(adapter), credentials));

    test('URLs de película y episodio con credenciales como segmentos', () {
      final s = source(FakeHttpAdapter((_) => jsonBody('[]')));
      final movie = s
          .movieStream(
            const VodItem(id: '501', name: 'x', containerExtension: 'mkv'),
          )
          .urls
          .single;
      expect(movie.pathSegments, ['movie', 'usu ario', 'cl@ve/1', '501.mkv']);
      final episode = s
          .episodeStream(
            const Episode(id: '9001', season: 1, number: 1, title: 'x'),
          )
          .urls
          .single;
      expect(episode.pathSegments.last, '9001.mp4', reason: 'mp4 por defecto');
      expect(episode.pathSegments.first, 'series');
    });

    test('acciones y parámetros de la API', () async {
      final adapter = FakeHttpAdapter((o) {
        return switch (o.uri.queryParameters['action']) {
          'get_vod_streams' => jsonBody(vodStreamsJson),
          'get_vod_info' => jsonBody(vodInfoJson),
          'get_series' => jsonBody(seriesJson),
          'get_series_info' => jsonBody(seriesInfoMapJson),
          _ => jsonBody('[]'),
        };
      });
      final s = source(adapter);
      expect(await s.vodItems(categoryId: '10'), hasLength(3));
      expect(adapter.requests.last.uri.queryParameters['category_id'], '10');
      await s.vodDetail(const VodItem(id: '501', name: 'x'));
      expect(adapter.requests.last.uri.queryParameters['vod_id'], '501');
      expect(await s.seriesItems(), hasLength(2));
      final d = await s.seriesDetail(const SeriesItem(id: '700', name: 'x'));
      expect(adapter.requests.last.uri.queryParameters['series_id'], '700');
      expect(d.seasons, hasLength(2));
      final all = logs.join('\n');
      expect(all, isNot(contains('cl@ve')));
      expect(all, isNot(contains('historia inventada')));
    });
  });

  group('M3uCatalog', () {
    test('separa vivo, películas y series con sus categorías', () async {
      final m3u = M3uSource(
        testDio(FakeHttpAdapter((_) => textBody(m3uVod))),
        M3uCredentials(playlist: Uri.parse('http://lista.example.com/a.m3u')),
      );
      expect(await m3u.liveChannels(), hasLength(1));
      expect(await m3u.vodItems(), hasLength(2));
      expect(await m3u.seriesItems(), hasLength(3));
    });

    test('nombres de episodio', () {
      expect(M3uCatalog.parseEpisodeName('Serie Ficticia S01 E02 Segundo'), (
        show: 'Serie Ficticia',
        season: 1,
        episode: 2,
        title: 'Segundo',
      ));
      expect(M3uCatalog.parseEpisodeName('Serie - S02E10 - Título'), (
        show: 'Serie',
        season: 2,
        episode: 10,
        title: 'Título',
      ));
      expect(M3uCatalog.parseEpisodeName('Otra Serie 1x03'), (
        show: 'Otra Serie',
        season: 1,
        episode: 3,
        title: null,
      ));
      expect(M3uCatalog.parseEpisodeName('Especial'), (
        show: 'Especial',
        season: null,
        episode: null,
        title: null,
      ));
    });
  });

  group('M3uSource películas y series', () {
    late M3uSource source;
    late FakeHttpAdapter adapter;
    setUp(() {
      adapter = FakeHttpAdapter((_) => textBody(m3uVod));
      source = M3uSource(
        testDio(adapter),
        M3uCredentials(playlist: Uri.parse('http://lista.example.com/a.m3u')),
      );
    });

    test('películas por categoría con año y extensión', () async {
      expect((await source.vodCategories()).map((c) => c.name), [
        'Estrenos',
        'Clásicos',
      ]);
      final movies = await source.vodItems();
      expect(movies.map((m) => m.name), [
        'Película Ficticia (2022)',
        'Otra Película',
      ]);
      expect(movies.first.year, 2022);
      expect(movies.first.containerExtension, 'mkv');
      expect(movies.first.id, startsWith('m3u:'));
      expect(
        source.movieStream(movies.first).urls.single.toString(),
        'http://stream.example.com/movie/u/p/10.mkv',
      );
      final detail = await source.vodDetail(movies.first);
      expect(detail.plot, isNull);
      // Una sola descarga para vivo, películas y series.
      await source.seriesItems();
      await source.liveChannels();
      expect(adapter.requests, hasLength(1));
    });

    test(
      'series agrupadas por nombre, temporadas y episodios ordenados',
      () async {
        final series = await source.seriesItems();
        expect(series.map((s) => s.name), [
          'Serie Ficticia',
          'Otra Serie',
          'Especial sin numeración',
        ]);
        final serie = series.first;
        expect(serie.posterUrl, 'http://img.example.com/s1.jpg');
        final d = await source.seriesDetail(serie);
        expect(d.seasons.map((s) => s.number), [1, 2]);
        expect(d.seasons.first.episodes.map((e) => e.number), [1, 2]);
        expect(d.seasons.first.episodes.last.title, 'Segundo');
        expect(d.seasons.last.episodes.single.title, 'Vuelta');
        final ep = d.seasons.first.episodes.first;
        expect(
          source.episodeStream(ep).urls.single.toString(),
          'http://stream.example.com/series/u/p/101.mp4',
        );
        // Sin numeración: temporada 1, episodio 1.
        final especial = await source.seriesDetail(series.last);
        expect(especial.seasons.single.episodes.single.number, 1);
      },
    );

    test('serie desconocida = error claro', () async {
      await source.seriesItems();
      await expectLater(
        source.seriesDetail(const SeriesItem(id: 'm3u:nada', name: 'x')),
        throwsA(isA<InvalidPlaylistFailure>()),
      );
    });
  });
}
