import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Logo de canal con carga diferida, tamaño de caché acotado y un ícono de
/// respaldo si no hay logo o falla la descarga.
class ChannelLogo extends StatelessWidget {
  const ChannelLogo({super.key, required this.url, this.size = 40});

  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final fallback = Icon(
      Icons.live_tv_rounded,
      size: size * 0.55,
      color: AppColors.textSecondary,
    );
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: url == null
          ? fallback
          : Image.network(
              url!,
              width: size,
              height: size,
              fit: BoxFit.contain,
              // Decodifica al tamaño mostrado: con miles de logos, la memoria
              // de imágenes se mantiene baja.
              cacheWidth: (size * dpr).round(),
              filterQuality: FilterQuality.medium,
              errorBuilder: (_, _, _) => fallback,
              frameBuilder: (context, child, frame, sync) =>
                  frame == null && !sync ? fallback : child,
            ),
    );
  }
}
