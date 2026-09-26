import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/logging/app_logger.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/date_format.dart';
import '../../core/widgets/global_messenger.dart';
import '../home/promo_banner.dart';
import 'update_check.dart';

/// Envuelve toda la app (`MaterialApp.builder`) y muestra el aviso de
/// actualización encima de cualquier pantalla.
///
/// - Versión nueva: tarjeta abajo a la derecha, con "Descargar" y ✕.
/// - Instalada menor que `minima`: la misma tarjeta con la fecha límite
///   ("Debes actualizar antes del…"), también cerrable.
/// - Vencido el plazo: bloqueo que tapa la app, no se cierra y no deja usar
///   el resto (ni mouse ni teclado), con descarga, instrucciones y la guía.
///   Solo con una respuesta del servidor: sin conexión nunca se bloquea.
class UpdateGate extends ConsumerWidget {
  const UpdateGate({super.key, required this.child});

  final Widget child;

  static Future<void> download(WidgetRef ref, Uri url) =>
      _open(ref, isTrustedDownload(url) ? url : UpdateConfig.fallbackDownload);

  static Future<void> openGuide(WidgetRef ref) =>
      _open(ref, UpdateConfig.installGuide);

  // Última comprobación antes de abrir: nunca un enlace ajeno.
  static Future<void> _open(WidgetRef ref, Uri url) async {
    final target = isTrustedDownload(url) ? url : UpdateConfig.fallbackDownload;
    AppLogger.event('update.abrir', {
      'destino': target == UpdateConfig.installGuide ? 'guia' : 'descarga',
    });
    var opened = false;
    try {
      opened = await ref.read(externalLinkProvider)(target);
    } on Object catch (e) {
      AppLogger.w('No se pudo abrir el enlace de actualización', e);
    }
    if (!opened) {
      showGlobalMessage('No se pudo abrir el navegador. Visita $target');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(updateProvider, (previous, next) {
      // Si el bloqueo llega con un video en curso (consulta periódica o
      // plazo vencido con la app abierta), se sale del reproductor o de En
      // vivo para cortarlo.
      if (next.locked && previous?.locked != true) {
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
    final locked = info != null && state.locked;
    return Stack(
      children: [
        ExcludeFocus(excluding: locked, child: child),
        if (locked)
          Positioned.fill(child: _LockedUpdate(info: info))
        else if (state.visible && info != null)
          Positioned(
            right: 16,
            bottom: 16,
            child: _UpdateCard(info: info, deadline: state.deadline),
          ),
      ],
    );
  }
}

class _UpdateCard extends ConsumerWidget {
  const _UpdateCard({required this.info, this.deadline});

  final UpdateInfo info;

  /// Fecha límite si la instalada es menor que la mínima.
  final DateTime? deadline;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final limit = deadline;
    final color = limit != null ? AppColors.favorite : AppColors.accent;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 400),
      child: Material(
        color: AppColors.surfaceHigh,
        elevation: 8,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.5)),
          ),
          child: Row(
            children: [
              Icon(
                limit != null
                    ? Icons.warning_amber_rounded
                    : Icons.system_update_alt_rounded,
                color: color,
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      limit != null
                          ? 'Actualización obligatoria: versión ${info.latest}'
                          : 'Nueva versión ${info.latest} disponible',
                      style: text.titleSmall,
                    ),
                    Text(
                      limit != null
                          ? 'Debes actualizar antes del '
                                '${DateFormatEs.date(limit)}. Tienes la '
                                '${info.current}.'
                          : 'Tienes la ${info.current}.',
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

/// Pasos para instalar la versión descargada, según el sistema.
String installSteps(String os) => switch (os) {
  'windows' =>
    'Abre el instalador descargado e instálalo encima de la versión actual. '
        'Si Windows muestra "Windows protegió su PC", elige "Más información" '
        'y luego "Ejecutar de todas formas". Tus cuentas se conservan.',
  'macos' =>
    'Abre el archivo .dmg descargado y arrastra EvemTv a Aplicaciones, '
        'reemplazando la anterior. Si macOS no la deja abrir, ve a Ajustes '
        'del Sistema → Privacidad y seguridad → "Abrir igualmente". Tus '
        'cuentas se conservan.',
  'linux' =>
    'Reemplaza el AppImage anterior por el descargado y dale permiso de '
        'ejecución (Propiedades → Permisos → "Permitir ejecutar como '
        'programa"). Tus cuentas se conservan.',
  _ =>
    'Instala la versión descargada encima de la actual. Tus cuentas se '
        'conservan.',
};

class _LockedUpdate extends ConsumerWidget {
  const _LockedUpdate({required this.info});

  final UpdateInfo info;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final secondary = text.bodyLarge?.copyWith(color: AppColors.textSecondary);
    return ColoredBox(
      color: AppColors.background.withValues(alpha: 0.96),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
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
                      '(${info.current}) ya no es compatible y el plazo para '
                      'actualizar venció. Descarga la versión ${info.latest} '
                      'para seguir usándola.',
                      textAlign: TextAlign.center,
                      style: secondary,
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      autofocus: true,
                      onPressed: () => UpdateGate.download(ref, info.download),
                      icon: const Icon(Icons.download_rounded),
                      label: const Text('Descargar'),
                    ),
                    const SizedBox(height: 24),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Cómo instalarla', style: text.titleSmall),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      installSteps(Platform.operatingSystem),
                      style: text.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextButton.icon(
                      onPressed: () => UpdateGate.openGuide(ref),
                      icon: const Icon(Icons.menu_book_rounded),
                      label: const Text('Ver la guía de instalación'),
                    ),
                    // El enlace a la vista, por si el navegador no abre.
                    Text(
                      '${UpdateConfig.installGuide}',
                      textAlign: TextAlign.center,
                      style: text.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
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
