import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Botón ★ para agregar o quitar de favoritos.
class FavoriteButton extends StatelessWidget {
  const FavoriteButton({
    super.key,
    required this.isFavorite,
    required this.onPressed,
    this.compact = false,
  });

  final bool isFavorite;
  final VoidCallback onPressed;

  /// Solo ícono (paneles angostos).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final icon = Icon(
      isFavorite ? Icons.star_rounded : Icons.star_outline_rounded,
      color: isFavorite ? AppColors.favorite : null,
    );
    final tooltip = isFavorite ? 'Quitar de favoritos' : 'Agregar a favoritos';
    if (compact) {
      return IconButton.outlined(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: icon,
      );
    }
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: icon,
      label: Text(isFavorite ? 'En favoritos' : 'Agregar a favoritos'),
    );
  }
}

/// Marca pequeña para filas y pósters que están en favoritos.
class FavoriteBadge extends StatelessWidget {
  const FavoriteBadge({super.key, this.size = 18});

  final double size;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'En favoritos',
    child: Icon(Icons.star_rounded, size: size, color: AppColors.favorite),
  );
}
