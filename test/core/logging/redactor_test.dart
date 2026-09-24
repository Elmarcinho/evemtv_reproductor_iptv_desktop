// Todos los datos de este archivo son ficticios. Se usan dominios reservados
// (example.com, .invalid) y credenciales inventadas.
import 'dart:convert';

import 'package:evemtv/core/errors/app_failure.dart';
import 'package:evemtv/core/logging/app_logger.dart';
import 'package:evemtv/core/logging/redactor.dart';
import 'package:flutter_test/flutter_test.dart';

/// Verifica que ninguno de [secrets] sobreviva en [text].
void expectNoLeak(String text, List<String> secrets) {
  for (final s in secrets) {
    expect(text, isNot(contains(s)), reason: 'se filtró "$s" en: $text');
  }
}

void main() {
  tearDown(Redactor.clearSecrets);

  group('Patrones – rutas de reproducción', () {
    test('enmascara en vivo, película, serie y timeshift', () {
      const cases = {
        'http://panel.example.com:8080/live/usuarioX/claveY/123.m3u8':
            'http://panel.example.com:8080/live/***/***/123.m3u8',
        'https://panel.example.com/movie/usuarioX/claveY/45.mkv':
            'https://panel.example.com/movie/***/***/45.mkv',
        'http://panel.example.com/series/usuarioX/claveY/9.mp4':
            'http://panel.example.com/series/***/***/9.mp4',
        'http://panel.example.com/timeshift/usuarioX/claveY/60/2026-01-01:10-00/7.ts': 'http://panel.example.com/timeshift/***/***/60/2026-01-01:10-00/7.ts',
      };
      cases.forEach((input, expected) {
        expect(Redactor.redact(input), expected);
      });
    });

    test('varias URLs en un mismo mensaje', () {
      expect(
        Redactor.redact(
          'fallo /live/a1b2c/d3e4f/1.ts, otra /live/a1b2c/d3e4f/1.m3u8',
        ),
        'fallo /live/***/***/1.ts, otra /live/***/***/1.m3u8',
      );
    });

    test('barras escapadas de JSON', () {
      expect(
        Redactor.redact(
          r'{"url":"http:\/\/panel.example.com\/live\/usuarioX\/claveY\/1.ts"}',
        ),
        r'{"url":"http:\/\/panel.example.com\/live\/***\/***\/1.ts"}',
      );
    });

    test('ruta codificada con %2F y %2f', () {
      for (final input in [
        'u=http%3A%2F%2Fpanel.example.com%2Flive%2FusuarioX%2FclaveY%2F1.ts',
        'u=http%3a%2f%2fpanel.example.com%2flive%2fusuarioX%2fclaveY%2f1.ts',
      ]) {
        expectNoLeak(Redactor.redact(input), ['usuarioX', 'claveY']);
      }
    });
  });

  group('Patrones – query y formularios', () {
    test('username y password en la query', () {
      expect(
        Redactor.redact(
          'http://panel.example.com/player_api.php?username=usuarioX&password=claveY&action=get_live_streams',
        ),
        'http://panel.example.com/player_api.php?username=***&password=***&action=get_live_streams',
      );
    });

    test('M3U get.php y token, sin importar mayúsculas', () {
      expect(
        Redactor.redact(
          'https://lista.invalid/get.php?USERNAME=abc&Password=def&type=m3u_plus&token=xyz',
        ),
        'https://lista.invalid/get.php?USERNAME=***&Password=***&type=m3u_plus&token=***',
      );
    });

    test('claves con letras codificadas (%75sername, %70assword)', () {
      expect(
        Redactor.redact(
          'https://lista.invalid/get.php?%75sername=usuarioX&%70assword=claveY',
        ),
        'https://lista.invalid/get.php?%75sername=***&%70assword=***',
      );
    });

    test('cuerpo de formulario', () {
      expect(
        Redactor.redact('username=usuarioX&password=claveY'),
        'username=***&password=***',
      );
    });

    test('credenciales en la URL, también escapadas o codificadas', () {
      expect(
        Redactor.redact('http://usuarioX:claveY@panel.example.com/lista.m3u'),
        'http://***@panel.example.com/lista.m3u',
      );
      expectNoLeak(
        Redactor.redact(r'"http:\/\/usuarioX:claveY@panel.example.com"'),
        ['usuarioX', 'claveY'],
      );
      expectNoLeak(
        Redactor.redact('http%3A%2F%2FusuarioX:claveY@panel.example.com'),
        ['usuarioX', 'claveY'],
      );
    });
  });

  group('Patrones – JSON', () {
    test('valores con comillas, escapes y numéricos', () {
      const cases = {
        '{"username":"usuarioX","password":"claveY"}':
            '{"username":"***","password":"***"}',
        '{"username" : "usuarioX", "password": 12345}':
            '{"username" : "***", "password": ***}',
        r'{"password":"cla\"veY","x":1}': '{"password":"***","x":1}',
      };
      cases.forEach((input, expected) {
        expect(Redactor.redact(input), expected);
      });
    });

    test('no confunde claves parecidas ni toca texto normal', () {
      const json = '{"user_info":{"status":"Active"},"auth_mode":2}';
      expect(Redactor.redact(json), json);
      const text = 'Categorías cargadas: 42 (https://example.com/logo.png)';
      expect(Redactor.redact(text), text);
    });
  });

  // Casos del informe de Codex sobre 4ddb18c, uno por categoría.
  group('Informe Codex', () {
    test('no decodificar: %26 dentro del valor no corta el campo', () {
      // Antes: se decodificaba a "?password=abc&def" y "def" quedaba afuera.
      expect(Redactor.redact('?password=abc%26def&x=1'), '?password=***&x=1');
    });

    test('no decodificar: un campo codificado se cubre con el secreto', () {
      // Sin decodificar, "password%3D" no se interpreta como clave; lo que
      // protege el valor es el registro del secreto (primera barrera aparte).
      Redactor.registerSecret('claveY');
      expect(
        Redactor.redact('?q=nota%26password%3DclaveY&x=1'),
        '?q=nota%26password%3D***&x=1',
      );
    });

    test('un secreto corto no corrompe la codificación de otro', () {
      Redactor.registerSecret('2F');
      Redactor.registerSecret('usu/ario');
      expect(Redactor.redact('/x/usu%2Fario/9'), '/x/***/9');
      // "2F" dentro de una secuencia %XX no se toca.
      expect(Redactor.redact('ruta%2Fotra'), 'ruta%2Fotra');
      // Como token completo sí.
      expect(Redactor.redact('/2F/'), '/***/');
    });

    test('doble codificación sin saltar representaciones intermedias', () {
      const secret = 'cla ve/ñ&1';
      Redactor.registerSecret(secret);
      final single = Uri.encodeComponent(secret);
      final double = Uri.encodeComponent(single);
      for (final v in [
        secret,
        single,
        single.toLowerCase(),
        double,
        Uri.encodeComponent(single.toLowerCase()),
        Uri.encodeQueryComponent(secret),
      ]) {
        expect(Redactor.redact('a=$v;'), 'a=***;', reason: v);
      }
    });

    test(', ; ) no terminan un valor de query', () {
      expect(
        Redactor.redact('?password=abc,def;ghi)jkl&x=1'),
        '?password=***&x=1',
      );
      expect(
        Redactor.redact('GET /get.php?username=u,1;2)3 HTTP/1.1'),
        'GET /get.php?username=*** HTTP/1.1',
      );
    });

    test('escapes JSON \\n y \\\\ no ocultan un secreto corto', () {
      Redactor.registerSecret('ab');
      expect(
        Redactor.redact(r'{"nota":"linea\nab"}'),
        r'{"nota":"linea\n***"}',
      );
      expect(Redactor.redact(r'{"ruta":"c:\\ab"}'), r'{"ruta":"c:\\***"}');
      expect(Redactor.redact(r'{"x":"\"ab\""}'), r'{"x":"\"***\""}');
      // Dentro de una palabra no se toca.
      expect(Redactor.redact('tabla'), 'tabla');
    });

    test('secreto con \\uXXXX, comillas, barras invertidas y barras', () {
      const secret = 'añ"o\\x/1';
      Redactor.registerSecret(secret);
      final json = jsonEncode({'v': secret});
      expectNoLeak(Redactor.redact(json), [r'a\u00f1', 'añ']);
      expect(Redactor.redact(r'{"v":"a\u00f1\"o\\x\/1"}'), '{"v":"***"}');
      expect(Redactor.redact(r'{"v":"a\u00F1\"o\\x\/1"}'), '{"v":"***"}');
      expect(Redactor.redact(json), '{"v":"***"}');
    });
  });

  group('Secretos registrados', () {
    test('formato corto {url}/{u}/{p}/{id}', () {
      Redactor.registerSecret('usuarioFicticio');
      Redactor.registerSecret('claveFicticia');
      expect(
        Redactor.redact(
          'http://panel.example.com/usuarioFicticio/claveFicticia/99',
        ),
        'http://panel.example.com/***/***/99',
      );
    });

    test('secretos antes que patrones: valor con espacios', () {
      Redactor.registerSecret('clave con espacios');
      final out = Redactor.redact('?password=clave con espacios&x=1');
      expect(out, '?password=***&x=1');
      expectNoLeak(out, ['clave', 'con', 'espacios']);
    });

    test('secreto con % literal', () {
      Redactor.registerSecret('ab%41cd');
      expect(Redactor.redact('valor ab%41cd fin'), 'valor *** fin');
    });

    test('secretos cortos solo como token completo', () {
      Redactor.registerSecret('ab');
      Redactor.registerSecret('7');
      expect(
        Redactor.redact('http://panel.example.com/ab/7/99'),
        'http://panel.example.com/***/***/99',
      );
      expect(Redactor.redact('tabla 77'), 'tabla 77');
    });

    test('clearSecrets olvida los secretos', () {
      Redactor.registerSecret('claveFicticia');
      Redactor.clearSecrets();
      expect(Redactor.redact('claveFicticia'), 'claveFicticia');
    });
  });

  group('AppLogger', () {
    late List<String> captured;
    late LogSink originalSink;
    late LogLevel originalLevel;
    late bool originalRelease;

    setUp(() {
      captured = [];
      originalSink = AppLogger.sink;
      originalLevel = AppLogger.minLevel;
      originalRelease = AppLogger.releaseMode;
      AppLogger.sink = (level, message) => captured.add(message);
      AppLogger.minLevel = LogLevel.debug;
    });

    tearDown(() {
      AppLogger.sink = originalSink;
      AppLogger.minLevel = originalLevel;
      AppLogger.releaseMode = originalRelease;
    });

    test('event arma una línea estructurada', () {
      AppLogger.event('player.open', {
        'kind': LogLevel.info,
        'stream_id': 123,
        'format': 'ts',
      });
      expect(captured.single, 'player.open kind=info stream_id=123 format=ts');
    });

    test('event igual redacta si alguien pasa una URL por error', () {
      AppLogger.event('x', {
        'u': 'http://h.example.com/live/usuarioX/claveY/1.ts',
      });
      expectNoLeak(captured.single, ['usuarioX', 'claveY']);
    });

    test('redacta mensaje y error en debug', () {
      AppLogger.e(
        'No se pudo abrir http://panel.example.com/live/usuarioX/claveY/1.ts',
        Exception('GET /player_api.php?username=usuarioX&password=claveY'),
      );
      expectNoLeak(captured.single, ['usuarioX', 'claveY']);
    });

    test('de un AppFailure solo registra tipo, detalle y tipo de la causa', () {
      AppLogger.e(
        'Login',
        const InvalidResponseFailure(
          detail: 'HTTP 200',
          cause: FormatException('{"secreto":"respuesta cruda"}'),
        ),
      );
      expect(
        captured.single,
        'Login | InvalidResponseFailure | HTTP 200 | causa: FormatException',
      );
    });

    test('en release, de un error externo solo registra el tipo', () {
      AppLogger.releaseMode = true;
      AppLogger.e('Fallo', StateError('respuesta cruda del servidor'));
      expect(captured.single, 'Fallo | StateError');
    });

    test('en debug recorta errores largos', () {
      AppLogger.e('Fallo', Exception('x' * 1000));
      expect(captured.single.length, lessThan(AppLogger.maxErrorLength + 50));
    });

    test('respeta el nivel mínimo', () {
      AppLogger.minLevel = LogLevel.warning;
      AppLogger.d('debug');
      AppLogger.i('info');
      AppLogger.w('warning');
      expect(captured, ['warning']);
    });
  });
}
