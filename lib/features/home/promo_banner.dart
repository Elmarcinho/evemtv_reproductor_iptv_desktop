import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/app_config.dart';
import '../../core/logging/app_logger.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/developer_credit.dart';
import '../../core/widgets/global_messenger.dart';

/// Abre un enlace fuera de la app (navegador o WhatsApp). Los tests lo
/// reemplazan.
final externalLinkProvider = Provider<Future<bool> Function(Uri url)>(
  (ref) =>
      (url) => launchUrl(url, mode: LaunchMode.externalApplication),
);

/// Si el banner del anuncio se muestra. Cerrarlo con ✕ lo oculta solo
/// hasta que se vuelve a abrir la app: no se guarda en ningún lado, así
/// cada vez que se abre la app el anuncio vuelve a aparecer.
class PromoController extends Notifier<bool> {
  @override
  bool build() => true;

  void dismiss() {
    state = false;
    AppLogger.event('promo.dismiss', const {});
  }
}

final promoProvider = NotifierProvider<PromoController, bool>(
  PromoController.new,
);

/// Anuncio del desarrollador: abre WhatsApp con el mensaje ya escrito. Se
/// puede cerrar con ✕ hasta la próxima vez que se abra la app.
///
/// Va en el selector de cuentas y el login; en el inicio se usa
/// [PromoChip], más discreto.
class PromoBanner extends ConsumerWidget {
  const PromoBanner({super.key});

  static const Color _green = Color(0xFF25D366);

  static Future<void> open(WidgetRef ref) async {
    AppLogger.event('promo.open', const {});
    var opened = false;
    try {
      opened = await ref.read(externalLinkProvider)(AppConfig.promoUrl);
    } on Object catch (e) {
      AppLogger.w('No se pudo abrir el anuncio', e);
    }
    if (!opened) {
      showGlobalMessage(
        'No se pudo abrir WhatsApp. Revisa que haya un navegador instalado.',
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(promoProvider)) return const SizedBox.shrink();
    final text = Theme.of(context).textTheme;
    // El número a la vista, para anotarlo desde otra pantalla.
    final phone = Text(
      'WhatsApp ${AppConfig.promoPhone}',
      style: text.titleMedium?.copyWith(
        color: _green,
        fontWeight: FontWeight.w600,
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) =>
          _full(ref, text, phone, wide: constraints.maxWidth >= 900),
    );
  }

  Widget _full(
    WidgetRef ref,
    TextTheme text,
    Widget phone, {
    required bool wide,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 8, 14),
      decoration: BoxDecoration(
        color: _green.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _green.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.chat_rounded, color: _green, size: 28),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  AppConfig.promoTitle,
                  style: text.titleMedium?.copyWith(color: _green),
                ),
                const SizedBox(height: 2),
                Text(
                  AppConfig.promoSubtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                // En ventanas angostas, el número va debajo del texto.
                if (!wide) ...[const SizedBox(height: 4), phone],
              ],
            ),
          ),
          const SizedBox(width: 16),
          if (wide) ...[phone, const SizedBox(width: 16)],
          OutlinedButton(
            onPressed: () => open(ref),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textPrimary,
              side: const BorderSide(color: AppColors.border),
            ),
            child: const Text('Escríbenos'),
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Cerrar',
            onPressed: () => ref.read(promoProvider.notifier).dismiss(),
            icon: const Icon(Icons.close_rounded, color: _green),
          ),
        ],
      ),
    );
  }
}

/// Anuncio del inicio: un botón chico con borde verde en la barra
/// superior, junto al usuario. Siempre visible (sin ✕) pero sin ocupar
/// espacio del contenido. Un clic abre WhatsApp con el mensaje escrito.
class PromoChip extends ConsumerWidget {
  const PromoChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    // En ventanas angostas, solo el icono y el número.
    final showLabel = MediaQuery.sizeOf(context).width >= 1200;
    return Tooltip(
      message: 'Escríbenos por WhatsApp',
      child: Material(
        color: Colors.transparent,
        shape: StadiumBorder(
          side: BorderSide(color: PromoBanner._green.withValues(alpha: 0.5)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => PromoBanner.open(ref),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.chat_rounded,
                  size: 16,
                  color: PromoBanner._green,
                ),
                const SizedBox(width: 8),
                if (showLabel) ...[
                  Text(
                    '¿Buscas IPTV?',
                    style: text.bodySmall?.copyWith(
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Text(
                  AppConfig.promoPhone,
                  style: text.bodySmall?.copyWith(
                    color: PromoBanner._green,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Pie del selector de cuentas y del login: el anuncio completo y la firma.
class PromoFooter extends StatelessWidget {
  const PromoFooter({super.key});

  @override
  Widget build(BuildContext context) => const Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Padding(
        padding: EdgeInsets.fromLTRB(48, 0, 48, 12),
        child: PromoBanner(),
      ),
      DeveloperCredit(),
    ],
  );
}
