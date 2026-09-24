import '../../core/utils/json_read.dart';
import 'profile.dart';

/// Credenciales de una fuente. Solo se guardan en el almacén seguro del
/// sistema y nunca se registran en logs (ver [secrets]).
sealed class SourceCredentials {
  const SourceCredentials();

  SourceType get type;

  /// Nombre para mostrar en la interfaz (el usuario de la cuenta), o `null`
  /// si no hay uno. Se obtiene en memoria desde el almacén seguro; nunca se
  /// guarda en la base de datos.
  String? get displayName;

  /// Valores que el redactor de logs debe enmascarar mientras esta sesión
  /// está activa.
  Iterable<String> get secrets;

  Map<String, Object?> toJson();

  /// Devuelve `null` si el JSON guardado está incompleto o dañado.
  static SourceCredentials? fromJson(Map<String, Object?> json) {
    switch (JsonRead.string(json['type'])) {
      case 'xtream':
        final server = Uri.tryParse(JsonRead.string(json['server']) ?? '');
        final username = json['username'];
        final password = json['password'];
        if (server == null || !server.hasScheme) return null;
        if (username is! String || password is! String) return null;
        return XtreamCredentials(
          server: server,
          username: username,
          password: password,
        );
      case 'm3u':
        final url = Uri.tryParse(JsonRead.string(json['url']) ?? '');
        if (url == null || !url.hasScheme) return null;
        return M3uCredentials(playlist: url);
    }
    return null;
  }
}

final class XtreamCredentials extends SourceCredentials {
  const XtreamCredentials({
    required this.server,
    required this.username,
    required this.password,
  });

  /// URL normalizada del servidor (sin barra final).
  final Uri server;
  final String username;
  final String password;

  @override
  SourceType get type => SourceType.xtream;

  @override
  String? get displayName => username;

  @override
  Iterable<String> get secrets => [
    username,
    password,
    server.toString(),
    server.host,
  ];

  @override
  Map<String, Object?> toJson() => {
    'type': 'xtream',
    'server': server.toString(),
    'username': username,
    'password': password,
  };
}

final class M3uCredentials extends SourceCredentials {
  const M3uCredentials({required this.playlist});

  /// URL completa de la lista; suele llevar usuario y contraseña en la query.
  final Uri playlist;

  @override
  SourceType get type => SourceType.m3u;

  /// Las listas `get.php?username=…` llevan el usuario en la query.
  @override
  String? get displayName {
    final params = {
      for (final e in playlist.queryParameters.entries)
        e.key.toLowerCase(): e.value,
    };
    final user = params['username']?.trim();
    return (user == null || user.isEmpty) ? null : user;
  }

  @override
  Iterable<String> get secrets => [
    playlist.toString(),
    playlist.host,
    ...playlist.queryParameters.values,
    if (playlist.userInfo.isNotEmpty) ...playlist.userInfo.split(':'),
  ];

  @override
  Map<String, Object?> toJson() => {'type': 'm3u', 'url': playlist.toString()};
}
