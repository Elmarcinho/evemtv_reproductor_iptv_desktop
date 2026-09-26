import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config/app_config.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/global_messenger.dart';
import 'features/usage/usage_ping.dart';

class EvemTvApp extends ConsumerWidget {
  const EvemTvApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Conteo de uso diario (solo tras aceptar los términos; ver §18).
    ref.watch(usagePingTriggerProvider);
    return MaterialApp.router(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: rootMessengerKey,
      theme: AppTheme.dark(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.dark,
      // Textos del framework (diálogos, menús, selectores) en español.
      locale: const Locale('es'),
      supportedLocales: const [Locale('es')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      routerConfig: ref.watch(appRouterProvider),
    );
  }
}
