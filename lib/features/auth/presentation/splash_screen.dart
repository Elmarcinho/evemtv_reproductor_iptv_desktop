import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/state_views.dart';
import '../application/terms_controller.dart';

/// Pantalla de arranque mientras se abre la base local.
class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final terms = ref.watch(termsProvider);
    return Scaffold(
      body: terms.hasError
          ? ErrorView(
              error: terms.error!,
              onRetry: () => ref.invalidate(termsProvider),
            )
          : const Center(child: AppLogo(size: 48)),
    );
  }
}
