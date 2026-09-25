import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../home/promo_banner.dart';

/// Encabezado de En vivo, Películas y Series con el filtro de la selección
/// actual: su etiqueta nombra la categoría ("Buscar en Favoritos") y queda
/// visible mientras se escribe. La búsqueda global está en el inicio. Al
/// lado, el botón discreto del anuncio ([PromoChip]).
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    required this.scopeLabel,
    required this.controller,
    required this.onFilter,
    this.onSubmitted,
  });

  final String title;

  /// Qué se filtra: "Favoritos", "Deportes", "todos los canales"…
  final String scopeLabel;
  final TextEditingController controller;
  final ValueChanged<String> onFilter;
  final VoidCallback? onSubmitted;

  @override
  Widget build(BuildContext context) {
    // El filtro se achica en ventanas chicas (entre 200 y 340 px).
    final filterWidth = (MediaQuery.sizeOf(context).width * 0.3).clamp(
      200.0,
      340.0,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 24, 12),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Volver (Esc)',
            onPressed: () => context.go(AppRoutes.home),
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
          const Spacer(),
          // Anuncio discreto, igual que en la barra del inicio.
          const PromoChip(),
          const SizedBox(width: 16),
          SizedBox(
            width: filterWidth,
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, _) => TextField(
                controller: controller,
                onChanged: onFilter,
                onSubmitted: (_) => onSubmitted?.call(),
                decoration: InputDecoration(
                  isDense: true,
                  // La etiqueta flota sobre el campo al escribir: siempre se
                  // ve en qué se está buscando.
                  labelText: 'Buscar en $scopeLabel',
                  prefixIcon: const Icon(Icons.filter_list_rounded),
                  suffixIcon: value.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Borrar',
                          icon: const Icon(Icons.close_rounded, size: 18),
                          onPressed: () {
                            controller.clear();
                            onFilter('');
                          },
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Nada coincide en la selección actual: lo dice y ofrece buscar en todo.
class NoMatchesInScope extends StatelessWidget {
  const NoMatchesInScope({
    super.key,
    required this.query,
    required this.scopeLabel,
  });

  final String query;
  final String scopeLabel;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Nada coincide con "$query" en $scopeLabel.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => context.push(AppRoutes.search, extra: query),
            icon: const Icon(Icons.travel_explore_rounded),
            label: Text('Buscar «$query» en todo el catálogo'),
          ),
        ],
      ),
    );
  }
}
