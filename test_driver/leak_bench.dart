// Banco de prueba de memoria del reproductor (solo Linux, modo perfil).
// Abre y cierra el reproductor muchas veces en variantes aisladas para
// ubicar una fuga: solo el Player, Player + textura mostrada, y lo mismo
// sin decodificación por hardware. Anota la memoria residente tras cada cierre.
//
// flutter run --profile -d linux -t test_driver/leak_bench.dart \
//   --dart-define=LEAK_VIDEO=/ruta/video.mp4 --dart-define=LEAK_OUT=/ruta/salida.txt
//
// Video sintético (patrón de prueba de ffmpeg, ver integration_test/README.md).
// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:evemtv/features/player/media_engine.dart';
import 'package:evemtv/features/player/playback_engine.dart';
import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';

const String videoPath = String.fromEnvironment('LEAK_VIDEO');
const String outPath = String.fromEnvironment('LEAK_OUT');
const int cycles = int.fromEnvironment('LEAK_CYCLES', defaultValue: 15);

/// Variantes: nombre → (crea VideoController, lo muestra, hwdec).
const variants = [
  (name: 'solo Player', controller: false, show: false, hwdec: 'auto-safe'),
  // Un VideoController sin mostrar no termina de inicializarse y el
  // dispose del Player lo espera: esa variante no se puede aislar.
  (
    name: 'Player + textura mostrada (hardware)',
    controller: true,
    show: true,
    hwdec: 'auto-safe',
  ),
  (
    name: 'Player + textura mostrada (software)',
    controller: true,
    show: true,
    hwdec: 'no',
  ),
];

double rssMb() => ProcessInfo.currentRss / (1024 * 1024);

/// `malloc_trim(0)` de glibc: devuelve al sistema la memoria libre que el
/// asignador retiene. Si la memoria baja mucho con esto, no era una fuga.
final int Function(int) mallocTrim = ffi.DynamicLibrary.process()
    .lookupFunction<ffi.Int32 Function(ffi.Size), int Function(int)>(
      'malloc_trim',
    );

void log(String line) {
  print(line);
  File(outPath).writeAsStringSync('$line\n', mode: FileMode.append);
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaEngine().ensureReady();
  runApp(const MaterialApp(home: _Bench()));
}

class _Bench extends StatefulWidget {
  const _Bench();

  @override
  State<_Bench> createState() => _BenchState();
}

class _BenchState extends State<_Bench> {
  VideoController? _shown;

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  Future<void> _run() async {
    await Future<void>.delayed(const Duration(seconds: 2));
    for (final v in variants) {
      mallocTrim(0);
      final start = rssMb();
      final after = <String>[];
      for (var i = 0; i < cycles; i++) {
        final engine = await MediaKitEngine.create();
        VideoController? controller;
        if (v.controller) {
          controller = VideoController(
            engine.player,
            configuration: VideoControllerConfiguration(hwdec: v.hwdec),
          );
        }
        if (v.show) setState(() => _shown = controller);
        await engine.open(Uri.file(videoPath));
        await Future<void>.delayed(const Duration(seconds: 3));
        if (v.show) {
          setState(() => _shown = null);
          await Future<void>.delayed(const Duration(milliseconds: 300));
        }
        await engine.dispose();
        // media_kit destruye el contexto de mpv 5 s después de dispose.
        await Future<void>.delayed(const Duration(seconds: 6));
        after.add(rssMb().toStringAsFixed(0));
      }
      final end = rssMb();
      mallocTrim(0);
      final trimmed = rssMb();
      log(
        'LEAK|${v.name}|inicio=${start.toStringAsFixed(0)}MB|'
        'tras cada cierre=${after.join(',')}|'
        'crecimiento=${(end - start).toStringAsFixed(0)}MB '
        '(${((end - start) / cycles).toStringAsFixed(1)}MB/ciclo)|'
        'tras malloc_trim=${trimmed.toStringAsFixed(0)}MB',
      );
    }
    log('LEAK|fin');
    exit(0);
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Colors.black,
    child: _shown == null
        ? const SizedBox.expand()
        : Video(controller: _shown!),
  );
}
