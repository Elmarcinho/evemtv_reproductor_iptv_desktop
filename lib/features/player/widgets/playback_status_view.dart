import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/state_views.dart';
import '../live_playback_controller.dart';

/// Estado de conexión sobre el video: conectando, reconectando o error con
/// "Reintentar". Nada cuando se está reproduciendo.
class PlaybackStatusView extends StatelessWidget {
  const PlaybackStatusView({
    super.key,
    required this.playback,
    this.compact = false,
  });

  final LivePlaybackController playback;

  /// Versión reducida para el mini reproductor.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: playback,
      builder: (context, _) {
        switch (playback.status) {
          case LivePlaybackStatus.playing:
            return const SizedBox.shrink();
          case LivePlaybackStatus.connecting:
            return const LoadingView(message: 'Conectando…');
          case LivePlaybackStatus.reconnecting:
            return LoadingView(
              message:
                  'Reconectando… (intento ${playback.attempt} de '
                  '${playback.maxAttempts})',
            );
          case LivePlaybackStatus.failed:
            return ColoredBox(
              color: Colors.black54,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.signal_wifi_bad_rounded,
                        size: compact ? 32 : 48,
                        color: AppColors.error,
                      ),
                      const SizedBox(height: 12),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: Text(
                          playback.failureMessage ?? '',
                          textAlign: TextAlign.center,
                          style: compact
                              ? Theme.of(context).textTheme.bodySmall
                              : null,
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: playback.retry,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Reintentar'),
                      ),
                    ],
                  ),
                ),
              ),
            );
        }
      },
    );
  }
}
