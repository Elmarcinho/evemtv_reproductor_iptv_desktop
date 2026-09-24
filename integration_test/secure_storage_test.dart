// Prueba el almacén seguro REAL del sistema (Keychain en macOS, DPAPI en
// Windows, libsecret en Linux) con la misma configuración que la app.
// Sirve para detectar en CI problemas del Keychain con firma ad-hoc.
// Datos ficticios; la entrada se borra al terminar.
import 'package:evemtv/data/storage/secure_credential_store.dart';
import 'package:evemtv/data/storage/secure_storage_factory.dart';
import 'package:evemtv/domain/entities/source_credentials.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('escribe, lee y borra credenciales en el almacén del sistema', (
    tester,
  ) async {
    // Id alto para no pisar perfiles reales del equipo de desarrollo.
    const profileId = 987654321;
    final store = SecureCredentialStore(createSecureStorage());
    final credentials = XtreamCredentials(
      server: Uri.parse('http://panel.example.com:8080'),
      username: 'usuario_ficticio',
      password: 'clave ficticia ñ/&',
    );

    try {
      await store.write(profileId, credentials);
      final read = await store.read(profileId);
      expect(read, isA<XtreamCredentials>());
      read as XtreamCredentials;
      expect(read.username, credentials.username);
      expect(read.password, credentials.password);
      expect(read.server, credentials.server);
    } finally {
      await store.delete(profileId);
    }
    expect(await store.read(profileId), isNull);
  });
}
