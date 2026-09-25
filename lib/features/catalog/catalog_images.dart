import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/catalog.dart';
import '../live/live_providers.dart';
import 'catalog_providers.dart';

/// Clave para buscar la imagen de un elemento en su categoría.
typedef CatalogImageKey = ({ContentKind kind, String? categoryId, String id});

/// Logo o póster de un elemento, resuelto en memoria desde la lista de su
/// categoría (la base local no guarda URLs). Se usa en búsqueda, favoritos
/// y "seguir viendo", solo para las filas visibles: cada categoría se pide
/// una vez y queda en memoria durante la sesión.
final catalogImageProvider = FutureProvider.autoDispose
    .family<String?, CatalogImageKey>(
      (ref, key) async {
        final categoryId = key.categoryId;
        if (categoryId == null) return null;
        try {
          switch (key.kind) {
            case ContentKind.live:
              final list = await ref.watch(
                liveChannelsProvider(categoryId).future,
              );
              return list.where((c) => c.id == key.id).firstOrNull?.logoUrl;
            case ContentKind.movie:
              final list = await ref.watch(vodItemsProvider(categoryId).future);
              return list.where((m) => m.id == key.id).firstOrNull?.posterUrl;
            case ContentKind.series:
              final list = await ref.watch(
                seriesItemsProvider(categoryId).future,
              );
              return list.where((s) => s.id == key.id).firstOrNull?.posterUrl;
          }
        } on Object {
          // La imagen es opcional.
          return null;
        }
      },
      dependencies: [
        liveChannelsProvider,
        vodItemsProvider,
        seriesItemsProvider,
      ],
    );
