// Seguridad de la reproducción con el mpv REAL de cada plataforma:
// (a) un servidor HTTPS con certificado autofirmado es rechazado ANTES de
//     enviar la petición (la ruta con credenciales nunca llega);
// (b) un servidor HTTPS con certificado válido sigue reproduciendo;
// (c) abrir una URL no deja archivos temporales con la URL.
// Datos ficticios. Ver integration_test/README.md.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:evemtv/features/player/media_engine.dart';
import 'package:evemtv/features/player/playback_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'tls_fixture.dart';

/// HTTPS con certificado válido (el mismo video, publicado en el repo).
/// En CI se pasa la URL del commit exacto con --dart-define.
const String validHttpsUrl = String.fromEnvironment(
  'TLS_VALID_URL',
  defaultValue:
      'https://raw.githubusercontent.com/Elmarcinho/'
      'evemtv_reproductor_iptv_desktop/main/integration_test/assets/tls_probe.mkv',
);

/// Ruta con "credenciales" ficticias, para comprobar que nunca se envía.
const String secretPath = '/movie/usuarioFicticio/claveFicticia/1.mkv';

/// Abierto = mpv informó una duración (el archivo se leyó).
Future<bool> opensWithin(MediaKitEngine engine, Uri url, Duration limit) async {
  final opened = engine.duration.firstWhere((d) => d > Duration.zero);
  await engine.open(url);
  try {
    await opened.timeout(limit);
    return true;
  } on TimeoutException {
    return false;
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late HttpServer server;
  final requests = <String>[];

  setUpAll(() async {
    MediaEngine().ensureReady();
    final context = SecurityContext()
      ..useCertificateChainBytes(utf8.encode(selfSignedCertPem))
      ..usePrivateKeyBytes(utf8.encode(selfSignedKeyPem));
    server = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      context,
    );
    final media = base64.decode(tlsProbeMediaBase64);
    server.listen(
      (request) {
        requests.add(request.uri.path);
        request.response
          ..headers.contentType = ContentType('video', 'x-matroska')
          ..add(media);
        unawaited(request.response.close());
      },
      // Los handshakes rechazados por mpv aparecen aquí: se ignoran.
      onError: (_) {},
    );
  });

  tearDownAll(() => server.close(force: true));

  testWidgets('mpv tiene la verificación TLS activada', (tester) async {
    await tester.runAsync(() async {
      final engine = await MediaKitEngine.create();
      final platform = engine.player.platform! as dynamic;
      expect(await platform.getProperty('tls-verify'), 'yes');
      await engine.dispose();
    });
  });

  testWidgets('(a) certificado autofirmado: rechazado sin enviar la ruta', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final engine = await MediaKitEngine.create();
      final url = Uri.parse('https://127.0.0.1:${server.port}$secretPath');
      final opened = await opensWithin(
        engine,
        url,
        const Duration(seconds: 10),
      );
      await engine.dispose();
      expect(opened, isFalse, reason: 'mpv aceptó un certificado no confiable');
      expect(
        requests,
        isEmpty,
        reason: 'la ruta con credenciales llegó al servidor',
      );
    });
  });

  testWidgets('(b) certificado válido: reproduce', (tester) async {
    await tester.runAsync(() async {
      final engine = await MediaKitEngine.create();
      final opened = await opensWithin(
        engine,
        Uri.parse(validHttpsUrl),
        const Duration(seconds: 30),
      );
      await engine.dispose();
      expect(
        opened,
        isTrue,
        reason:
            'mpv no pudo abrir un HTTPS válido: ¿faltan los certificados '
            'raíz del sistema en esta plataforma?',
      );
    });
  });

  testWidgets('(c) abrir una URL no deja archivos temporales con ella', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final marker = 'marcaFicticia${DateTime.now().microsecondsSinceEpoch}';
      final engine = await MediaKitEngine.create();
      await engine.open(
        Uri.parse('http://127.0.0.1:9/movie/$marker/claveFicticia/1.mkv'),
      );
      await Future<void>.delayed(const Duration(seconds: 1));
      final leaked = <String>[];
      await for (final entity
          in Directory.systemTemp.list(recursive: true).handleError((_) {})) {
        if (entity is! File) continue;
        try {
          if (await entity.length() > 1024 * 1024) continue;
          if ((await entity.readAsString()).contains(marker)) {
            leaked.add(entity.path);
          }
        } on Object {
          // Archivos ilegibles o binarios: se ignoran.
        }
      }
      await engine.dispose();
      expect(leaked, isEmpty);
    });
  });
}
