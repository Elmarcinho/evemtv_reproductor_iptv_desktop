// Datos ficticios.
import 'package:evemtv/core/errors/app_failure.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('toString nunca incluye el texto de la causa', () {
    final failure = ServerUnavailableFailure(
      cause: Exception('http://panel.example.com/live/usuarioX/claveY/1.ts'),
    );
    expect(failure.toString(), isNot(contains('panel.example.com')));
    expect(failure.toString(), contains('causa: _Exception'));
  });

  test('los mensajes para el usuario son textos fijos', () {
    expect(
      InvalidUrlFailure(InvalidUrlReason.containsSpaces).message,
      'La URL no puede contener espacios.',
    );
    expect(
      StorageFailure(StorageFailureKind.keyringUnavailable).message,
      contains('llavero'),
    );
  });
}
