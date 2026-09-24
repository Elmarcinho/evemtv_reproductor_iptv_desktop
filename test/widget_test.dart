import 'package:evemtv/app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('la app arranca con tema oscuro y muestra la pantalla base', (
    tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: EvemTvApp()));
    await tester.pumpAndSettle();

    expect(find.text('EvemTv'), findsOneWidget);
    expect(find.text('Iniciar sesión'), findsOneWidget);
  });
}
