import 'dart:convert';

/// Hash FNV-1a de 64 bits en hexadecimal.
///
/// Da un identificador estable para un canal M3U sin guardar su URL (que
/// suele llevar credenciales). No es criptográfico: solo evita que la URL
/// quede en claro en la base local.
String stableHash(String input) {
  // FNV-1a 64 bits con aritmética de 64 bits de Dart (desborde modular).
  var hash = 0xcbf29ce484222325;
  const prime = 0x100000001b3;
  for (final byte in utf8.encode(input)) {
    hash ^= byte;
    hash *= prime;
  }
  // Los int de Dart tienen signo: se formatean las dos mitades de 32 bits
  // para obtener el valor sin signo.
  final high = (hash >>> 32).toRadixString(16).padLeft(8, '0');
  final low = (hash & 0xffffffff).toRadixString(16).padLeft(8, '0');
  return '$high$low';
}
