import '../../core/errors/app_failure.dart';
import '../../core/utils/json_read.dart';
import '../../domain/entities/account_info.dart';

/// Interpreta la respuesta de login de `player_api.php` (sin `action`).
abstract final class XtreamAccountParser {
  /// Convierte el JSON decodificado en [AccountInfo] sin validar el estado.
  ///
  /// Lanza [InvalidCredentialsFailure] si la respuesta está vacía (muchos
  /// paneles responden `[]` o `{}` con credenciales incorrectas) e
  /// [InvalidResponseFailure] si no tiene la forma de un panel Xtream.
  static AccountInfo parse(Object? json) {
    final root = JsonRead.map(json);
    if (root == null || root.isEmpty) {
      if (json == null || (json is List && json.isEmpty) || json is Map) {
        throw const InvalidCredentialsFailure(detail: 'respuesta vacía');
      }
      throw InvalidResponseFailure(detail: 'raíz ${json.runtimeType}');
    }

    final user = JsonRead.map(root['user_info']);
    if (user == null) {
      throw const InvalidResponseFailure(detail: 'sin user_info');
    }
    final server = JsonRead.map(root['server_info']) ?? const {};

    return AccountInfo(
      authenticated: JsonRead.integer(user['auth']) == 1,
      status: AccountStatus.parse(JsonRead.string(user['status'])),
      expiresAt: JsonRead.unixSeconds(user['exp_date']),
      createdAt: JsonRead.unixSeconds(user['created_at']),
      isTrial: JsonRead.boolean(user['is_trial']),
      activeConnections: JsonRead.integer(user['active_cons']),
      maxConnections: JsonRead.integer(user['max_connections']),
      allowedOutputFormats: JsonRead.stringList(user['allowed_output_formats']),
      serverTimezone: JsonRead.string(server['timezone']),
    );
  }

  /// Verifica que la cuenta se pueda usar: `auth == 1`, estado `Active` y
  /// fecha de vencimiento no pasada.
  static void ensureUsable(AccountInfo info, {required DateTime now}) {
    if (!info.authenticated) {
      throw const InvalidCredentialsFailure(detail: 'auth != 1');
    }
    if (info.status != AccountStatus.active) {
      throw AccountExpiredFailure(detail: 'status=${info.status.name}');
    }
    if (info.isExpiredAt(now)) {
      throw const AccountExpiredFailure(detail: 'exp_date pasada');
    }
  }
}
