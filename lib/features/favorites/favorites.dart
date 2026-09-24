import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logging/app_logger.dart';
import '../../data/providers.dart';
import '../../domain/entities/favorite.dart';
import '../../domain/entities/live.dart';
import '../../domain/entities/source_credentials.dart';
import '../../domain/entities/vod.dart';
import '../auth/application/session.dart';

/// Id de la categoría virtual "Favoritos" en En vivo, Películas y Series.
const String favoritesCategoryId = '__favoritos__';

/// Favoritos de un tipo en el perfil activo, en tiempo real.
final favoritesProvider = StreamProvider.family<List<Favorite>, FavoriteKind>((
  ref,
  kind,
) {
  final profileId = ref.watch(sessionProvider.select((s) => s?.profile.id));
  if (profileId == null) return Stream.value(const []);
  return ref.watch(favoritesRepositoryProvider).watch(profileId, kind);
});

/// Ids favoritos de un tipo, para marcar filas y pósters.
final favoriteIdsProvider = Provider.family<Set<String>, FavoriteKind>((
  ref,
  kind,
) {
  final list = ref.watch(favoritesProvider(kind)).value ?? const [];
  return {for (final f in list) f.itemId};
});

/// Agregar y quitar favoritos del perfil activo.
class FavoritesService {
  FavoritesService(this._ref);

  final Ref _ref;

  Future<void> toggleChannel(LiveChannel c) => _toggle(
    FavoriteKind.live,
    c.id,
    () => Favorite(
      kind: FavoriteKind.live,
      itemId: c.id,
      name: c.name,
      number: c.number,
      imageUrl: safeImageUrl(c.logoUrl),
      addedAt: DateTime.now(),
    ),
  );

  Future<void> toggleMovie(VodItem m) => _toggle(
    FavoriteKind.movie,
    m.id,
    () => Favorite(
      kind: FavoriteKind.movie,
      itemId: m.id,
      name: m.name,
      imageUrl: safeImageUrl(m.posterUrl),
      containerExtension: m.containerExtension,
      year: m.year,
      addedAt: DateTime.now(),
    ),
  );

  Future<void> toggleSeries(SeriesItem s) => _toggle(
    FavoriteKind.series,
    s.id,
    () => Favorite(
      kind: FavoriteKind.series,
      itemId: s.id,
      name: s.name,
      imageUrl: safeImageUrl(s.posterUrl),
      year: s.year,
      addedAt: DateTime.now(),
    ),
  );

  Future<void> _toggle(
    FavoriteKind kind,
    String itemId,
    Favorite Function() build,
  ) async {
    final profileId = _ref.read(sessionProvider)?.profile.id;
    if (profileId == null) return;
    final repo = _ref.read(favoritesRepositoryProvider);
    final isFavorite = _ref.read(favoriteIdsProvider(kind)).contains(itemId);
    if (isFavorite) {
      await repo.remove(profileId, kind, itemId);
    } else {
      await repo.add(profileId, build());
    }
    AppLogger.event('favorite.toggle', {'kind': kind, 'added': !isFavorite});
  }

  /// La URL de la imagen solo se guarda si no revela el servidor ni las
  /// credenciales de la sesión: la base local no debe guardar el host del
  /// panel (spec de seguridad). Si no, el favorito se muestra con un ícono.
  String? safeImageUrl(String? url) {
    if (url == null) return null;
    final uri = Uri.tryParse(url);
    final credentials = _ref.read(sessionProvider)?.credentials;
    if (uri == null || credentials == null) return null;
    final serverHost = switch (credentials) {
      XtreamCredentials(:final server) => server.host,
      M3uCredentials(:final playlist) => playlist.host,
    };
    if (uri.host.toLowerCase() == serverHost.toLowerCase()) return null;
    for (final secret in credentials.secrets) {
      if (secret.length >= 3 && url.contains(secret)) return null;
    }
    return url;
  }
}

final favoritesServiceProvider = Provider<FavoritesService>(
  FavoritesService.new,
);
