import 'dart:convert';

/// Segunda barrera contra fugas de credenciales en los logs.
///
/// La primera barrera es no registrar nunca URLs, cuerpos de respuesta ni
/// textos externos crudos (ver `AppLogger.event`). Este redactor cubre lo que
/// se escape a esa regla. Modelo de amenaza y riesgo residual aceptado:
/// `docs/decisiones.md`.
///
/// Diseño deliberadamente simple: **nunca decodifica la entrada**.
/// 1. Cada secreto registrado se expande al registrarse en sus
///    representaciones habituales (literal, percent-encoding en mayúsculas y
///    minúsculas, doble codificación, escape JSON con `\uXXXX` y barras
///    escapadas) y se reemplazan todas, de la más larga a la más corta.
/// 2. Después se aplican patrones independientes por formato (rutas Xtream,
///    query/formulario, JSON, credenciales en la URL), también sin decodificar.
class Redactor {
  Redactor._();

  static const String mask = '***';

  /// Secretos más cortos se reemplazan solo como token completo: reemplazar
  /// cada aparición de una contraseña "1" destruiría el log.
  static const int shortSecretLength = 3;

  /// Variante → expresión compilada, ordenadas de la más larga a la más corta.
  static final Map<String, RegExp> _secretPatterns = <String, RegExp>{};
  static List<RegExp> _ordered = const [];

  /// Límite izquierdo de un token: inicio del texto, un carácter que no es
  /// alfanumérico ni `%` ni `\`, o justo después de una secuencia completa
  /// `%XX`, un escape JSON (`\n`, `\\`, `\"`, `\/`…) o un `\uXXXX`. Así un
  /// secreto corto nunca empieza dentro de una secuencia `%XX`.
  static const String _tokenStart =
      r'(?:^|(?<=[^A-Za-z0-9%\\])|(?<=%[0-9A-Fa-f]{2})'
      r'|(?<=\\[nrtbf"\\/])|(?<=\\u[0-9A-Fa-f]{4}))';
  static const String _tokenEnd = r'(?![A-Za-z0-9])';

  static const List<String> _sensitiveKeys = [
    'username',
    'password',
    'passwd',
    'pass',
    'pwd',
    'user',
    'token',
    'auth',
    'key',
  ];

  static const String _streamKinds = '(live|movie|series|timeshift)';

  /// `/live/u/p/`, sin decodificar.
  static final RegExp _pathPlain = RegExp(
    '/$_streamKinds/[^/\\s?#"\'\\\\]+/[^/\\s?#"\'\\\\]+/',
    caseSensitive: false,
  );

  /// `\/live\/u\/p\/` (barras escapadas de JSON).
  static final RegExp _pathJson = RegExp(
    r'\\/'
    '$_streamKinds'
    r'\\/(?:(?!\\/)[^\s"])+\\/(?:(?!\\/)[^\s"])+\\/',
    caseSensitive: false,
  );

  /// `%2Flive%2Fu%2Fp%2F` (mayúsculas o minúsculas).
  static final RegExp _pathEncoded = RegExp(
    '%2F$_streamKinds%2F(?:(?!%2F)[^\\s/?#&"\'])+%2F(?:(?!%2F)[^\\s/?#&"\'])+%2F',
    caseSensitive: false,
  );

  /// Query o formulario: `?password=…`, `&user=…`, `password=…` al inicio o
  /// tras un espacio. La clave puede venir con letras codificadas
  /// (`%70assword`). El valor llega hasta `&`, `#`, espacio o comilla: `,`
  /// `;` y `)` son parte del valor.
  static final RegExp _queryPair = RegExp(
    '((?:^|[?&\\s])(?:${_sensitiveKeys.map(_encodableKey).join('|')})=)'
    '[^&#\\s"\']*',
    caseSensitive: false,
  );

  /// JSON: `"password": "…"` (con escapes) o `"password": 123`.
  static final RegExp _jsonPair = RegExp(
    '("(?:${_sensitiveKeys.join('|')})"\\s*:\\s*)'
    r'("(?:[^"\\]|\\.)*"|[^,}\]\s]+)',
    caseSensitive: false,
  );

  /// `esquema://usuario:clave@`, también con `:\/\/` o `%3A%2F%2F`.
  static final RegExp _userInfo = RegExp(
    r'([a-z][a-z0-9+.\-]*(?::\/\/|:\\\/\\\/|%3A%2F%2F))[^/@\s"\\]+@',
    caseSensitive: false,
  );

  /// `username` → `(?:u|%75)(?:s|%73)…` para aceptar letras codificadas.
  static String _encodableKey(String key) => key.codeUnits
      .map(
        (c) =>
            '(?:${String.fromCharCode(c)}|%${c.toRadixString(16).padLeft(2, '0')})',
      )
      .join();

  /// Registra un valor que nunca debe aparecer en logs (usuario, contraseña,
  /// URL del perfil activo) junto con todas sus variantes.
  static void registerSecret(String? value) {
    if (value == null || value.isEmpty) return;
    final short = value.length < shortSecretLength;
    for (final variant in variantsOf(value)) {
      final escaped = RegExp.escape(variant);
      _secretPatterns[variant] = RegExp(
        short ? '$_tokenStart$escaped$_tokenEnd' : escaped,
      );
    }
    final keys = _secretPatterns.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    _ordered = [for (final k in keys) _secretPatterns[k]!];
  }

  /// Olvida todos los secretos registrados (al cerrar sesión o cambiar perfil).
  static void clearSecrets() {
    _secretPatterns.clear();
    _ordered = const [];
  }

  /// Representaciones de [secret] que se buscan en el texto.
  static Set<String> variantsOf(String secret) {
    final out = <String>{secret};

    // Percent-encoding: componente y query (+ para espacios), en mayúsculas
    // y minúsculas, y doble codificación de cada una.
    for (final single in {
      Uri.encodeComponent(secret),
      Uri.encodeQueryComponent(secret),
      secret.replaceAll(' ', '+'),
    }) {
      for (final s in {single, _lowerHex(single)}) {
        out.add(s);
        final dbl = Uri.encodeComponent(s);
        out
          ..add(dbl)
          ..add(_lowerHex(dbl));
      }
    }

    // JSON: escapes estándar (\" \\ \n …) combinados con barras escapadas
    // (\/) y no-ASCII como \uXXXX en minúsculas o mayúsculas. PHP, el
    // lenguaje de los paneles Xtream, usa por defecto \/ y \uXXXX a la vez.
    // Además, la forma con \uXXXX para todo lo que no es alfanumérico.
    final json = jsonEncode(secret);
    final jsonBody = json.substring(1, json.length - 1);
    out.add(secret.replaceAll('/', r'\/'));
    for (final body in {
      jsonBody,
      _escapeNonAscii(jsonBody, upper: false),
      _escapeNonAscii(jsonBody, upper: true),
    }) {
      out
        ..add(body)
        ..add(body.replaceAll('/', r'\/'));
    }
    out
      ..add(_escapeAllSymbols(secret, upper: false))
      ..add(_escapeAllSymbols(secret, upper: true));
    out.remove('');
    return out;
  }

  static final RegExp _hexSeq = RegExp(r'%[0-9A-F]{2}');

  static String _lowerHex(String s) =>
      s.replaceAllMapped(_hexSeq, (m) => m[0]!.toLowerCase());

  static final RegExp _alnum = RegExp(r'[A-Za-z0-9]');

  static String _hex4(int unit, {required bool upper}) {
    final hex = unit.toRadixString(16).padLeft(4, '0');
    return '\\u${upper ? hex.toUpperCase() : hex}';
  }

  /// Caracteres fuera de ASCII como `\uXXXX`; el resto sin cambios.
  static String _escapeNonAscii(String s, {required bool upper}) =>
      String.fromCharCodes(
        s.codeUnits.expand((u) {
          return u < 0x7F ? [u] : _hex4(u, upper: upper).codeUnits;
        }),
      );

  /// Todo lo que no es alfanumérico ASCII como `\uXXXX`.
  static String _escapeAllSymbols(String s, {required bool upper}) {
    final b = StringBuffer();
    for (final unit in s.codeUnits) {
      final ch = String.fromCharCode(unit);
      b.write(_alnum.hasMatch(ch) ? ch : _hex4(unit, upper: upper));
    }
    return b.toString();
  }

  /// Devuelve [input] con todas las credenciales conocidas enmascaradas.
  static String redact(String input) {
    if (input.isEmpty) return input;
    var out = input;
    // Secretos primero, de la variante más larga a la más corta: un patrón
    // podría cortar un valor con espacios y dejar el resto sin cubrir, y un
    // secreto corto no debe tocar la codificación de uno más largo.
    for (final pattern in _ordered) {
      out = out.replaceAll(pattern, mask);
    }
    return out
        .replaceAllMapped(_pathPlain, (m) => '/${m[1]}/$mask/$mask/')
        .replaceAllMapped(_pathJson, (m) => '\\/${m[1]}\\/$mask\\/$mask\\/')
        .replaceAllMapped(_pathEncoded, (m) => '%2F${m[1]}%2F$mask%2F$mask%2F')
        .replaceAllMapped(_queryPair, (m) => '${m[1]}$mask')
        .replaceAllMapped(
          _jsonPair,
          (m) => '${m[1]}${m[2]!.startsWith('"') ? '"$mask"' : mask}',
        )
        .replaceAllMapped(_userInfo, (m) => '${m[1]}$mask@');
  }

  /// Versión segura de `toString()` para objetos arbitrarios.
  static String redactObject(Object? value) =>
      value == null ? 'null' : redact(value.toString());
}
