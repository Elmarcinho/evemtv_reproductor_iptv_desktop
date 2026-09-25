// Anuncio del inicio.
import 'package:evemtv/core/config/app_config.dart';
import 'package:evemtv/core/logging/app_logger.dart';
import 'package:evemtv/core/theme/app_theme.dart';
import 'package:evemtv/core/widgets/global_messenger.dart';
import 'package:evemtv/features/home/promo_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late LogSink originalSink;
  setUp(() {
    originalSink = AppLogger.sink;
    AppLogger.sink = (_, _) {};
  });
  tearDown(() {
    AppLogger.sink = originalSink;
  });

  Future<List<Uri>> pump(
    WidgetTester tester, {
    bool opens = true,
    Widget banner = const PromoBanner(),
  }) async {
    final opened = <Uri>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          externalLinkProvider.overrideWithValue((url) async {
            opened.add(url);
            return opens;
          }),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          scaffoldMessengerKey: rootMessengerKey,
          home: Scaffold(body: banner),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return opened;
  }

  testWidgets('muestra el anuncio y "Escríbenos" abre WhatsApp', (
    tester,
  ) async {
    final opened = await pump(tester);
    expect(find.text('¿Buscas un servicio de IPTV?'), findsOneWidget);
    expect(
      find.text(
        'Fútbol nacional e internacional, últimas películas y series del año.',
      ),
      findsOneWidget,
    );
    // El número se ve, para anotarlo desde otra pantalla.
    expect(find.text('WhatsApp +591 33217668'), findsOneWidget);
    await tester.tap(find.text('Escríbenos'));
    await tester.pumpAndSettle();
    expect(opened, [AppConfig.promoUrl]);
    expect(opened.single.host, 'wa.me');
    // El número visible es el mismo del enlace.
    expect(
      opened.single.path,
      '/${AppConfig.promoPhone.replaceAll(RegExp(r'\D'), '')}',
    );
    expect(
      opened.single.queryParameters['text'],
      'Hola, vi el anuncio en EvemTv y quiero información',
    );
  });

  testWidgets('si no se puede abrir, lo avisa', (tester) async {
    await pump(tester, opens: false);
    await tester.tap(find.text('Escríbenos'));
    await tester.pumpAndSettle();
    expect(find.textContaining('No se pudo abrir WhatsApp'), findsOneWidget);
  });

  testWidgets('✕ lo cierra solo hasta que se vuelve a abrir la app', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.byTooltip('Cerrar'));
    await tester.pumpAndSettle();
    expect(find.text('¿Buscas un servicio de IPTV?'), findsNothing);

    // Al volver a abrir la app (otro ProviderScope), aparece de nuevo.
    await tester.pumpWidget(const SizedBox());
    await pump(tester);
    expect(find.text('¿Buscas un servicio de IPTV?'), findsOneWidget);
  });

  testWidgets('en el inicio es un botón chico con el número y el enlace', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final opened = await pump(tester, banner: const Center(child: PromoChip()));
    expect(find.text('¿Buscas IPTV?'), findsOneWidget);
    expect(find.text('+591 33217668'), findsOneWidget);
    // Discreto: una sola línea, sin ✕.
    expect(tester.getSize(find.byType(PromoChip)).height, lessThan(44));
    expect(find.byTooltip('Ocultar por unos días'), findsNothing);
    await tester.tap(find.byType(PromoChip));
    await tester.pumpAndSettle();
    expect(opened, [AppConfig.promoUrl]);

    // Aunque se haya cerrado el banner, el botón sigue visible.
    await tester.pumpWidget(const SizedBox());
    await pump(
      tester,
      banner: const Column(children: [PromoBanner(), PromoChip()]),
    );
    await tester.tap(find.byTooltip('Cerrar'));
    await tester.pumpAndSettle();
    expect(find.byType(PromoChip), findsOneWidget);
    expect(find.text('+591 33217668'), findsOneWidget);
  });

  testWidgets('en ventanas angostas el botón muestra solo el número', (
    tester,
  ) async {
    await pump(tester, banner: const Center(child: PromoChip()));
    expect(find.text('¿Buscas IPTV?'), findsNothing);
    expect(find.text('+591 33217668'), findsOneWidget);
  });

  testWidgets('en pantallas anchas el número va junto al botón', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pump(tester);
    final phone = tester.getCenter(find.text('WhatsApp +591 33217668'));
    final button = tester.getCenter(find.text('Escríbenos'));
    expect(phone.dy, closeTo(button.dy, 2));
    expect(phone.dx, lessThan(button.dx));
  });

  testWidgets(
    'en el selector de cuentas y el login va completo, con la firma',
    (tester) async {
      await pump(tester, banner: const PromoFooter());
      expect(find.text('¿Buscas un servicio de IPTV?'), findsOneWidget);
      expect(find.text('Desarrollado por Godebol'), findsOneWidget);
      expect(tester.getSize(find.byType(PromoBanner)).height, greaterThan(44));
    },
  );
}
