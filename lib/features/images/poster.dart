import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import 'app_images.dart';

/// Póster 2:3 con carga diferida y caché en disco, decodificado al tamaño
/// mostrado y con un respaldo si no hay imagen o falla la descarga.
class Poster extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
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
              : Image(
                  // Caché en disco + decodificado al tamaño mostrado: miles
                  // de pósters sin disparar la memoria ni la red.
                  image: appImage(
                    ref,
                    url!,
                    cacheWidth: w.isFinite ? (w * dpr).round() : null,
                  ),
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => fallback,
                  frameBuilder: (context, child, frame, sync) =>
                      frame == null && !sync ? fallback : child,
                ),
        );
      },
    );
  }
}
