import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/application/session.dart';
import '../../features/auth/application/terms_controller.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/profiles_screen.dart';
import '../../features/auth/presentation/splash_screen.dart';
import '../../features/auth/presentation/terms_screen.dart';
import '../../features/home/home_screen.dart';

abstract final class AppRoutes {
  static const String splash = '/splash';
  static const String terms = '/terms';
  static const String profiles = '/profiles';
  static const String login = '/login';
  static const String home = '/home';

  /// Pantallas accesibles sin sesión.
  static const Set<String> _public = {profiles, login};

  /// Decide a dónde ir según términos y sesión. Separado del router para
  /// poder probarlo sin interfaz.
  static String? redirect({
    required String location,
    required AsyncValue<bool> termsAccepted,
    required bool hasSession,
  }) {
    if (!termsAccepted.hasValue) return location == splash ? null : splash;
    if (termsAccepted.value != true) return location == terms ? null : terms;
    if (!hasSession) return _public.contains(location) ? null : profiles;
    return _public.contains(location) || location == splash || location == terms
        ? home
        : null;
  }
}

final appRouterProvider = Provider<GoRouter>((ref) {
  // Avisa al router cuando cambian términos o sesión para reevaluar la
  // redirección.
  final refresh = ValueNotifier<int>(0);
  ref
    ..listen(termsProvider, (_, _) => refresh.value++)
    ..listen(sessionProvider, (_, _) => refresh.value++);

  final router = GoRouter(
    initialLocation: AppRoutes.splash,
    refreshListenable: refresh,
    redirect: (context, state) => AppRoutes.redirect(
      location: state.matchedLocation,
      termsAccepted: ref.read(termsProvider),
      hasSession: ref.read(sessionProvider) != null,
    ),
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: AppRoutes.terms,
        builder: (context, state) => const TermsScreen(),
      ),
      GoRoute(
        path: AppRoutes.profiles,
        builder: (context, state) => const ProfilesScreen(),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: AppRoutes.home,
        builder: (context, state) => const HomeScreen(),
      ),
    ],
  );
  ref.onDispose(() {
    router.dispose();
    refresh.dispose();
  });
  return router;
});
