import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/images/image_disk_cache.dart';
import '../../core/logging/app_logger.dart';
import '../../data/providers.dart';
import '../../data/storage/image_cache_key_store.dart';
import '../auth/application/session.dart';

/// Carpeta raíz de las cachés de imágenes (una subcarpeta por perfil).
/// Los tests la reemplazan por una carpeta temporal.
final imageCacheRootProvider = Provider<Future<Directory> Function()>(
  (ref) =>
      () async => Directory(
        p.join((await getApplicationSupportDirectory()).path, 'image_cache'),
      ),
);

/// Comprobación de que una imagen decodifica antes de guardarla. Los tests
/// sin motor gráfico la reemplazan.
final imageDecodeCheckProvider = Provider<Future<bool> Function(Uint8List)>(
  (ref) => ImageDiskCache.decodes,
);

final imageCacheKeyStoreProvider = Provider<ImageCacheKeyStore>(
  (ref) => ImageCacheKeyStore(ref.watch(secureStorageProvider)),
);

/// Cachés de imágenes abiertas, por perfil. Vive fuera de las sesiones para
/// que el cierre de sesión pueda cerrarlas **antes** de borrar la carpeta:
/// así ninguna descarga tardía la vuelve a crear.
class ImageCacheRegistry {
  ImageCacheRegistry(this._root, this._keys);

  final Future<Directory> Function() _root;
  final ImageCacheKeyStore _keys;
  final Map<int, Set<ImageDiskCache>> _open = {};

  /// Perfiles que se están eliminando: una caché que se abra para ellos
  /// nace cerrada.
  final Set<int> _closing = {};

  Future<Directory> directoryFor(int profileId) async =>
      Directory(p.join((await _root()).path, '$profileId'));

  void register(int profileId, ImageDiskCache cache) {
    (_open[profileId] ??= {}).add(cache);
    if (_closing.contains(profileId)) unawaited(cache.close());
  }

  void unregister(int profileId, ImageDiskCache cache) {
    final set = _open[profileId];
    set?.remove(cache);
    if (set != null && set.isEmpty) _open.remove(profileId);
  }

  /// Cierra todas las cachés del perfil y espera sus operaciones en curso.
  Future<void> close(int profileId) async {
    _closing.add(profileId);
    await Future.wait([
      for (final c in _open[profileId]?.toList() ?? const <ImageDiskCache>[])
        c.close(),
    ]);
  }

  /// Deshace [close] (la eliminación falló y el perfil sigue en uso).
  void reopen(int profileId) {
    _closing.remove(profileId);
    for (final c in _open[profileId] ?? const <ImageDiskCache>{}) {
      c.reopen();
    }
  }

  /// Borra la carpeta y la clave del perfil y **comprueba** que ya no
  /// existan. Lanza si algo quedó. Solo después de [close].
  Future<void> purge(int profileId) async {
    try {
      final dir = await directoryFor(profileId);
      if (await dir.exists()) await dir.delete(recursive: true);
      await _keys.delete(profileId);
      if (await dir.exists()) {
        throw const FileSystemException('la carpeta sigue existiendo');
      }
      if (await _keys.exists(profileId)) {
        throw StateError('la clave sigue guardada');
      }
    } finally {
      // Los ids se pueden reutilizar: un perfil nuevo con este id no debe
      // nacer con la caché cerrada.
      _closing.remove(profileId);
    }
  }
}

final imageCacheRegistryProvider = Provider<ImageCacheRegistry>(
  (ref) => ImageCacheRegistry(
    ref.watch(imageCacheRootProvider),
    ref.watch(imageCacheKeyStoreProvider),
  ),
);

/// Caché de imágenes en disco del perfil de la sesión, o `null` si no se
/// puede usar (sin llavero, sin carpeta de la app): en ese caso las
/// imágenes se cargan de la red como antes. Se cierra con la sesión.
final imageDiskCacheProvider = FutureProvider<ImageDiskCache?>((ref) async {
  final profileId = ref.watch(sessionContextProvider).profileId;
  final registry = ref.watch(imageCacheRegistryProvider);
  final dio = ref.watch(dioProvider);
  final keys = ref.watch(imageCacheKeyStoreProvider);
  final verifyDecodes = ref.watch(imageDecodeCheckProvider);
  try {
    final key = await keys.keyFor(profileId);
    final directory = await registry.directoryFor(profileId);
    // La sesión terminó mientras se preparaba: no se abre nada.
    if (!ref.mounted) return null;
    final cache = ImageDiskCache(
      directory: directory,
      key: key,
      dio: dio,
      verifyDecodes: verifyDecodes,
    );
    registry.register(profileId, cache);
    ref.onDispose(() {
      registry.unregister(profileId, cache);
      unawaited(cache.close());
    });
    unawaited(cache.prune());
    return cache;
  } on Object catch (e) {
    AppLogger.w('Caché de imágenes no disponible', e);
    return null;
  }
}, dependencies: [sessionContextProvider]);

/// Imagen de red con caché en disco (si está disponible), decodificada al
/// tamaño mostrado. Mientras la caché de la sesión se abre, la imagen se
/// pide a la red: nunca se usa la caché de otra sesión.
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
