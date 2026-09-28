// Ajustes → "Acerca de EvemTv" y la versión al pie. Respuestas simuladas.
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:evemtv/core/config/app_config.dart';
import 'package:evemtv/core/logging/app_logger.dart';
import 'package:evemtv/core/widgets/developer_credit.dart';
import 'package:evemtv/data/providers.dart';
import 'package:evemtv/features/auth/application/session.dart';
import 'package:evemtv/features/home/promo_banner.dart';
import 'package:evemtv/features/settings/settings_screen.dart';
import 'package:evemtv/features/update/update_check.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fakes.dart';

final _endpoint = Uri.parse('http://127.0.0.1:18080/api/evemtv/version');

void main() {
  late LogSink originalSink;
  setUp(() {
    originalSink = AppLogger.sink;
    AppLogger.sink = (_, _) {};
  });
  tearDown(() => AppLogger.sink = originalSink);

  testWidgets('la versión al pie, junto a la firma', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: DeveloperCredit())),
    );
    expect(
      find.text('${AppConfig.appName} ${AppConfig.version} · '),
      findsOneWidget,
    );
    expect(find.text('Desarrollado por Godebol'), findsOneWidget);
  });

  group('Acerca de', () {
    late FakeHttpAdapter http;
    late List<Uri> opened;

    Future<ProviderContainer> pump(
      WidgetTester tester, {
      bool enabled = true,
    }) async {
      tester.view.physicalSize = const Size(1280, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      http = FakeHttpAdapter((_) => jsonBody('{"ultima_version":"0.1.0"}'));
      opened = [];
      final c = ProviderContainer.test(
        overrides: [
          ...parentalTestOverrides(),
          sessionContextProvider.overrideWithValue(testSessionContext()),
          dioProvider.overrideWithValue(testDio(http)),
          updateEndpointProvider.overrideWithValue(enabled ? _endpoint : null),
          externalLinkProvider.overrideWithValue((url) async {
            opened.add(url);
            return true;
          }),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: const MaterialApp(home: SettingsScreen()),
        ),
      );
      await tester.pumpAndSettle();
      return c;
    }

    Future<void> finish(WidgetTester tester, ProviderContainer c) async {
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    }

    Future<void> search(WidgetTester tester) async {
      await tester.tap(find.text('Buscar actualizaciones'));
      await tester.pumpAndSettle();
    }

    testWidgets('muestra la versión y dice si está al día', (tester) async {
      final c = await pump(tester);
      expect(find.text('Acerca de EvemTv'), findsOneWidget);
      expect(find.text('Versión ${AppConfig.version}'), findsOneWidget);
      await search(tester);
      expect(find.text('Tienes la última versión.'), findsOneWidget);
      await finish(tester, c);
    });

    testWidgets('versión nueva: vuelve a mostrar el aviso aunque se haya '
        'cerrado', (tester) async {
      final c = await pump(tester);
      http.handler = (_) => jsonBody(
        '{"ultima_version":"99.0.0",'
        '"descarga":"https://evemtv.godebol.com","minima":"0.1.0"}',
      );
      unawaited(c.read(updateProvider.notifier).check());
      await tester.pumpAndSettle();
      c.read(updateProvider.notifier).dismiss();
      expect(c.read(updateProvider).visible, isFalse);
      await search(tester);
      expect(find.textContaining('Hay una versión nueva'), findsOneWidget);
      expect(c.read(updateProvider).visible, isTrue);
      await finish(tester, c);
    });

    testWidgets('sin respuesta del servidor o desactivado: lo dice claro', (
      tester,
    ) async {
      final c = await pump(tester);
      http.handler = (o) =>
          throw DioException.connectionError(requestOptions: o, reason: 'x');
      await search(tester);
      expect(find.textContaining('No se pudo consultar ahora'), findsOneWidget);
      await finish(tester, c);

      final d = await pump(tester, enabled: false);
      await search(tester);
      expect(find.textContaining('solo funciona en la app'), findsOneWidget);
      await finish(tester, d);
    });

    testWidgets('abre la página de descarga (enlace permitido); sin guía '
        'de instalación', (tester) async {
      final c = await pump(tester);
      expect(find.text('Guía de instalación'), findsNothing);
      await tester.tap(find.text('Página de descarga'));
      expect(opened, [UpdateConfig.downloadPage]);
      expect(isTrustedDownload(UpdateConfig.downloadPage), isTrue);
      await finish(tester, c);
    });
  });
}
