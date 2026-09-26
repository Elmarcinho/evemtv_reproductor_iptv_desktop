// Prueba del Keychain con el .app de RELEASE firmado ad hoc (la de
// integration_test/ usa la compilación de depuración, con otros
// entitlements). Se compila como la app, con otro punto de entrada:
//
//   flutter build macos --release -t test_driver/keychain_release_check.dart
//   codesign --force --deep --sign - build/macos/Build/Products/Release/EvemTv.app
//   build/macos/Build/Products/Release/EvemTv.app/Contents/MacOS/EvemTv
//
// Usa el mismo almacén que la app (secureStorageProvider) con un valor
// ficticio, lo lee, lo borra y termina con código 0 si todo funcionó.
import 'dart:io';

import 'package:evemtv/data/providers.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final storage = ProviderContainer().read(secureStorageProvider);
  const key = 'evemtv.release_check';
  final value = 'valor-ficticio-${DateTime.now().microsecondsSinceEpoch}';
  var ok = false;
  try {
    await storage.write(key: key, value: value);
    final read = await storage.read(key: key);
    await storage.delete(key: key);
    ok = read == value && await storage.read(key: key) == null;
  } on Object catch (e) {
    // Solo el tipo: el mensaje del sistema podría traer detalles del equipo.
    stdout.writeln('Error del almacén seguro: ${e.runtimeType}');
  }
  // stdout directo (print en release puede ir al registro del sistema).
  stdout.writeln(ok ? 'KEYCHAIN_RELEASE_OK' : 'KEYCHAIN_RELEASE_FALLO');
  await stdout.flush();
  exit(ok ? 0 : 1);
}
