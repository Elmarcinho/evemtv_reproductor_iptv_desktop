// Aviso de actualización. Respuestas simuladas; nunca sale a la red real.
import 'package:dio/dio.dart';
import 'package:evemtv/core/logging/app_logger.dart';
import 'package:evemtv/data/providers.dart';
import 'package:evemtv/features/home/promo_banner.dart';
import 'package:evemtv/features/update/update_check.dart';
import 'package:evemtv/features/update/update_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fakes.dart';

final _endpoint = Uri.parse('http://127.0.0.1:18080/api/evemtv/version');
const _current = AppVersion(1, 0, 0);
const _release =
    'https://github.com/Elmarcinho/evemtv_reproductor_iptv_desktop/releases/tag/v1.1.0';

void main() {
  late LogSink originalSink;
  setUp(() {
    originalSink = AppLogger.sink;
    AppLogger.sink = (_, _) {};
  });
  tearDown(() => AppLogger.sink = originalSink);

  group('versiones', () {
    test('se comparan por número, no como texto', () {
      AppVersion v(String s) => AppVersion.tryParse(s)!;
      expect(v('1.10.0') > v('1.9.9'), isTrue);
      expect(v('2.0.0') > v('1.99.99'), isTrue);
      expect(v('1.0.0') == v('v1.0.0'), isTrue);
      expect(v('1.2') == v('1.2.0'), isTrue);
      expect(v('1.0.0+7') == v('1.0.0'), isTrue);
      expect(v('1.0.1') < v('1.0.2'), isTrue);
    });

    test('valores raros no rompen nada', () {
      for (final raw in [null, '', 'abc', '1..2', '1.2.3.4', <int>[]]) {
        expect(AppVersion.tryParse(raw), isNull, reason: '$raw');
      }
      expect(AppVersion.tryParse(2), const AppVersion(2, 0, 0));
      expect(AppVersion.tryParse(1.5), const AppVersion(1, 5, 0));
    });
  });

  group('enlaces de descarga', () {
    test('se aceptan solo github.com/Elmarcinho y godebol.com por HTTPS', () {
      for (final ok in [
        _release,
        'https://github.com/elmarcinho/otro/releases/latest',
        'https://godebol.com/evemtv/descargas',
      ]) {
        expect(isTrustedDownload(Uri.parse(ok)), isTrue, reason: ok);
      }
      for (final bad in [
        'http://github.com/Elmarcinho/x/releases',
        'https://github.com/OtroUsuario/x/releases',
        'https://github.com/',
        'https://godebol.com.example.com/x',
        'https://evil.example.com/godebol.com',
        'https://sub.godebol.com/x',
        'https://usuario:clave@godebol.com/x',
        'https://godebol.com:8443/x',
        'https://github.com.example.com/Elmarcinho/x',
        'javascript:alert(1)',
        'file:///etc/passwd',
      ]) {
        expect(isTrustedDownload(Uri.parse(bad)), isFalse, reason: bad);
      }
    });
  });

  group('respuesta del servidor', () {
    test('versión nueva: aviso cerrable con el enlace recibido', () {
      final info = parseUpdate({
        'ultima_version': '1.1.0',
        'descarga': _release,
        'minima': '1.0.0',
      }, _current)!;
      expect(info.latest, const AppVersion(1, 1, 0));
      expect(info.forced, isFalse);
      expect(info.download, Uri.parse(_release));
    });

    test('instalada menor que la mínima: aviso obligatorio', () {
      final info = parseUpdate({
        'ultima_version': '1.3.0',
        'descarga': _release,
        'minima': '1.2.0',
      }, _current)!;
      expect(info.forced, isTrue);
      expect(info.latest, const AppVersion(1, 3, 0));
    });

    test('al día (o más nueva que la publicada): nada', () {
      expect(
        parseUpdate({'ultima_version': '1.0.0', 'minima': '0.9.0'}, _current),
        isNull,
      );
      expect(parseUpdate({'ultima_version': '0.9.0'}, _current), isNull);
    });

    test('enlace no confiable: se usa la página de releases', () {
      final info = parseUpdate({
        'ultima_version': '1.1.0',
        'descarga': 'https://descargas.example.com/evemtv.exe',
      }, _current)!;
      expect(info.download, UpdateConfig.fallbackDownload);
      expect(isTrustedDownload(UpdateConfig.fallbackDownload), isTrue);
    });

    test('campos raros o faltantes no rompen nada', () {
      for (final json in <Object?>[
        null,
        'texto',
        [],
        <String, Object?>{},
        {'ultima_version': null, 'descarga': 5},
        {'ultima_version': 'x.y', 'minima': <int>[]},
      ]) {
        expect(parseUpdate(json, _current), isNull, reason: '$json');
      }
      // Sin enlace ni mínima, pero con versión nueva: aviso con respaldo.
      final info = parseUpdate({'ultima_version': 2}, _current)!;
      expect(info.latest, const AppVersion(2, 0, 0));
      expect(info.download, UpdateConfig.fallbackDownload);
      // Mínima mayor que la "última": manda la mínima.
      final odd = parseUpdate({
        'ultima_version': '1.1.0',
        'minima': '1.5.0',
      }, _current)!;
      expect(odd.latest, const AppVersion(1, 5, 0));
      expect(odd.forced, isTrue);
    });
  });

  group('consulta', () {
    late FakeHttpAdapter http;
    setUp(() => http = FakeHttpAdapter((_) => jsonBody('{}')));

    UpdateChecker checker({bool enabled = true}) => UpdateChecker(
      dio: testDio(http),
      endpoint: enabled ? _endpoint : null,
      current: _current,
    );

    test('GET sin datos de cuenta ni instalación', () async {
      http.handler = (_) => jsonBody(
        '{"ultima_version":"1.1.0","descarga":"$_release","minima":"1.0.0"}',
      );
      final info = await checker().check();
      expect(info?.latest, const AppVersion(1, 1, 0));
      final request = http.requests.single;
      expect(request.method, 'GET');
      expect(request.uri, _endpoint);
      expect(request.data, isNull);
    });

    for (final code in [404, 429, 500, 503]) {
      test('$code: se ignora', () async {
        http.handler = (_) => jsonBody('{"ultima_version":"9.0.0"}', code);
        expect(await checker().check(), isNull);
        expect(http.requests, hasLength(1), reason: 'sin reintentos');
      });
    }

    test('sin conexión o JSON inválido: se ignora sin lanzar', () async {
      http.handler = (o) =>
          throw DioException.connectionError(requestOptions: o, reason: 'x');
      expect(await checker().check(), isNull);
      http.handler = (_) => textBody('<html>no es JSON</html>');
      expect(await checker().check(), isNull);
    });

    test('desactivado: no consulta', () async {
      expect(await checker(enabled: false).check(), isNull);
      expect(http.requests, isEmpty);
    });

    test('en depuración y tests el destino nunca es el servidor real', () {
      final c = ProviderContainer.test();
      expect(
        c.read(updateEndpointProvider),
        isNot(UpdateConfig.releaseEndpoint),
      );
    });
  });

  group('aviso', () {
    late FakeHttpAdapter http;
    late List<Uri> opened;
    late int appTaps;

    // Desmonta y cancela la consulta periódica antes de que el test
    // verifique que no quedan temporizadores.
    Future<void> finish(WidgetTester tester, ProviderContainer c) async {
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    }

    Future<ProviderContainer> pump(WidgetTester tester, String json) async {
      http = FakeHttpAdapter((_) => jsonBody(json));
      opened = [];
      appTaps = 0;
      final container = ProviderContainer.test(
        overrides: [
          dioProvider.overrideWithValue(testDio(http)),
          updateEndpointProvider.overrideWithValue(_endpoint),
          externalLinkProvider.overrideWithValue((url) async {
            opened.add(url);
            return true;
          }),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            builder: (context, child) => UpdateGate(child: child!),
            home: Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => appTaps++,
                  child: const Text('Pantalla de la app'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(UpdateConfig.firstDelay);
      await tester.pumpAndSettle();
      return container;
    }

    testWidgets('versión nueva: se puede descargar y cerrar', (tester) async {
      final c = await pump(
        tester,
        '{"ultima_version":"1.1.0","descarga":"$_release","minima":"0.5.0"}',
      );
      expect(find.text('Nueva versión 1.1.0 disponible'), findsOneWidget);
      await tester.tap(find.text('Descargar'));
      expect(opened, [Uri.parse(_release)]);
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pump();
      expect(find.text('Nueva versión 1.1.0 disponible'), findsNothing);
      await finish(tester, c);
    });

    testWidgets('versión obligatoria: no se cierra y tapa la app', (
      tester,
    ) async {
      final c = await pump(
        tester,
        '{"ultima_version":"2.0.0","descarga":"$_release","minima":"2.0.0"}',
      );
      expect(find.text('Actualización necesaria'), findsOneWidget);
      expect(find.byIcon(Icons.close_rounded), findsNothing);
      c.read(updateProvider.notifier).dismiss();
      await tester.pump();
      expect(find.text('Actualización necesaria'), findsOneWidget);
      // La pantalla de abajo no recibe clics.
      await tester.tap(find.text('Pantalla de la app'), warnIfMissed: false);
      expect(appTaps, 0);
      await tester.tap(find.text('Descargar'));
      expect(opened, [Uri.parse(_release)]);
      await finish(tester, c);
    });

    testWidgets('al día: no se muestra nada', (tester) async {
      final c = await pump(tester, '{"ultima_version":"1.0.0"}');
      expect(find.text('Descargar'), findsNothing);
      await finish(tester, c);
    });
  });
}
