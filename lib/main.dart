import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/config/app_config.dart';
import 'core/logging/app_logger.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/fatal_error_view.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Errores no controlados: se registran redactados, nunca se envían fuera.
  FlutterError.onError = (details) {
    AppLogger.e('Error de Flutter', details.exception, details.stack);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    AppLogger.e('Error no controlado', error, stack);
    return true;
  };
  ErrorWidget.builder = (details) => const FatalErrorView();

  // El motor de video (media_kit) NO se inicializa aquí: ver MediaEngine.
  await _setUpWindow();

  runApp(const ProviderScope(child: EvemTvApp()));
}

Future<void> _setUpWindow() async {
  await windowManager.ensureInitialized();
  const options = WindowOptions(
    title: AppConfig.appName,
    size: AppConfig.initialWindowSize,
    minimumSize: AppConfig.minWindowSize,
    center: true,
    backgroundColor: AppColors.background,
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();
    await windowManager.focus();
  });
}
