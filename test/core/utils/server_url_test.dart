// URLs ficticias con dominios reservados.
import 'package:evemtv/core/errors/app_failure.dart';
import 'package:evemtv/core/utils/server_url.dart';
import 'package:flutter_test/flutter_test.dart';

Matcher throwsUrl(InvalidUrlReason reason) =>
    throwsA(isA<InvalidUrlFailure>().having((f) => f.reason, 'reason', reason));

void main() {
  group('normalizeXtream', () {
    test('con y sin puerto, con y sin barra final, http y https', () {
      const cases = {
        'http://panel.example.com': 'http://panel.example.com',
        'http://panel.example.com/': 'http://panel.example.com',
        'http://panel.example.com:8080//': 'http://panel.example.com:8080',
        'HTTPS://Panel.Example.COM:8443': 'https://panel.example.com:8443',
        // El puerto por defecto se omite: es la misma dirección.
        '  http://panel.example.com:80  ': 'http://panel.example.com',
        'http://10.0.0.1:25461': 'http://10.0.0.1:25461',
      };
      cases.forEach((input, expected) {
        expect(ServerUrl.normalizeXtream(input).toString(), expected);
      });
    });

    test('quita endpoints pegados, query y fragmento', () {
      expect(
        ServerUrl.normalizeXtream(
          'http://panel.example.com:8080/player_api.php?username=a&password=b',
        ).toString(),
        'http://panel.example.com:8080',
      );
      expect(
        ServerUrl.normalizeXtream('http://panel.example.com/sub/get.php#x')
            .toString(),
        'http://panel.example.com/sub',
      );
    });

    test('rechaza entradas inválidas con el motivo correcto', () {
      expect(
        () => ServerUrl.normalizeXtream('  '),
        throwsUrl(InvalidUrlReason.empty),
      );
      expect(
        () => ServerUrl.normalizeXtream('http://panel example.com'),
        throwsUrl(InvalidUrlReason.containsSpaces),
      );
      expect(
        () => ServerUrl.normalizeXtream('panel.example.com:8080'),
        throwsUrl(InvalidUrlReason.unsupportedScheme),
      );
      expect(
        () => ServerUrl.normalizeXtream('ftp://panel.example.com'),
        throwsUrl(InvalidUrlReason.unsupportedScheme),
      );
      expect(
        () => ServerUrl.normalizeXtream('http://'),
        throwsUrl(InvalidUrlReason.malformed),
      );
      expect(
        () => ServerUrl.normalizeXtream('http://panel..example.com'),
        throwsUrl(InvalidUrlReason.malformed),
      );
      expect(
        () => ServerUrl.normalizeXtream('http://panel.example.com:99999'),
        throwsUrl(InvalidUrlReason.malformed),
      );
      expect(
        () => ServerUrl.normalizeXtream('http://u:p@panel.example.com'),
        throwsUrl(InvalidUrlReason.embeddedCredentials),
      );
    });
  });

  group('validatePlaylist', () {
    test('conserva ruta y query, quita el fragmento', () {
      expect(
        ServerUrl.validatePlaylist(
          'HTTP://Lista.Example.com/get.php?username=a&password=b&type=m3u_plus#x',
        ).toString(),
        'http://lista.example.com/get.php?username=a&password=b&type=m3u_plus',
      );
    });

    test('rechaza esquemas no http', () {
      expect(
        () => ServerUrl.validatePlaylist('file:///tmp/lista.m3u'),
        throwsUrl(InvalidUrlReason.unsupportedScheme),
      );
    });
  });

  group('tryExtractXtream', () {
    test('reconoce get.php con usuario y contraseña', () {
      final result = ServerUrl.tryExtractXtream(
        Uri.parse(
          'http://panel.example.com:8080/get.php?username=demo&password=clave&type=m3u_plus',
        ),
      );
      expect(result, isNotNull);
      expect(result!.server.toString(), 'http://panel.example.com:8080');
      expect(result.username, 'demo');
      expect(result.password, 'clave');
    });

    test('ignora otras listas', () {
      expect(
        ServerUrl.tryExtractXtream(
          Uri.parse('http://lista.example.com/canales.m3u'),
        ),
        isNull,
      );
      expect(
        ServerUrl.tryExtractXtream(
          Uri.parse('http://panel.example.com/get.php?username=demo'),
        ),
        isNull,
      );
    });
  });
}
