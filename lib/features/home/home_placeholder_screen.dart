import 'package:flutter/material.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_theme.dart';

/// Pantalla provisoria de la Fase 0 para verificar ventana, tema y router.
/// Se reemplaza por la pantalla de inicio real en la Fase 1.
class HomePlaceholderScreen extends StatelessWidget {
  const HomePlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.live_tv_rounded,
                    size: 56,
                    color: AppColors.accent,
                  ),
                  const SizedBox(height: 16),
                  Text(AppConfig.appName, style: text.headlineMedium),
                  const SizedBox(height: 8),
                  Text(
                    'Base del proyecto lista. El inicio de sesión llega en la Fase 1.',
                    textAlign: TextAlign.center,
                    style: text.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: null,
                    icon: const Icon(Icons.login_rounded),
                    label: const Text('Iniciar sesión'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
