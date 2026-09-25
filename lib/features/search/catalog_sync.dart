import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logging/app_logger.dart';
import '../../data/providers.dart';
import '../../domain/entities/catalog.dart';
import '../../domain/entities/live.dart';
import '../../domain/repositories/content_source.dart';
import '../auth/application/session.dart';

/// Estado de la actualización del catálogo local.
class CatalogSyncState {
  const CatalogSyncState({
    this.running = false,
    this.current,
    this.info = const {},
    this.failed = const {},
  });

  final bool running;

  /// Tipo que se está descargando ahora.
  final ContentKind? current;
  final Map<ContentKind, CatalogSyncInfo> info;

  /// Tipos que fallaron en la última actualización.
  final Set<ContentKind> failed;

  bool get hasIndex => info.isNotEmpty;

  CatalogSyncState copyWith({
    bool? running,
    ContentKind? current,
    bool clearCurrent = false,
    Map<ContentKind, CatalogSyncInfo>? info,
    Set<ContentKind>? failed,
  }) => CatalogSyncState(
    running: running ?? this.running,
    current: clearCurrent ? null : (current ?? this.current),
    info: info ?? this.info,
    failed: failed ?? this.failed,
  );
}

/// Mantiene el catálogo local (y el índice de búsqueda) de la sesión activa.
///
/// - Al abrir la sesión, actualiza en segundo plano los tipos con más de
///   [maxAge] (o nunca descargados): en vivo, películas y series, de a uno.
/// - Las descargas grandes se decodifican en otro isolate y drift escribe en
///   su propio isolate: la interfaz no se bloquea.
/// - Si la sesión cambia a mitad de camino, lo descargado se descarta
///   (mismo mecanismo de época que el resto de la app).
class CatalogSyncController extends Notifier<CatalogSyncState> {
  static const Duration maxAge = Duration(hours: 12);

  @override
  CatalogSyncState build() {
    final session = ref.watch(sessionProvider);
    if (session == null) return const CatalogSyncState();
    // Arranca después de construir, sin bloquear.
    Future.microtask(() => sync());
    return const CatalogSyncState();
  }

  /// Sincronización en curso: una segunda llamada la reutiliza en lugar de
  /// descargar todo otra vez (la bandera `running` recién se activa después
  /// del primer `await`).
  Future<void>? _inFlight;

  /// Época de sesión de [_inFlight]: si cambió, esa sincronización ya no
  /// sirve (se descartará sola) y hay que empezar otra.
  SessionToken? _inFlightToken;

  /// Actualiza los tipos vencidos, o todos si [force].
  Future<void> sync({bool force = false}) {
    final token = ref.read(sessionProvider.notifier).token;
    final existing = _inFlight;
    if (existing != null && _inFlightToken == token) return existing;
    _inFlightToken = token;
    late final Future<void> current;
    current = _sync(force: force).whenComplete(() {
      // Solo limpia la suya: la de una sesión nueva puede estar en curso.
      if (identical(_inFlight, current)) _inFlight = null;
    });
    return _inFlight = current;
  }

  Future<void> _sync({bool force = false}) async {
    final sessions = ref.read(sessionProvider.notifier);
    final token = sessions.token;
    final profileId = ref.read(sessionProvider)?.profile.id;
    final source = ref.read(contentSourceProvider);
    if (profileId == null || source == null) return;
    final cache = ref.read(catalogCacheProvider);

    // Estado actual del índice.
    final info = <ContentKind, CatalogSyncInfo>{};
    for (final kind in ContentKind.values) {
      final i = await cache.syncInfo(profileId, kind);
      if (i != null) info[kind] = i;
    }
    if (!ref.mounted || !sessions.isCurrent(token)) return;
    state = state.copyWith(info: info);

    final now = DateTime.now();
    final pending = [
      for (final kind in ContentKind.values)
        if (force ||
            info[kind] == null ||
            now.difference(info[kind]!.syncedAt) > maxAge)
          kind,
    ];
    if (pending.isEmpty) return;

    state = state.copyWith(running: true, failed: {});
    final failed = <ContentKind>{};
    for (final kind in pending) {
      if (!ref.mounted || !sessions.isCurrent(token)) return;
      state = state.copyWith(current: kind);
      try {
        final (categories, items) = await _download(source, kind);
        if (!ref.mounted || !sessions.isCurrent(token)) return;
        await cache.replace(profileId, kind, categories, items);
        final updated = await cache.syncInfo(profileId, kind);
        if (!ref.mounted || !sessions.isCurrent(token)) return;
        state = state.copyWith(info: {...state.info, kind: ?updated});
        AppLogger.event('catalog.synced', {
          'kind': kind,
          'items': items.length,
        });
      } on Object catch (e) {
        failed.add(kind);
        AppLogger.w('No se pudo actualizar el catálogo', e);
      }
    }
    if (!ref.mounted || !sessions.isCurrent(token)) return;
    state = state.copyWith(running: false, clearCurrent: true, failed: failed);
  }

  static Future<(List<ContentCategory>, List<CatalogEntry>)> _download(
    ContentSource source,
    ContentKind kind,
  ) async {
    switch (kind) {
      case ContentKind.live:
        return (
          await source.liveCategories(),
          [
            for (final c in await source.liveChannels())
              CatalogEntry.fromChannel(c),
          ],
        );
      case ContentKind.movie:
        return (
          await source.vodCategories(),
          [for (final m in await source.vodItems()) CatalogEntry.fromMovie(m)],
        );
      case ContentKind.series:
        return (
          await source.seriesCategories(),
          [
            for (final s in await source.seriesItems())
              CatalogEntry.fromSeries(s),
          ],
        );
    }
  }
}

final catalogSyncProvider =
    NotifierProvider<CatalogSyncController, CatalogSyncState>(
      CatalogSyncController.new,
    );

/// Resultados de la búsqueda global en el catálogo local del perfil activo.
final searchResultsProvider = FutureProvider.autoDispose
    .family<SearchResults, String>((ref, query) async {
      final profileId = ref.watch(sessionProvider.select((s) => s?.profile.id));
      if (profileId == null || query.trim().isEmpty) {
        return SearchResults.empty;
      }
      // Se vuelve a buscar cuando termina una actualización del catálogo.
      ref.watch(catalogSyncProvider.select((s) => s.info));
      return ref.watch(catalogCacheProvider).search(profileId, query);
    });

/// Nombres de categorías de un tipo, para mostrar en los resultados.
final categoryNamesProvider = FutureProvider.autoDispose
    .family<Map<String, String>, ContentKind>((ref, kind) async {
      final profileId = ref.watch(sessionProvider.select((s) => s?.profile.id));
      if (profileId == null) return const {};
      ref.watch(catalogSyncProvider.select((s) => s.info[kind]));
      return ref.watch(catalogCacheProvider).categoryNames(profileId, kind);
    });

/// Mantiene viva la actualización del catálogo mientras haya sesión (se
/// escucha desde el inicio).
void keepCatalogSyncAlive(WidgetRef ref) =>
    ref.listen(catalogSyncProvider, (_, _) {});
