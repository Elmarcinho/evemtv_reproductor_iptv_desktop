import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/account_info.dart';
import '../auth/application/session.dart';

/// Datos de la cuenta de la sesión. Usa los obtenidos en el login si los
/// hay; si no (perfil guardado), los pide al servidor.
///
/// Vive en el contenedor de la sesión: una respuesta que llega después de
/// cambiar de perfil no tiene dónde aplicarse (`ref.mounted` es falso).
class AccountInfoController extends AsyncNotifier<AccountInfo?> {
  @override
  Future<AccountInfo?> build() async {
    final ctx = ref.watch(sessionContextProvider);
    if (ctx.initialAccountInfo != null) return ctx.initialAccountInfo;
    return _fetch();
  }

  Future<AccountInfo?> _fetch() =>
      ref.read(contentSourceProvider).fetchAccountInfo();

  Future<void> refresh() async {
    state = const AsyncLoading();
    final result = await AsyncValue.guard(_fetch);
    if (!ref.mounted) return;
    state = result;
  }
}

final accountInfoProvider =
    AsyncNotifierProvider<AccountInfoController, AccountInfo?>(
      AccountInfoController.new,
      dependencies: [sessionContextProvider, contentSourceProvider],
    );
