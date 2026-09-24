// Repositorios drift (base en memoria) y almacén de credenciales falso.
import 'package:drift/native.dart';
import 'package:evemtv/core/errors/app_failure.dart';
import 'package:evemtv/core/logging/app_logger.dart';
import 'package:evemtv/data/storage/app_database.dart';
import 'package:evemtv/data/storage/drift_repositories.dart';
import 'package:evemtv/data/storage/secure_credential_store.dart';
import 'package:evemtv/domain/entities/profile.dart';
import 'package:evemtv/domain/entities/source_credentials.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fakes.dart';

void main() {
  late LogSink originalSink;
  setUp(() {
    originalSink = AppLogger.sink;
    AppLogger.sink = (_, _) {};
  });
  tearDown(() => AppLogger.sink = originalSink);

  group('DriftProfileRepository', () {
    late AppDatabase db;
    late DateTime now;
    late DriftProfileRepository repo;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      now = DateTime(2026, 1, 1);
      repo = DriftProfileRepository(db, clock: () => now);
    });
    tearDown(() => db.close());

    test('crea, ordena por último uso y borra', () async {
      final a = await repo.create(name: 'Casa', type: SourceType.xtream);
      now = now.add(const Duration(minutes: 1));
      final b = await repo.create(name: 'Lista', type: SourceType.m3u);
      expect(await repo.count(), 2);

      // Sin uso: el más nuevo primero.
      expect((await repo.watchAll().first).map((p) => p.id), [b.id, a.id]);

      now = now.add(const Duration(minutes: 1));
      await repo.markUsed(a.id);
      final list = await repo.watchAll().first;
      expect(list.map((p) => p.id), [a.id, b.id]);
      expect(list.first.lastUsedAt, now);
      expect(list.last.type, SourceType.m3u);

      await repo.delete(a.id);
      expect(await repo.count(), 1);
    });

    test('la tabla de perfiles no tiene columnas de URL ni credenciales', () {
      final columns = db.profiles.$columns.map((c) => c.name).toSet();
      expect(columns, {'id', 'name', 'type', 'created_at', 'last_used_at'});
    });
  });

  group('DriftSettingsRepository', () {
    test('guarda y reemplaza valores', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final settings = DriftSettingsRepository(db);
      expect(await settings.get('k'), isNull);
      await settings.set('k', '1');
      await settings.set('k', '2');
      expect(await settings.get('k'), '2');
    });
  });

  group('SecureCredentialStore', () {
    final xtream = XtreamCredentials(
      server: Uri.parse('http://panel.example.com:8080'),
      username: 'demo',
      password: 'clave',
    );

    test('ida y vuelta de Xtream y M3U', () async {
      final store = SecureCredentialStore(FakeSecureStorage(), isLinux: false);
      await store.write(1, xtream);
      await store.write(
        2,
        M3uCredentials(
          playlist: Uri.parse('http://lista.example.com/a.m3u?t=x'),
        ),
      );

      final a = await store.read(1);
      expect(a, isA<XtreamCredentials>());
      a as XtreamCredentials;
      expect(a.server, xtream.server);
      expect(a.username, 'demo');
      expect(a.password, 'clave');

      final b = await store.read(2);
      expect((b! as M3uCredentials).playlist.query, 't=x');

      await store.delete(1);
      expect(await store.read(1), isNull);
    });

    test('datos dañados se tratan como ausentes', () async {
      final storage = FakeSecureStorage()
        ..values['profile.1.credentials'] = '{no es json';
      storage.values['profile.2.credentials'] = '{"type":"xtream"}';
      final store = SecureCredentialStore(storage, isLinux: false);
      expect(await store.read(1), isNull);
      expect(await store.read(2), isNull);
    });

    test(
      'llavero no disponible en Linux = mensaje claro, nada guardado',
      () async {
        final storage = FakeSecureStorage()
          ..failWith = PlatformException(code: 'Libsecret error');
        final store = SecureCredentialStore(storage, isLinux: true);
        await expectLater(
          store.write(1, xtream),
          throwsA(
            isA<StorageFailure>().having(
              (f) => f.kind,
              'kind',
              StorageFailureKind.keyringUnavailable,
            ),
          ),
        );
        expect(storage.values, isEmpty);
      },
    );

    test('en otras plataformas = error de lectura/escritura', () async {
      final storage = FakeSecureStorage()
        ..failWith = PlatformException(code: 'x');
      final store = SecureCredentialStore(storage, isLinux: false);
      await expectLater(
        store.read(1),
        throwsA(
          isA<StorageFailure>().having(
            (f) => f.kind,
            'kind',
            StorageFailureKind.readWrite,
          ),
        ),
      );
    });
  });
}
