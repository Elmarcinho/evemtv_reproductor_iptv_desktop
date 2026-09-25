import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/date_format.dart';
import '../../core/utils/text_format.dart';
import '../../core/widgets/developer_credit.dart';
import '../../core/widgets/global_messenger.dart';
import '../../core/widgets/keyboard_help.dart';
import '../../core/widgets/state_views.dart';
import '../../domain/entities/account_info.dart';
import '../../domain/entities/catalog.dart';
import '../../domain/entities/profile.dart';
import '../auth/application/auth_service.dart';
import '../auth/application/session.dart';
import '../player/watch_progress.dart';
import '../search/catalog_sync.dart';
import 'account_info_controller.dart';
import 'continue_watching_row.dart';
import 'featured_carousel.dart';
import 'promo_banner.dart';

/// Inicio: búsqueda global, cuenta (usuario y vencimiento), acceso a En
/// vivo, Películas y Series, y "seguir viendo".
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
      // Nada aparece resaltado al abrir (con mouse parecía "seleccionado");
      // el foco está en la pantalla y la primera flecha o Tab entra a los
      // controles, que desde ahí muestran el foco como siempre.
      child: Focus(
        autofocus: true,
        onKeyEvent: _enterWithKeyboard,
        child: Scaffold(
          bottomNavigationBar: const DeveloperCredit(),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(40, 28, 40, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const AppLogo(height: 52),
                      const SizedBox(width: 40),
                      const Expanded(child: Center(child: _GlobalSearchBox())),
                      const SizedBox(width: 24),
                      const PromoChip(),
                      const SizedBox(width: 16),
                      _AccountMenu(
                        name: session.credentials.displayName ?? profile.name,
                        type: profile.type,
                        onSwitch: () =>
                            ref.read(authServiceProvider).switchProfile(),
                        onLogout: () => _confirmLogout(context, ref, profile),
                      ),
                    ],
                  ),
                  const SizedBox(height: 40),
                  const Expanded(child: _HomeBody()),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static KeyEventResult _enterWithKeyboard(FocusNode node, KeyEvent event) {
    if (!node.hasPrimaryFocus || event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final entry = {
      LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.arrowUp,
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.arrowRight,
    };
    if (!entry.contains(event.logicalKey)) return KeyEventResult.ignored;
    node.nextFocus();
    return KeyEventResult.handled;
  }
}

/// Cuerpo del inicio. Se reorganiza según haya o no "Seguir viendo":
///
/// - **Sin nada a medio ver:** las secciones y, debajo, las novedades de
///   películas y series lado a lado, grandes y con su ficha breve.
/// - **Con algo a medio ver:** "Seguir viendo" pasa al área principal y las
///   novedades a una columna compacta a la derecha.
///
/// El cambio de un arreglo al otro se anima con un fundido.
class _HomeBody extends ConsumerWidget {
  const _HomeBody();

  /// Alto de las tarjetas de sección.
  static const double tilesHeight = 150;

  /// Separación entre las secciones y los carruseles.
  static const double sectionsGap = 64;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(allWatchProgressProvider);
    // Hasta saber si hay algo a medio ver, solo las secciones: así no se
    // muestra un arreglo y enseguida el otro.
    final hasContinue = progress.value?.isNotEmpty;
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 1100;
        final Widget body;
        final String layout;
        if (hasContinue == null) {
          layout = 'cargando';
          body = const Align(
            alignment: Alignment.topCenter,
            child: SizedBox(height: tilesHeight, child: _SectionTiles()),
          );
        } else if (!wide) {
          layout = 'angosto';
          body = ListView(
            children: [
              const SizedBox(height: tilesHeight, child: _SectionTiles()),
              const SizedBox(height: 32),
              if (hasContinue) ...[
                const ContinueWatchingRow(),
                const SizedBox(height: 32),
              ],
              const Wrap(
                spacing: 40,
                runSpacing: 24,
                children: [
                  FeaturedCarousel(kind: ContentKind.movie, cardHeight: 300),
                  FeaturedCarousel(kind: ContentKind.series, cardHeight: 300),
                ],
              ),
            ],
          );
        } else if (hasContinue) {
          layout = 'seguir-viendo';
          body = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ListView(
                  children: [
                    const SizedBox(height: tilesHeight, child: _SectionTiles()),
                    const SizedBox(height: 36),
                    const ContinueWatchingRow(),
                  ],
                ),
              ),
              const SizedBox(width: 40),
              _FeaturedColumn(height: constraints.maxHeight),
            ],
          );
        } else {
          layout = 'destacados';
          // Tres carruseles, uno por columna (alineados con las secciones):
          // películas nuevas, series nuevas y mejor valoradas. Las tarjetas
          // ocupan lo que queda debajo de las secciones, sin desplazar.
          final cardHeight =
              (constraints.maxHeight -
                      tilesHeight -
                      sectionsGap -
                      44 -
                      StackedCarousel.progressHeight -
                      FeaturedHero.infoHeight)
                  .clamp(240.0, 400.0);
          body = ListView(
            children: [
              const SizedBox(height: tilesHeight, child: _SectionTiles()),
              const SizedBox(height: sectionsGap),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: FeaturedHero(
                      kind: ContentKind.movie,
                      cardHeight: cardHeight,
                    ),
                  ),
                  const SizedBox(width: _SectionTiles.gap),
                  Expanded(
                    child: FeaturedHero(
                      kind: ContentKind.series,
                      cardHeight: cardHeight,
                    ),
                  ),
                  const SizedBox(width: _SectionTiles.gap),
                  Expanded(child: FeaturedHero(cardHeight: cardHeight)),
                ],
              ),
            ],
          );
        }
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 350),
          switchInCurve: Curves.easeOutCubic,
          layoutBuilder: (current, previous) => Stack(
            alignment: Alignment.topLeft,
            children: [...previous, ?current],
          ),
          child: KeyedSubtree(key: ValueKey(layout), child: body),
        );
      },
    );
  }
}

/// Novedades compactas a la derecha: películas arriba y series abajo, con
/// las tarjetas del alto que permite la ventana.
class _FeaturedColumn extends StatelessWidget {
  const _FeaturedColumn({required this.height});

  final double height;

  /// Título + barra de avance + separación de cada carrusel.
  static const double chrome = 44 + StackedCarousel.progressHeight + 16;

  @override
  Widget build(BuildContext context) {
    final cardHeight = ((height - 2 * chrome) / 2).clamp(240.0, 420.0);
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FeaturedCarousel(kind: ContentKind.movie, cardHeight: cardHeight),
          const SizedBox(height: 16),
          FeaturedCarousel(kind: ContentKind.series, cardHeight: cardHeight),
        ],
      ),
    );
  }
}

/// Búsqueda global en la barra superior, con aspecto de campo de búsqueda:
/// al activarla abre la pantalla de búsqueda (canales, películas y series).
class _GlobalSearchBox extends StatelessWidget {
  const _GlobalSearchBox();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: Semantics(
        button: true,
        label: 'Búsqueda global',
        child: Material(
          color: AppColors.surface,
          shape: const StadiumBorder(side: BorderSide(color: AppColors.border)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => context.push(AppRoutes.search),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                children: [
                  const Icon(
                    Icons.search_rounded,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Buscar canales, películas y series',
                      overflow: TextOverflow.ellipsis,
                      style: text.bodyLarge?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Text(
                      'Ctrl+F',
                      style: text.labelSmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
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

/// Usuario y vencimiento juntos, arriba a la derecha. Al pulsarlo se abre
/// el menú de la cuenta (actualizar, cambiar de cuenta, cerrar sesión).
class _AccountMenu extends ConsumerWidget {
  const _AccountMenu({
    required this.name,
    required this.type,
    required this.onSwitch,
    required this.onLogout,
  });

  final String name;
  final SourceType type;
  final VoidCallback onSwitch;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final info = ref.watch(accountInfoProvider);
    final (detail, color) = _expiryLine(info);
    return PopupMenuButton<VoidCallback>(
      tooltip: 'Cuenta',
      position: PopupMenuPosition.under,
      onSelected: (action) => action(),
      itemBuilder: (context) => [
        if (type == SourceType.xtream)
          PopupMenuItem(
            value: () => ref.read(accountInfoProvider.notifier).refresh(),
            child: const ListTile(
              leading: Icon(Icons.refresh_rounded),
              title: Text('Actualizar datos de la cuenta'),
            ),
          ),
        PopupMenuItem(
          value: onSwitch,
          child: const ListTile(
            leading: Icon(Icons.switch_account_outlined),
            title: Text('Cambiar cuenta'),
          ),
        ),
        PopupMenuItem(
          value: onLogout,
          child: const ListTile(
            leading: Icon(Icons.logout_rounded, color: AppColors.error),
            title: Text('Cerrar sesión'),
          ),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: AppColors.surfaceHigh,
              child: Text(
                name.isEmpty ? '?' : name.characters.first.toUpperCase(),
                style: text.titleMedium,
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 220),
                  child: Text(
                    name,
                    style: text.titleSmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 2),
                Text(detail, style: text.bodySmall?.copyWith(color: color)),
              ],
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.expand_more_rounded,
              color: AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }

  /// Segunda línea: el vencimiento (o por qué no se puede mostrar).
  (String, Color) _expiryLine(AsyncValue<AccountInfo?> info) {
    if (info.isLoading) {
      return ('Consultando la cuenta…', AppColors.textSecondary);
    }
    if (info.hasError) {
      return ('No se pudo consultar la cuenta', AppColors.error);
    }
    final data = info.value;
    if (data == null) return (type.label, AppColors.textSecondary);
    final now = DateTime.now();
    if (data.isExpiredAt(now)) {
      return (
        'Vencida el ${DateFormatEs.date(data.expiresAt!)}',
        AppColors.error,
      );
    }
    if (data.status != AccountStatus.active) {
      return ('Cuenta ${data.status.label.toLowerCase()}', AppColors.error);
    }
    final expires = data.expiresAt;
    if (expires == null) return ('Sin vencimiento', AppColors.textSecondary);
    final soon = expires.difference(now) < const Duration(days: 7);
    return (
      'Vence el ${DateFormatEs.date(expires)}',
      soon ? AppColors.favorite : AppColors.textSecondary,
    );
  }
}

class _SectionTiles extends StatelessWidget {
  const _SectionTiles();

  /// Separación entre columnas (la usan también los carruseles).
  static const double gap = 20;

  static const _sections = [
    (
      Icons.live_tv_rounded,
      'En vivo',
      'Canales y guía',
      AppRoutes.live,
      ContentKind.live,
    ),
    (
      Icons.movie_outlined,
      'Películas',
      'Catálogo de películas',
      AppRoutes.movies,
      ContentKind.movie,
    ),
    (
      Icons.video_library_outlined,
      'Series',
      'Temporadas y episodios',
      AppRoutes.series,
      ContentKind.series,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, s) in _sections.indexed) ...[
          if (i > 0) const SizedBox(width: gap),
          Expanded(
            child: _SectionTile(
              icon: s.$1,
              title: s.$2,
              subtitle: s.$3,
              route: s.$4,
              kind: s.$5,
            ),
          ),
        ],
      ],
    );
  }
}

/// Acceso a una sección: icono a la izquierda y, al lado, el nombre y la
/// cantidad de elementos del catálogo local (si ya se descargó).
class _SectionTile extends ConsumerWidget {
  const _SectionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.route,
    required this.kind,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String route;
  final ContentKind kind;

  static String _count(ContentKind kind, int n) {
    final number = TextFormat.thousands(n);
    return switch (kind) {
      ContentKind.live => n == 1 ? '1 canal' : '$number canales',
      ContentKind.movie => n == 1 ? '1 película' : '$number películas',
      ContentKind.series => n == 1 ? '1 serie' : '$number series',
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final count = ref.watch(
      catalogSyncProvider.select((s) => s.info[kind]?.itemCount),
    );
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.go(route),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Icono grande de fondo, apenas visible, para dar peso.
            Positioned(
              right: -18,
              bottom: -26,
              child: Icon(
                icon,
                size: 150,
                color: AppColors.accent.withValues(alpha: 0.06),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Row(
                children: [
                  Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Icon(icon, size: 40, color: AppColors.accent),
                  ),
                  const SizedBox(width: 22),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: text.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          count == null ? subtitle : _count(kind, count),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.titleSmall?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 28,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
