import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../images/app_images.dart';

/// Logo de canal con carga diferida, tamaño de caché acotado y un ícono de
/// respaldo si no hay logo o falla la descarga.
class ChannelLogo extends ConsumerWidget {
  const ChannelLogo({super.key, required this.url, this.size = 40});

  final String? url;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
          : Image(
              // Caché en disco + decodificado al tamaño mostrado: con miles
              // de logos, la memoria y la red se mantienen bajas.
              image: appImage(ref, url!, cacheWidth: (size * dpr).round()),
              width: size,
              height: size,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
              errorBuilder: (_, _, _) => fallback,
              frameBuilder: (context, child, frame, sync) =>
                  frame == null && !sync ? fallback : child,
            ),
    );
  }
}
