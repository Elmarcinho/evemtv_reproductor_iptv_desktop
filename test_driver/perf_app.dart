// App para medir el rendimiento con `flutter drive --profile` (ver
// test_driver/perf_app_test.dart). Es la app real con el ciclo de cuadros
// normal; solo cambia dónde guarda los datos: base, llavero e imágenes van
// a una carpeta temporal (nunca a los datos reales del usuario).
import 'dart:io';

import 'package:drift/native.dart';
import 'package:evemtv/app.dart';
import 'package:evemtv/data/providers.dart';
import 'package:evemtv/data/storage/app_database.dart';
import 'package:evemtv/features/images/app_images.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_driver/driver_extension.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../test/helpers/fakes.dart' show FakeSecureStorage;

/// Cuadros dibujados desde que arrancó (el conductor los pide para saber
/// si algo se redibuja en reposo).
var _frames = 0;

Future<void> main() async {
  enableFlutterDriverExtension(
    handler: (message) async {
      switch (message) {
        case 'frames':
          return '$_frames';
        case 'lifecycle':
          return '${WidgetsBinding.instance.lifecycleState}';
        case 'minimize':
          await windowManager.minimize();
        case 'restore':
          await windowManager.restore();
          await windowManager.focus();
      }
      return '';
    },
  );
  SchedulerBinding.instance.addTimingsCallback((t) => _frames += t.length);

  // Ventana visible y siempre encima mientras mide: en Wayland, una
  // ventana tapada no recibe cuadros y la app quedaría esperando.
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  await windowManager.waitUntilReadyToShow(
    const WindowOptions(size: Size(1600, 900), center: true),
    () async {
      await windowManager.show();
      await windowManager.focus();
      await windowManager.setAlwaysOnTop(true);
    },
  );

  final data = Directory('${Directory.systemTemp.path}/evemtv_perf');
  if (data.existsSync()) data.deleteSync(recursive: true);
  data.createSync();
  final db = AppDatabase(
    NativeDatabase.createInBackground(File('${data.path}/perf.sqlite')),
  );
  runApp(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        secureStorageProvider.overrideWithValue(FakeSecureStorage()),
        imageCacheRootProvider.overrideWithValue(
          () async => Directory('${data.path}/img'),
        ),
      ],
      child: const EvemTvApp(),
    ),
  );
}
