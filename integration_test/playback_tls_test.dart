// Seguridad de la reproducción con el mpv REAL de cada plataforma:
// (a) un servidor HTTPS con certificado autofirmado es rechazado ANTES de
//     enviar la petición (la ruta con credenciales nunca llega);
// (b) un servidor HTTPS con certificado válido sigue reproduciendo;
// (c) abrir una URL no deja archivos temporales con la URL.
// Datos ficticios. Ver integration_test/README.md.
//
// Los resultados se imprimen también como anotaciones de GitHub Actions
// (`::notice::` / `::error::`) para poder diagnosticar sin los logs.
// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:evemtv/features/player/media_engine.dart';
import 'package:evemtv/features/player/playback_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';

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

String get _os => Platform.operatingSystem;

void report(String test, bool ok, String detail) {
  final level = ok ? 'notice' : 'error';
  // Una sola línea: GitHub la convierte en anotación.
  print('::$level title=TLS $_os $test::${detail.replaceAll('\n', ' | ')}');
}

/// Resultado de intentar abrir: si llegó a abrir (mpv informó duración) y
/// los errores que emitió mpv (sin URLs: solo para diagnóstico en CI con
/// datos ficticios).
Future<({bool opened, List<String> errors})> tryOpen(
  MediaKitEngine engine,
  Uri url,
  Duration limit,
) async {
  final errors = <String>[];
  final sub = engine.error.listen(errors.add);
  final opened = engine.duration.firstWhere((d) => d > Duration.zero);
  await engine.open(url);
  var ok = true;
  try {
    await opened.timeout(limit);
  } on TimeoutException {
    ok = false;
  }
  await sub.cancel();
  return (opened: ok, errors: errors);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  HttpServer? server;
  final requests = <String>[];
  Object? setupError;

  setUpAll(() async {
    try {
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
      server!.listen(
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
    } on Object catch (e, s) {
      setupError = e;
      report('preparación', false, '$e ${s.toString().split('\n').first}');
      rethrow;
    }
  });

  tearDownAll(() => server?.close(force: true));

  testWidgets('mpv tiene la verificación TLS activada', (tester) async {
    await tester.runAsync(() async {
      final engine = await MediaKitEngine.create();
      final platform = engine.player.platform! as NativePlayer;
      final verify = await platform.getProperty('tls-verify');
      final caFile = await platform.getProperty('tls-ca-file');
      report(
        'tls-verify',
        verify == 'yes',
        'tls-verify=$verify tls-ca-file=$caFile',
      );
      await engine.dispose();
      expect(verify, 'yes');
    });
  });

  testWidgets('(a) certificado autofirmado: rechazado sin enviar la ruta', (
    tester,
  ) async {
    expect(setupError, isNull);
    await tester.runAsync(() async {
      final engine = await MediaKitEngine.create();
      final url = Uri.parse('https://127.0.0.1:${server!.port}$secretPath');
      final r = await tryOpen(engine, url, const Duration(seconds: 10));
      await engine.dispose();
      final ok = !r.opened && requests.isEmpty;
      report(
        '(a) autofirmado',
        ok,
        'abrió=${r.opened} peticiones=${requests.length} errores=${r.errors.length}',
      );
      expect(
        r.opened,
        isFalse,
        reason: 'mpv aceptó un certificado no confiable',
      );
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
      final r = await tryOpen(
        engine,
        Uri.parse(validHttpsUrl),
        const Duration(seconds: 30),
      );
      await engine.dispose();
      // La URL de prueba es pública y sin credenciales: el error de mpv se
      // puede mostrar tal cual para diagnosticar (p. ej. certificados).
      report('(b) válido', r.opened, 'abrió=${r.opened} errores=${r.errors}');
      expect(
        r.opened,
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
      // Servidor local que responde 404 al instante: sin esperas de red
      // (un puerto cerrado puede quedar colgado según la plataforma).
      final plain = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      plain.listen((r) {
        r.response.statusCode = HttpStatus.notFound;
        unawaited(r.response.close());
      });
      final engine = await MediaKitEngine.create();
      await engine.open(
        Uri.parse(
          'http://127.0.0.1:${plain.port}/movie/$marker/claveFicticia/1.mkv',
        ),
      );
      await Future<void>.delayed(const Duration(seconds: 1));
      // media_kit escribía su lista directamente en Directory.systemTemp
      // (sin subcarpetas): basta revisar ese nivel, sin seguir enlaces.
      final leaked = <String>[];
      var scanned = 0;
      await for (final entity
          in Directory.systemTemp
              .list(followLinks: false)
              .handleError((Object _) {})) {
        if (entity is! File) continue;
        try {
          // Solo archivos regulares: Dart lista como File también tuberías
          // (FIFO) y sockets, y leerlos bloquea para siempre (pasaba en el
          // runner de Linux).
          final stat = await entity.stat();
          if (stat.type != FileSystemEntityType.file) continue;
          if (stat.size > 1024 * 1024) continue;
          scanned++;
          final text = await entity.readAsString().timeout(
            const Duration(seconds: 2),
          );
          if (text.contains(marker)) leaked.add(entity.path);
        } on Object {
          // Archivos ilegibles, binarios o que no responden: se ignoran.
        }
      }
      await engine.dispose();
      await plain.close(force: true);
      report(
        '(c) temporales',
        leaked.isEmpty,
        'revisados=$scanned con la URL=${leaked.length}',
      );
      expect(leaked, isEmpty);
    });
  });
}
