// Casos de uso de autenticación con dobles en memoria y datos ficticios.
import 'dart:async';

import 'package:drift/native.dart';
import 'package:evemtv/core/errors/app_failure.dart';
import 'package:evemtv/core/logging/app_logger.dart';
import 'package:evemtv/core/logging/redactor.dart';
import 'package:evemtv/data/providers.dart';
import 'package:evemtv/data/storage/app_database.dart';
import 'package:evemtv/domain/entities/profile.dart';
import 'package:evemtv/domain/entities/source_credentials.dart';
import 'package:evemtv/features/auth/application/auth_service.dart';
import 'package:evemtv/features/auth/application/session.dart';
import 'package:evemtv/features/home/account_info_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fixtures/xtream_fixtures.dart';
import '../../helpers/fakes.dart';

void main() {
  late ProviderContainer container;
  late FakeSecureStorage storage;
  late FakeHttpAdapter http;
  late LogSink originalSink;

  setUp(() {
    originalSink = AppLogger.sink;
    AppLogger.sink = (_, _) {};
    storage = FakeSecureStorage();
    http = FakeHttpAdapter((_) => jsonBody(loginOk));
    container = ProviderContainer.test(
      overrides: [
        appDatabaseProvider.overrideWith((ref) {
          final db = AppDatabase(NativeDatabase.memory());
          ref.onDispose(db.close);
          return db;
        }),
        secureStorageProvider.overrideWithValue(storage),
        dioProvider.overrideWithValue(testDio(http)),
      ],
    );
  });

  tearDown(() {
    AppLogger.sink = originalSink;
    Redactor.clearSecrets();
  });

  AuthService auth() => container.read(authServiceProvider);
  Future<int> profileCount() async =>
      (await container.read(profileRepositoryProvider).watchAll().first).length;

  test(
    'addXtream: guarda perfil y credenciales, abre sesión y registra secretos',
    () async {
      await auth().addXtream(
        name: '',
        url: 'http://panel.example.com:8080/',
        username: ' usuarioDemo ',
        password: 'claveDemo',
      );

      final session = container.read(sessionProvider)!;
      // En la base queda un nombre genérico; el usuario solo en el almacén seguro.
      expect(session.profile.name, 'Cuenta 1');
      expect(
        await container.read(
          profileDisplayNameProvider(session.profile.id).future,
        ),
        'usuarioDemo',
      );
      expect(session.initialAccountInfo?.maxConnections, 2);
      final creds = session.credentials as XtreamCredentials;
      expect(creds.server.toString(), 'http://panel.example.com:8080');
      expect(creds.username, 'usuarioDemo');

      // Credenciales solo en el almacén seguro.
      expect(storage.values.keys, [
        'profile.${session.profile.id}.credentials',
      ]);
      expect(await profileCount(), 1);

      // Una sola petición para validar y leer la cuenta.
      expect(http.requests, hasLength(1));

      expect(Redactor.redact('x claveDemo usuarioDemo'), 'x *** ***');
    },
  );

  test('addXtream con credenciales incorrectas no guarda nada', () async {
    http.handler = (_) => jsonBody(loginAuthZero);
    await expectLater(
      auth().addXtream(
        name: 'Casa',
        url: 'http://panel.example.com',
        username: 'a',
        password: 'b',
      ),
      throwsA(isA<InvalidCredentialsFailure>()),
    );
    expect(await profileCount(), 0);
    expect(storage.values, isEmpty);
    expect(container.read(sessionProvider), isNull);
  });

  test('URL inválida falla antes de llamar al servidor', () async {
    await expectLater(
      auth().addXtream(
        name: '',
        url: 'panel.example.com',
        username: 'a',
        password: 'b',
      ),
      throwsA(isA<InvalidUrlFailure>()),
    );
    expect(http.requests, isEmpty);
  });

  test('si el llavero falla, se deshace el perfil', () async {
    storage.failWith = PlatformException(code: 'x');
    await expectLater(
      auth().addXtream(
        name: '',
        url: 'http://panel.example.com',
        username: 'a',
        password: 'b',
      ),
      throwsA(isA<StorageFailure>()),
    );
    expect(await profileCount(), 0);
    expect(container.read(sessionProvider), isNull);
  });

  test('addM3u verifica la lista y guarda la URL completa', () async {
    http.handler = (_) => textBody(m3uHead);
    await auth().addM3u(
      name: 'Lista',
      url: 'http://lista.example.com/lista.m3u?token=abc123',
    );
    final creds =
        container.read(sessionProvider)!.credentials as M3uCredentials;
    expect(creds.playlist.queryParameters['token'], 'abc123');
    expect(Redactor.redact('token abc123'), isNot(contains('abc123')));
  });

  test(
    'cambiar de cuenta conserva el perfil; cerrar sesión lo borra',
    () async {
      await auth().addXtream(
        name: 'Casa',
        url: 'http://panel.example.com',
        username: 'usuarioDemo',
        password: 'claveDemo',
      );
      final profile = container.read(sessionProvider)!.profile;

      auth().switchProfile();
      expect(container.read(sessionProvider), isNull);
      expect(Redactor.redact('claveDemo'), 'claveDemo');
      expect(await profileCount(), 1);

      await auth().open(profile);
      expect(container.read(sessionProvider)?.profile.id, profile.id);
      expect(container.read(sessionProvider)?.initialAccountInfo, isNull);

      await auth().logout(profile);
      expect(container.read(sessionProvider), isNull);
      expect(await profileCount(), 0);
      expect(storage.values, isEmpty);
    },
  );

  test('abrir un perfil sin credenciales da un error claro', () async {
    final profile = await container
        .read(profileRepositoryProvider)
        .create(name: 'Huérfano', type: SourceType.xtream);
    await expectLater(auth().open(profile), throwsA(isA<StorageFailure>()));
  });

  test('displayName: usuario de Xtream o de una lista get.php', () {
    expect(
      M3uCredentials(
        playlist: Uri.parse(
          'http://lista.example.com/get.php?USERNAME=demo&password=x',
        ),
      ).displayName,
      'demo',
    );
    expect(
      M3uCredentials(playlist: Uri.parse('http://lista.example.com/a.m3u'))
          .displayName,
      isNull,
    );
  });

  group('Informe Codex Fase 1', () {
    Future<void> addDemo({String user = 'usuarioDemo'}) => auth().addXtream(
      url: 'http://panel.example.com',
      username: user,
      password: 'claveDemo',
    );

    test(
      '1. si el borrado falla, cerrar sesión no termina la sesión',
      () async {
        await addDemo();
        final profile = container.read(sessionProvider)!.profile;
        storage.failDeleteWith = PlatformException(code: 'locked');

        await expectLater(
          auth().logout(profile),
          throwsA(
            isA<StorageFailure>().having(
              (f) => f.kind,
              'kind',
              StorageFailureKind.deleteFailed,
            ),
          ),
        );
        // La sesión sigue abierta (el inicio puede mostrar el error) y la
        // cuenta sigue guardada: nada se anunció como borrado.
        expect(container.read(sessionProvider)?.profile.id, profile.id);
        expect(await profileCount(), 1);
        expect(storage.values, isNotEmpty);

        // Al reintentar con el llavero disponible, se completa.
        storage.failDeleteWith = null;
        await auth().logout(profile);
        expect(container.read(sessionProvider), isNull);
        expect(await profileCount(), 0);
      },
    );

    test('2. una apertura pendiente no revive un perfil eliminado', () async {
      await addDemo();
      final profile = container.read(sessionProvider)!.profile;
      auth().switchProfile();

      storage.readGate = Completer<void>();
      final opening = auth().open(profile);
      await auth().removeProfile(profile);
      storage.readGate!.complete();

      expect(await opening, isFalse);
      expect(container.read(sessionProvider), isNull);
      expect(Redactor.redact('claveDemo'), 'claveDemo');
    });

    test('2b. de dos aperturas solapadas, la obsoleta se descarta', () async {
      await addDemo(user: 'usuarioA');
      final a = container.read(sessionProvider)!.profile;
      auth().switchProfile();
      await addDemo(user: 'usuarioB');
      final b = container.read(sessionProvider)!.profile;
      auth().switchProfile();

      // La lectura de A queda esperando; B abre mientras tanto.
      final gateA = Completer<void>();
      storage.readGate = gateA;
      final openingA = auth().open(a);
      storage.readGate = null;
      expect(await auth().open(b), isTrue);

      gateA.complete();
      expect(await openingA, isFalse);
      expect(container.read(sessionProvider)?.profile.id, b.id);
    });

    test(
      '3. una actualización de la cuenta anterior no pisa la nueva',
      () async {
        // Las peticiones de A esperan a holdA cuando está puesto y responden
        // con otra cantidad de conexiones; las de B responden al instante.
        Completer<void>? holdA;
        http.handler = (o) async {
          if (o.uri.queryParameters['username'] == 'usuarioA' &&
              holdA != null) {
            await holdA.future;
            return jsonBody(
              loginOk.replaceFirst(
                '"max_connections": "2"',
                '"max_connections": "9"',
              ),
            );
          }
          return jsonBody(loginOk);
        };

        await addDemo(user: 'usuarioA');
        final sub = container.listen(accountInfoProvider, (_, _) {});
        addTearDown(sub.close);
        await container.read(accountInfoProvider.future);

        holdA = Completer<void>();
        final refreshA = container.read(accountInfoProvider.notifier).refresh();

        auth().switchProfile();
        await addDemo(user: 'usuarioB');
        expect(
          (await container.read(accountInfoProvider.future))?.maxConnections,
          2,
        );

        holdA.complete();
        await refreshA;
        expect(
          container.read(sessionProvider)?.credentials.displayName,
          'usuarioB',
        );
        expect(container.read(accountInfoProvider).value?.maxConnections, 2);
      },
    );
  });
}
