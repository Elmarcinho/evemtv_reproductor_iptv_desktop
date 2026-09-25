import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../theme/app_theme.dart';

/// Firma "Desarrollado por …" al pie de las pantallas principales.
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
        child: Text(
          'Desarrollado por ${AppConfig.developer}',
          textAlign: TextAlign.center,
          style: style,
        ),
      ),
    );
  }
}
