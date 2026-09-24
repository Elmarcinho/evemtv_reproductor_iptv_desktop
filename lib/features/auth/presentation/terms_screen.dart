import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/state_views.dart';
import '../application/terms_controller.dart';

/// Términos de uso al primer inicio (y cuando cambia su versión).
class TermsScreen extends ConsumerWidget {
  const TermsScreen({super.key});

  static const List<String> _points = [
    'EvemTv es solo un reproductor. No incluye ni vende listas, canales, '
        'películas, series ni ningún otro contenido.',
    'Para usarlo necesitas un servicio propio, compatible con Xtream Codes o '
        'con listas M3U, contratado con un proveedor de tu elección.',
    'Eres el único responsable del servicio que configures y del contenido al '
        'que accedas, y de contar con los derechos para verlo.',
    'Tus credenciales se guardan solo en el almacén seguro de este equipo. '
        'La app no envía datos de uso ni estadísticas a terceros.',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const AppLogo(),
                    const SizedBox(height: 24),
                    Text('Antes de empezar', style: text.headlineSmall),
                    const SizedBox(height: 16),
                    for (final point in _points)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(
                              padding: EdgeInsets.only(top: 2),
                              child: Icon(
                                Icons.check_circle_outline_rounded,
                                size: 20,
                                color: AppColors.accent,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(child: Text(point, style: text.bodyLarge)),
                          ],
                        ),
                      ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => windowManager.close(),
                          child: const Text('Salir'),
                        ),
                        const SizedBox(width: 12),
                        FilledButton(
                          autofocus: true,
                          onPressed: () =>
                              ref.read(termsProvider.notifier).accept(),
                          child: const Text('Acepto y continúo'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
