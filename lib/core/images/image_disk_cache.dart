import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:path/path.dart' as p;

import '../logging/app_logger.dart';
import '../network/retry_interceptor.dart';

/// Formatos de imagen que se guardan en disco (reconocidos por sus
/// primeros bytes, no por la URL ni el Content-Type del servidor).
enum CachedImageFormat { png, jpeg, webp }

/// Caché de pósters y logos en disco, por perfil.
///
/// **No guarda URLs.** Cada archivo se llama como el HMAC-SHA256 de la URL
/// con una clave aleatoria del perfil que vive en el almacén seguro: sin esa
/// clave no se puede comprobar a qué URL corresponde un archivo (ni probar
/// contraseñas candidatas). En disco quedan solo los bytes de la imagen.
///
/// - Solo se guardan PNG, JPEG y WebP que además se decodifican bien: una
///   página HTML, un error del panel o cualquier otra cosa nunca llega al
///   disco (se muestra, si se puede, pero no se guarda).
/// - Tamaño acotado ([maxBytes]) en **cada** escritura: si la imagen nueva
///   no entra, antes se borran las usadas hace más tiempo.
/// - [close] rechaza escrituras nuevas, cancela las descargas y espera a
///   que termine lo que estaba en curso: después nada vuelve a crear la
///   carpeta (se llama antes de borrarla al cerrar sesión).
class ImageDiskCache {
  ImageDiskCache({
    required this.directory,
    required List<int> key,
    required this._dio,
    this.maxBytes = 300 * 1024 * 1024,
    this.maxImageBytes = 5 * 1024 * 1024,
    Future<bool> Function(Uint8List bytes)? verifyDecodes,
  }) : _hmac = Hmac(sha256, key),
       _verifyDecodes = verifyDecodes ?? decodes;

  final Directory directory;
  final Hmac _hmac;
  final Dio _dio;
  final int maxBytes;
  final int maxImageBytes;
  final Future<bool> Function(Uint8List bytes) _verifyDecodes;

  final Map<String, Future<Uint8List>> _inFlight = {};
  CancelToken _cancel = CancelToken();
  bool _closed = false;

  /// Bytes ocupados en disco; `null` hasta el primer recuento.
  int? _bytes;

  /// Cola de escrituras y limpiezas: van de a una para que el recuento de
  /// bytes sea exacto.
  Future<void> _queue = Future.value();

  bool get isClosed => _closed;

  /// Nombre del archivo para [url] (sin revelar la URL).
  String fileNameFor(String url) => _hmac.convert(utf8.encode(url)).toString();

  File _fileFor(String url) => File(p.join(directory.path, fileNameFor(url)));

  /// Formato de [bytes] según su cabecera, o `null` si no es uno admitido.
  static CachedImageFormat? formatOf(List<int> bytes) {
    bool startsWith(List<int> prefix, [int offset = 0]) {
      if (bytes.length < offset + prefix.length) return false;
      for (var i = 0; i < prefix.length; i++) {
        if (bytes[offset + i] != prefix[i]) return false;
      }
      return true;
    }

    if (startsWith(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) {
      return CachedImageFormat.png;
    }
    if (startsWith(const [0xFF, 0xD8, 0xFF])) return CachedImageFormat.jpeg;
    // RIFF <tamaño de 4 bytes> WEBP
    if (startsWith(const [0x52, 0x49, 0x46, 0x46]) &&
        startsWith(const [0x57, 0x45, 0x42, 0x50], 8)) {
      return CachedImageFormat.webp;
    }
    return null;
  }

  /// `true` si el motor de Flutter decodifica el primer cuadro de [bytes].
  static Future<bool> decodes(Uint8List bytes) async {
    ui.Codec? codec;
    try {
      codec = await ui.instantiateImageCodec(bytes, targetWidth: 64);
      final frame = await codec.getNextFrame();
      frame.image.dispose();
      return true;
    } on Object {
      return false;
    } finally {
      codec?.dispose();
    }
  }

  /// Bytes de la imagen: del disco si está, si no de la red (y se guarda si
  /// es una imagen válida). Con la caché cerrada lanza [StateError].
  Future<Uint8List> load(String url) {
    if (_closed) return Future.error(StateError('caché de imágenes cerrada'));
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
        if (formatOf(bytes) != null) {
          // Marca de uso para el orden de borrado (LRU).
          unawaited(
            file.setLastModified(DateTime.now()).catchError((Object _) {}),
          );
          return bytes;
        }
        // Guardado por una versión sin validación: se descarta.
        await _enqueue(() async {
          final size = await _sizeOf(file);
          await file.delete();
          if (_bytes != null) _bytes = _bytes! - size;
        });
      }
    } on FileSystemException {
      // Archivo dañado o ilegible: se vuelve a descargar.
    }
    final bytes = await _download(url);
    if (formatOf(bytes) == null) {
      // Se muestra si Flutter puede (p. ej. GIF), pero no se guarda.
      AppLogger.event('image_cache.skip', {'reason': 'format'});
      return bytes;
    }
    if (!await _verifyDecodes(bytes)) {
      AppLogger.event('image_cache.skip', {'reason': 'decode'});
      return bytes;
    }
    await _enqueue(() => _write(file, bytes));
    return bytes;
  }

  Future<Uint8List> _download(String url) async {
    final uri = Uri.parse(url);
    if (!uri.isScheme('http') && !uri.isScheme('https')) {
      throw const FormatException('esquema no soportado');
    }
    final response = await _dio.getUri<List<int>>(
      uri,
      cancelToken: _cancel,
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

  /// Ejecuta [task] después de las escrituras y limpiezas anteriores.
  Future<void> _enqueue(Future<void> Function() task) {
    final next = _queue.then((_) => task());
    // La cola sigue aunque una tarea falle.
    _queue = next.catchError((Object _) {});
    return next;
  }

  Future<void> _write(File file, Uint8List bytes) async {
    if (_closed || bytes.length > maxBytes) return;
    try {
      var total = _bytes ??= await _scanSize();
      final previous = await _sizeOf(file);
      total -= previous;
      // Si no entra, primero se hace lugar: el tope se cumple siempre.
      if (total + bytes.length > maxBytes) {
        total = await _evict(
          target: min((maxBytes * 0.8).round(), maxBytes - bytes.length),
          except: file.path,
        );
        total -= await _sizeOf(file);
      }
      if (_closed) return;
      await directory.create(recursive: true);
      // Escritura atómica: nunca queda un archivo a medias.
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsBytes(bytes, flush: true);
      if (_closed) {
        await tmp.delete().catchError((Object _) => tmp);
        return;
      }
      await tmp.rename(file.path);
      _bytes = total + bytes.length;
    } on FileSystemException catch (e) {
      // Recuento incierto: se rehace en la próxima escritura.
      _bytes = null;
      AppLogger.w('No se pudo guardar una imagen en caché', e);
    }
  }

  static Future<int> _sizeOf(File file) async {
    final stat = await file.stat();
    return stat.type == FileSystemEntityType.file ? stat.size : 0;
  }

  Future<List<({File file, int size, DateTime used})>> _files() async {
    final files = <({File file, int size, DateTime used})>[];
    if (!await directory.exists()) return files;
    await for (final e in directory.list(followLinks: false)) {
      if (e is! File) continue;
      final stat = await e.stat();
      if (stat.type != FileSystemEntityType.file) continue;
      files.add((file: e, size: stat.size, used: stat.modified));
    }
    return files;
  }

  Future<int> _scanSize() async =>
      (await _files()).fold<int>(0, (sum, f) => sum + f.size);

  /// Borra las imágenes usadas hace más tiempo (salvo [except]) hasta
  /// quedar en [target] bytes o menos. Devuelve el total resultante.
  Future<int> _evict({required int target, String? except}) async {
    final files = await _files();
    var total = files.fold<int>(0, (sum, f) => sum + f.size);
    if (total <= target) return total;
    files.sort((a, b) => a.used.compareTo(b.used));
    var removed = 0;
    for (final f in files) {
      if (total <= target) break;
      if (f.file.path == except) continue;
      try {
        await f.file.delete();
        total -= f.size;
        removed++;
      } on FileSystemException {
        // Se sigue con el resto.
      }
    }
    AppLogger.event('image_cache.prune', {'removed': removed});
    return total;
  }

  /// Si la carpeta supera [maxBytes], la deja en el 80 % (al abrir la
  /// caché, por si quedó grande de una versión anterior).
  Future<void> prune() => _enqueue(() async {
    try {
      final total = await _scanSize();
      _bytes = total > maxBytes
          ? await _evict(target: (maxBytes * 0.8).round())
          : total;
    } on FileSystemException catch (e) {
      _bytes = null;
      AppLogger.w('No se pudo limpiar la caché de imágenes', e);
    }
  });

  /// Cierra la caché: rechaza cargas y escrituras nuevas, cancela las
  /// descargas en curso y espera a que terminen las operaciones pendientes.
  /// Al volver, nada de esta caché toca el disco.
  Future<void> close() async {
    if (!_closed) {
      _closed = true;
      _cancel.cancel('caché cerrada');
    }
    await Future.wait([
      for (final f in _inFlight.values.toList())
        f.then((_) {}, onError: (_) {}),
      _queue,
    ]);
  }

  /// Vuelve a abrir una caché cerrada (el cierre de sesión falló y la
  /// sesión sigue abierta).
  void reopen() {
    if (!_closed) return;
    _closed = false;
    _cancel = CancelToken();
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
