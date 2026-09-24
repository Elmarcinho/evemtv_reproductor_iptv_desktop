// Pantalla de login con datos ficticios.
import 'package:evemtv/features/auth/application/auth_service.dart';
import 'package:evemtv/features/auth/presentation/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpLogin(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [profilesProvider.overrideWith((ref) => Stream.value([]))],
        child: const MaterialApp(home: LoginScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  String fieldText(WidgetTester tester, String label) => tester
      .widget<TextField>(
        find.descendant(
          of: find.widgetWithText(TextFormField, label),
          matching: find.byType(TextField),
        ),
      )
      .controller!
      .text;

  testWidgets(
    'Codex 6: corregir solo la contraseña actualiza la sugerencia Xtream',
    (tester) async {
      await pumpLogin(tester);
      await tester.tap(find.text('Lista M3U'));
      await tester.pumpAndSettle();

      final m3uField = find.widgetWithText(
        TextFormField,
        'URL de la lista M3U / M3U8',
      );
      await tester.enterText(
        m3uField,
        'http://panel.example.com/get.php?username=demo&password=vieja',
      );
      await tester.pump();
      expect(find.text('Usar Xtream'), findsOneWidget);

      await tester.enterText(
        m3uField,
        'http://panel.example.com/get.php?username=demo&password=nueva',
      );
      await tester.pump();
      await tester.tap(find.text('Usar Xtream'));
      await tester.pumpAndSettle();

      expect(fieldText(tester, 'Contraseña'), 'nueva');
      expect(fieldText(tester, 'Usuario'), 'demo');
      expect(fieldText(tester, 'URL del servidor'), 'http://panel.example.com');
    },
  );

  testWidgets('Codex 5: una URL dañada muestra el mensaje previsto', (
    tester,
  ) async {
    await pumpLogin(tester);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'URL del servidor'),
      'https://panel.example.com/%FF',
    );
    await tester.tap(find.text('Conectar'));
    await tester.pumpAndSettle();
    expect(find.text('La URL no tiene un formato válido.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
