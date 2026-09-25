import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:path/path.dart' as p;

import '../logging/app_logger.dart';
import '../network/retry_interceptor.dart';

/// Caché de pósters y logos en disco, por perfil.
///
/// **No guarda URLs.** Cada archivo se llama como el HMAC-SHA256 de la URL
/// con una clave aleatoria del perfil que vive en el almacén seguro: sin esa
/// clave no se puede comprobar a qué URL corresponde un archivo (ni probar
/// contraseñas candidatas). En disco quedan solo los bytes de la imagen.
///
/// Tamaño acotado ([maxBytes]): se borran primero las imágenes usadas hace
/// más tiempo. Al cerrar sesión se borra la carpeta y la clave.
class ImageDiskCache {
  ImageDiskCache({
    required this.directory,
    required List<int> key,
    required this._dio,
    this.maxBytes = 300 * 1024 * 1024,
    this.maxImageBytes = 5 * 1024 * 1024,
  }) : _hmac = Hmac(sha256, key);

  final Directory directory;
  final Hmac _hmac;
  final Dio _dio;
  final int maxBytes;
  final int maxImageBytes;

  final Map<String, Future<Uint8List>> _inFlight = {};
  int _writesSincePrune = 0;

  /// Nombre del archivo para [url] (sin revelar la URL).
  String fileNameFor(String url) => _hmac.convert(utf8.encode(url)).toString();

  File _fileFor(String url) => File(p.join(directory.path, fileNameFor(url)));

  /// Bytes de la imagen: del disco si está, si no de la red (y se guarda).
  Future<Uint8List> load(String url) {
    final name = fileNameFor(url);
    // El callback NO debe devolver el Future quitado: whenComplete lo
    // esperaría y el futuro quedaría esperándose a sí mismo.
    return _inFlight[name] ??= _load(url).whenComplete(() {
      _inFlight.remove(name);
    });
  }

  Future<Uint8List> _load(String url) async {
    final file = _fileFor(url);
    try {
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        // Marca de uso para el orden de borrado (LRU).
        unawaited(
          file.setLastModified(DateTime.now()).catchError((Object _) {}),
        );
        return bytes;
      }
    } on FileSystemException {
      // Archivo dañado o ilegible: se vuelve a descargar.
    }
    final bytes = await _download(url);
    await _write(file, bytes);
    return bytes;
  }

  Future<Uint8List> _download(String url) async {
    final uri = Uri.parse(url);
    if (!uri.isScheme('http') && !uri.isScheme('https')) {
      throw const FormatException('esquema no soportado');
    }
    final response = await _dio.getUri<List<int>>(
      uri,
      options: Options(
        responseType: ResponseType.bytes,
        receiveTimeout: const Duration(seconds: 20),
        extra: <String, Object?>{RetryInterceptor.maxRetriesKey: 0},
      ),
    );
    final data = response.data;
    if (data == null || data.isEmpty) {
      throw const FormatException('imagen vacía');
    }
    if (data.length > maxImageBytes) {
      throw const FormatException('imagen demasiado grande');
    }
    return data is Uint8List ? data : Uint8List.fromList(data);
  }

  Future<void> _write(File file, Uint8List bytes) async {
    try {
      await directory.create(recursive: true);
      // Escritura atómica: nunca queda un archivo a medias.
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsBytes(bytes, flush: true);
      await tmp.rename(file.path);
      if (++_writesSincePrune >= 200) {
        _writesSincePrune = 0;
        unawaited(prune());
      }
    } on FileSystemException catch (e) {
      AppLogger.w('No se pudo guardar una imagen en caché', e);
    }
  }

  /// Borra las imágenes usadas hace más tiempo hasta quedar en el 80 % de
  /// [maxBytes].
  Future<void> prune() async {
    try {
      if (!await directory.exists()) return;
      final files = <({File file, int size, DateTime used})>[];
      var total = 0;
      await for (final e in directory.list(followLinks: false)) {
        if (e is! File) continue;
        final stat = await e.stat();
        if (stat.type != FileSystemEntityType.file) continue;
        total += stat.size;
        files.add((file: e, size: stat.size, used: stat.modified));
      }
      if (total <= maxBytes) return;
      files.sort((a, b) => a.used.compareTo(b.used));
      final target = (maxBytes * 0.8).round();
      var removed = 0;
      for (final f in files) {
        if (total <= target) break;
        await f.file.delete().catchError((Object _) => f.file);
        total -= f.size;
        removed++;
      }
      AppLogger.event('image_cache.prune', {'removed': removed});
    } on FileSystemException catch (e) {
      AppLogger.w('No se pudo limpiar la caché de imágenes', e);
    }
  }

  /// Borra toda la caché del perfil.
  Future<void> clear() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}

/// Imagen servida desde [ImageDiskCache].
@immutable
class DiskCachedImage extends ImageProvider<DiskCachedImage> {
  const DiskCachedImage(this.url, this.cache);

  final String url;
  final ImageDiskCache cache;

  @override
  Future<DiskCachedImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    DiskCachedImage key,
    ImageDecoderCallback decode,
  ) => MultiFrameImageStreamCompleter(codec: _decode(decode), scale: 1);

  Future<ui.Codec> _decode(ImageDecoderCallback decode) async {
    final bytes = await cache.load(url);
    return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
  }

  @override
  bool operator ==(Object other) =>
      other is DiskCachedImage &&
      other.url == url &&
      identical(other.cache, cache);

  @override
  int get hashCode => Object.hash(url, identityHashCode(cache));

  // Sin la URL: podría llevar credenciales.
  @override
  String toString() => 'DiskCachedImage(${cache.fileNameFor(url)})';
}
