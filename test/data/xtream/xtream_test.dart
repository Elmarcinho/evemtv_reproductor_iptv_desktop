// Cliente y fuente Xtream contra respuestas ficticias.
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:evemtv/core/errors/app_failure.dart';
import 'package:evemtv/core/logging/app_logger.dart';
import 'package:evemtv/data/xtream/xtream_account_parser.dart';
import 'package:evemtv/data/xtream/xtream_client.dart';
import 'package:evemtv/data/xtream/xtream_source.dart';
import 'package:evemtv/domain/entities/account_info.dart';
import 'package:evemtv/domain/entities/source_credentials.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fixtures/xtream_fixtures.dart';
import '../../helpers/fakes.dart';

final credentials = XtreamCredentials(
  server: Uri.parse('http://panel.example.com:8080'),
  username: 'usuario demo',
  password: 'cl@ve&demo',
);

final fixedNow = DateTime.utc(2026, 1, 1);

void main() {
  late List<String> logs;
  late LogSink originalSink;

  setUp(() {
    logs = [];
    originalSink = AppLogger.sink;
    AppLogger.sink = (_, message) => logs.add(message);
  });
  tearDown(() => AppLogger.sink = originalSink);

  group('XtreamAccountParser', () {
    test('respuesta de manual', () {
      final info = XtreamAccountParser.parse(jsonDecode(loginOk));
      expect(info.authenticated, isTrue);
      expect(info.status, AccountStatus.active);
      expect(info.expiresAt, DateTime.utc(2100, 1, 1));
      expect(info.createdAt, DateTime.utc(2024, 1, 1));
      expect(info.isTrial, isFalse);
      expect(info.activeConnections, 1);
      expect(info.maxConnections, 2);
      expect(info.allowedOutputFormats, ['m3u8', 'ts', 'rtmp']);
      expect(info.serverTimezone, 'America/Argentina/Buenos_Aires');
    });

    test('tipos inconsistentes no rompen el parseo', () {
      final info = XtreamAccountParser.parse(jsonDecode(loginMessyTypes));
      expect(info.authenticated, isTrue);
      expect(info.status, AccountStatus.active);
      expect(info.expiresAt, isNull);
      expect(info.createdAt, isNull);
      expect(info.isTrial, isTrue);
      expect(info.activeConnections, 0);
      expect(info.maxConnections, 1);
      expect(info.allowedOutputFormats, ['ts', 'm3u8']);
      expect(info.serverTimezone, isNull);
    });

    test('respuestas vacías = credenciales incorrectas', () {
      for (final body in [loginEmptyList, '{}']) {
        expect(
          () => XtreamAccountParser.parse(jsonDecode(body)),
          throwsA(isA<InvalidCredentialsFailure>()),
          reason: body,
        );
      }
      expect(
        () => XtreamAccountParser.parse(null),
        throwsA(isA<InvalidCredentialsFailure>()),
      );
    });

    test('JSON sin user_info o de otro tipo = respuesta no reconocida', () {
      expect(
        () => XtreamAccountParser.parse({'hola': 1}),
        throwsA(isA<InvalidResponseFailure>()),
      );
      expect(
        () => XtreamAccountParser.parse('texto'),
        throwsA(isA<InvalidResponseFailure>()),
      );
    });

    test('ensureUsable', () {
      AccountInfo parse(String s) => XtreamAccountParser.parse(jsonDecode(s));
      expect(
        () => XtreamAccountParser.ensureUsable(
          parse(loginAuthZero),
          now: fixedNow,
        ),
        throwsA(isA<InvalidCredentialsFailure>()),
      );
      for (final body in [loginExpired, loginBanned, loginActiveButPastDate]) {
        expect(
          () => XtreamAccountParser.ensureUsable(parse(body), now: fixedNow),
          throwsA(isA<AccountExpiredFailure>()),
          reason: body,
        );
      }
      XtreamAccountParser.ensureUsable(parse(loginOk), now: fixedNow);
    });
  });

  group('XtreamClient', () {
    test('arma la URL de la API con credenciales codificadas', () {
      final client = XtreamClient(Dio(), credentials);
      final uri = client.apiUri({'action': 'get_live_categories'});
      expect(uri.path, '/player_api.php');
      expect(uri.port, 8080);
      expect(uri.queryParameters, {
        'username': 'usuario demo',
        'password': 'cl@ve&demo',
        'action': 'get_live_categories',
      });
    });

    test('respeta una subruta del servidor', () {
      final client = XtreamClient(
        Dio(),
        XtreamCredentials(
          server: Uri.parse('https://panel.example.com/sub'),
          username: 'a',
          password: 'b',
        ),
      );
      expect(client.apiUri().path, '/sub/player_api.php');
    });

    test('HTML en lugar de JSON = respuesta no reconocida, sin registrar el cuerpo', () async {
      final adapter = FakeHttpAdapter((_) => textBody(htmlPage));
      final client = XtreamClient(testDio(adapter), credentials);
      await expectLater(
        client.get(null),
        throwsA(isA<InvalidResponseFailure>()),
      );
      expect(logs.join('\n'), isNot(contains('Página de ejemplo')));
    });

    test('401 = credenciales incorrectas, sin reintentos', () async {
      final adapter = FakeHttpAdapter((_) => textBody('', 401));
      final client = XtreamClient(testDio(adapter), credentials);
      await expectLater(
        client.get(null),
        throwsA(isA<InvalidCredentialsFailure>()),
      );
      expect(adapter.requests, hasLength(1));
    });

    test('503 se reintenta con espera y luego funciona', () async {
      var calls = 0;
      final adapter = FakeHttpAdapter(
        (_) => ++calls < 3 ? textBody('', 503) : jsonBody(loginOk),
      );
      final client = XtreamClient(testDio(adapter), credentials);
      final json = await client.get(null);
      expect(json, isA<Map<String, Object?>>());
      expect(calls, 3);
    });

    test(
      'servidor caído = ServerUnavailableFailure tras los reintentos',
      () async {
        final adapter = FakeHttpAdapter(
          (o) => throw DioException.connectionError(
            requestOptions: o,
            reason: 'refused',
            error: const SocketException(
              'refused',
              osError: OSError('Connection refused', 111),
            ),
          ),
        );
        final client = XtreamClient(testDio(adapter), credentials);
        await expectLater(
          client.get(null),
          throwsA(isA<ServerUnavailableFailure>()),
        );
        expect(adapter.requests, hasLength(3));
      },
    );

    test('los logs no contienen credenciales ni URL', () async {
      final adapter = FakeHttpAdapter((_) => textBody('', 500));
      final client = XtreamClient(testDio(adapter, maxRetries: 0), credentials);
      await expectLater(
        client.get('get_live_streams'),
        throwsA(isA<AppFailure>()),
      );
      final all = logs.join('\n');
      expect(all, contains('get_live_streams'));
      for (final secret in ['usuario', 'cl@ve', 'panel.example.com']) {
        expect(all, isNot(contains(secret)));
      }
    });
  });

  group('XtreamSource', () {
    XtreamSource sourceWith(String body) => XtreamSource(
      XtreamClient(
        testDio(FakeHttpAdapter((_) => jsonBody(body))),
        credentials,
      ),
      clock: () => fixedNow,
    );

    test('verify devuelve los datos de la cuenta', () async {
      final info = await sourceWith(loginOk).verify();
      expect(info.maxConnections, 2);
    });

    test('verify rechaza auth 0 y cuentas vencidas', () async {
      await expectLater(
        sourceWith(loginAuthZero).verify(),
        throwsA(isA<InvalidCredentialsFailure>()),
      );
      await expectLater(
        sourceWith(loginExpired).verify(),
        throwsA(isA<AccountExpiredFailure>()),
      );
    });

    test('verify usa un solo reintento', () async {
      final adapter = FakeHttpAdapter((_) => textBody('', 503));
      final source = XtreamSource(
        XtreamClient(testDio(adapter, maxRetries: 5), credentials),
      );
      await expectLater(
        source.verify(),
        throwsA(isA<ServerUnavailableFailure>()),
      );
      expect(adapter.requests, hasLength(2));
    });
  });
}
