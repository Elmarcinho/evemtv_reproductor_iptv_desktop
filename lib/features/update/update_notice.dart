import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/logging/app_logger.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/global_messenger.dart';
import '../home/promo_banner.dart';
import 'update_check.dart';

/// Envuelve toda la app (`MaterialApp.builder`) y muestra el aviso de
/// actualización encima de cualquier pantalla.
///
/// - Versión nueva: tarjeta abajo a la derecha, con "Descargar" y ✕.
/// - Versión obligatoria (la instalada es menor que `minima`): tapa la app,
///   no se puede cerrar y no deja usar el resto (ni mouse ni teclado).
class UpdateGate extends ConsumerWidget {
  const UpdateGate({super.key, required this.child});

  final Widget child;

  static Future<void> download(WidgetRef ref, Uri url) async {
    AppLogger.event('update.descargar', const {});
    var opened = false;
    // Última comprobación antes de abrir: nunca un enlace ajeno.
    final target = isTrustedDownload(url) ? url : UpdateConfig.fallbackDownload;
    try {
      opened = await ref.read(externalLinkProvider)(target);
    } on Object catch (e) {
      AppLogger.w('No se pudo abrir la descarga', e);
    }
    if (!opened) {
      showGlobalMessage(
        'No se pudo abrir el navegador. Descarga la nueva versión desde '
        '${UpdateConfig.fallbackDownload}',
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(updateProvider, (previous, next) {
      // Si llega un aviso obligatorio con un video en curso (consulta
      // periódica), se sale del reproductor o de En vivo para cortarlo.
      if (next.info?.forced == true && previous?.info?.forced != true) {
        final router = ref.read(appRouterProvider);
        final path = router.routerDelegate.currentConfiguration.uri.path;
        if (path.startsWith(AppRoutes.live) ||
            path.startsWith(AppRoutes.vodPlayer)) {
          router.go(AppRoutes.home);
        }
      }
    });
    final state = ref.watch(updateProvider);
    final info = state.info;
    final forced = info != null && info.forced;
    return Stack(
      children: [
        ExcludeFocus(excluding: forced, child: child),
        if (forced)
          Positioned.fill(child: _ForcedUpdate(info: info))
        else if (state.visible && info != null)
          Positioned(right: 16, bottom: 16, child: _UpdateCard(info: info)),
      ],
    );
  }
}

class _UpdateCard extends ConsumerWidget {
  const _UpdateCard({required this.info});

  final UpdateInfo info;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 380),
      child: Material(
        color: AppColors.surfaceHigh,
        elevation: 8,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.accent.withValues(alpha: 0.5)),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.system_update_alt_rounded,
                color: AppColors.accent,
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Nueva versión ${info.latest} disponible',
                      style: text.titleSmall,
                    ),
                    Text(
                      'Tienes la ${info.current}.',
                      style: text.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: () => UpdateGate.download(ref, info.download),
                child: const Text('Descargar'),
              ),
              IconButton(
                // Sin tooltip: el aviso vive fuera del Navigator (sin Overlay).
                icon: const Icon(Icons.close_rounded, size: 20),
                onPressed: () => ref.read(updateProvider.notifier).dismiss(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ForcedUpdate extends ConsumerWidget {
  const _ForcedUpdate({required this.info});

  final UpdateInfo info;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    return ColoredBox(
      color: AppColors.background.withValues(alpha: 0.94),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Material(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.system_update_alt_rounded,
                      size: 48,
                      color: AppColors.accent,
                    ),
                    const SizedBox(height: 16),
                    Text('Actualización necesaria', style: text.headlineSmall),
                    const SizedBox(height: 12),
                    Text(
                      'Esta versión de ${AppConfig.appName} '
                      '(${info.current}) ya no es compatible. Descarga la '
                      'versión ${info.latest} para seguir usándola.',
                      textAlign: TextAlign.center,
                      style: text.bodyLarge?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      autofocus: true,
                      onPressed: () => UpdateGate.download(ref, info.download),
                      icon: const Icon(Icons.download_rounded),
                      label: const Text('Descargar'),
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
