import '../errors/app_failure.dart';

/// Datos de Xtream extraídos de una URL de lista `get.php`.
typedef XtreamFromPlaylist = ({Uri server, String username, String password});

/// Validación y normalización de las URLs que ingresa el usuario.
abstract final class ServerUrl {
  /// Archivos de la API que el usuario a veces pega junto con el servidor.
  static const _knownEndpoints = {
    'player_api.php',
    'get.php',
    'xmltv.php',
    'panel_api.php',
  };

  static final RegExp _whitespace = RegExp(r'\s');
  static final RegExp _validHost = RegExp(r'^[A-Za-z0-9.\-]+$');

  /// Valida y normaliza la URL de un servidor Xtream.
  ///
  /// Resultado: `esquema://host[:puerto][/ruta]`, en minúsculas, sin barra
  /// final, sin query ni fragmento y sin el nombre del endpoint si se pegó
  /// (`/player_api.php`, `/get.php`…). Lanza [InvalidUrlFailure].
  static Uri normalizeXtream(String input) {
    final uri = _parse(input);
    if (uri.userInfo.isNotEmpty) {
      throw InvalidUrlFailure(InvalidUrlReason.embeddedCredentials);
    }
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.isNotEmpty &&
        _knownEndpoints.contains(segments.last.toLowerCase())) {
      segments.removeLast();
    }
    return Uri(
      scheme: uri.scheme.toLowerCase(),
      host: uri.host.toLowerCase(),
      port: uri.hasPort ? uri.port : null,
      pathSegments: segments.isEmpty ? null : segments,
    );
  }

  /// Valida la URL de una lista M3U. Conserva ruta y query completas: suelen
  /// llevar las credenciales y son necesarias para descargar la lista.
  static Uri validatePlaylist(String input) {
    final uri = _parse(input);
    return uri.removeFragment().replace(
      scheme: uri.scheme.toLowerCase(),
      host: uri.host.toLowerCase(),
    );
  }

  /// Si [playlist] es una lista `get.php?username=…&password=…` de un panel
  /// Xtream, devuelve servidor y credenciales para ofrecer el ingreso Xtream,
  /// que tiene EPG, películas y series.
  static XtreamFromPlaylist? tryExtractXtream(Uri playlist) {
    final segments = playlist.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty || segments.last.toLowerCase() != 'get.php') {
      return null;
    }
    final params = {
      for (final e in playlist.queryParameters.entries)
        e.key.toLowerCase(): e.value,
    };
    final username = params['username'];
    final password = params['password'];
    if (username == null || username.isEmpty) return null;
    if (password == null || password.isEmpty) return null;
    try {
      final server = normalizeXtream(
        playlist.replace(query: '', userInfo: '').toString(),
      );
      return (server: server, username: username, password: password);
    } on InvalidUrlFailure {
      return null;
    }
  }

  static Uri _parse(String input) {
    final text = input.trim();
    if (text.isEmpty) throw InvalidUrlFailure(InvalidUrlReason.empty);
    if (_whitespace.hasMatch(text)) {
      throw InvalidUrlFailure(InvalidUrlReason.containsSpaces);
    }
    if (!text.contains('://')) {
      throw InvalidUrlFailure(InvalidUrlReason.unsupportedScheme);
    }
    final uri = Uri.tryParse(text);
    if (uri == null) throw InvalidUrlFailure(InvalidUrlReason.malformed);
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      throw InvalidUrlFailure(InvalidUrlReason.unsupportedScheme);
    }
    final host = uri.host;
    final isIpv6 = host.contains(':');
    if (host.isEmpty ||
        (!isIpv6 && !_validHost.hasMatch(host)) ||
        host.startsWith('.') ||
        host.endsWith('.') ||
        host.contains('..')) {
      throw InvalidUrlFailure(InvalidUrlReason.malformed);
    }
    if (uri.hasPort && (uri.port < 1 || uri.port > 65535)) {
      throw InvalidUrlFailure(InvalidUrlReason.malformed);
    }
    return uri;
  }
}
