import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/images/image_disk_cache.dart';
import '../../core/logging/app_logger.dart';
import '../../data/providers.dart';
import '../../data/storage/image_cache_key_store.dart';
import '../auth/application/session.dart';

Future<Directory> _cacheDir(int profileId) async => Directory(
  p.join(
    (await getApplicationSupportDirectory()).path,
    'image_cache',
    '$profileId',
  ),
);

final imageCacheKeyStoreProvider = Provider<ImageCacheKeyStore>(
  (ref) => ImageCacheKeyStore(ref.watch(secureStorageProvider)),
);

/// Caché de imágenes en disco del perfil activo, o `null` si no se puede
/// usar (sin sesión, sin llavero, sin carpeta de la app): en ese caso las
/// imágenes se cargan de la red como antes.
final imageDiskCacheProvider = FutureProvider<ImageDiskCache?>((ref) async {
  final profileId = ref.watch(sessionProvider.select((s) => s?.profile.id));
  if (profileId == null) return null;
  try {
    final key = await ref.read(imageCacheKeyStoreProvider).keyFor(profileId);
    final cache = ImageDiskCache(
      directory: await _cacheDir(profileId),
      key: key,
      dio: ref.watch(dioProvider),
    );
    unawaited(cache.prune());
    return cache;
  } on Object catch (e) {
    AppLogger.w('Caché de imágenes no disponible', e);
    return null;
  }
});

/// Imagen de red con caché en disco (si está disponible), decodificada al
/// tamaño mostrado.
ImageProvider appImage(
  WidgetRef ref,
  String url, {
  int? cacheWidth,
  int? cacheHeight,
}) {
  final cache = ref.watch(imageDiskCacheProvider).value;
  final ImageProvider base = cache == null
      ? NetworkImage(url)
      : DiskCachedImage(url, cache);
  return ResizeImage.resizeIfNeeded(cacheWidth, cacheHeight, base);
}

/// Borra la caché de imágenes y su clave al eliminar un perfil.
Future<void> clearProfileImageCache(
  ImageCacheKeyStore keys,
  int profileId,
) async {
  try {
    final dir = await _cacheDir(profileId);
    if (await dir.exists()) await dir.delete(recursive: true);
  } on Object catch (e) {
    AppLogger.w('No se pudo borrar la caché de imágenes', e);
  }
  try {
    await keys.delete(profileId);
  } on Object catch (e) {
    AppLogger.w('No se pudo borrar la clave de la caché de imágenes', e);
  }
}
