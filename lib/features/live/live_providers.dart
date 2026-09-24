import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logging/app_logger.dart';
import '../../domain/entities/live.dart';
import '../auth/application/session.dart';

// Todos dependen de `contentSourceProvider`: al cambiar de sesión se
// recalculan y Riverpod descarta los resultados que llegan tarde de la
// sesión anterior.

/// Categorías de TV en vivo (se cargan primero; los canales, bajo demanda).
final liveCategoriesProvider = FutureProvider<List<ContentCategory>>((
  ref,
) async {
  final source = ref.watch(contentSourceProvider);
  if (source == null) return const [];
  return source.liveCategories();
});

/// Canales de una categoría, o todos con `null`. Se mantienen en memoria
/// durante la sesión para volver rápido a una categoría ya vista.
final liveChannelsProvider = FutureProvider.family<List<LiveChannel>, String?>((
  ref,
  categoryId,
) async {
  final source = ref.watch(contentSourceProvider);
  if (source == null) return const [];
  return source.liveChannels(categoryId: categoryId);
});

/// EPG corta de un canal. Es informativa: si falla, lista vacía (la fila
/// simplemente no muestra programa). Se guarda 5 minutos tras dejar de
/// usarse para no repetir peticiones al hacer scroll.
final shortEpgProvider = FutureProvider.autoDispose
    .family<List<EpgEntry>, LiveChannel>((ref, channel) async {
      final source = ref.watch(contentSourceProvider);
      if (source == null) return const [];
      final link = ref.keepAlive();
      final timer = Timer(const Duration(minutes: 5), link.close);
      ref.onDispose(timer.cancel);
      try {
        return await source.shortEpg(channel);
      } on Object catch (e) {
        AppLogger.w('EPG corta no disponible', e);
        link.close();
        return const [];
      }
    });

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
