import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Póster 2:3 con carga diferida, decodificado al tamaño mostrado y con un
/// respaldo si no hay imagen o falla la descarga.
class Poster extends StatelessWidget {
  const Poster({
    super.key,
    required this.url,
    required this.title,
    this.width,
    this.icon = Icons.movie_outlined,
  });

  final String? url;
  final String title;
  final double? width;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final fallback = ColoredBox(
      color: AppColors.surfaceHigh,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 32, color: AppColors.textSecondary),
              const SizedBox(height: 8),
              Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = width ?? constraints.maxWidth;
        final dpr = MediaQuery.devicePixelRatioOf(context);
        return AspectRatio(
          aspectRatio: 2 / 3,
          child: url == null
              ? fallback
              : Image.network(
                  url!,
                  fit: BoxFit.cover,
                  // Decodifica al tamaño mostrado: miles de pósters sin
                  // disparar la memoria.
                  cacheWidth: w.isFinite ? (w * dpr).round() : null,
                  errorBuilder: (_, _, _) => fallback,
                  frameBuilder: (context, child, frame, sync) =>
                      frame == null && !sync ? fallback : child,
                ),
        );
      },
    );
  }
}
