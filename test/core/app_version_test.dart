// La versión de la app vive en dos lugares: pubspec.yaml (instaladores,
// ejecutable de Windows, Info.plist) y AppConfig.version (User-Agent y
// aviso de actualización). Deben coincidir.
import 'dart:io';

import 'package:evemtv/core/config/app_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AppConfig.version coincide con pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(
      r'^version:\s*(\d+\.\d+\.\d+)\+\d+\s*$',
      multiLine: true,
    ).firstMatch(pubspec);
    expect(match, isNotNull, reason: 'version: x.y.z+n en pubspec.yaml');
    expect(AppConfig.version, match!.group(1));
  });
}
