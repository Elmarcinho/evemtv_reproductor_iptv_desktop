// Informe Codex Fase 4: cada escenario reproducido como prueba, ahora con
// un contenedor de Riverpod por sesión (SessionScope). Datos ficticios.
import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:evemtv/core/errors/app_failure.dart';
import 'package:evemtv/core/images/image_disk_cache.dart';
import 'package:evemtv/core/logging/app_logger.dart';
import 'package:evemtv/core/logging/redactor.dart';
import 'package:evemtv/data/content_source_factory.dart';
import 'package:evemtv/data/providers.dart';
import 'package:evemtv/data/storage/app_database.dart';
import 'package:evemtv/data/storage/drift_repositories.dart';
import 'package:evemtv/domain/entities/live.dart';
import 'package:evemtv/domain/entities/profile.dart';
import 'package:evemtv/domain/entities/source_credentials.dart';
import 'package:evemtv/domain/entities/vod.dart';
import 'package:evemtv/domain/entities/watch_progress.dart';
import 'package:evemtv/domain/repositories/watch_progress_repository.dart';
import 'package:evemtv/features/auth/application/auth_service.dart';
import 'package:evemtv/features/auth/application/session.dart';
import 'package:evemtv/features/images/app_images.dart';
import 'package:evemtv/features/player/vod_player_screen.dart';
import 'package:evemtv/features/player/watch_progress.dart';
import 'package:evemtv/features/search/catalog_sync.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../fixtures/xtream_fixtures.dart';
import '../helpers/fakes.dart';
import 'player/live_playback_controller_test.dart' show FakeSource;

AppDatabase _memoryDb() => AppDatabase(
  DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true),
);

Session _sessionFor(int id) => Session(
  profile: Profile(
    id: id,
    name: 'Cuenta $id',
    type: SourceType.xtream,
    createdAt: DateTime(2026),
  ),
  credentials: XtreamCredentials(
    server: Uri.parse('http://panel.example.com'),
    username: 'usuario$id',
    password: 'clave$id',
  ),
);

/// Crea los perfiles 1 y 2 (las tablas tienen clave foránea al perfil).
Future<void> _twoProfiles(AppDatabase db) async {
  final repo = DriftProfileRepository(db);
  await repo.create(name: 'A', type: SourceType.xtream);
  await repo.create(name: 'B', type: SourceType.xtream);
}

/// Progreso cuyo borrado espera a [removeGate] (para cambiar de perfil a
/// mitad de un guardado).
class _GatedProgressRepo implements WatchProgressRepository {
  _GatedProgressRepo(this._inner);

  final WatchProgressRepository _inner;
  Completer<void>? removeGate;

  @override
  Stream<List<WatchProgress>> watchRecent(int profileId, {int limit = 20}) =>
      _inner.watchRecent(profileId, limit: limit);

  @override
  Future<WatchProgress?> get(int profileId, ProgressKind kind, String id) =>
      _inner.get(profileId, kind, id);

  @override
  Future<void> save(int profileId, WatchProgress progress) =>
      _inner.save(profileId, progress);

  @override
  Future<void> remove(int profileId, ProgressKind kind, String id) async {
    await removeGate?.future;
    await _inner.remove(profileId, kind, id);
  }
}

/// Fuente cuyas categorías en vivo esperan a [gate]; registra cada llamada.
class _GatedSource extends FakeSource {
  final gate = Completer<void>();
  final calls = <String>[];

  @override
  Future<List<ContentCategory>> liveCategories() async {
    calls.add('liveCategories');
    await gate.future;
    return const [ContentCategory(id: 'd', name: 'Deportes')];
  }

  @override
  Future<List<LiveChannel>> liveChannels({String? categoryId}) async {
    calls.add('liveChannels');
    return const [LiveChannel(id: '1', name: 'Canal', categoryId: 'd')];
  }
}

void main() {
  late LogSink originalSink;
  setUp(() {
    originalSink = AppLogger.sink;
    AppLogger.sink = (_, _) {};
  });
  tearDown(() {
    AppLogger.sink = originalSink;
    Redactor.clearSecrets();
  });

  const serie = SeriesItem(id: 's1', name: 'Serie Ficticia', categoryId: 'x');
  const e1 = Episode(id: 'e1', season: 1, number: 1, title: 'Piloto');
  const e2 = Episode(id: 'e2', season: 1, number: 2, title: 'Segundo');

  test('1. el siguiente episodio de A nunca se escribe en B', () async {
    final db = _memoryDb();
    addTearDown(db.close);
    await _twoProfiles(db);
    final repo = _GatedProgressRepo(DriftWatchProgressRepository(db));
    final root = ProviderContainer.test(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        watchProgressRepositoryProvider.overrideWithValue(repo),
      ],
    );
    root.read(sessionProvider.notifier).start(_sessionFor(1));
    final a = sessionContainerFor(root, _sessionFor(1));
    final tracker = VodProgressTracker(a.read(watchProgressServiceProvider));

    // Termina el episodio 1 de A: se quita y se prepara el 2… pero el
    // borrado se demora y, mientras, se cambia al perfil B.
    repo.removeGate = Completer<void>();
    final saving = tracker.save(
      const EpisodePlayable(series: serie, episodes: [e1, e2], index: 0),
      position: const Duration(minutes: 45),
      duration: const Duration(minutes: 45),
      completed: true,
    );
    a.dispose();
    root.read(sessionProvider.notifier).start(_sessionFor(2));
    final b = sessionContainerFor(root, _sessionFor(2));
    addTearDown(b.dispose);
    repo.removeGate!.complete();
    await saving;

    expect(await repo.get(2, ProgressKind.episode, 'e2'), isNull);
    expect((await repo.get(1, ProgressKind.episode, 'e2'))?.seriesId, 's1');
  });

  testWidgets(
    '2. al cambiar de perfil, ningún cuadro muestra datos del anterior',
    (tester) async {
      final db = _memoryDb();
      await tester.runAsync(() async {
        await _twoProfiles(db);
        await DriftWatchProgressRepository(db).save(
          1,
          WatchProgress(
            kind: ProgressKind.movie,
            itemId: 'm1',
            title: 'Película de A',
            position: const Duration(minutes: 30),
            duration: const Duration(hours: 2),
            updatedAt: DateTime(2026),
          ),
        );
      });
      final root = ProviderContainer(
        retry: (_, _) => null,
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          secureStorageProvider.overrideWithValue(FakeSecureStorage()),
          dioProvider.overrideWithValue(
            testDio(FakeHttpAdapter((_) => jsonBody('{}'))),
          ),
          tempImageCacheRoot(),
        ],
      );
      root.read(sessionProvider.notifier).start(_sessionFor(1));

      // Cada cuadro deja constancia de lo que ve.
      final frames = <String>[];
      SessionContext? lastContext;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: root,
          child: MaterialApp(
            home: SessionScope(
              child: Consumer(
                builder: (context, ref, _) {
                  final ctx = ref.watch(sessionContextProvider);
                  lastContext = ctx;
                  final titles = ref
                      .watch(continueWatchingProvider)
                      .map((w) => w.title)
                      .join(',');
                  final cache = ref.watch(imageDiskCacheProvider).value;
                  final dir = cache == null
                      ? '-'
                      : p.basename(cache.directory.path);
                  frames.add('perfil ${ctx.profileId}: [$titles] caché $dir');
                  return Text(frames.last);
                },
              ),
            ),
          ),
        ),
      );
      await settleIo(tester);
      expect(frames.last, 'perfil 1: [Película de A] caché 1');
      final contextA = lastContext!;

      root.read(sessionProvider.notifier).start(_sessionFor(2));
      await tester.pump();
      await settleIo(tester);

      final framesB = frames.where((f) => f.startsWith('perfil 2'));
      expect(framesB, isNotEmpty);
      for (final f in framesB) {
        expect(f, isNot(contains('Película de A')));
        expect(f, isNot(contains('caché 1')));
      }
      expect(framesB.last, 'perfil 2: [] caché 2');
      // La sesión anterior quedó cerrada (cancela sus peticiones).
      expect(contextA.lifetime.isActive, isFalse);
      expect(contextA.lifetime.cancelToken.isCancelled, isTrue);

      await tester.pumpWidget(const SizedBox());
      root.dispose();
      await tester.runAsync(db.close);
    },
  );

  group('3. solo se guardan imágenes válidas', () {
    late Directory dir;
    late FakeHttpAdapter http;
    const url = 'http://img.example.com/p.png';

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('evemtv_img_');
    });
    tearDown(() => dir.delete(recursive: true));

    ImageDiskCache cacheWith(
      List<int> body, {
      Future<bool> Function(Uint8List)? verify,
    }) {
      http = FakeHttpAdapter((_) => ResponseBody.fromBytes(body, 200));
      return ImageDiskCache(
        directory: dir,
        key: List<int>.generate(32, (i) => i),
        dio: testDio(http),
        verifyDecodes: verify ?? (_) async => true,
      );
    }

    test('formato por sus primeros bytes: PNG, JPEG y WebP', () {
      expect(ImageDiskCache.formatOf(tinyPng), CachedImageFormat.png);
      expect(
        ImageDiskCache.formatOf([0xFF, 0xD8, 0xFF, 0xE0, 0, 0]),
        CachedImageFormat.jpeg,
      );
      expect(
        ImageDiskCache.formatOf('RIFF\x00\x00\x00\x00WEBPVP8 '.codeUnits),
        CachedImageFormat.webp,
      );
      expect(
        ImageDiskCache.formatOf('RIFF\x00\x00\x00\x00WAVE'.codeUnits),
        isNull,
      );
      expect(ImageDiskCache.formatOf('GIF89a'.codeUnits), isNull);
      expect(ImageDiskCache.formatOf('<!DOCTYPE html>'.codeUnits), isNull);
      expect(ImageDiskCache.formatOf(const []), isNull);
    });

    test('una página HTML se devuelve pero no llega al disco', () async {
      final html = '<html><body>Error del panel</body></html>'.codeUnits;
      final cache = cacheWith(html);
      expect(await cache.load(url), html);
      expect(dir.listSync(), isEmpty);
    });

    test('con cabecera PNG pero sin decodificar, no se guarda', () async {
      final cache = cacheWith(fakePng(500), verify: (_) async => false);
      await cache.load(url);
      expect(dir.listSync(), isEmpty);
    });

    test('un archivo inválido de una versión anterior se descarta', () async {
      final cache = cacheWith(fakePng(300));
      File(p.join(dir.path, cache.fileNameFor(url)))
          .writeAsStringSync('<html></html>');
      final bytes = await cache.load(url);
      expect(ImageDiskCache.formatOf(bytes), CachedImageFormat.png);
      expect(http.requests, hasLength(1));
      expect(
        File(p.join(dir.path, cache.fileNameFor(url))).readAsBytesSync(),
        bytes,
      );
    });

    testWidgets('decodificación real: un PNG válido sí, basura no', (
      tester,
    ) async {
      await tester.runAsync(() async {
        expect(await ImageDiskCache.decodes(tinyPng), isTrue);
        expect(await ImageDiskCache.decodes(fakePng(500)), isFalse);

        final ok = cacheWith(tinyPng, verify: ImageDiskCache.decodes);
        await ok.load(url);
        expect(dir.listSync(), hasLength(1));
      });
    });
  });

  group('4. cierre de sesión con la caché de imágenes', () {
    late AppDatabase db;
    late FakeSecureStorage storage;
    late Directory root;
    late ProviderContainer app;
    late Completer<void> slowImage;

    setUp(() async {
      db = _memoryDb();
      storage = FakeSecureStorage();
      root = await Directory.systemTemp.createTemp('evemtv_root_');
      slowImage = Completer<void>();
      final http = FakeHttpAdapter((o) async {
        if (o.uri.path.endsWith('lenta.png')) {
          await slowImage.future;
          return ResponseBody.fromBytes(fakePng(400), 200);
        }
        if (o.uri.path.endsWith('.png')) {
          return ResponseBody.fromBytes(fakePng(400), 200);
        }
        return jsonBody(loginOk);
      });
      app = ProviderContainer.test(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          secureStorageProvider.overrideWithValue(storage),
          dioProvider.overrideWithValue(testDio(http)),
          imageCacheRootProvider.overrideWithValue(() async => root),
          imageDecodeCheckProvider.overrideWithValue((_) async => true),
        ],
      );
    });
    tearDown(() async {
      if (!slowImage.isCompleted) slowImage.complete();
      await db.close();
      if (root.existsSync()) await root.delete(recursive: true);
    });

    /// Inicia sesión y abre la caché de imágenes de la sesión.
    Future<(Session, ProviderContainer, ImageDiskCache)> login() async {
      await app
          .read(authServiceProvider)
          .addXtream(
            url: 'http://panel.example.com',
            username: 'usuarioDemo',
            password: 'claveDemo',
          );
      final session = app.read(sessionProvider)!;
      final scope = sessionContainerFor(app, session);
      addTearDown(scope.dispose);
      scope.listen(imageDiskCacheProvider, (_, _) {});
      final cache = (await scope.read(imageDiskCacheProvider.future))!;
      await cache.load('http://img.example.com/guardada.png');
      expect(cache.directory.existsSync(), isTrue);
      return (session, scope, cache);
    }

    bool hasImageKey() =>
        storage.values.keys.any((k) => k.contains('image_cache_key'));

    test('una descarga en curso se cancela y no recrea la carpeta', () async {
      final (session, _, cache) = await login();
      final pending = cache
          .load('http://img.example.com/lenta.png')
          .then((_) => 'guardada', onError: (Object _) => 'cancelada');
      await pumpEventQueue();

      await app.read(authServiceProvider).logout(session.profile);
      expect(await pending, 'cancelada');
      // Aunque el servidor responda después, nada vuelve a escribirse.
      slowImage.complete();
      await pumpEventQueue();

      expect(cache.directory.existsSync(), isFalse);
      expect(hasImageKey(), isFalse);
      expect(app.read(sessionProvider), isNull);
      expect(storage.values, isEmpty);
    });

    test('si la carpeta o la clave no se borran, se avisa en vez de informar '
        'éxito', () async {
      final (session, _, _) = await login();
      storage.ignoreDeleteOf = (k) => k.contains('image_cache_key');

      await expectLater(
        app.read(authServiceProvider).logout(session.profile),
        throwsA(
          isA<StorageFailure>().having(
            (f) => f.kind,
            'kind',
            StorageFailureKind.cleanupIncomplete,
          ),
        ),
      );
      // Las credenciales y el perfil ya se borraron y la sesión se cerró:
      // el aviso es solo por los restos de imágenes.
      expect(app.read(sessionProvider), isNull);
      expect(storage.values.keys.where((k) => k.contains('cred')), isEmpty);
      expect(hasImageKey(), isTrue);
    });

    test('si falla el borrado de credenciales, la caché se reabre', () async {
      final (session, _, cache) = await login();
      storage.failDeleteWith = PlatformException(code: 'locked');
      await expectLater(
        app.read(authServiceProvider).logout(session.profile),
        throwsA(isA<StorageFailure>()),
      );
      expect(app.read(sessionProvider), isNotNull);
      expect(cache.isClosed, isFalse);
      await cache.load('http://img.example.com/otra.png');
      expect(cache.directory.listSync(), hasLength(2));
    });
  });

  test(
    '6. tras cerrar sesión, la actualización no hace otra petición',
    () async {
      final db = _memoryDb();
      addTearDown(db.close);
      await _twoProfiles(db);
      final source = _GatedSource();
      final root = ProviderContainer.test(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
      );
      final lifetime = SessionLifetime();
      final scope = sessionContainerFor(
        root,
        _sessionFor(1),
        lifetime: lifetime,
        overrides: [contentSourceProvider.overrideWithValue(source)],
      );

      final running = scope.read(catalogSyncProvider.notifier).sync();
      await pumpEventQueue();
      expect(source.calls, ['liveCategories']);

      // Lo que hace SessionScope al cerrar sesión.
      lifetime.close();
      scope.dispose();
      source.gate.complete();
      await running;

      expect(source.calls, ['liveCategories'], reason: 'sin petición nueva');
      expect(await db.select(db.catalogItems).get(), isEmpty);
      expect(await db.select(db.catalogCategories).get(), isEmpty);
    },
  );

  test('6b. al cerrar la sesión se cancelan sus peticiones de red', () async {
    final slow = Completer<void>();
    final http = FakeHttpAdapter((o) async {
      await slow.future;
      return jsonBody('[]');
    });
    addTearDown(() {
      if (!slow.isCompleted) slow.complete();
    });
    final lifetime = SessionLifetime();
    final source = ContentSourceFactory(testDio(http))
        .create(_sessionFor(1).credentials, cancelToken: lifetime.cancelToken);

    final pending = source.liveChannels();
    await pumpEventQueue();
    expect(http.requests, hasLength(1));

    lifetime.close();
    await expectLater(pending, throwsA(isA<AppFailure>()));
    // Una petición nueva de la sesión cerrada no sale a la red.
    await expectLater(source.liveCategories(), throwsA(isA<AppFailure>()));
    expect(http.requests, hasLength(1));
  });
}
