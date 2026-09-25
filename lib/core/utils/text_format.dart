/// Formatos de texto para mostrar, en español.
abstract final class TextFormat {
  /// Año que muchos paneles pegan al nombre: `" (2026)"`, `" [2026]"` o
  /// `" - 2026"` al final.
  static final RegExp _trailingYear = RegExp(
    r'\s*(?:[\(\[]\d{4}[\)\]]|[-–]\s*\d{4})\s*$',
  );

  /// Nombre sin el año del final (se muestra aparte, no dos veces). Si el
  /// nombre es solo el año, se deja como está.
  static String withoutYear(String name) {
    final clean = name.replaceFirst(_trailingYear, '').trim();
    return clean.isEmpty ? name : clean;
  }

  /// Etiquetas técnicas que los paneles pegan al final del nombre.
  static final RegExp _trailingTag = RegExp(
    r'[\s\-–|·]*\b(?:fhd|hd|uhd|sd|4k|8k|hdr|1080p|720p|480p|latino|'
    r'castellano|español|subtitulado|sub|subs|dual|esp|eng|multi|cam|ts)'
    r'\s*$',
    caseSensitive: false,
  );

  /// Nombre limpio para mostrar: sin etiquetas técnicas ("FHD", "Latino",
  /// "4K"…) ni el año del final. "Robin Hood (2026) FHD Latino" →
  /// "Robin Hood". Si no queda nada, se deja como está.
  static String displayName(String name) {
    var current = name.trim();
    while (true) {
      final next = withoutYear(current.replaceFirst(_trailingTag, ''))
          .replaceFirst(RegExp(r'[\s\-–|·]+$'), '');
      if (next == current || next.isEmpty) break;
      current = next;
    }
    return current.isEmpty ? name : current;
  }

  /// `1240` → `1.240`.
  static String thousands(int n) {
    final digits = n.abs().toString();
    final buffer = StringBuffer(n < 0 ? '-' : '');
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write('.');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }
}
