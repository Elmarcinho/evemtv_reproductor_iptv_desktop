// Todos los datos de este archivo son ficticios. Se usan dominios reservados
// (example.com, .invalid) y credenciales inventadas.
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

  group('Redactor – rutas de reproducción', () {
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

    test('enmascara varias URLs dentro de un mismo mensaje', () {
      final out = Redactor.redact(
        'fallo /live/a1b2c/d3e4f/1.ts, reintento /live/a1b2c/d3e4f/1.m3u8',
      );
      expect(out, 'fallo /live/***/***/1.ts, reintento /live/***/***/1.m3u8');
    });

    test('enmascara rutas con barras escapadas de JSON', () {
      final out = Redactor.redact(
        r'{"url":"http:\/\/panel.example.com\/live\/usuarioX\/claveY\/1.ts"}',
      );
      expectNoLeak(out, ['usuarioX', 'claveY']);
    });

    test('enmascara rutas codificadas (%2f en minúsculas y %2F)', () {
      for (final input in [
        'http%3a%2f%2fpanel.example.com%2flive%2fusuarioX%2fclaveY%2f1.ts',
        'http%3A%2F%2Fpanel.example.com%2Flive%2FusuarioX%2FclaveY%2F1.ts',
      ]) {
        expectNoLeak(Redactor.redact(input), ['usuarioX', 'claveY']);
      }
    });
  });

  group('Redactor – pares clave/valor', () {
    test('enmascara username y password en la query', () {
      final out = Redactor.redact(
        'http://panel.example.com/player_api.php?username=usuarioX&password=claveY&action=get_live_streams',
      );
      expect(
        out,
        'http://panel.example.com/player_api.php?username=***&password=***&action=get_live_streams',
      );
    });

    test('enmascara lista M3U (get.php) y tokens sin importar mayúsculas', () {
      final out = Redactor.redact(
        'https://lista.invalid/get.php?USERNAME=abc&Password=def&type=m3u_plus&token=xyz',
      );
      expect(
        out,
        'https://lista.invalid/get.php?USERNAME=***&Password=***&type=m3u_plus&token=***',
      );
    });

    test('enmascara claves de query codificadas (%75sername, %70assword)', () {
      final out = Redactor.redact(
        'https://lista.invalid/get.php?%75sername=usuarioX&%70assword=claveY',
      );
      expectNoLeak(out, ['usuarioX', 'claveY']);
    });

    test('enmascara valores doblemente codificados', () {
      final out = Redactor.redact(
        'https://lista.invalid/get.php?username%253DusuarioX%2526password%253DclaveY',
      );
      expectNoLeak(out, ['usuarioX', 'claveY']);
    });

    test('enmascara JSON con comillas dobles, simples y valores numéricos', () {
      final cases = {
        '{"username":"usuarioX","password":"claveY"}':
            '{"username":"***","password":"***"}',
        '{"username" : "usuarioX", "password": 12345}':
            '{"username" : "***", "password": ***}',
        "{'user': 'usuarioX', 'pass': 'claveY'}":
            "{'user': '***', 'pass': '***'}",
        r'{"password":"cla\"veY"}': '{"password":"***"}',
      };
      cases.forEach((input, expected) {
        expect(Redactor.redact(input), expected);
      });
    });

    test('enmascara mapas de Dart y cuerpos de formulario', () {
      expectNoLeak(Redactor.redact('{username: usuarioX, password: claveY}'), [
        'usuarioX',
        'claveY',
      ]);
      expectNoLeak(Redactor.redact('username=usuarioX&password=claveY'), [
        'usuarioX',
        'claveY',
      ]);
    });

    test('enmascara credenciales embebidas en la URL', () {
      expect(
        Redactor.redact('http://usuarioX:claveY@panel.example.com/lista.m3u'),
        'http://***@panel.example.com/lista.m3u',
      );
    });

    test('no altera texto sin credenciales', () {
      const text = 'Categorías cargadas: 42 (https://example.com/logo.png)';
      expect(Redactor.redact(text), text);
    });

    test('no confunde claves parecidas (user_info, auth_mode)', () {
      const text = '{"user_info":{"status":"Active"},"auth_mode":2}';
      expect(Redactor.redact(text), text);
    });
  });

  group('Redactor – secretos registrados', () {
    test('enmascara el formato corto {url}/{u}/{p}/{id}', () {
      Redactor.registerSecret('usuarioFicticio');
      Redactor.registerSecret('claveFicticia');
      expect(
        Redactor.redact(
          'http://panel.example.com/usuarioFicticio/claveFicticia/99',
        ),
        'http://panel.example.com/***/***/99',
      );
    });

    test('secretos antes que patrones: valor con espacios en la query', () {
      Redactor.registerSecret('clave con espacios');
      final out = Redactor.redact('?password=clave con espacios&x=1');
      expect(out, '?password=***&x=1');
      expectNoLeak(out, ['clave', 'con', 'espacios']);
    });

    test('enmascara la versión codificada para URL (+, %20 y minúsculas)', () {
      Redactor.registerSecret('clave con espacios&signos');
      for (final encoded in [
        Uri.encodeQueryComponent('clave con espacios&signos'),
        Uri.encodeComponent('clave con espacios&signos'),
        Uri.encodeComponent('clave con espacios&signos').toLowerCase(),
      ]) {
        final out = Redactor.redact('error en ?x=$encoded');
        expect(out, 'error en ?x=***', reason: encoded);
      }
    });

    test('enmascara secretos que contienen % literal', () {
      Redactor.registerSecret('ab%41cd');
      expectNoLeak(Redactor.redact('valor ab%41cd fin'), ['ab%41cd']);
    });

    test('enmascara secretos cortos cuando aparecen como palabra', () {
      Redactor.registerSecret('ab');
      Redactor.registerSecret('7');
      expect(
        Redactor.redact('http://panel.example.com/ab/7/99'),
        'http://panel.example.com/***/***/99',
      );
      // Dentro de otra palabra no se tocan, para no destruir el log.
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

    test('redacta mensaje y error', () {
      AppLogger.e(
        'No se pudo abrir http://panel.example.com/live/usuarioX/claveY/1.ts',
        Exception('GET /player_api.php?username=usuarioX&password=claveY'),
      );
      expect(captured, hasLength(1));
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

    test('en release, de un error arbitrario solo registra el tipo', () {
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
