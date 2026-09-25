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

/// Lista de categorías con una primera fila "todo" (`id == null`) y filas
/// fijas opcionales ([pinned]) antes de las categorías del proveedor.
class CategoryList extends StatelessWidget {
  const CategoryList({
    super.key,
    required this.categories,
    required this.selectedId,
    required this.onSelect,
    required this.allLabel,
    this.pinned = const [],
  });

  final List<ContentCategory> categories;
  final String? selectedId;
  final ValueChanged<String?> onSelect;

  /// Texto de la primera fila, p. ej. "Todos los canales".
  final String allLabel;
  final List<PinnedCategory> pinned;

  @override
  Widget build(BuildContext context) {
    final rows = <({String? id, String name, IconData? icon, Color? color})>[
      (id: null, name: allLabel, icon: Icons.apps_rounded, color: null),
      for (final p in pinned)
        (
          id: p.id,
          name: p.name,
          icon: p.icon,
          color: p.color ?? AppColors.favorite,
        ),
      for (final c in categories)
        (id: c.id, name: c.name, icon: null, color: null),
    ];
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: rows.length,
      itemBuilder: (context, i) {
        final row = rows[i];
        return ListTile(
          dense: true,
          selected: row.id == selectedId,
          selectedTileColor: AppColors.accent.withValues(alpha: 0.14),
          selectedColor: AppColors.textPrimary,
          leading: row.icon == null
              ? null
              : Icon(row.icon, size: 20, color: row.color),
          title: Text(row.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          onTap: () => onSelect(row.id),
        );
      },
    );
  }
}
