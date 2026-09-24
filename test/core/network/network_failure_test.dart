import 'dart:io';

import 'package:dio/dio.dart';
import 'package:evemtv/core/errors/app_failure.dart';
import 'package:evemtv/core/network/network_failure.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final options = RequestOptions(path: '/');

  DioException socket(int code) => DioException.connectionError(
    requestOptions: options,
    reason: 'x',
    error: SocketException('x', osError: OSError('x', code)),
  );

  DioException status(int code) => DioException.badResponse(
    statusCode: code,
    requestOptions: options,
    response: Response<Object?>(requestOptions: options, statusCode: code),
  );

  test('red caída = sin conexión; conexión rechazada = servidor caído', () {
    expect(mapDioException(socket(101)), isA<NoConnectionFailure>());
    expect(mapDioException(socket(51)), isA<NoConnectionFailure>());
    expect(mapDioException(socket(10051)), isA<NoConnectionFailure>());
    expect(mapDioException(socket(111)), isA<ServerUnavailableFailure>());
  });

  test('códigos HTTP', () {
    expect(mapDioException(status(401)), isA<InvalidCredentialsFailure>());
    expect(mapDioException(status(403)), isA<InvalidCredentialsFailure>());
    expect(mapDioException(status(404)), isA<ResourceNotFoundFailure>());
    expect(mapDioException(status(502)), isA<ServerUnavailableFailure>());
    expect(mapDioException(status(418)), isA<InvalidResponseFailure>());
  });

  test('timeouts y certificados', () {
    expect(
      mapDioException(
        DioException.connectionTimeout(
          timeout: Duration.zero,
          requestOptions: options,
        ),
      ),
      isA<TimeoutFailure>(),
    );
    expect(
      mapDioException(
        DioException(
          requestOptions: options,
          type: DioExceptionType.unknown,
          error: const HandshakeException('x'),
        ),
      ),
      isA<CertificateFailure>(),
    );
  });

  test('el detalle solo lleva datos propios', () {
    final failure = mapDioException(status(403));
    expect(failure.detail, 'HTTP 403');
  });
}
