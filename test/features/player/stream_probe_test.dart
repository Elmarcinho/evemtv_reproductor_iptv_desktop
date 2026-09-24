// Consulta HTTP de un stream con servidor simulado.
import 'package:dio/dio.dart';
import 'package:evemtv/core/logging/app_logger.dart';
import 'package:evemtv/features/player/stream_probe.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fakes.dart';

void main() {
  late LogSink originalSink;
  late List<String> logs;
  setUp(() {
    logs = [];
    originalSink = AppLogger.sink;
    AppLogger.sink = (_, m) => logs.add(m);
  });
  tearDown(() => AppLogger.sink = originalSink);

  final url = Uri.parse('http://s.example.com/movie/usuarioX/claveY/1.mp4');

  test('devuelve el código, pide un solo byte y no reintenta', () async {
    final adapter = FakeHttpAdapter((_) => textBody('', 404));
    final probe = httpStreamProbe(testDio(adapter));
    expect(await probe(url), 404);
    expect(adapter.requests, hasLength(1));
    expect(adapter.requests.single.headers['Range'], 'bytes=0-0');
    expect(logs.join('\n'), isNot(contains('claveY')));
  });

  test('206 y 200 se informan tal cual', () async {
    expect(
      await httpStreamProbe(
        testDio(FakeHttpAdapter((_) => textBody('x', 206))),
      )(url),
      206,
    );
  });

  test('sin conexión = null', () async {
    final adapter = FakeHttpAdapter(
      (o) => throw DioException.connectionError(requestOptions: o, reason: 'x'),
    );
    expect(await httpStreamProbe(testDio(adapter))(url), isNull);
    expect(adapter.requests, hasLength(1), reason: 'sin reintentos');
  });

  test('protocolos que no son http = null sin consultar', () async {
    final adapter = FakeHttpAdapter((_) => textBody('', 200));
    expect(
      await httpStreamProbe(testDio(adapter))(
        Uri.parse('rtmp://s.example.com/x'),
      ),
      isNull,
    );
    expect(adapter.requests, isEmpty);
  });
}
