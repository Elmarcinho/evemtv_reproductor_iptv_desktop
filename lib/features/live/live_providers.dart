import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logging/app_logger.dart';
import '../../core/utils/task_pool.dart';
import '../../domain/entities/catalog.dart';
import '../../domain/entities/live.dart';
import '../auth/application/session.dart';
import '../catalog/category_cache.dart';
import '../parental/parental.dart';

// Todos viven en el contenedor de la sesión (dependen de
// `contentSourceProvider`): se destruyen con ella, junto con sus peticiones.

/// Todas las categorías de TV en vivo del proveedor, sin filtrar. La
/// interfaz usa [liveCategoriesProvider] (sin las ocultas por el control
/// parental).
final liveCategoriesAllProvider = FutureProvider<List<ContentCategory>>((
  ref,
) async {
  final source = ref.watch(contentSourceProvider);
  return source.liveCategories();
}, dependencies: [contentSourceProvider]);

/// Categorías de TV en vivo visibles (se cargan primero; los canales, bajo
/// demanda). Las de adultos o bloqueadas se ocultan mientras el control
/// parental esté bloqueado.
final liveCategoriesProvider = FutureProvider<List<ContentCategory>>((
  ref,
) async {
  final all = await ref.watch(liveCategoriesAllProvider.future);
  return visibleCategories(ref.watch(parentalProvider), ContentKind.live, all);
}, dependencies: [liveCategoriesAllProvider, parentalProvider]);

/// Canales de una categoría del proveedor, sin filtrar. En memoria solo
/// las últimas categorías usadas, para volver rápido a una ya vista sin que
/// la memoria crezca sin límite (ver [CategoryListCache]).
final liveChannelsSourceProvider = FutureProvider.autoDispose
    .family<List<LiveChannel>, String?>((ref, categoryId) async {
      final source = ref.watch(contentSourceProvider);
      final channels = await source.liveChannels(categoryId: categoryId);
      if (ref.mounted) keepRecentCategory(ref, ('live', categoryId));
      return channels;
    }, dependencies: [contentSourceProvider, categoryListCacheProvider]);

/// Canales visibles de una categoría, o de todas con `null`: sin los de
/// adultos ni los de categorías ocultas mientras el control parental esté
/// bloqueado (también al cambiar de canal con las flechas).
final liveChannelsProvider = FutureProvider.autoDispose
    .family<List<LiveChannel>, String?>(
      (ref, categoryId) async {
        final channels = await ref.watch(
          liveChannelsSourceProvider(categoryId).future,
        );
        final parental = ref.watch(parentalProvider);
        if (parental.unlocked) return channels;
        final hidden = await hiddenCategoryIdsOf(
          ref,
          parental,
          ContentKind.live,
          liveCategoriesAllProvider,
        );
        if (categoryId != null && hidden.contains(categoryId)) return const [];
        return [
          for (final c in channels)
            if (!c.adult && !hidden.contains(c.categoryId)) c,
        ];
      },
      dependencies: [
        liveChannelsSourceProvider,
        liveCategoriesAllProvider,
        parentalProvider,
      ],
    );

/// EPG corta de un canal. Es informativa: si falla, lista vacía (la fila
/// simplemente no muestra programa). Lo obtenido se guarda 5 minutos tras
/// dejar de usarse para no repetir peticiones al hacer scroll.
final shortEpgProvider = FutureProvider.autoDispose
    .family<List<EpgEntry>, LiveChannel>((ref, channel) async {
      final source = ref.watch(contentSourceProvider);
      // Si la fila deja de verse antes de que le toque el turno, la
      // petición se descarta (evita colas largas al recorrer la lista).
      var disposed = false;
      ref.onDispose(() => disposed = true);
      try {
        final result = await source.shortEpg(
          channel,
          isCancelled: () => disposed,
        );
        // Solo lo obtenido se conserva 5 minutos.
        final link = ref.keepAlive();
        final timer = Timer(const Duration(minutes: 5), link.close);
        ref.onDispose(timer.cancel);
        return result;
      } on TaskCancelledException {
        return const [];
      } on Object catch (e) {
        AppLogger.w('EPG corta no disponible', e);
        return const [];
      }
    }, dependencies: [contentSourceProvider]);

/// Programa en emisión y el siguiente, a partir de la EPG corta.
({EpgEntry? now, EpgEntry? next}) nowAndNext(
  List<EpgEntry> entries,
  DateTime at,
) {
  for (var i = 0; i < entries.length; i++) {
    if (entries[i].isLiveAt(at)) {
      return (
        now: entries[i],
        next: i + 1 < entries.length ? entries[i + 1] : null,
      );
    }
  }
  final upcoming = entries.where((e) => e.start.isAfter(at)).firstOrNull;
  return (now: null, next: upcoming);
}
