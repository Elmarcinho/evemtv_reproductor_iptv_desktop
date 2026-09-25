import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logging/app_logger.dart';
import '../../data/providers.dart';
import '../../domain/entities/vod.dart';
import '../../domain/entities/watch_progress.dart';
import '../auth/application/session.dart';

/// Todo el progreso del perfil activo (los más recientes primero). Las
/// entradas terminadas se borran, así que la lista se mantiene chica.
final allWatchProgressProvider = StreamProvider<List<WatchProgress>>((ref) {
  final profileId = ref.watch(sessionProvider.select((s) => s?.profile.id));
  if (profileId == null) return Stream.value(const []);
  return ref
      .watch(watchProgressRepositoryProvider)
      .watchRecent(profileId, limit: 500);
});

/// Fila "Seguir viendo" del inicio.
final continueWatchingProvider = Provider<List<WatchProgress>>((ref) {
  final all = ref.watch(allWatchProgressProvider).value ?? const [];
  return all.take(20).toList();
});

/// Progreso de una película o episodio concreto, o `null`.
final progressForProvider =
    Provider.family<WatchProgress?, ({ProgressKind kind, String id})>((
      ref,
      key,
    ) {
      final all = ref.watch(allWatchProgressProvider).value ?? const [];
      return all
          .where((p) => p.kind == key.kind && p.itemId == key.id)
          .firstOrNull;
    });

/// Último episodio visto de una serie, o `null`.
final seriesProgressProvider = Provider.family<WatchProgress?, String>((
  ref,
  seriesId,
) {
  final all = ref.watch(allWatchProgressProvider).value ?? const [];
  return all
      .where((p) => p.kind == ProgressKind.episode && p.seriesId == seriesId)
      .firstOrNull;
});

/// Guarda y consulta el progreso del perfil activo.
class WatchProgressService {
  WatchProgressService(this._ref);

  final Ref _ref;

  int? get _profileId => _ref.read(sessionProvider)?.profile.id;

  Future<WatchProgress?> find(ProgressKind kind, String id) async {
    final profileId = _profileId;
    if (profileId == null) return null;
    return _ref.read(watchProgressRepositoryProvider).get(profileId, kind, id);
  }

  Future<void> save(WatchProgress progress) async {
    final profileId = _profileId;
    if (profileId == null) return;
    try {
      await _ref
          .read(watchProgressRepositoryProvider)
          .save(profileId, progress);
    } on Object catch (e) {
      AppLogger.w('No se pudo guardar el progreso', e);
    }
  }

  Future<void> remove(ProgressKind kind, String id) async {
    final profileId = _profileId;
    if (profileId == null) return;
    try {
      await _ref
          .read(watchProgressRepositoryProvider)
          .remove(profileId, kind, id);
    } on Object catch (e) {
      AppLogger.w('No se pudo quitar el progreso', e);
    }
  }

  static WatchProgress forMovie(
    VodItem movie, {
    required Duration position,
    required Duration duration,
  }) => WatchProgress(
    kind: ProgressKind.movie,
    itemId: movie.id,
    title: movie.name,
    position: position,
    duration: duration,
    updatedAt: DateTime.now(),
    categoryId: movie.categoryId,
    containerExtension: movie.containerExtension,
  );

  static WatchProgress forEpisode(
    SeriesItem series,
    Episode episode, {
    required Duration position,
    required Duration duration,
  }) => WatchProgress(
    kind: ProgressKind.episode,
    itemId: episode.id,
    title: series.name,
    position: position,
    duration: duration,
    updatedAt: DateTime.now(),
    categoryId: series.categoryId,
    containerExtension: episode.containerExtension,
    seriesId: series.id,
    season: episode.season,
    episode: episode.number,
    episodeTitle: episode.title,
  );
}

final watchProgressServiceProvider = Provider<WatchProgressService>(
  WatchProgressService.new,
);

/// Qué necesita el seguimiento de un contenido reproducible.
abstract interface class ProgressTarget {
  bool get startOver;
  ({ProgressKind kind, String id}) get progressKey;
  WatchProgress progressAt(Duration position, Duration duration);

  /// Siguiente contenido (episodio) para dejar listo al terminar, o `null`.
  ProgressTarget? get nextTarget;
}

/// Reglas de "seguir viendo" del reproductor, separadas de la interfaz.
class VodProgressTracker {
  VodProgressTracker(this._service);

  final WatchProgressService _service;

  /// Posición desde la que retomar (5 s antes de lo guardado), o `null` si
  /// se pidió empezar de cero, no hay nada, es muy poco o ya terminó.
  Future<Duration?> resumePosition(ProgressTarget target) async {
    if (target.startOver) return null;
    final key = target.progressKey;
    final saved = await _service.find(key.kind, key.id);
    if (saved == null || WatchProgress.isTooEarly(saved.position)) return null;
    if (WatchProgress.isFinished(saved.position, saved.duration)) return null;
    final back = saved.position - const Duration(seconds: 5);
    return back > Duration.zero ? back : null;
  }

  /// Guarda la posición; si terminó, la quita y deja el siguiente episodio
  /// listo. Sin duración conocida no hace nada.
  Future<void> save(
    ProgressTarget target, {
    required Duration position,
    required Duration duration,
    bool completed = false,
  }) async {
    if (duration <= Duration.zero) return;
    final key = target.progressKey;
    final end = completed ? duration : position;
    if (completed || WatchProgress.isFinished(end, duration)) {
      await _service.remove(key.kind, key.id);
      final next = target.nextTarget;
      if (next != null) {
        await _service.save(next.progressAt(Duration.zero, Duration.zero));
      }
      return;
    }
    if (WatchProgress.isTooEarly(position)) return;
    await _service.save(target.progressAt(position, duration));
  }
}
