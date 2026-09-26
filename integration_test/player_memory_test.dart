// Memoria tras cerrar el reproductor, con el mpv REAL de cada plataforma:
// abre y cierra 20 veces un video 720p sintético (reproductor + textura
// mostrada, como en la app) y anota la memoria residente tras cada cierre.
//
// Los números se publican como anotaciones de GitHub Actions. Solo falla
// ante una fuga grosera; la tendencia se sigue en las anotaciones.
// Video: integration_test/assets/memory_probe.mp4 (patrón de prueba de
// ffmpeg, ver integration_test/README.md).
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:evemtv/features/player/media_engine.dart';
import 'package:evemtv/features/player/playback_engine.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// En CI se pasa la URL del commit exacto con --dart-define.
const String videoUrl = String.fromEnvironment(
  'MEMORY_VIDEO_URL',
  defaultValue:
      'https://raw.githubusercontent.com/Elmarcinho/'
      'evemtv_reproductor_iptv_desktop/main/integration_test/assets/memory_probe.mp4',
);

const int cycles = 20;

/// Con textura (VideoController + Video, como en la app) o solo el Player.
/// En el runner de macOS de GitHub la app se detiene al abrir un video con
/// textura (se corta dentro de `open`; probablemente por la VM sin GPU, no
/// se pudo confirmar sin los registros). Allí se mide solo el Player, que es
/// donde estaba la fuga en Linux. La textura en macOS se prueba a mano.
const bool withTexture = bool.fromEnvironment(
  'MEMORY_TEXTURE',
  defaultValue: true,
);

/// Crecimiento promedio por ciclo (últimos 10) a partir del cual se
/// considera fuga grosera. Con el asignador de glibc en Linux se midieron
/// ~9 MB por ciclo con 1080p; con mimalloc, menos de 1,5 MB.
const double maxGrowthPerCycleMb = 6;

double rssMb() => ProcessInfo.currentRss / (1024 * 1024);

Future<void> waitReal(WidgetTester tester, Duration d) async {
  final end = DateTime.now().add(d);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('la memoria no crece con cada reproductor que se cierra', (
    tester,
  ) async {
    final os = Platform.operatingSystem;
    // Etapas como anotaciones: si el proceso se cae (p. ej. en macOS sin
    // GPU), se sabe hasta dónde llegó sin tener que leer los registros.
    void stage(String text) =>
        print('::notice title=Memoria del reproductor $os (etapa)::$text');
    MediaEngine().ensureReady();
    stage('motor listo');
    final after = <double>[];
    final hwdec = <String>{};
    for (var i = 0; i < cycles; i++) {
      final engine = await MediaKitEngine.create();
      if (withTexture) {
        final controller = createVideoController(engine.player);
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Video(controller: controller),
          ),
        );
      }
      if (i == 0) {
        stage(
          withTexture
              ? 'reproductor y textura creados'
              : 'reproductor creado (sin textura)',
        );
      }
      await engine.open(Uri.parse(videoUrl));
      if (i == 0) stage('video abierto');
      await waitReal(tester, const Duration(seconds: 4));
      if (i == 0) stage('4 s de reproducción');
      hwdec.add(await engine.hwdecCurrent());
      if (i == 0) stage('reproduciendo: hwdec=${hwdec.first}');
      await tester.pumpWidget(const SizedBox());
      await engine.dispose();
      // media_kit destruye el contexto de mpv 5 s después de dispose.
      await waitReal(tester, const Duration(seconds: 6));
      after.add(rssMb());
      if (i == 0) stage('primer cierre: ${after.first.toStringAsFixed(0)} MB');
    }

    final lastTen = after.sublist(cycles - 10);
    final perCycle = (lastTen.last - lastTen.first) / 9;
    final summary =
        '${withTexture ? 'con textura' : 'solo Player'} | '
        'hwdec=${hwdec.join('/')} | tras cada cierre: '
        '${after.map((m) => m.toStringAsFixed(0)).join(', ')} MB | '
        'últimos 10: ${perCycle.toStringAsFixed(1)} MB/ciclo';
    final ok = perCycle <= maxGrowthPerCycleMb;
    print(
      '::${ok ? 'notice' : 'error'} title=Memoria del reproductor $os::$summary',
    );
    expect(ok, isTrue, reason: summary);
  });
}
