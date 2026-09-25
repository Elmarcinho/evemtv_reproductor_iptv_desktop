// Flujo completo de pantallas con servidor simulado y datos ficticios.
import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:evemtv/app.dart';
import 'package:evemtv/core/logging/app_logger.dart';
import 'package:evemtv/core/logging/redactor.dart';
import 'package:evemtv/data/providers.dart';
import 'package:evemtv/data/storage/app_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/xtream_fixtures.dart';
import 'helpers/fakes.dart';

void main() {
  late LogSink originalSink;
  setUp(() {
    originalSink = AppLogger.sink;
    AppLogger.sink = (_, _) {};
  });
  tearDown(() {
    AppLogger.sink = originalSink;
    Redactor.clearSecrets();
  });

  testWidgets(
    'términos → login Xtream → inicio con datos de la cuenta → cerrar sesión',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      // closeStreamsSynchronously: sin esto drift cierra sus streams con un
      // timer que el reloj simulado de testWidgets deja pendiente.
      final db = AppDatabase(
        DatabaseConnection(
          NativeDatabase.memory(),
          closeStreamsSynchronously: true,
        ),
      );
      final http = FakeHttpAdapter((_) => jsonBody(loginOk));
      await tester.pumpWidget(
        ProviderScope(
          retry: (_, _) => null,
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            secureStorageProvider.overrideWithValue(FakeSecureStorage()),
            dioProvider.overrideWithValue(testDio(http)),
          ],
          child: const EvemTvApp(),
        ),
      );
      await tester.pumpAndSettle();

      // Términos al primer inicio.
      expect(find.text('Antes de empezar'), findsOneWidget);
      await tester.tap(find.text('Acepto y continúo'));
      await tester.pumpAndSettle();

      // Sin cuentas: estado vacío.
      expect(find.text('Todavía no hay cuentas guardadas'), findsOneWidget);
      await tester.tap(find.text('Agregar cuenta'));
      await tester.pumpAndSettle();

      // Validación local de la URL.
      await tester.enterText(
        find.widgetWithText(TextFormField, 'URL del servidor'),
        'panel.example.com',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Usuario'),
        'demo',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Contraseña'),
        'clave',
      );
      await tester.tap(find.text('Conectar'));
      await tester.pumpAndSettle();
      expect(
        find.text('La URL debe empezar con http:// o https://.'),
        findsOneWidget,
      );
      expect(http.requests, isEmpty);

      // Login correcto.
      await tester.enterText(
        find.widgetWithText(TextFormField, 'URL del servidor'),
        'http://panel.example.com:8080',
      );
      await tester.tap(find.text('Conectar'));
      await tester.pumpAndSettle();

      expect(find.text('Tu cuenta'), findsOneWidget);
      // Búsqueda global junto a las tres secciones.
      expect(find.text('Explorar'), findsOneWidget);
      expect(find.text('Búsqueda global'), findsOneWidget);
      expect(find.text('Activa'), findsOneWidget);
      expect(find.text('1 activas de 2'), findsOneWidget);
      // Se muestra el usuario (en memoria), no "Cuenta 1".
      expect(find.text('demo'), findsOneWidget);

      // Cerrar sesión borra la cuenta y vuelve al selector vacío.
      await tester.tap(find.widgetWithText(TextButton, 'Cerrar sesión'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Cerrar sesión'));
      // Cerrar sesión también borra la caché de imágenes del perfil (E/S real
      // de disco y almacén seguro), que no avanza con el reloj simulado.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Todavía no hay cuentas guardadas'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await db.close();
    },
  );
}
