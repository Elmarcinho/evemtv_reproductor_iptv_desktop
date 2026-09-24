// Dobles de prueba compartidos. Sin datos reales.
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:evemtv/core/network/retry_interceptor.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// Adaptador HTTP simulado: responde con [handler] y guarda las peticiones.
class FakeHttpAdapter implements HttpClientAdapter {
  FakeHttpAdapter(this.handler);

  FutureOr<ResponseBody> Function(RequestOptions options) handler;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody jsonBody(String body, [int status = 200]) =>
    ResponseBody.fromString(
      body,
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );

ResponseBody textBody(String body, [int status = 200]) =>
    ResponseBody.fromString(
      body,
      status,
      headers: {
        Headers.contentTypeHeader: ['text/plain'],
      },
    );

/// Dio de pruebas: mismas opciones que la app, reintentos sin espera real.
Dio testDio(FakeHttpAdapter adapter, {int maxRetries = 2}) {
  final dio = Dio(BaseOptions(responseType: ResponseType.plain))
    ..httpClientAdapter = adapter;
  dio.interceptors.add(
    RetryInterceptor(dio, maxRetries: maxRetries, sleep: (_) async {}),
  );
  return dio;
}

/// Almacén seguro en memoria. [failWith] simula un llavero no disponible.
class FakeSecureStorage extends Fake implements FlutterSecureStorage {
  final Map<String, String> values = {};
  PlatformException? failWith;

  /// Solo falla al borrar (simula un llavero que se bloquea a mitad).
  PlatformException? failDeleteWith;

  /// Si no es `null`, las lecturas esperan a que se complete (para simular
  /// un llavero lento y solapar operaciones).
  Completer<void>? readGate;

  void _maybeFail() {
    if (failWith != null) throw failWith!;
  }

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _maybeFail();
    final value = values[key];
    await readGate?.future;
    return value;
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _maybeFail();
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _maybeFail();
    if (failDeleteWith != null) throw failDeleteWith!;
    values.remove(key);
  }
}
