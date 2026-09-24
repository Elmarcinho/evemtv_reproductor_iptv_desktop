import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/network/dio_factory.dart';
import '../domain/repositories/credential_store.dart';
import '../domain/repositories/favorites_repository.dart';
import '../domain/repositories/profile_repository.dart';
import '../domain/repositories/settings_repository.dart';
import 'content_source_factory.dart';
import 'storage/app_database.dart';
import 'storage/drift_repositories.dart';
import 'storage/secure_credential_store.dart';
import 'storage/secure_storage_factory.dart';

/// Infraestructura compartida. Los tests reemplazan estos providers con
/// `overrides` (base en memoria, almacén seguro falso, Dio simulado).

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final secureStorageProvider = Provider<FlutterSecureStorage>(
  (ref) => createSecureStorage(),
);

final dioProvider = Provider<Dio>((ref) {
  final dio = createDio();
  ref.onDispose(dio.close);
  return dio;
});

final profileRepositoryProvider = Provider<ProfileRepository>(
  (ref) => DriftProfileRepository(ref.watch(appDatabaseProvider)),
);

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => DriftSettingsRepository(ref.watch(appDatabaseProvider)),
);

final credentialStoreProvider = Provider<CredentialStore>(
  (ref) => SecureCredentialStore(ref.watch(secureStorageProvider)),
);

final contentSourceFactoryProvider = Provider<ContentSourceFactory>(
  (ref) => ContentSourceFactory(ref.watch(dioProvider)),
);

final favoritesRepositoryProvider = Provider<FavoritesRepository>(
  (ref) => DriftFavoritesRepository(ref.watch(appDatabaseProvider)),
);
