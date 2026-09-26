import 'package:flutter/material.dart';

import '../../domain/entities/live.dart';
import '../theme/app_theme.dart';

/// Fila fija al principio de la lista (p. ej. "Favoritos").
/// Categoría fija. [color] del icono: por defecto el de favoritos.
typedef PinnedCategory = ({
  String id,
  String name,
  IconData icon,
  Color? color,
});

/// Acciones de control parental sobre las categorías del proveedor.
class CategoryParentalActions {
  const CategoryParentalActions({
    required this.isBlocked,
    required this.isAutomatic,
    required this.onBlock,
    required this.onUnblock,
  });

  /// Bloqueada (se ve solo con el contenido adulto desbloqueado).
  final bool Function(ContentCategory category) isBlocked;

  /// De adultos por marca del panel o por nombre: no se puede desbloquear
  /// de forma permanente.
  final bool Function(ContentCategory category) isAutomatic;
  final ValueChanged<ContentCategory> onBlock;
  final ValueChanged<ContentCategory> onUnblock;
}

/// Lista de categorías con una primera fila "todo" (`id == null`) y filas
/// fijas opcionales ([pinned]) antes de las categorías del proveedor.
///
/// Con [parental], cada categoría del proveedor tiene un menú (clic derecho,
/// o ⋮ en la seleccionada) para ocultarla o volver a mostrarla, y las
/// bloqueadas llevan un candado. [footer] va fijo al pie.
class CategoryList extends StatelessWidget {
  const CategoryList({
    super.key,
    required this.categories,
    required this.selectedId,
    required this.onSelect,
    required this.allLabel,
    this.pinned = const [],
    this.parental,
    this.footer,
  });

  final List<ContentCategory> categories;
  final String? selectedId;
  final ValueChanged<String?> onSelect;

  /// Texto de la primera fila, p. ej. "Todos los canales".
  final String allLabel;
  final List<PinnedCategory> pinned;
  final CategoryParentalActions? parental;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final fixed = <({String? id, String name, IconData icon, Color? color})>[
      (id: null, name: allLabel, icon: Icons.apps_rounded, color: null),
      for (final p in pinned)
        (
          id: p.id,
          name: p.name,
          icon: p.icon,
          color: p.color ?? AppColors.favorite,
        ),
    ];
    final list = ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: fixed.length + categories.length,
      itemBuilder: (context, i) {
        if (i < fixed.length) {
          final row = fixed[i];
          return ListTile(
            dense: true,
            selected: row.id == selectedId,
            selectedTileColor: AppColors.accent.withValues(alpha: 0.14),
            selectedColor: AppColors.textPrimary,
            leading: Icon(row.icon, size: 20, color: row.color),
            title: Text(row.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: () => onSelect(row.id),
          );
        }
        return _CategoryTile(
          category: categories[i - fixed.length],
          selected: categories[i - fixed.length].id == selectedId,
          onSelect: onSelect,
          parental: parental,
        );
      },
    );
    if (footer == null) return list;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: list),
        const Divider(height: 1),
        footer!,
      ],
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.category,
    required this.selected,
    required this.onSelect,
    required this.parental,
  });

  final ContentCategory category;
  final bool selected;
  final ValueChanged<String?> onSelect;
  final CategoryParentalActions? parental;

  List<PopupMenuEntry<VoidCallback>> _menu() {
    final p = parental!;
    if (p.isAutomatic(category)) {
      return const [
        PopupMenuItem(
          enabled: false,
          child: Text('Contenido para adultos (se oculta siempre)'),
        ),
      ];
    }
    return [
      if (p.isBlocked(category))
        PopupMenuItem(
          value: () => p.onUnblock(category),
          child: const ListTile(
            leading: Icon(Icons.lock_open_rounded),
            title: Text('Volver a mostrar esta categoría'),
          ),
        )
      else
        PopupMenuItem(
          value: () => p.onBlock(category),
          child: const ListTile(
            leading: Icon(Icons.lock_outline_rounded),
            title: Text('Ocultar esta categoría (control parental)'),
          ),
        ),
    ];
  }

  Future<void> _showMenuAt(BuildContext context, Offset position) async {
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final action = await showMenu<VoidCallback>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: _menu(),
    );
    action?.call();
  }

  @override
  Widget build(BuildContext context) {
    final p = parental;
    final blocked = p != null && p.isBlocked(category);
    final tile = ListTile(
      dense: true,
      selected: selected,
      selectedTileColor: AppColors.accent.withValues(alpha: 0.14),
      selectedColor: AppColors.textPrimary,
      leading: blocked
          ? const Icon(
              Icons.lock_rounded,
              size: 18,
              color: AppColors.favorite,
              semanticLabel: 'Bloqueada',
            )
          : null,
      title: Text(category.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: p != null && selected
          ? PopupMenuButton<VoidCallback>(
              tooltip: 'Opciones de la categoría',
              icon: const Icon(Icons.more_vert_rounded, size: 20),
              onSelected: (action) => action(),
              itemBuilder: (_) => _menu(),
            )
          : null,
      onTap: () => onSelect(category.id),
    );
    if (p == null) return tile;
    return GestureDetector(
      onSecondaryTapDown: (d) => _showMenuAt(context, d.globalPosition),
      child: tile,
    );
  }
}
