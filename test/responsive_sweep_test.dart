// Barrido de tamaños: cada pantalla principal en tamaños de ventana
// reales, sin desbordes (las franjas amarillas y negras de Flutter).
//
// Incluye los tamaños LÓGICOS que resultan del escalado de Windows:
// 1920×1080 al 150 % = 1280×720, 1366×768 al 125 % = 1093×614 y
// 1366×768 al 150 % = 911×512 (con barra de tareas y título, la ventana
// maximizada queda cerca del mínimo de la app). Datos ficticios.
import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart' show ResponseBody;
import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:evemtv/app.dart';
import 'package:evemtv/core/config/app_config.dart';
import 'package:evemtv/core/logging/app_logger.dart';
import 'package:evemtv/core/logging/redactor.dart';
import 'package:evemtv/core/router/app_router.dart';
import 'package:evemtv/data/providers.dart';
import 'package:evemtv/data/storage/app_database.dart';
import 'package:evemtv/data/storage/drift_repositories.dart';
import 'package:evemtv/domain/entities/vod.dart';
import 'package:evemtv/domain/entities/watch_progress.dart';
import 'package:evemtv/domain/repositories/settings_repository.dart';
import 'package:evemtv/features/auth/application/auth_service.dart';
import 'package:evemtv/features/auth/application/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/xtream_fixtures.dart';
import 'helpers/fakes.dart';

class _MemorySettings implements SettingsRepository {
  final values = <String, String>{
    SettingsKeys.acceptedTermsVersion: AppConfig.termsVersion,
  };

  @override
  Future<String?> get(String key) async => values[key];

  @override
  Future<void> set(String key, String value) async => values[key] = value;
}

/// Nombre largo, como los de muchos paneles.
String _long(String what, int i) =>
    '$what de prueba número $i con un título bastante largo (2026) FHD Latino';

/// Panel ficticio pequeño: responde según `action`.
ResponseBody _panel(Uri uri) {
  final q = uri.queryParameters;
  Object body;
  switch (q['action']) {
    case null:
      return jsonBody(loginOk);
    case 'get_live_categories':
      body = [
        for (var c = 1; c <= 3; c++)
          {'category_id': '$c', 'category_name': 'Canales $c'},
      ];
    case 'get_live_streams':
      body = [
        for (var i = 1; i <= 30; i++)
          {
            'num': i,
            'name': _long('Canal', i),
            'stream_id': i,
            'category_id': '${i % 3 + 1}',
          },
      ];
    case 'get_vod_categories':
      body = [
        for (var c = 1; c <= 3; c++)
          {'category_id': '$c', 'category_name': 'Categoría $c'},
      ];
    case 'get_vod_streams':
      body = [
        for (var i = 1; i <= 30; i++)
          {
            'num': i,
            'name': _long('Película', i),
            'stream_id': i,
            'rating': '8.5',
            'added': '${1767225600 + i}',
            'category_id': '${i % 3 + 1}',
            'container_extension': 'mp4',
          },
      ];
    case 'get_vod_info':
      body = {
        'info': {
          'plot': 'Sinopsis ficticia ' * 20,
          'genre': 'Drama / Comedia / Suspenso',
          'cast': 'Actriz Inventada, ' * 15,
          'director': 'Directora Inventada',
          'duration_secs': 6000,
        },
        'movie_data': {'stream_id': q['vod_id'], 'container_extension': 'mp4'},
      };
    case 'get_series_categories':
      body = [
        for (var c = 1; c <= 3; c++)
          {'category_id': '$c', 'category_name': 'Series $c'},
      ];
    case 'get_series':
      body = [
        for (var i = 1; i <= 30; i++)
          {
            'num': i,
            'name': _long('Serie', i),
            'series_id': i,
            'rating': '9',
            'last_modified': '${1767225600 + i}',
            'category_id': '${i % 3 + 1}',
          },
      ];
    case 'get_series_info':
      body = {
        'info': {'plot': 'Trama ficticia ' * 20},
        'seasons': [
          for (var s = 1; s <= 8; s++) {'season_number': s, 'name': 'T$s'},
        ],
        'episodes': {
          for (var s = 1; s <= 8; s++)
            '$s': [
              for (var e = 1; e <= 12; e++)
                {
                  'id': '$s$e',
                  'episode_num': e,
                  'season': s,
                  'title': _long('Episodio', e),
                  'container_extension': 'mp4',
                },
            ],
        },
      };
    case 'get_short_epg':
      body = {'epg_listings': <Object>[]};
    default:
      body = <Object>[];
  }
  return jsonBody(jsonEncode(body));
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

  const sizes = [
    Size(800, 450), // mínimo de la ventana
    Size(911, 512), // 1366×768 al 150 %
    Size(1093, 614), // 1366×768 al 125 %
    Size(1280, 720), // 1920×1080 al 150 %
    Size(1366, 768),
    Size(1920, 1080),
    Size(2560, 1440),
    Size(3840, 2160),
  ];

  test('el mínimo de la ventana entra en el menor tamaño lógico', () {
    expect(AppConfig.minWindowSize.width, lessThanOrEqualTo(sizes.first.width));
    expect(
      AppConfig.minWindowSize.height,
      lessThanOrEqualTo(sizes.first.height),
    );
  });

  for (final size in sizes) {
    testWidgets('${size.width.toInt()}×${size.height.toInt()}: sin desbordes', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final db = AppDatabase(
        DatabaseConnection(
          NativeDatabase.memory(),
          closeStreamsSynchronously: true,
        ),
      );
      final container = ProviderContainer(
        retry: (_, _) => null,
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          settingsRepositoryProvider.overrideWithValue(_MemorySettings()),
          secureStorageProvider.overrideWithValue(FakeSecureStorage()),
          dioProvider.overrideWithValue(
            testDio(FakeHttpAdapter((o) => _panel(o.uri))),
          ),
          tempImageCacheRoot(),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const EvemTvApp(),
        ),
      );
      await settleIo(tester);

      final problems = <String>[];
      Future<void> check(String screen) async {
        await settleIo(tester);
        // Deja terminar animaciones de entrada.
        await tester.pump(const Duration(seconds: 1));
        final error = tester.takeException();
        if (error != null) problems.add('$screen: $error');
      }

      final router = container.read(appRouterProvider);
      await check('selector de cuentas vacío');
      router.go(AppRoutes.login);
      await check('login');

      // Sin runAsync: la base vive en el reloj simulado; settleIo alterna
      // E/S real y bombeo hasta que termina.
      unawaited(
        container
            .read(authServiceProvider)
            .addXtream(
              url: 'http://panel.example.com',
              username: 'usuarioDemo',
              password: 'claveDemo',
            ),
      );
      await check('inicio (novedades)');

      router.go(AppRoutes.live);
      await check('En vivo');
      router.go(AppRoutes.movies);
      await check('Películas');
      router.go(AppRoutes.series);
      await check('Series');
      router.go(AppRoutes.search);
      await check('Búsqueda');
      router.go(AppRoutes.home);
      unawaited(
        router.push(
          AppRoutes.movieDetail,
          extra: VodItem(id: '1', name: _long('Película', 1), categoryId: '2'),
        ),
      );
      await check('Ficha de película');
      router.go(AppRoutes.home);
      unawaited(
        router.push(
          AppRoutes.seriesDetail,
          extra: SeriesItem(id: '1', name: _long('Serie', 1), categoryId: '2'),
        ),
      );
      await check('Ficha de serie');

      // Inicio con "Seguir viendo" (otro arreglo).
      unawaited(
        DriftWatchProgressRepository(db).save(
          container.read(sessionProvider)!.profile.id,
          WatchProgress(
            kind: ProgressKind.movie,
            itemId: '1',
            title: _long('Película', 1),
            position: const Duration(minutes: 30),
            duration: const Duration(hours: 2),
            updatedAt: DateTime(2026),
          ),
        ),
      );
      router.go(AppRoutes.home);
      await check('inicio con Seguir viendo');

      // Selector con cuentas guardadas.
      container.read(authServiceProvider).switchProfile();
      await check('selector de cuentas');

      expect(problems, isEmpty, reason: problems.join('\n'));

      await tester.pumpWidget(const SizedBox());
      container.dispose();
      await tester.runAsync(db.close);
    });
  }
}
