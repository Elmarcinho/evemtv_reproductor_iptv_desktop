import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

/// Controles compartidos por los reproductores de vivo y de películas/series.

/// Estilo común de los botones de la barra del reproductor.
final ButtonStyle barButtonStyle = IconButton.styleFrom(
  foregroundColor: barIconColor,
  iconSize: barIconSize,
);
const Color barIconColor = Colors.white;
const double barIconSize = 24;

class VolumeControl extends StatelessWidget {
  const VolumeControl({super.key, required this.player});

  final Player player;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<double>(
      stream: player.stream.volume,
      initialData: player.state.volume,
      builder: (context, snap) {
        final volume = snap.data ?? 100;
        return Row(
          children: [
            IconButton(
              tooltip: volume > 0 ? 'Silenciar (M)' : 'Activar sonido (M)',
              onPressed: () => player.setVolume(volume > 0 ? 0 : 100),
              icon: Icon(
                volume == 0
                    ? Icons.volume_off_rounded
                    : volume < 50
                    ? Icons.volume_down_rounded
                    : Icons.volume_up_rounded,
              ),
            ),
            SizedBox(
              width: 120,
              child: Slider(
                value: volume.clamp(0, 100),
                max: 100,
                onChanged: player.setVolume,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Selección de pista de audio y subtítulos.
class TracksMenu extends StatelessWidget {
  const TracksMenu({super.key, required this.player});

  final Player player;

  static String _label(String? title, String? language, int index) {
    final parts = [?title, ?language];
    return parts.isEmpty ? 'Pista ${index + 1}' : parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Tracks>(
      stream: player.stream.tracks,
      initialData: player.state.tracks,
      builder: (context, snap) {
        final tracks = snap.data ?? const Tracks();
        // media_kit agrega las opciones "auto" y "no": solo se listan las
        // pistas reales.
        final audio = tracks.audio
            .where((t) => t.id != 'auto' && t.id != 'no')
            .toList();
        final subtitles = tracks.subtitle
            .where((t) => t.id != 'auto' && t.id != 'no')
            .toList();
        return PopupMenuButton<VoidCallback>(
          tooltip: 'Audio y subtítulos',
          style: barButtonStyle,
          iconColor: barIconColor,
          iconSize: barIconSize,
          icon: const Icon(Icons.subtitles_outlined),
          onSelected: (action) => action(),
          itemBuilder: (context) => [
            const PopupMenuItem(enabled: false, child: Text('Audio')),
            if (audio.isEmpty)
              const PopupMenuItem(enabled: false, child: Text('  Única pista')),
            for (final (i, t) in audio.indexed)
              CheckedPopupMenuItem(
                checked: player.state.track.audio.id == t.id,
                value: () => player.setAudioTrack(t),
                child: Text(_label(t.title, t.language, i)),
              ),
            const PopupMenuDivider(),
            const PopupMenuItem(enabled: false, child: Text('Subtítulos')),
            CheckedPopupMenuItem(
              checked: player.state.track.subtitle.id == 'no',
              value: () => player.setSubtitleTrack(SubtitleTrack.no()),
              child: const Text('Desactivados'),
            ),
            for (final (i, t) in subtitles.indexed)
              CheckedPopupMenuItem(
                checked: player.state.track.subtitle.id == t.id,
                value: () => player.setSubtitleTrack(t),
                child: Text(_label(t.title, t.language, i)),
              ),
          ],
        );
      },
    );
  }
}
