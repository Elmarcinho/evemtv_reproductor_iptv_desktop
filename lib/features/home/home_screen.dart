import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/date_format.dart';
import '../../core/widgets/global_messenger.dart';
import '../../core/widgets/keyboard_help.dart';
import '../../core/widgets/state_views.dart';
import '../../domain/entities/account_info.dart';
import '../../domain/entities/profile.dart';
import '../auth/application/auth_service.dart';
import '../auth/application/session.dart';
import '../search/catalog_sync.dart';
import 'account_info_controller.dart';
import 'continue_watching_row.dart';

/// Inicio: acceso a En vivo, Películas y Series, y datos de la cuenta.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  Future<void> _confirmLogout(
    BuildContext context,
    WidgetRef ref,
    Profile profile,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cerrar sesión'),
        content: const Text(
          'Se borrarán de este equipo las credenciales, el catálogo y la guía '
          'guardados de esta cuenta. Para volver a usarla tendrás que '
          'ingresar los datos de nuevo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cerrar sesión'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(authServiceProvider).logout(profile);
    } on Object catch (e) {
      // Global: si la sesión ya se cerró (limpieza incompleta), esta
      // pantalla ya no existe y el aviso igual debe verse.
      showGlobalMessage(userMessageFor(e));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionContextProvider);
    final profile = session.profile;
    // Mantiene el catálogo local (búsqueda) al día en segundo plano.
    ref.listen(catalogSyncProvider, (_, _) {});

    return ScreenShortcuts(
      title: 'Inicio',
      help: ShortcutCatalog.home,
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): () =>
            context.push(AppRoutes.search),
      },
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(40, 28, 40, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const AppLogo(height: 52),
                    const Spacer(),
                    Text(
                      session.credentials.displayName ?? profile.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(width: 16),
                    OutlinedButton.icon(
                      onPressed: () =>
                          ref.read(authServiceProvider).switchProfile(),
                      icon: const Icon(Icons.switch_account_outlined),
                      label: const Text('Cambiar cuenta'),
                    ),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: () => _confirmLogout(context, ref, profile),
                      icon: const Icon(Icons.logout_rounded),
                      label: const Text('Cerrar sesión'),
                    ),
                  ],
                ),
                const SizedBox(height: 40),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final wide = constraints.maxWidth >= 1100;
                      final tiles = const _SectionTiles();
                      final account = _AccountPanel(type: profile.type);
                      return wide
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: ListView(
                                    children: [
                                      const _ExploreHeader(),
                                      const SizedBox(height: 16),
                                      SizedBox(height: 260, child: tiles),
                                      const SizedBox(height: 32),
                                      const ContinueWatchingRow(),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 32),
                                SizedBox(width: 340, child: account),
                              ],
                            )
                          : ListView(
                              children: [
                                const _ExploreHeader(),
                                const SizedBox(height: 16),
                                SizedBox(height: 220, child: tiles),
                                const SizedBox(height: 24),
                                const ContinueWatchingRow(),
                                const SizedBox(height: 24),
                                account,
                              ],
                            );
                    },
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

/// Título de las secciones con la búsqueda global al lado: busca en
/// canales, películas y series a la vez.
class _ExploreHeader extends StatelessWidget {
  const _ExploreHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text('Explorar', style: Theme.of(context).textTheme.titleLarge),
        const Spacer(),
        Tooltip(
          message: 'Buscar en todos los canales, películas y series (Ctrl+F)',
          child: FilledButton.tonalIcon(
            onPressed: () => context.push(AppRoutes.search),
            icon: const Icon(Icons.travel_explore_rounded),
            label: const Text('Búsqueda global'),
          ),
        ),
      ],
    );
  }
}

class _SectionTiles extends StatelessWidget {
  const _SectionTiles();

  /// Ruta de cada sección.
  static const _sections = [
    (
      Icons.live_tv_rounded,
      'En vivo',
      'Canales y guía de programación',
      AppRoutes.live,
    ),
    (
      Icons.movie_outlined,
      'Películas',
      'Catálogo de películas',
      AppRoutes.movies,
    ),
    (
      Icons.video_library_outlined,
      'Series',
      'Temporadas y episodios',
      AppRoutes.series,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, s) in _sections.indexed) ...[
          if (i > 0) const SizedBox(width: 20),
          Expanded(
            child: _SectionTile(
              icon: s.$1,
              title: s.$2,
              subtitle: s.$3,
              route: s.$4,
              autofocus: i == 0,
            ),
          ),
        ],
      ],
    );
  }
}

class _SectionTile extends StatelessWidget {
  const _SectionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.route,
    this.autofocus = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? route;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final enabled = route != null;
    final card = Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        autofocus: autofocus && enabled,
        onTap: enabled ? () => context.go(route!) : null,
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Icon(
                icon,
                size: 44,
                color: enabled ? AppColors.accent : AppColors.textSecondary,
              ),
              const SizedBox(height: 20),
              Text(title, style: text.headlineSmall),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: text.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              if (!enabled) ...[
                const SizedBox(height: 12),
                Text(
                  'Próximamente',
                  style: text.labelMedium?.copyWith(color: AppColors.accent),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    return enabled
        ? card
        : Tooltip(message: 'Disponible próximamente', child: card);
  }
}

class _AccountPanel extends ConsumerWidget {
  const _AccountPanel({required this.type});

  final SourceType type;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(accountInfoProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(
                  'Tu cuenta',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Spacer(),
                if (type == SourceType.xtream)
                  IconButton(
                    tooltip: 'Actualizar',
                    onPressed: info.isLoading
                        ? null
                        : () =>
                              ref.read(accountInfoProvider.notifier).refresh(),
                    icon: const Icon(Icons.refresh_rounded),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            info.when(
              skipLoadingOnRefresh: false,
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: LoadingView(),
              ),
              error: (e, _) => ErrorView(
                error: e,
                onRetry: () => ref.read(accountInfoProvider.notifier).refresh(),
              ),
              data: (data) => data == null
                  ? _Row(label: 'Tipo', value: type.label)
                  : _AccountDetails(info: data),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountDetails extends StatelessWidget {
  const _AccountDetails({required this.info});

  final AccountInfo info;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final expired = info.isExpiredAt(now);
    final status = expired ? AccountStatus.expired : info.status;
    final statusColor = status == AccountStatus.active
        ? AppColors.success
        : AppColors.error;
    final expires = info.expiresAt;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Row(
          label: 'Estado',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.circle, size: 10, color: statusColor),
              const SizedBox(width: 8),
              Text(status.label),
            ],
          ),
        ),
        _Row(
          label: 'Vence',
          value: expires == null
              ? 'Sin vencimiento'
              : '${DateFormatEs.date(expires)} '
                    '(${DateFormatEs.relativeDays(expires, now: now)})',
        ),
        _Row(
          label: 'Conexiones',
          value:
              '${info.activeConnections ?? '—'} activas de '
              '${info.maxConnections ?? '—'}',
        ),
        _Row(label: 'Tipo', value: info.isTrial ? 'Prueba' : 'Completa'),
        if (info.createdAt != null)
          _Row(label: 'Creada', value: DateFormatEs.date(info.createdAt!)),
        if (info.allowedOutputFormats.isNotEmpty)
          _Row(
            label: 'Formatos',
            value: info.allowedOutputFormats.join(', ').toUpperCase(),
          ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, this.value, this.child});

  final String label;
  final String? value;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
          Expanded(child: child ?? Text(value ?? '—')),
        ],
      ),
    );
  }
}
