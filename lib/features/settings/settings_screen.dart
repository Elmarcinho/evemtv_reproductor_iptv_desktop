import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_config.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/entities/catalog.dart';
import '../../domain/entities/live.dart';
import '../catalog/catalog_providers.dart';
import '../home/promo_banner.dart';
import '../live/live_providers.dart';
import '../parental/parental.dart';
import '../parental/parental_widgets.dart';
import '../update/update_check.dart';

/// Ajustes de la cuenta. Por ahora, el control parental; es la base para
/// futuras opciones.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              context.go(AppRoutes.home),
        },
        child: Focus(
          autofocus: true,
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 24, 12),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Volver (Esc)',
                        onPressed: () => context.go(AppRoutes.home),
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                      const SizedBox(width: 8),
                      Text('Ajustes', style: text.headlineSmall),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 24,
                    ),
                    children: [
                      Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 720),
                          child: const Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _ParentalSection(),
                              SizedBox(height: 24),
                              _AboutSection(),
                            ],
                          ),
                        ),
                      ),
                    ],
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

class _ParentalSection extends ConsumerWidget {
  const _ParentalSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final parental = ref.watch(parentalProvider);
    final secondary = text.bodyMedium?.copyWith(color: AppColors.textSecondary);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.family_restroom_rounded),
                const SizedBox(width: 12),
                Text('Control parental', style: text.titleLarge),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              parental.unlocked
                  ? 'El contenido para adultos está visible hasta que cierres '
                        'la app, cambies de cuenta o lo bloquees de nuevo.'
                  : 'El contenido para adultos está oculto en todas las '
                        'pantallas: listas, búsqueda, novedades, "Seguir '
                        'viendo" y favoritos.',
              style: text.bodyLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Se ocultan siempre los canales, películas y series que tu '
              'proveedor marca para adultos y las categorías con nombres '
              'como XXX, Adultos o +18. También puedes ocultar cualquier '
              'otra categoría: haz clic derecho sobre ella en En vivo, '
              'Películas o Series.',
              style: secondary,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                if (parental.unlocked)
                  FilledButton.tonalIcon(
                    onPressed: () => ref.read(parentalProvider.notifier).lock(),
                    icon: const Icon(Icons.lock_rounded),
                    label: const Text('Bloquear de nuevo'),
                  )
                else
                  FilledButton.tonalIcon(
                    onPressed: () => unlockAdultContent(context, ref),
                    icon: const Icon(Icons.lock_open_rounded),
                    label: const Text('Mostrar contenido adulto'),
                  ),
                OutlinedButton.icon(
                  onPressed: () => showChangePinDialog(context, ref),
                  icon: const Icon(Icons.password_rounded),
                  label: const Text('Cambiar PIN'),
                ),
                TextButton(
                  onPressed: () => showResetPinDialog(context, ref),
                  child: const Text('Olvidé mi PIN'),
                ),
              ],
            ),
            if (parental.defaultPin) ...[
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    size: 20,
                    color: AppColors.favorite,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Tu PIN todavía es 0000, el que viene de fábrica. Te '
                      'recomendamos cambiarlo.',
                      style: secondary,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 24),
            Text('Categorías que ocultaste', style: text.titleMedium),
            const SizedBox(height: 8),
            if (parental.blocked.isEmpty)
              Text('Ninguna por ahora.', style: secondary)
            else
              for (final b in _sorted(parental.blocked))
                _BlockedTile(kind: b.kind, categoryId: b.id),
          ],
        ),
      ),
    );
  }

  static List<({ContentKind kind, String id})> _sorted(
    Set<({ContentKind kind, String id})> blocked,
  ) => blocked.toList()..sort((a, b) => a.kind.index.compareTo(b.kind.index));
}

class _BlockedTile extends ConsumerWidget {
  const _BlockedTile({required this.kind, required this.categoryId});

  final ContentKind kind;
  final String categoryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(switch (kind) {
      ContentKind.live => liveCategoriesAllProvider,
      ContentKind.movie => vodCategoriesAllProvider,
      ContentKind.series => seriesCategoriesAllProvider,
    });
    final name =
        categories.value
            ?.where((ContentCategory c) => c.id == categoryId)
            .firstOrNull
            ?.name ??
        'Categoría $categoryId';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.lock_rounded, color: AppColors.favorite),
      title: Text(name),
      subtitle: Text(kind.label),
      trailing: TextButton(
        onPressed: () => unblockCategory(context, ref, kind, categoryId, name),
        child: const Text('Volver a mostrar'),
      ),
    );
  }
}

/// "Acerca de EvemTv": versión instalada, buscar actualizaciones y enlaces.
class _AboutSection extends ConsumerStatefulWidget {
  const _AboutSection();

  @override
  ConsumerState<_AboutSection> createState() => _AboutSectionState();
}

class _AboutSectionState extends ConsumerState<_AboutSection> {
  bool _checking = false;
  String? _result;

  Future<void> _check() async {
    setState(() {
      _checking = true;
      _result = null;
    });
    final outcome = await ref.read(updateProvider.notifier).check(manual: true);
    if (!mounted) return;
    setState(() {
      _checking = false;
      _result = switch (outcome) {
        UpdateCheckOutcome.available =>
          'Hay una versión nueva: mira el aviso abajo a la derecha.',
        UpdateCheckOutcome.upToDate => 'Tienes la última versión.',
        UpdateCheckOutcome.noAnswer =>
          'No se pudo consultar ahora. Revisa tu conexión e inténtalo más '
              'tarde.',
        UpdateCheckOutcome.disabled =>
          'La búsqueda de actualizaciones solo funciona en la app instalada.',
      };
    });
  }

  Future<void> _open(Uri url) async {
    var opened = false;
    try {
      opened = await ref.read(externalLinkProvider)(url);
    } on Object {
      opened = false;
    }
    if (!opened && mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('No se pudo abrir el navegador. Visita $url')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final secondary = text.bodyMedium?.copyWith(color: AppColors.textSecondary);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.info_outline_rounded),
                const SizedBox(width: 12),
                Text('Acerca de ${AppConfig.appName}', style: text.titleLarge),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Versión ${AppConfig.version}',
              style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              'Reproductor IPTV. Desarrollado por ${AppConfig.developer}.',
              style: secondary,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.tonalIcon(
                  onPressed: _checking ? null : _check,
                  icon: _checking
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.system_update_alt_rounded),
                  label: const Text('Buscar actualizaciones'),
                ),
                TextButton(
                  onPressed: () => _open(UpdateConfig.installGuide),
                  child: const Text('Guía de instalación'),
                ),
                TextButton(
                  onPressed: () => _open(UpdateConfig.downloadPage),
                  child: const Text('Página de descarga'),
                ),
              ],
            ),
            if (_result != null) ...[
              const SizedBox(height: 12),
              Text(_result!, style: secondary),
            ],
          ],
        ),
      ),
    );
  }
}
