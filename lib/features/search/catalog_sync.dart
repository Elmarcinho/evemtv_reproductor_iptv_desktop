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

/// Mantiene el catálogo local (y el índice de búsqueda) de la sesión.
///
/// - Al abrir la sesión, actualiza en segundo plano los tipos con más de
///   [maxAge] (o nunca descargados): en vivo, películas y series, de a uno.
/// - Las descargas grandes se decodifican en otro isolate y drift escribe en
///   su propio isolate: la interfaz no se bloquea.
/// - Vive en el contenedor de la sesión y usa su perfil fijo. Al terminar
///   la sesión, la petición en curso se cancela y, entre un paso y otro,
///   [SessionLifetime.ensureActive] corta la sincronización: no sale
///   ninguna petición nueva ni se escribe nada.
class CatalogSyncController extends Notifier<CatalogSyncState> {
  static const Duration maxAge = Duration(hours: 12);

  @override
  CatalogSyncState build() {
    ref.watch(sessionContextProvider);
    // Arranca después de construir, sin bloquear.
    Future.microtask(() {
      if (ref.mounted) unawaited(sync());
    });
    return const CatalogSyncState();
  }

  /// Sincronización en curso: una segunda llamada la reutiliza en lugar de
  /// descargar todo otra vez (la bandera `running` recién se activa después
  /// del primer `await`).
  Future<void>? _inFlight;

  /// Actualiza los tipos vencidos, o todos si [force].
  Future<void> sync({bool force = false}) =>
      _inFlight ??= _sync(force: force).whenComplete(() => _inFlight = null);

  Future<void> _sync({bool force = false}) async {
    final ctx = ref.read(sessionContextProvider);
    final lifetime = ctx.lifetime;
    final profileId = ctx.profileId;
    final source = ref.read(contentSourceProvider);
    final cache = ref.read(catalogCacheProvider);
    // `false` si la sesión terminó: no se sigue ni se toca el estado.
    bool alive() => ref.mounted && lifetime.isActive;

    try {
      // Estado actual del índice.
      final info = <ContentKind, CatalogSyncInfo>{};
      for (final kind in ContentKind.values) {
        final i = await cache.syncInfo(profileId, kind);
        if (i != null) info[kind] = i;
      }
      if (!alive()) return;
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
        if (!alive()) return;
        state = state.copyWith(current: kind);
        try {
          final (categories, items) = await _download(source, kind, lifetime);
          lifetime.ensureActive();
          await cache.replace(profileId, kind, categories, items);
          final updated = await cache.syncInfo(profileId, kind);
          if (!alive()) return;
          state = state.copyWith(info: {...state.info, kind: ?updated});
          AppLogger.event('catalog.synced', {
            'kind': kind,
            'items': items.length,
          });
        } on SessionClosedException {
          rethrow;
        } on Object catch (e) {
          if (!alive()) return;
          failed.add(kind);
          AppLogger.w('No se pudo actualizar el catálogo', e);
        }
      }
      if (!alive()) return;
      state = state.copyWith(
        running: false,
        clearCurrent: true,
        failed: failed,
      );
    } on SessionClosedException {
      AppLogger.event('catalog.sync_stopped', {'reason': 'session_closed'});
    }
  }

  /// Descarga categorías y elementos de un tipo. Entre una petición y otra
  /// comprueba que la sesión siga activa.
  static Future<(List<ContentCategory>, List<CatalogEntry>)> _download(
    ContentSource source,
    ContentKind kind,
    SessionLifetime lifetime,
  ) async {
    lifetime.ensureActive();
    switch (kind) {
      case ContentKind.live:
        final categories = await source.liveCategories();
        lifetime.ensureActive();
        return (
          categories,
          [
            for (final c in await source.liveChannels())
              CatalogEntry.fromChannel(c),
          ],
        );
      case ContentKind.movie:
        final categories = await source.vodCategories();
        lifetime.ensureActive();
        return (
          categories,
          [for (final m in await source.vodItems()) CatalogEntry.fromMovie(m)],
        );
      case ContentKind.series:
        final categories = await source.seriesCategories();
        lifetime.ensureActive();
        return (
          categories,
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
      dependencies: [sessionContextProvider, contentSourceProvider],
    );

/// Resultados de la búsqueda global en el catálogo local de la sesión.
final searchResultsProvider = FutureProvider.autoDispose
    .family<SearchResults, String>((ref, query) async {
      final profileId = ref.watch(sessionContextProvider).profileId;
      if (query.trim().isEmpty) return SearchResults.empty;
      // Se vuelve a buscar cuando termina una actualización del catálogo.
      ref.watch(catalogSyncProvider.select((s) => s.info));
      return ref.watch(catalogCacheProvider).search(profileId, query);
    }, dependencies: [sessionContextProvider, catalogSyncProvider]);

/// Nombres de categorías de un tipo, para mostrar en los resultados.
final categoryNamesProvider = FutureProvider.autoDispose
    .family<Map<String, String>, ContentKind>((ref, kind) async {
      final profileId = ref.watch(sessionContextProvider).profileId;
      ref.watch(catalogSyncProvider.select((s) => s.info[kind]));
      return ref.watch(catalogCacheProvider).categoryNames(profileId, kind);
    }, dependencies: [sessionContextProvider, catalogSyncProvider]);
