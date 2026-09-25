// Mide CPU y memoria de la app real en modo perfil, contra un servidor
// Xtream ficticio local (test_driver/fake_panel.dart), en tres momentos:
//   A. inicio sin tocar nada,
//   B. navegar un catálogo grande (y B2: el inicio después),
//   C. reproducir una película 720p.
//
// La medición se hace desde afuera del proceso (/proc/<pid>), con la app
// dibujando como siempre (sin el arnés de pruebas, que dibuja sin parar).
// Solo Linux. Uso: ver integration_test/README.md.
// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';

import 'fake_panel.dart';

/// Puerto del panel ficticio (el mismo que usa perf_app.dart).
const int panelPort = 48123;

String get assetsDir => Platform.environment['PERF_ASSETS'] ?? '';
String get runLabel => Platform.environment['PERF_LABEL'] ?? 'corrida';

/// CPU del proceso (todos sus hilos), en segundos.
double cpuSeconds(int pid) {
  final stat = File('/proc/$pid/stat').readAsStringSync();
  final fields = stat.substring(stat.lastIndexOf(')') + 2).split(' ');
  return (int.parse(fields[11]) + int.parse(fields[12])) / 100;
}

/// Memoria residente del proceso, en MB.
double rssMb(int pid) {
  final status = File('/proc/$pid/status').readAsLinesSync();
  final line = status.firstWhere((l) => l.startsWith('VmRSS:'));
  return int.parse(RegExp(r'\d+').firstMatch(line)!.group(0)!) / 1024;
}

Future<void> measure(
  FlutterDriver driver,
  int pid,
  String phase,
  Duration duration, [
  Future<void> Function()? during,
]) async {
  final frames0 = int.parse(await driver.requestData('frames'));
  final cpu0 = cpuSeconds(pid);
  final watch = Stopwatch()..start();
  var peak = rssMb(pid);
  final sampler = Timer.periodic(const Duration(milliseconds: 200), (_) {
    final rss = rssMb(pid);
    if (rss > peak) peak = rss;
  });
  await Future.wait([
    during?.call() ?? Future<void>.value(),
    Future<void>.delayed(duration),
  ]);
  sampler.cancel();
  final seconds = watch.elapsedMilliseconds / 1000;
  final cpu = (cpuSeconds(pid) - cpu0) / seconds * 100;
  final frames = int.parse(await driver.requestData('frames')) - frames0;
  final line =
      'PERF|$runLabel|$phase|cpu=${cpu.toStringAsFixed(1)}%|'
      'rss=${rssMb(pid).toStringAsFixed(0)}MB|pico=${peak.toStringAsFixed(0)}MB|'
      'cuadros/s=${(frames / seconds).toStringAsFixed(1)}|'
      'duración=${seconds.toStringAsFixed(1)}s';
  print(line);
  File('$assetsDir/perf_results.txt')
      .writeAsStringSync('$line\n', mode: FileMode.append);
}

Future<void> sleep(Duration d) => Future<void>.delayed(d);

Future<void> main() async {
  if (assetsDir.isEmpty) {
    print('Falta PERF_ASSETS=<carpeta con perf_video.mp4, poster.jpg…>');
    exit(2);
  }
  final panel = FakePanel(
    File('$assetsDir/perf_video.mp4'),
    File('$assetsDir/poster.jpg').readAsBytesSync(),
    File('$assetsDir/backdrop.jpg').readAsBytesSync(),
  );
  await panel.start(panelPort);
  final driver = await FlutterDriver.connect();
  final pid = (await driver.serviceClient.getVM()).pid!;

  try {
    // Sin sincronizar con los cuadros: con animaciones en pantalla (p. ej.
    // tarjetas de muestra mientras cargan) el conductor esperaría para
    // siempre.
    await driver.runUnsynchronized(() => _scenario(driver, pid, panel));
  } finally {
    await driver.close();
    await panel.server.close(force: true);
    final data = Directory('${Directory.systemTemp.path}/evemtv_perf');
    if (data.existsSync()) data.deleteSync(recursive: true);
  }
}

Future<void> _scenario(FlutterDriver driver, int pid, FakePanel panel) async {
  const timeout = Duration(minutes: 3);
  final log = File('$assetsDir/perf_steps.txt')..writeAsStringSync('');
  void step(String s) => log.writeAsStringSync(
    '${DateTime.now().toIso8601String()} $s\n',
    mode: FileMode.append,
  );
  step('inicio');
  {
    // Términos y cuenta ficticia.
    await driver.waitFor(find.text('Acepto y continúo'), timeout: timeout);
    step('términos');
    await driver.tap(find.text('Acepto y continúo'), timeout: timeout);
    await driver.waitFor(find.text('Agregar cuenta'), timeout: timeout);
    await driver.tap(find.text('Agregar cuenta'), timeout: timeout);
    Future<void> type(String label, String value) async {
      // Se toca el campo (la etiqueta flotante no recibe toques).
      await driver.tap(
        find.ancestor(
          of: find.text(label),
          matching: find.byType('TextFormField'),
          firstMatchOnly: true,
        ),
      );
      await driver.enterText(value);
    }

    step('login');
    await type('URL del servidor', panel.base);
    await type('Usuario', 'usuarioPerf');
    await type('Contraseña', 'clavePerf');
    await driver.tap(find.text('Conectar'));

    step('conectando');
    // Inicio con el catálogo descargado y los carruseles cargados.
    await driver.waitFor(find.text('Mejor valoradas'), timeout: timeout);
    await sleep(const Duration(seconds: 10));

    await measure(
      driver,
      pid,
      'A inicio en reposo',
      const Duration(seconds: 20),
    );

    // Con la ventana minimizada, el inicio no debería gastar casi nada.
    await driver.requestData('minimize');
    await sleep(const Duration(seconds: 3));
    await measure(
      driver,
      pid,
      'A2 inicio minimizado',
      const Duration(seconds: 15),
    );
    await driver.requestData('restore');
    await sleep(const Duration(seconds: 3));

    await measure(
      driver,
      pid,
      'B catálogo grande',
      const Duration(seconds: 5),
      () async {
        step('B películas');
        await driver.tap(find.text('Películas'));
        step('B recientes');
        await driver.tap(find.text('Recién agregadas'), timeout: timeout);
        await sleep(const Duration(seconds: 4));
        await driver.tap(find.text('Todas las películas'));
        final grid = find.byType('GridView');
        await driver.waitFor(grid, timeout: timeout);
        await sleep(const Duration(seconds: 2));
        for (var i = 0; i < 8; i++) {
          await driver.scroll(
            grid,
            0,
            -2500,
            const Duration(milliseconds: 300),
          );
          await sleep(const Duration(milliseconds: 800));
        }
        step('B categorías');
        final list = find.byType('CategoryList');
        for (var c = 2; c <= 13; c++) {
          final name = find.text('Categoría ${c.toString().padLeft(2, '0')}');
          await driver.scrollUntilVisible(list, name, dyScroll: -60);
          await driver.tap(name);
          await sleep(const Duration(milliseconds: 1200));
        }
      },
    );
    step('B volver');
    await driver.tap(find.byTooltip('Volver (Esc)'));
    await sleep(const Duration(seconds: 10));
    await measure(
      driver,
      pid,
      'B2 inicio tras navegar',
      const Duration(seconds: 10),
    );

    // B3. Sesión larga: 47 categorías más. Solo las últimas 10 deberían
    // quedar en memoria.
    await measure(
      driver,
      pid,
      'B3 sesión larga (60 categorías)',
      const Duration(seconds: 5),
      () async {
        await driver.tap(find.text('Películas'));
        final list = find.byType('CategoryList');
        await driver.waitFor(list, timeout: timeout);
        for (var c = 14; c <= 60; c++) {
          final name = find.text('Categoría ${c.toString().padLeft(2, '0')}');
          await driver.scrollUntilVisible(list, name, dyScroll: -60);
          await driver.tap(name);
          await sleep(const Duration(milliseconds: 700));
        }
        await driver.tap(find.byTooltip('Volver (Esc)'));
        await sleep(const Duration(seconds: 5));
      },
    );

    await driver.tap(find.text('Películas'));
    final grid = find.byType('GridView');
    await driver.waitFor(grid, timeout: timeout);
    await sleep(const Duration(seconds: 2));
    await driver.tap(
      find.descendant(
        of: grid,
        matching: find.byType('InkWell'),
        firstMatchOnly: true,
      ),
    );
    step('C reproducir');
    await driver.tap(find.text('Reproducir'), timeout: timeout);
    await sleep(const Duration(seconds: 8));
    await measure(
      driver,
      pid,
      'C reproducción 720p',
      const Duration(seconds: 20),
    );
  }
}
