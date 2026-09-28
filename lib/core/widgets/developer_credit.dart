import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../theme/app_theme.dart';

/// Firma con la versión ("EvemTv 1.0.1 · Desarrollado por …") al pie de
/// las pantallas principales.
class DeveloperCredit extends StatelessWidget {
  const DeveloperCredit({super.key});

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: AppColors.textSecondary.withValues(alpha: 0.7),
      letterSpacing: 0.4,
    );
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        // "EvemTv 1.0.1 · Desarrollado por Godebol": la versión a la vista
        // también sin entrar a una cuenta (cuentas, login e inicio).
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${AppConfig.appName} ${AppConfig.version} · ', style: style),
            Text('Desarrollado por ${AppConfig.developer}', style: style),
          ],
        ),
      ),
    );
  }
}
