// Verificación de listas M3U con respuestas ficticias.
import 'package:dio/dio.dart';
import 'package:evemtv/core/errors/app_failure.dart';
import 'package:evemtv/core/logging/app_logger.dart';
import 'package:evemtv/data/m3u/m3u_source.dart';
import 'package:evemtv/domain/entities/source_credentials.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fixtures/xtream_fixtures.dart';
import '../../helpers/fakes.dart';

final credentials = M3uCredentials(
  playlist: Uri.parse('http://lista.example.com/get.php?username=a&password=b'),
);

void main() {
  late LogSink originalSink;
  setUp(() {
    originalSink = AppLogger.sink;
    AppLogger.sink = (_, _) {};
  });
  tearDown(() => AppLogger.sink = originalSink);

  M3uSource sourceWith(ResponseBody Function() body) =>
      M3uSource(testDio(FakeHttpAdapter((_) => body())), credentials);

  test('acepta una lista con cabecera #EXTM3U', () async {
    expect(await sourceWith(() => textBody(m3uHead)).verify(), isNull);
  });

  test('acepta BOM, espacios y listas sin cabecera con #EXTINF', () {
    expect(M3uSource.looksLikePlaylist('\uFEFF\n  #EXTM3U\n'), isTrue);
    expect(M3uSource.looksLikePlaylist('#extm3u'), isTrue);
    expect(
      M3uSource.looksLikePlaylist('#EXTINF:-1,Canal\nhttp://x.example.com/1'),
      isTrue,
    );
  });

  test('rechaza HTML u otros contenidos', () async {
    await expectLater(
      sourceWith(() => textBody(htmlPage)).verify(),
      throwsA(isA<InvalidPlaylistFailure>()),
    );
  });

  test('404 = no encontrada', () async {
    await expectLater(
      sourceWith(() => textBody('', 404)).verify(),
      throwsA(isA<ResourceNotFoundFailure>()),
    );
  });

  test('lee solo el inicio de listas grandes', () async {
    final big =
        '$m3uHead${'#EXTINF:-1,Canal\nhttp://s.example.com/1.ts\n' * 20000}';
    expect(big.length, greaterThan(M3uSource.probeBytes * 10));
    expect(await sourceWith(() => textBody(big)).verify(), isNull);
  });

  test(
    'Codex 7: una página de error que menciona #EXTINF no es una lista',
    () async {
      expect(
        M3uSource.looksLikePlaylist(
          '<html>Error: se esperaba #EXTINF para una lista</html>',
        ),
        isFalse,
      );
      expect(M3uSource.looksLikePlaylist('Error #EXTM3U'), isFalse);
      expect(M3uSource.looksLikePlaylist(''), isFalse);
      await expectLater(
        sourceWith(
          () => textBody(
            '<html>Error: se esperaba #EXTINF para una lista</html>',
          ),
        ).verify(),
        throwsA(isA<InvalidPlaylistFailure>()),
      );
    },
  );

  test(
    'Codex 8: se conservan como máximo 4 KB aunque llegue un chunk enorme',
    () async {
      final head = await M3uSource.readHead(
        Stream.fromIterable([List<int>.filled(1000008, 65)]),
      );
      expect(head.length, M3uSource.probeBytes);

      final many = await M3uSource.readHead(
        Stream.fromIterable(
          List.generate(10, (_) => List<int>.filled(1000, 65)),
        ),
      );
      expect(many.length, M3uSource.probeBytes);

      final small = await M3uSource.readHead(Stream.value([1, 2, 3]));
      expect(small, [1, 2, 3]);
    },
  );
}
