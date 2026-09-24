// Dobles de prueba compartidos. Sin datos reales.
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:evemtv/core/network/retry_interceptor.dart';
import 'package:evemtv/domain/entities/favorite.dart';
import 'package:evemtv/domain/entities/profile.dart';
import 'package:evemtv/domain/entities/source_credentials.dart';
import 'package:evemtv/domain/repositories/favorites_repository.dart';
import 'package:evemtv/features/auth/application/session.dart';
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

/// Favoritos en memoria (para pruebas de pantallas).
class InMemoryFavoritesRepository implements FavoritesRepository {
  final Map<(int, FavoriteKind), List<Favorite>> _data = {};
  final _changes = StreamController<void>.broadcast();

  @override
  Stream<List<Favorite>> watch(int profileId, FavoriteKind kind) async* {
    yield List.of(_data[(profileId, kind)] ?? const []);
    await for (final _ in _changes.stream) {
      yield List.of(_data[(profileId, kind)] ?? const []);
    }
  }

  @override
  Future<void> add(int profileId, Favorite favorite) async {
    final list = _data.putIfAbsent((profileId, favorite.kind), () => []);
    list
      ..removeWhere((f) => f.itemId == favorite.itemId)
      ..insert(0, favorite);
    _changes.add(null);
  }

  @override
  Future<void> remove(int profileId, FavoriteKind kind, String itemId) async {
    _data[(profileId, kind)]?.removeWhere((f) => f.itemId == itemId);
    _changes.add(null);
  }
}

/// Sesión fija para pruebas de pantallas (datos ficticios).
class FixedSession extends SessionController {
  FixedSession([this.credentials]);

  final SourceCredentials? credentials;

  @override
  Session? build() => Session(
    profile: Profile(
      id: 1,
      name: 'Cuenta 1',
      type: SourceType.xtream,
      createdAt: DateTime(2026),
    ),
    credentials:
        credentials ??
        XtreamCredentials(
          server: Uri.parse('http://panel.example.com:8080'),
          username: 'usuarioDemo',
          password: 'claveDemo',
        ),
  );
}
