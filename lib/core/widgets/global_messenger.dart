import 'package:flutter/material.dart';

/// Mensajero global: muestra avisos que deben sobrevivir a un cambio de
/// pantalla (p. ej. una limpieza incompleta al cerrar sesión, cuando el
/// inicio ya no existe).
final rootMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// Muestra [message] con el mensajero global.
void showGlobalMessage(String message) => rootMessengerKey.currentState
    ?.showSnackBar(SnackBar(content: Text(message)));
