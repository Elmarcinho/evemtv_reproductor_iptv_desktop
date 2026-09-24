import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../data/providers.dart';
import '../../../domain/repositories/settings_repository.dart';

/// `true` si el usuario aceptó la versión vigente de los términos.
class TermsController extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    final accepted = await ref
        .watch(settingsRepositoryProvider)
        .get(SettingsKeys.acceptedTermsVersion);
    return accepted == AppConfig.termsVersion;
  }

  Future<void> accept() async {
    await ref
        .read(settingsRepositoryProvider)
        .set(SettingsKeys.acceptedTermsVersion, AppConfig.termsVersion);
    state = const AsyncData(true);
  }
}

final termsProvider = AsyncNotifierProvider<TermsController, bool>(
  TermsController.new,
);
