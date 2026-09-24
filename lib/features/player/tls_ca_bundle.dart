import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/logging/app_logger.dart';

/// Certificados raíz para la verificación TLS de mpv.
///
/// El libmpv que media_kit incluye en **Windows y macOS** no encuentra los
/// certificados del sistema: con `tls-verify=yes` rechaza todo HTTPS,
/// incluso los válidos (confirmado en CI). Por eso la app incluye el paquete
/// de certificados raíz de Mozilla (`assets/certs/cacert.pem`, publicado
/// por curl.se) y se lo pasa a mpv con `tls-ca-file`. mpv necesita una ruta
/// de archivo, así que se copia una vez a la carpeta de soporte de la app.
///
/// En Linux se usa el libmpv de la distribución, que sí usa los
/// certificados del sistema.
abstract final class TlsCaBundle {
  static const String asset = 'assets/certs/cacert.pem';

  /// `true` en las plataformas que necesitan el paquete propio.
  static bool get needed => Platform.isWindows || Platform.isMacOS;

  /// Ruta del paquete listo para mpv, o `null` si la plataforma no lo
  /// necesita. Lanza si no se pudo preparar: sin certificados, mpv no
  /// podría reproducir HTTPS de forma segura.
  static Future<String?> ensure() async {
    if (!needed) return null;
    final dir = await getApplicationSupportDirectory();
    final file = File(p.join(dir.path, 'certs', 'cacert.pem'));
    final bytes = (await rootBundle.load(asset)).buffer.asUint8List();
    if (!await _isCurrent(file, bytes)) {
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
      AppLogger.event('tls.ca_bundle', {'bytes': bytes.length});
    }
    return file.path;
  }

  static Future<bool> _isCurrent(File file, Uint8List bytes) async {
    if (!await file.exists()) return false;
    if (await file.length() != bytes.length) return false;
    return listEquals(await file.readAsBytes(), bytes);
  }
}
