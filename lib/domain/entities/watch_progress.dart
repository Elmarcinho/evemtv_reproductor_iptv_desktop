import 'vod.dart';

enum ProgressKind { movie, episode }

/// Posición guardada de una película o episodio ("Seguir viendo").
/// **Sin URLs**: solo ids y datos para mostrar y reanudar.
class WatchProgress {
  const WatchProgress({
    required this.kind,
    required this.itemId,
    required this.title,
    required this.position,
    required this.duration,
    required this.updatedAt,
    this.categoryId,
    this.containerExtension,
    this.seriesId,
    this.season,
    this.episode,
    this.episodeTitle,
  });

  final ProgressKind kind;

  /// Id de la película o del episodio.
  final String itemId;

  /// Nombre de la película o de la serie.
  final String title;
  final Duration position;
  final Duration duration;
  final DateTime updatedAt;

  /// Categoría de la película o de la serie (para resolver la imagen).
  final String? categoryId;
  final String? containerExtension;

  // Solo episodios.
  final String? seriesId;
  final int? season;
  final int? episode;
  final String? episodeTitle;

  double get fraction => duration.inMilliseconds <= 0
      ? 0
      : (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);

  String? get subtitle => kind == ProgressKind.episode
      ? 'T$season · E$episode${episodeTitle == null ? '' : ' · $episodeTitle'}'
      : null;

  VodItem toMovie() => VodItem(
    id: itemId,
    name: title,
    categoryId: categoryId,
    containerExtension: containerExtension,
  );

  SeriesItem toSeries() =>
      SeriesItem(id: seriesId ?? '', name: title, categoryId: categoryId);

  Episode toEpisode() => Episode(
    id: itemId,
    season: season ?? 1,
    number: episode ?? 1,
    title: episodeTitle ?? title,
    containerExtension: containerExtension,
  );

  /// Terminado: más del 95 % visto o menos de 90 s para el final. Ya no se
  /// muestra en "Seguir viendo".
  static bool isFinished(Duration position, Duration duration) {
    if (duration <= Duration.zero) return false;
    return position >= duration * 0.95 ||
        duration - position < const Duration(seconds: 90);
  }

  /// Menos de 30 s vistos: no vale la pena guardarlo.
  static bool isTooEarly(Duration position) =>
      position < const Duration(seconds: 30);
}
