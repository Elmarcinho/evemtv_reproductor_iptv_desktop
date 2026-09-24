import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/state_views.dart';
import '../../player/live_player_provider.dart';
import '../../player/widgets/playback_status_view.dart';

/// Mini reproductor de la pantalla En vivo (16:9). Un clic sobre el video
/// abre la pantalla completa.
class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key, required this.onExpand});

  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(livePlayerProvider);
    final handle = state.handle;

    final Widget content;
    if (state.error != null) {
      content = Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            userMessageFor(state.error!),
            textAlign: TextAlign.center,
          ),
        ),
      );
    } else if (handle == null) {
      content = const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.play_circle_outline_rounded,
              size: 40,
              color: AppColors.textSecondary,
            ),
            SizedBox(height: 8),
            Text(
              'Selecciona un canal para verlo aquí',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    } else {
      content = Stack(
        fit: StackFit.expand,
        children: [
          // Sin controles de media_kit: un clic amplía.
          Video(controller: handle.video, controls: null),
          PlaybackStatusView(playback: handle.playback, compact: true),
          Positioned.fill(
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(onTap: onExpand),
            ),
          ),
          Positioned(
            right: 8,
            bottom: 8,
            child: _MiniButton(
              icon: Icons.fullscreen_rounded,
              tooltip: 'Ampliar (Enter)',
              onPressed: onExpand,
            ),
          ),
          Positioned(
            left: 8,
            bottom: 8,
            child: StreamBuilder<double>(
              stream: handle.engine.player.stream.volume,
              initialData: handle.engine.player.state.volume,
              builder: (context, snap) {
                final muted = (snap.data ?? 100) == 0;
                return _MiniButton(
                  icon: muted
                      ? Icons.volume_off_rounded
                      : Icons.volume_up_rounded,
                  tooltip: muted ? 'Activar sonido' : 'Silenciar',
                  onPressed: () =>
                      handle.engine.player.setVolume(muted ? 100 : 0),
                );
              },
            ),
          ),
        ],
      );
    }

    return AspectRatio(
      aspectRatio: 16 / 9,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: ColoredBox(color: Colors.black, child: content),
      ),
    );
  }
}

class _MiniButton extends StatelessWidget {
  const _MiniButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black54,
      shape: const CircleBorder(),
      child: IconButton(
        tooltip: tooltip,
        iconSize: 20,
        onPressed: onPressed,
        icon: Icon(icon, color: Colors.white),
      ),
    );
  }
}
