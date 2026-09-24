import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/account_info.dart';
import '../auth/application/session.dart';

/// Datos de la cuenta de la sesión activa. Usa los obtenidos en el login si
/// los hay; si no (perfil guardado), los pide al servidor.
///
/// Los resultados de una sesión anterior se descartan con [SessionToken]:
/// si mientras se esperaba la respuesta cambió la sesión, no se aplican.
class AccountInfoController extends AsyncNotifier<AccountInfo?> {
  @override
  Future<AccountInfo?> build() async {
    final session = ref.watch(sessionProvider);
    if (session == null) return null;
    if (session.initialAccountInfo != null) return session.initialAccountInfo;
    return _fetch();
  }

  Future<AccountInfo?> _fetch() async =>
      ref.read(contentSourceProvider)?.fetchAccountInfo();

  Future<void> refresh() async {
    final sessions = ref.read(sessionProvider.notifier);
    final token = sessions.token;
    state = const AsyncLoading();
    final result = await AsyncValue.guard(_fetch);
    if (!ref.mounted || !sessions.isCurrent(token)) return;
    state = result;
  }
}

final accountInfoProvider =
    AsyncNotifierProvider<AccountInfoController, AccountInfo?>(
      AccountInfoController.new,
    );
