import 'package:evemtv/core/router/app_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  String? go(String location, AsyncValue<bool> terms, {bool session = false}) =>
      AppRoutes.redirect(
        location: location,
        termsAccepted: terms,
        hasSession: session,
      );

  const loading = AsyncLoading<bool>();
  const accepted = AsyncData(true);
  const pending = AsyncData(false);

  test('mientras carga, splash', () {
    expect(go(AppRoutes.home, loading), AppRoutes.splash);
    expect(go(AppRoutes.splash, loading), isNull);
    expect(
      go(AppRoutes.home, AsyncError<bool>('x', StackTrace.empty)),
      AppRoutes.splash,
    );
  });

  test('sin términos aceptados, términos', () {
    expect(go(AppRoutes.splash, pending), AppRoutes.terms);
    expect(go(AppRoutes.home, pending, session: true), AppRoutes.terms);
    expect(go(AppRoutes.terms, pending), isNull);
  });

  test('sin sesión, solo perfiles y login', () {
    expect(go(AppRoutes.splash, accepted), AppRoutes.profiles);
    expect(go(AppRoutes.home, accepted), AppRoutes.profiles);
    expect(go(AppRoutes.login, accepted), isNull);
    expect(go(AppRoutes.profiles, accepted), isNull);
  });

  test('con sesión, al inicio', () {
    expect(go(AppRoutes.login, accepted, session: true), AppRoutes.home);
    expect(go(AppRoutes.profiles, accepted, session: true), AppRoutes.home);
    expect(go(AppRoutes.home, accepted, session: true), isNull);
  });
}
