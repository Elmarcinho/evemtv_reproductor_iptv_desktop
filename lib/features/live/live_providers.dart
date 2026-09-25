import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logging/app_logger.dart';
import '../../core/utils/task_pool.dart';
import '../../domain/entities/live.dart';
import '../auth/application/session.dart';

// Todos viven en el contenedor de la sesión (dependen de
// `contentSourceProvider`): se destruyen con ella, junto con sus peticiones.

/// Categorías de TV en vivo (se cargan primero; los canales, bajo demanda).
final liveCategoriesProvider = FutureProvider<List<ContentCategory>>((
  ref,
) async {
  final source = ref.watch(contentSourceProvider);
  return source.liveCategories();
}, dependencies: [contentSourceProvider]);

/// Canales de una categoría, o todos con `null`. Se mantienen en memoria
/// durante la sesión para volver rápido a una categoría ya vista.
final liveChannelsProvider = FutureProvider.family<List<LiveChannel>, String?>((
  ref,
  categoryId,
) async {
  final source = ref.watch(contentSourceProvider);
  return source.liveChannels(categoryId: categoryId);
}, dependencies: [contentSourceProvider]);

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
