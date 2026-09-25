import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// Un atajo documentado.
typedef ShortcutDoc = ({String keys, String action});

/// Catálogo único de atajos: la ayuda (tecla ?) y el comportamiento de cada
/// pantalla salen de aquí, así no se desalinean.
///
/// Reglas comunes a toda la app:
/// - `?` o F1: ayuda de la pantalla. Esc: volver (o salir de pantalla
///   completa / cerrar el panel abierto).
/// - Ctrl+F: búsqueda global (en inicio, En vivo, Películas y Series).
/// - Listas y grillas: flechas para moverse, Enter para abrir o reproducir.
/// - Reproductores: Espacio pausa, F pantalla completa, M silencio.
abstract final class ShortcutCatalog {
  static const List<ShortcutDoc> general = [
    (keys: '? / F1', action: 'Mostrar esta ayuda'),
    (keys: 'Esc', action: 'Volver'),
    (keys: 'Tab / Mayús+Tab', action: 'Pasar de un elemento a otro'),
  ];

  static const List<ShortcutDoc> home = [
    (keys: 'Ctrl+F', action: 'Buscar en vivo, películas y series'),
    (keys: 'Flechas / Enter', action: 'Elegir una sección o seguir viendo'),
  ];

  static const List<ShortcutDoc> liveList = [
    (keys: '↑ / ↓', action: 'Recorrer canales (se reproduce al detenerse)'),
    (keys: 'Re Pág / Av Pág', action: 'Saltar de a 10 canales'),
    (keys: 'Enter', action: 'Pantalla completa'),
    (keys: 'Ctrl+F', action: 'Búsqueda global'),
  ];

  static const List<ShortcutDoc> livePlayer = [
    (keys: 'Espacio', action: 'Pausa / reanudar'),
    (keys: '↑ / ↓', action: 'Canal anterior / siguiente'),
    (keys: '← / →', action: 'Bajar / subir volumen'),
    (keys: 'M', action: 'Silenciar'),
    (keys: 'L', action: 'Lista de canales'),
    (keys: 'F', action: 'Pantalla completa'),
    (
      keys: 'Esc',
      action: 'Cerrar la lista, salir de pantalla completa o volver',
    ),
  ];

  static const List<ShortcutDoc> catalog = [
    (keys: 'Flechas', action: 'Moverse por la grilla'),
    (keys: 'Enter', action: 'Abrir la ficha'),
    (keys: 'Ctrl+F', action: 'Búsqueda global'),
  ];

  static const List<ShortcutDoc> detail = [
    (keys: 'Enter', action: 'Reproducir / continuar'),
    (keys: 'Tab', action: 'Pasar a favoritos, temporadas y episodios'),
  ];

  static const List<ShortcutDoc> vodPlayer = [
    (keys: 'Espacio', action: 'Pausa / reanudar'),
    (keys: '← / →', action: 'Retroceder / adelantar 10 s'),
    (keys: '↑ / ↓', action: 'Subir / bajar volumen'),
    (keys: 'M', action: 'Silenciar'),
    (keys: 'N', action: 'Siguiente episodio'),
    (keys: 'F', action: 'Pantalla completa'),
    (keys: 'Esc', action: 'Salir de pantalla completa o volver'),
  ];

  static const List<ShortcutDoc> search = [
    (keys: 'Escribir', action: 'Buscar (sin importar tildes ni mayúsculas)'),
    (keys: '↓ / Tab', action: 'Pasar a los resultados'),
    (keys: 'Enter', action: 'Abrir o reproducir el resultado'),
  ];
}

/// Muestra la ayuda de atajos de una pantalla.
Future<void> showKeyboardHelp(
  BuildContext context, {
  required String title,
  required List<ShortcutDoc> shortcuts,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Atajos de teclado · $title'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final s in [...shortcuts, ...ShortcutCatalog.general])
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 150,
                        child: Text(
                          s.keys,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: AppColors.accent,
                          ),
                        ),
                      ),
                      Expanded(child: Text(s.action)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          autofocus: true,
          onPressed: () => Navigator.pop(context),
          child: const Text('Cerrar'),
        ),
      ],
    ),
  );
}

/// Atajos de una pantalla + `?`/F1 para su ayuda.
class ScreenShortcuts extends StatelessWidget {
  const ScreenShortcuts({
    super.key,
    required this.title,
    required this.help,
    required this.child,
    this.bindings = const {},
  });

  final String title;
  final List<ShortcutDoc> help;
  final Map<ShortcutActivator, VoidCallback> bindings;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    void show() => showKeyboardHelp(context, title: title, shortcuts: help);
    return Shortcuts(
      shortcuts: const {
        CharacterActivator('?'): _HelpIntent(typed: true),
        SingleActivator(LogicalKeyboardKey.f1): _HelpIntent(typed: false),
      },
      child: Actions(
        actions: {_HelpIntent: _HelpAction(show)},
        child: CallbackShortcuts(bindings: bindings, child: child),
      ),
    );
  }
}

class _HelpIntent extends Intent {
  const _HelpIntent({required this.typed});

  /// Viene de una tecla que escribe texto (`?`).
  final bool typed;
}

/// `?` no abre la ayuda mientras se escribe en un campo de texto: la acción
/// se desactiva y la tecla llega al campo. F1 funciona siempre.
class _HelpAction extends Action<_HelpIntent> {
  _HelpAction(this._show);

  final VoidCallback _show;

  static bool get _editingText {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null) return false;
    return context.widget is EditableText ||
        context.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  @override
  bool isEnabled(_HelpIntent intent) => !(intent.typed && _editingText);

  @override
  Object? invoke(_HelpIntent intent) {
    _show();
    return null;
  }
}
