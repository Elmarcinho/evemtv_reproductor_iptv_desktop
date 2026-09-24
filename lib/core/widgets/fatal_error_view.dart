import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';

/// Reemplazo de la pantalla roja de Flutter (también en debug): el mensaje
/// de la excepción podría incluir URLs o datos del usuario, así que se
/// muestra un texto fijo y el detalle va solo al logger, redactado.
///
/// Usa solo `widgets` (sin Material) porque puede construirse fuera del
/// árbol de `MaterialApp`.
class FatalErrorView extends StatelessWidget {
  const FatalErrorView({super.key});

  static const String message =
      'Algo salió mal al mostrar esta sección. Intenta volver atrás o '
      'reiniciar la aplicación.';

  @override
  Widget build(BuildContext context) {
    return const Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: AppColors.background,
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
            ),
          ),
        ),
      ),
    );
  }
}
