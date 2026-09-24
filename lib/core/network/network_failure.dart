import 'dart:io';

import 'package:dio/dio.dart';

import '../errors/app_failure.dart';

/// Códigos de "red inalcanzable / red caída" en Linux, macOS y Windows.
const _networkDownCodes = {
  100, 101, // Linux: ENETDOWN, ENETUNREACH
  50, 51, // macOS: ENETDOWN, ENETUNREACH
  10050, 10051, // Windows: WSAENETDOWN, WSAENETUNREACH
};

/// Convierte un error de Dio en un [AppFailure] con mensaje en español.
///
/// El `detail` se arma solo con datos propios (tipo y código HTTP): nunca con
/// `e.message`, la URL ni el cuerpo de la respuesta.
AppFailure mapDioException(DioException e) {
  final status = e.response?.statusCode;
  switch (e.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
    case DioExceptionType.transformTimeout:
      return TimeoutFailure(detail: e.type.name, cause: e);
    case DioExceptionType.badCertificate:
      return CertificateFailure(detail: e.type.name, cause: e);
    case DioExceptionType.badResponse:
      final detail = 'HTTP $status';
      if (status == 401 || status == 403) {
        return InvalidCredentialsFailure(detail: detail, cause: e);
      }
      if (status == 404) {
        return ResourceNotFoundFailure(detail: detail, cause: e);
      }
      if (status != null && status >= 500) {
        return ServerUnavailableFailure(detail: detail, cause: e);
      }
      return InvalidResponseFailure(detail: detail, cause: e);
    case DioExceptionType.connectionError:
    case DioExceptionType.unknown:
      return _mapLowLevel(e);
    case DioExceptionType.cancel:
      return UnknownFailure(detail: e.type.name, cause: e);
  }
}

AppFailure _mapLowLevel(DioException e) {
  final error = e.error;
  if (error is HandshakeException || error is TlsException) {
    return CertificateFailure(detail: 'tls', cause: e);
  }
  if (error is SocketException) {
    final code = error.osError?.errorCode;
    if (code != null && _networkDownCodes.contains(code)) {
      return NoConnectionFailure(detail: 'socket $code', cause: e);
    }
    return ServerUnavailableFailure(detail: 'socket $code', cause: e);
  }
  if (e.type == DioExceptionType.connectionError) {
    return ServerUnavailableFailure(detail: e.type.name, cause: e);
  }
  return UnknownFailure(
    detail: '${e.type.name} ${error.runtimeType}',
    cause: e,
  );
}
