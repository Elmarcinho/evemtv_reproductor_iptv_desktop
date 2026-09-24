import 'package:evemtv/core/errors/app_failure.dart';
import 'package:evemtv/core/logging/app_logger.dart';
import 'package:evemtv/features/player/media_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late LogSink originalSink;

  setUp(() {
    originalSink = AppLogger.sink;
    AppLogger.sink = (_, _) {};
  });

  tearDown(() => AppLogger.sink = originalSink);

  test('si libmpv falla lanza PlayerUnavailableFailure y no reintenta', () {
    var calls = 0;
    final engine = MediaEngine(
      initializer: () {
        calls++;
        throw ArgumentError('libmpv.so.2: no se pudo abrir');
      },
    );

    expect(engine.ensureReady, throwsA(isA<PlayerUnavailableFailure>()));
    expect(engine.ensureReady, throwsA(isA<PlayerUnavailableFailure>()));
    expect(calls, 1);
    expect(engine.isReady, isFalse);
  });

  test('inicializa una sola vez cuando funciona', () {
    var calls = 0;
    final engine = MediaEngine(initializer: () => calls++);

    engine.ensureReady();
    engine.ensureReady();

    expect(calls, 1);
    expect(engine.isReady, isTrue);
  });
}
