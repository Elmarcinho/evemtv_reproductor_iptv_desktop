// Conteo de uso diario. Respuestas simuladas; datos ficticios (dominios
// reservados). Nunca sale a la red real.
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:evemtv/core/config/app_config.dart';
import 'package:evemtv/core/logging/app_logger.dart';
import 'package:evemtv/data/providers.dart';
import 'package:evemtv/domain/entities/profile.dart';
import 'package:evemtv/domain/entities/source_credentials.dart';
import 'package:evemtv/domain/repositories/settings_repository.dart';
import 'package:evemtv/features/auth/application/session.dart';
import 'package:evemtv/features/usage/usage_ping.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fakes.dart';

class _MemorySettings implements SettingsRepository {
  final values = <String, String>{};

  @override
  Future<String?> get(String key) async => values[key];

  @override
  Future<void> set(String key, String value) async => values[key] = value;
}

final _endpoint = Uri.parse('http://127.0.0.1:18080/api/evemtv/ping');

final _xtream = XtreamCredentials(
  server: Uri.parse('http://Panel.Example.com:8080/'),
  username: 'Demo_Ana',
  password: 'claveSecreta123',
);

String _sha(String s) => sha256.convert(utf8.encode(s)).toString();

void main() {
  late LogSink originalSink;
  late List<String> logs;
  setUp(() {
    originalSink = AppLogger.sink;
    logs = [];
    AppLogger.sink = (_, m) => logs.add(m);
  });
  tearDown(() => AppLogger.sink = originalSink);

  late _MemorySettings settings;
  late FakeHttpAdapter http;
  var now = DateTime.utc(2026, 9, 26, 12);

  UsagePingService service({Uri? endpoint, bool enabled = true}) =>
      UsagePingService(
        dio: testDio(http),
        settings: settings,
        endpoint: enabled ? (endpoint ?? _endpoint) : null,
        os: 'linux',
        clock: () => now,
      );

  ResponseBody status(int code) => ResponseBody.fromString('', code);

  setUp(() {
    settings = _MemorySettings();
    now = DateTime.utc(2026, 9, 26, 12);
    http = FakeHttpAdapter((_) => status(204));
  });

  group('huella de la cuenta', () {
    test('SHA-256 de "usuario_en_minúsculas|host", sin esquema ni puerto', () {
      expect(accountHash(_xtream), _sha('demo_ana|panel.example.com'));
      expect(accountHash(_xtream), matches(RegExp(r'^[0-9a-f]{64}$')));
    });

    test('lista M3U: con usuario en la URL se usa; sin usuario, nada', () {
      expect(
        accountHash(
          M3uCredentials(
            playlist: Uri.parse(
              'https://lista.example.com:8443/get.php?username=Luis&password=x',
            ),
          ),
        ),
        _sha('luis|lista.example.com'),
      );
      expect(
        accountHash(
          M3uCredentials(
            playlist: Uri.parse('https://lista.example.com/a.m3u'),
          ),
        ),
        isNull,
      );
    });
  });

  test('install_id: UUID v4, uno por instalación y persistente', () async {
    final s = service();
    final id = await s.installId();
    expect(
      id,
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-'
          r'[0-9a-f]{12}$',
        ),
      ),
    );
    expect(await service().installId(), id);
  });

  test(
    'el cuerpo tiene solo los tres campos y nunca usuario ni contraseña',
    () async {
      final s = service();
      expect(await s.pingIfDue(_xtream), isTrue);
      final request = http.requests.single;
      expect(request.method, 'POST');
      expect(request.uri, _endpoint);
      final sent = request.data as Map<String, String>;
      expect(sent.keys.toSet(), {'install_id', 'os', 'account_hash'});
      expect(sent['os'], 'linux');
      expect(sent['account_hash'], _sha('demo_ana|panel.example.com'));
      final raw = jsonEncode(sent).toLowerCase();
      for (final secret in [
        'demo_ana',
        'clavesecreta123',
        'panel.example.com',
      ]) {
        expect(raw, isNot(contains(secret)));
      }
      // Sin cuenta abierta: el campo se omite.
      now = now.add(const Duration(days: 1));
      await s.pingIfDue(null);
      expect((http.requests.last.data as Map<String, String>).keys.toSet(), {
        'install_id',
        'os',
      });
    },
  );

  test('204: se envía una sola vez por día', () async {
    final s = service();
    expect(await s.pingIfDue(_xtream), isTrue);
    expect(await s.pingIfDue(_xtream), isFalse);
    expect(await service().pingIfDue(_xtream), isFalse, reason: 'reapertura');
    expect(http.requests, hasLength(1));
    // Al día siguiente, otra vez.
    now = now.add(const Duration(days: 1));
    expect(await s.pingIfDue(_xtream), isTrue);
    expect(http.requests, hasLength(2));
    expect(logs.join('\n'), contains('usage.ping'));
    expect(logs.join('\n'), isNot(contains(accountHash(_xtream)!)));
  });

  for (final code in [400, 429, 500, 503]) {
    test('$code: se ignora, no insiste en esta ejecución y reintenta en la '
        'próxima apertura', () async {
      http.handler = (_) => status(code);
      final s = service();
      expect(await s.pingIfDue(_xtream), isFalse);
      expect(await s.pingIfDue(_xtream), isFalse);
      expect(http.requests, hasLength(1), reason: 'sin reintentos agresivos');
      expect(settings.values[SettingsKeys.usagePingDay], isNull);
      expect(logs.join('\n'), contains('http=$code'));

      http.handler = (_) => status(204);
      expect(await service().pingIfDue(_xtream), isTrue);
    });
  }

  test('sin conexión: se ignora sin lanzar', () async {
    http.handler = (o) => throw DioException.connectionError(
      requestOptions: o,
      reason: 'sin red',
    );
    final s = service();
    expect(await s.pingIfDue(_xtream), isFalse);
    expect(await s.pingIfDue(_xtream), isFalse);
    expect(http.requests, hasLength(1));
    expect(settings.values[SettingsKeys.usagePingDay], isNull);
  });

  test('desactivado (depuración sin URL): no envía nada', () async {
    expect(await service(enabled: false).pingIfDue(_xtream), isFalse);
    expect(http.requests, isEmpty);
  });

  test('en depuración y tests el destino nunca es el servidor real', () {
    final c = ProviderContainer.test();
    expect(
      c.read(usagePingEndpointProvider),
      isNot(UsagePingConfig.releaseEndpoint),
    );
  });

  group('disparador', () {
    Session sessionOf(SourceCredentials credentials) => Session(
      profile: Profile(
        id: 1,
        name: 'Cuenta 1',
        type: SourceType.xtream,
        createdAt: DateTime(2026),
      ),
      credentials: credentials,
    );

    ProviderContainer container({required bool termsAccepted}) {
      if (termsAccepted) {
        settings.values[SettingsKeys.acceptedTermsVersion] =
            AppConfig.termsVersion;
      }
      return ProviderContainer.test(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(settings),
          dioProvider.overrideWithValue(testDio(http)),
          usagePingEndpointProvider.overrideWithValue(_endpoint),
        ],
      );
    }

    test('sin aceptar los términos no envía nada', () {
      fakeAsync((async) {
        final c = container(termsAccepted: false);
        c.read(usagePingTriggerProvider);
        c.read(sessionProvider.notifier).start(sessionOf(_xtream));
        async.elapse(const Duration(minutes: 5));
        expect(http.requests, isEmpty);
      });
    });

    test('al abrir una cuenta envía con su huella', () {
      fakeAsync((async) {
        final c = container(termsAccepted: true);
        c.read(usagePingTriggerProvider);
        async.flushMicrotasks();
        c.read(sessionProvider.notifier).start(sessionOf(_xtream));
        async.elapse(const Duration(seconds: 1));
        expect(http.requests, hasLength(1));
        expect(
          (http.requests.single.data as Map<String, String>)['account_hash'],
          accountHash(_xtream),
        );
        // El envío de "app abierta" ya no sale ese día.
        async.elapse(UsagePingConfig.appOpenDelay * 2);
        expect(http.requests, hasLength(1));
      });
    });

    test('si nadie abre una cuenta, envía sin huella tras la espera', () {
      fakeAsync((async) {
        final c = container(termsAccepted: true);
        c.read(usagePingTriggerProvider);
        async.elapse(UsagePingConfig.appOpenDelay - const Duration(seconds: 1));
        expect(http.requests, isEmpty);
        async.elapse(const Duration(seconds: 2));
        expect(http.requests, hasLength(1));
        expect(
          (http.requests.single.data as Map<String, String>).containsKey(
            'account_hash',
          ),
          isFalse,
        );
      });
    });
  });
}
