import 'package:evemtv/features/player/tls_ca_bundle.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('paquete de certificados propio: Windows, macOS y el AppImage', () {
    bool needed(String os, [Map<String, String> env = const {}]) =>
        TlsCaBundle.neededFor(os: os, environment: env);
    expect(needed('windows'), isTrue);
    expect(needed('macos'), isTrue);
    expect(needed('linux'), isFalse, reason: 'libmpv de la distribución');
    expect(
      needed('linux', {'APPIMAGE': '/home/demo/EvemTv-1.0.0-x86_64.AppImage'}),
      isTrue,
      reason: 'libmpv incluido en el AppImage',
    );
    expect(needed('linux', {'APPIMAGE': ''}), isFalse);
  });
}
