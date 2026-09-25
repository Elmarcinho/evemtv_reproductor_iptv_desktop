// Flujo completo de pantallas con servidor simulado y datos ficticios.
import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:evemtv/app.dart';
import 'package:evemtv/core/errors/app_failure.dart';
import 'package:evemtv/core/logging/app_logger.dart';
import 'package:evemtv/core/logging/redactor.dart';
import 'package:evemtv/data/providers.dart';
import 'package:evemtv/data/storage/app_database.dart';
import 'package:evemtv/data/storage/image_cache_key_store.dart';
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
            tempImageCacheRoot(),
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
      // Al crear el perfil se borran restos de caché de imágenes con su id
      // (E/S real de disco, que no avanza con el reloj simulado).
      await settleIo(tester);
      await tester.pumpAndSettle();

      expect(find.text('Tu cuenta'), findsOneWidget);
      // Búsqueda global junto a las tres secciones.
      expect(find.text('Explorar'), findsOneWidget);
      expect(find.text('Búsqueda global'), findsOneWidget);
      expect(find.text('Activa'), findsOneWidget);
      expect(find.text('1 activas de 2'), findsOneWidget);
      // Se muestra el usuario (en memoria), no "Cuenta 1".
      expect(find.text('demo'), findsOneWidget);

      // Cada sección se abre dentro del contenedor de la sesión (si algún
      // provider de sesión no declarara sus dependencias, fallaría aquí).
      for (final section in ['En vivo', 'Películas', 'Series']) {
        await tester.tap(find.text(section).first);
        await settleIo(tester);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: section);
        // Un provider evaluado fuera de la sesión fallaría con un error
        // genérico (StateError de sessionContextProvider).
        expect(
          find.text(const UnknownFailure().message),
          findsNothing,
          reason: section,
        );
        await tester.tap(find.byTooltip('Volver (Esc)'));
        await tester.pumpAndSettle();
        expect(find.text('Tu cuenta'), findsOneWidget, reason: section);
      }
      await tester.tap(find.text('Búsqueda global'));
      await settleIo(tester);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Volver (Esc)'));
      await tester.pumpAndSettle();
      expect(find.text('Tu cuenta'), findsOneWidget);

      // Cerrar sesión borra la cuenta y vuelve al selector vacío.
      await tester.tap(find.widgetWithText(TextButton, 'Cerrar sesión'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Cerrar sesión'));
      // Cerrar sesión también borra la caché de imágenes del perfil (E/S real
      // de disco y almacén seguro), que no avanza con el reloj simulado.
      await settleIo(tester);
      await tester.pumpAndSettle();
      expect(find.text('Todavía no hay cuentas guardadas'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await db.close();
    },
  );

  // Informe Codex Fase 4, punto 4: si al cerrar sesión quedan restos de la
  // caché de imágenes, el aviso se ve aunque el inicio ya no exista.
  testWidgets('cerrar sesión con limpieza incompleta avisa con el mensajero '
      'global', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    final storage = FakeSecureStorage();
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          secureStorageProvider.overrideWithValue(storage),
          dioProvider.overrideWithValue(
            testDio(FakeHttpAdapter((_) => jsonBody(loginOk))),
          ),
          tempImageCacheRoot(),
        ],
        child: const EvemTvApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Acepto y continúo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Agregar cuenta'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'URL del servidor'),
      'http://panel.example.com',
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
    await settleIo(tester);
    await tester.pumpAndSettle();
    expect(find.text('Tu cuenta'), findsOneWidget);

    // Ya hay clave de imágenes (se crea al mostrar la primera) y el llavero
    // la "borra" pero la entrada sigue ahí.
    await tester.runAsync(() => ImageCacheKeyStore(storage).keyFor(1));
    storage.ignoreDeleteOf = (k) => k.contains('image_cache_key');
    await tester.tap(find.widgetWithText(TextButton, 'Cerrar sesión'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Cerrar sesión'));
    await settleIo(tester);
    await tester.pump();

    expect(find.text('Todavía no hay cuentas guardadas'), findsOneWidget);
    expect(
      find.text(StorageFailureKind.cleanupIncomplete.message),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox());
    await db.close();
  });
}
