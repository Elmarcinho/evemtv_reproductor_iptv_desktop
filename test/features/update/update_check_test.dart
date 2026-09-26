// Aviso de actualización. Respuestas simuladas; nunca sale a la red real.
import 'dart:async';
import 'dart:io' show HttpDate;

import 'package:dio/dio.dart';
import 'package:evemtv/core/logging/app_logger.dart';
import 'package:evemtv/data/providers.dart';
import 'package:evemtv/domain/repositories/settings_repository.dart';
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
    test('se aceptan solo github.com/Elmarcinho, godebol.com y '
        'evemtv.godebol.com por HTTPS', () {
      for (final ok in [
        _release,
        'https://github.com/elmarcinho/otro/releases/latest',
        'https://godebol.com/evemtv/descargas',
        'https://evemtv.godebol.com/',
        'https://EvemTv.Godebol.com/#windows',
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
        'http://evemtv.godebol.com/',
        'https://evemtv.godebol.com.example.com/',
        'https://x.evemtv.godebol.com/',
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
    });
  });

  group('la mínima solo cuenta con una respuesta coherente', () {
    Map<String, Object?> body({
      Object? ultima = '1.3.0',
      Object? minima = '1.2.0',
      Object? descarga = _release,
    }) => {'ultima_version': ?ultima, 'minima': ?minima, 'descarga': ?descarga};

    test('las tres válidas y minima <= ultima_version: obligatoria', () {
      expect(parseUpdate(body(), _current)!.forced, isTrue);
      expect(
        parseUpdate(body(ultima: '1.2.0'), _current)!.forced,
        isTrue,
        reason: 'minima == ultima_version',
      );
    });

    test('minima mayor que ultima_version: solo aviso informativo', () {
      final info = parseUpdate(body(minima: '1.5.0'), _current)!;
      expect(info.forced, isFalse);
      expect(info.minimum, isNull);
      expect(info.latest, const AppVersion(1, 3, 0));
      // Tampoco "sube" la última a la mínima.
      final odd = parseUpdate(
        body(ultima: '1.1.0', minima: '9.0.0'),
        _current,
      )!;
      expect(odd.latest, const AppVersion(1, 1, 0));
      expect(odd.forced, isFalse);
    });

    test('sin enlace, con enlace inválido o ajeno: solo aviso informativo', () {
      for (final descarga in <Object?>[
        null,
        '',
        5,
        'no es un enlace',
        'http://github.com/Elmarcinho/x/releases',
        'https://descargas.example.com/evemtv.exe',
      ]) {
        final info = parseUpdate(body(descarga: descarga), _current)!;
        expect(info.forced, isFalse, reason: '$descarga');
        expect(info.download, UpdateConfig.fallbackDownload);
      }
    });

    test('sin ultima_version válida: nada, aunque la mínima exija', () {
      for (final ultima in <Object?>[null, '', 'x.y', <int>[]]) {
        expect(
          parseUpdate(body(ultima: ultima, minima: '2.0.0'), _current),
          isNull,
          reason: '$ultima',
        );
      }
    });

    test('mínima rara: se ignora', () {
      for (final minima in <Object?>['x', '', <int>[], true]) {
        final info = parseUpdate(body(minima: minima), _current)!;
        expect(info.forced, isFalse, reason: '$minima');
      }
    });
  });

  group('fecha del servidor (encabezado Date)', () {
    test('formato HTTP estándar', () {
      expect(
        parseServerDate('Sat, 26 Sep 2026 12:00:00 GMT'),
        DateTime.utc(2026, 9, 26, 12),
      );
    });

    test('ausente o ilegible: null', () {
      for (final raw in [
        null,
        '',
        '   ',
        'ayer',
        '2026-09-26',
        'Sat, 99 Foo',
      ]) {
        expect(parseServerDate(raw), isNull, reason: '$raw');
      }
    });

    test('fechas imposibles: null (HttpDate.parse las "corrige")', () {
      // Caso de la revisión: HttpDate.parse lo toma como 08/12/2026.
      expect(HttpDate.parse('Sat, 99 Sep 2026 12:00:00 GMT').month, 12);
      for (final raw in [
        'Sat, 99 Sep 2026 12:00:00 GMT',
        'Tue, 31 Feb 2026 12:00:00 GMT',
        'Wed, 00 Sep 2026 12:00:00 GMT',
        'Sat, 26 Sep 2026 24:00:00 GMT',
        'Sat, 26 Sep 2026 12:60:00 GMT',
        'Sat, 26 Sep 2026 12:00:60 GMT',
        'Sat, 26 Sep 0026 12:00:00 GMT',
        // Día de la semana que no corresponde (el 26/09/2026 es sábado).
        'Fri, 26 Sep 2026 12:00:00 GMT',
        // Otros formatos o zonas: solo el estándar IMF-fixdate en GMT.
        'Saturday, 26-Sep-26 12:00:00 GMT',
        'Sat Sep 26 12:00:00 2026',
        'Sat, 26 Sep 2026 12:00:00 +0000',
        'Sat, 26 Sep 2026 12:00:00 gmt',
        'Sat, 26 Sep 2026 12:00 GMT',
      ]) {
        expect(parseServerDate(raw), isNull, reason: raw);
      }
      // Bisiesto válido.
      expect(
        parseServerDate('Tue, 29 Feb 2028 23:59:59 GMT'),
        DateTime.utc(2028, 2, 29, 23, 59, 59),
      );
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
      final answer = await checker().check();
      expect(answer?.info?.latest, const AppVersion(1, 1, 0));
      final request = http.requests.single;
      expect(request.method, 'GET');
      expect(request.uri, _endpoint);
      expect(request.data, isNull);
    });

    test('al día: hay respuesta, sin aviso', () async {
      http.handler = (_) => jsonBody('{"ultima_version":"1.0.0"}');
      final answer = await checker().check();
      expect(answer, isNotNull);
      expect(answer!.info, isNull);
    });

    for (final code in [404, 429, 500, 503]) {
      test('$code: sin respuesta, se ignora', () async {
        http.handler = (_) => jsonBody('{"ultima_version":"9.0.0"}', code);
        expect(await checker().check(), isNull);
        expect(http.requests, hasLength(1), reason: 'sin reintentos');
      });
    }

    test('sin conexión o JSON inválido: sin respuesta, sin lanzar', () async {
      http.handler = (o) =>
          throw DioException.connectionError(requestOptions: o, reason: 'x');
      expect(await checker().check(), isNull);
      http.handler = (_) => textBody('<html>no es JSON</html>');
      expect(await checker().check(), isNull);
      http.handler = (_) => jsonBody('["1.1.0"]');
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

  test('instrucciones de instalación para cada sistema', () {
    expect(installSteps('windows'), contains('Ejecutar de todas formas'));
    expect(installSteps('macos'), contains('Abrir igualmente'));
    expect(installSteps('linux'), contains('AppImage'));
    expect(installSteps('fuchsia'), contains('Tus cuentas se conservan'));
  });

  group('aviso', () {
    late FakeHttpAdapter http;
    late _MemorySettings settings;
    late List<Uri> opened;
    late int appTaps;
    // Hora local: la fecha límite se muestra en hora local.
    late DateTime now;
    var serverDate = 'ok';

    const obligatoria =
        '{"ultima_version":"2.0.0","descarga":"$_release","minima":"2.0.0"}';

    setUp(() {
      settings = _MemorySettings();
      now = DateTime(2026, 9, 26, 12);
      serverDate = 'ok';
    });

    // Desmonta y cancela las consultas y el plazo antes de que el test
    // verifique que no quedan temporizadores.
    Future<void> finish(WidgetTester tester, ProviderContainer c) async {
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    }

    // Respuesta con el encabezado Date del servidor ([now]); sin fecha si
    // [serverDate] es 'sin' y con una ilegible si es 'rara'.
    ResponseBody withDate(String json, [int status = 200]) =>
        ResponseBody.fromString(
          json,
          status,
          headers: {
            Headers.contentTypeHeader: ['application/json'],
            if (serverDate == 'ok') 'date': [HttpDate.format(now)],
            if (serverDate == 'rara') 'date': ['mañana a las 3'],
            if (serverDate == 'imposible')
              'date': ['Sat, 99 Sep 2026 12:00:00 GMT'],
          },
        );

    Future<ProviderContainer> pump(WidgetTester tester, String json) async {
      http = FakeHttpAdapter((_) => withDate(json));
      opened = [];
      appTaps = 0;
      final container = ProviderContainer.test(
        overrides: [
          dioProvider.overrideWithValue(testDio(http)),
          settingsRepositoryProvider.overrideWithValue(settings),
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

    Future<void> expectAppUsable(WidgetTester tester) async {
      final before = appTaps;
      await tester.tap(find.text('Pantalla de la app'));
      expect(appTaps, before + 1);
    }

    Future<void> expectAppBlocked(WidgetTester tester) async {
      final before = appTaps;
      await tester.tap(find.text('Pantalla de la app'), warnIfMissed: false);
      expect(appTaps, before);
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

    testWidgets('menor que la mínima: 3 días de plazo, aviso cerrable', (
      tester,
    ) async {
      final c = await pump(tester, obligatoria);
      expect(
        find.text('Actualización obligatoria: versión 2.0.0'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Debes actualizar antes del 29/09/2026'),
        findsOneWidget,
      );
      expect(find.text('Actualización necesaria'), findsNothing);
      await expectAppUsable(tester);
      // Se guarda la primera detección, por versión mínima.
      expect(
        settings.values[SettingsKeys.updateMinimumSeen],
        '2.0.0|${now.toUtc().toIso8601String()}',
      );
      await tester.tap(find.text('Descargar'));
      expect(opened, [Uri.parse(_release)]);
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pump();
      expect(find.textContaining('Debes actualizar'), findsNothing);
      await finish(tester, c);
    });

    testWidgets('al reabrir dentro del plazo cuenta desde la primera vez', (
      tester,
    ) async {
      settings.values[SettingsKeys.updateMinimumSeen] =
          '2.0.0|${now.subtract(const Duration(days: 2)).toUtc().toIso8601String()}';
      final c = await pump(tester, obligatoria);
      expect(
        find.textContaining('Debes actualizar antes del 27/09/2026'),
        findsOneWidget,
      );
      await expectAppUsable(tester);
      await finish(tester, c);
    });

    testWidgets('plazo vencido: bloqueo sin cerrar, con descarga, '
        'instrucciones y guía', (tester) async {
      settings.values[SettingsKeys.updateMinimumSeen] =
          '2.0.0|${now.subtract(const Duration(days: 4)).toUtc().toIso8601String()}';
      final c = await pump(tester, obligatoria);
      expect(find.text('Actualización necesaria'), findsOneWidget);
      expect(find.byIcon(Icons.close_rounded), findsNothing);
      c.read(updateProvider.notifier).dismiss();
      await tester.pump();
      expect(find.text('Actualización necesaria'), findsOneWidget);
      await expectAppBlocked(tester);
      expect(find.text('Cómo instalarla'), findsOneWidget);
      expect(find.text('${UpdateConfig.installGuide}'), findsOneWidget);
      await tester.tap(find.text('Descargar'));
      await tester.tap(find.text('Ver la guía de instalación'));
      expect(opened, [Uri.parse(_release), UpdateConfig.installGuide]);
      expect(isTrustedDownload(UpdateConfig.installGuide), isTrue);
      await finish(tester, c);
    });

    testWidgets('si la mínima cambia, el plazo empieza de nuevo', (
      tester,
    ) async {
      settings.values[SettingsKeys.updateMinimumSeen] =
          '1.5.0|${now.subtract(const Duration(days: 10)).toUtc().toIso8601String()}';
      final c = await pump(tester, obligatoria);
      expect(find.text('Actualización necesaria'), findsNothing);
      expect(
        find.textContaining('Debes actualizar antes del 29/09/2026'),
        findsOneWidget,
      );
      expect(
        settings.values[SettingsKeys.updateMinimumSeen],
        startsWith('2.0.0|'),
      );
      await finish(tester, c);
    });

    testWidgets('el plazo vence con la app abierta: se bloquea', (
      tester,
    ) async {
      final c = await pump(tester, obligatoria);
      await expectAppUsable(tester);
      now = now.add(UpdateConfig.gracePeriod);
      await tester.pump(UpdateConfig.gracePeriod);
      await tester.pump();
      expect(find.text('Actualización necesaria'), findsOneWidget);
      await expectAppBlocked(tester);
      await finish(tester, c);
    });

    for (final failure in ['500', 'sin conexión']) {
      testWidgets('plazo vencido pero el servidor no responde ($failure): '
          'la app funciona normal', (tester) async {
        settings.values[SettingsKeys.updateMinimumSeen] =
            '2.0.0|${now.subtract(const Duration(days: 30)).toUtc().toIso8601String()}';
        http = FakeHttpAdapter(
          (o) => failure == '500'
              ? withDate(obligatoria, 500)
              : throw DioException.connectionError(
                  requestOptions: o,
                  reason: 'x',
                ),
        );
        final c3 = ProviderContainer.test(
          overrides: [
            dioProvider.overrideWithValue(testDio(http)),
            settingsRepositoryProvider.overrideWithValue(settings),
            updateEndpointProvider.overrideWithValue(_endpoint),
          ],
        );
        appTaps = 0;
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: c3,
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
        expect(http.requests, hasLength(1));
        expect(find.text('Actualización necesaria'), findsNothing);
        expect(find.textContaining('Debes actualizar'), findsNothing);
        await expectAppUsable(tester);
        await finish(tester, c3);
      });
    }

    for (final (caso, date) in [
      ('sin encabezado Date', 'sin'),
      ('con un Date ilegible', 'rara'),
      ('con un Date imposible (99 de septiembre)', 'imposible'),
    ]) {
      testWidgets('menor que la mínima, $caso: sin plazo ni bloqueo', (
        tester,
      ) async {
        serverDate = date;
        settings.values[SettingsKeys.updateMinimumSeen] =
            '2.0.0|${now.subtract(const Duration(days: 30)).toUtc().toIso8601String()}';
        final c = await pump(tester, obligatoria);
        expect(find.text('Actualización necesaria'), findsNothing);
        expect(find.textContaining('Debes actualizar'), findsNothing);
        // Aviso informativo, cerrable.
        expect(find.text('Nueva versión 2.0.0 disponible'), findsOneWidget);
        await expectAppUsable(tester);
        // No registra una primera detección sin fecha confiable.
        expect(
          settings.values[SettingsKeys.updateMinimumSeen],
          startsWith('2.0.0|2026-08'),
        );
        await finish(tester, c);
      });
    }

    testWidgets('respuesta incoherente (minima > ultima_version) con plazo '
        'vencido: nunca bloquea', (tester) async {
      settings.values[SettingsKeys.updateMinimumSeen] =
          '3.0.0|${now.subtract(const Duration(days: 30)).toUtc().toIso8601String()}';
      final c = await pump(
        tester,
        '{"ultima_version":"2.0.0","descarga":"$_release","minima":"3.0.0"}',
      );
      expect(find.text('Actualización necesaria'), findsNothing);
      expect(find.textContaining('Debes actualizar'), findsNothing);
      expect(find.text('Nueva versión 2.0.0 disponible'), findsOneWidget);
      await expectAppUsable(tester);
      await finish(tester, c);
    });

    testWidgets('respuesta sin enlace de descarga: nunca bloquea', (
      tester,
    ) async {
      settings.values[SettingsKeys.updateMinimumSeen] =
          '2.0.0|${now.subtract(const Duration(days: 30)).toUtc().toIso8601String()}';
      final c = await pump(
        tester,
        '{"ultima_version":"2.0.0","minima":"2.0.0"}',
      );
      expect(find.text('Actualización necesaria'), findsNothing);
      await expectAppUsable(tester);
      await finish(tester, c);
    });

    testWidgets('corrección del reloj del equipo: el plazo sigue la fecha del '
        'servidor', (tester) async {
      // Primera detección el 26/09 según el servidor. (La app no lee el
      // reloj del equipo: adelantarlo o atrasarlo no cambia nada.)
      final c = await pump(tester, obligatoria);
      expect(
        find.textContaining('Debes actualizar antes del 29/09/2026'),
        findsOneWidget,
      );
      expect(
        settings.values[SettingsKeys.updateMinimumSeen],
        '2.0.0|${now.toUtc().toIso8601String()}',
      );
      await finish(tester, c);

      // Una versión anterior pudo guardar la primera detección con un
      // reloj adelantado (10 días en el futuro): no alarga el plazo.
      settings.values[SettingsKeys.updateMinimumSeen] =
          '2.0.0|${now.add(const Duration(days: 10)).toUtc().toIso8601String()}';
      final c2 = await pump(tester, obligatoria);
      expect(
        find.textContaining('Debes actualizar antes del 29/09/2026'),
        findsOneWidget,
      );
      await finish(tester, c2);

      // Reabierta cuando el SERVIDOR ya está 4 días después: bloqueo.
      settings.values[SettingsKeys.updateMinimumSeen] =
          '2.0.0|${now.toUtc().toIso8601String()}';
      now = now.add(const Duration(days: 4));
      final c3 = await pump(tester, obligatoria);
      expect(find.text('Actualización necesaria'), findsOneWidget);
      await expectAppBlocked(tester);
      await finish(tester, c3);
    });

    testWidgets('fecha guardada por la versión anterior (reloj del equipo, '
        'otra clave): se descarta y el plazo empieza con la del servidor', (
      tester,
    ) async {
      settings.values['update_minimum_seen'] =
          '2.0.0|${now.subtract(const Duration(days: 30)).toUtc().toIso8601String()}';
      final c = await pump(tester, obligatoria);
      expect(find.text('Actualización necesaria'), findsNothing);
      expect(
        find.textContaining('Debes actualizar antes del 29/09/2026'),
        findsOneWidget,
      );
      expect(
        settings.values[SettingsKeys.updateMinimumSeen],
        '2.0.0|${now.toUtc().toIso8601String()}',
      );
      await expectAppUsable(tester);
      await finish(tester, c);
    });

    testWidgets('interruptor de emergencia: bajar minima en el servidor '
        'desbloquea en la siguiente consulta', (tester) async {
      settings.values[SettingsKeys.updateMinimumSeen] =
          '2.0.0|${now.subtract(const Duration(days: 4)).toUtc().toIso8601String()}';
      final c = await pump(tester, obligatoria);
      expect(find.text('Actualización necesaria'), findsOneWidget);
      await expectAppBlocked(tester);

      http.handler = (_) => withDate(
        '{"ultima_version":"2.0.0","descarga":"$_release","minima":"1.0.0"}',
      );
      // Siguiente consulta (sin esperar las 12 h).
      unawaited(c.read(updateProvider.notifier).check());
      await tester.pumpAndSettle();
      expect(find.text('Actualización necesaria'), findsNothing);
      expect(find.text('Nueva versión 2.0.0 disponible'), findsOneWidget);
      await expectAppUsable(tester);
      await finish(tester, c);
    });

    testWidgets('al día: no se muestra nada', (tester) async {
      final c = await pump(tester, '{"ultima_version":"1.0.0"}');
      expect(find.text('Descargar'), findsNothing);
      await finish(tester, c);
    });
  });
}

class _MemorySettings implements SettingsRepository {
  final values = <String, String>{};

  @override
  Future<String?> get(String key) async => values[key];

  @override
  Future<void> set(String key, String value) async => values[key] = value;
}
