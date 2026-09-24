/// Lectura tolerante de JSON.
///
/// Los paneles Xtream devuelven tipos inconsistentes: números como texto,
/// `null`, `""`, `[]` donde se esperaba un objeto, booleanos como `1`/`"1"`.
/// Estas funciones nunca lanzan: ante un valor raro devuelven `null` o un
/// valor vacío, y el modelo decide el valor por defecto.
abstract final class JsonRead {
  /// Texto recortado. Números y booleanos se convierten; `""` y `"null"`
  /// cuentan como ausentes.
  static String? string(Object? value) {
    final String text;
    if (value is String) {
      text = value.trim();
    } else if (value is num || value is bool) {
      text = value.toString();
    } else {
      return null;
    }
    if (text.isEmpty || text.toLowerCase() == 'null') return null;
    return text;
  }

  /// Entero desde `int`, `double`, `"12"`, `"12.0"` o `true`/`false`.
  static int? integer(Object? value) {
    if (value is int) return value;
    if (value is double) return value.isFinite ? value.toInt() : null;
    if (value is bool) return value ? 1 : 0;
    final text = string(value);
    if (text == null) return null;
    return int.tryParse(text) ?? double.tryParse(text)?.toInt();
  }

  /// Booleano desde `true`, `1`, `"1"`, `"true"`, `"yes"`.
  static bool boolean(Object? value, {bool fallback = false}) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    final text = string(value)?.toLowerCase();
    if (text == null) return fallback;
    if (const {'1', 'true', 'yes', 'si', 'sí'}.contains(text)) return true;
    if (const {'0', 'false', 'no'}.contains(text)) return false;
    return fallback;
  }

  /// Objeto JSON. Un `[]` vacío (muy común en lugar de `{}`) devuelve `null`.
  static Map<String, Object?>? map(Object? value) {
    if (value is! Map) return null;
    return {
      for (final entry in value.entries) entry.key.toString(): entry.value,
    };
  }

  /// Lista JSON. Si llega un objeto con claves numéricas (otra rareza de
  /// algunos paneles) se usan sus valores. Cualquier otra cosa: lista vacía.
  static List<Object?> list(Object? value) {
    if (value is List) return value.cast<Object?>();
    if (value is Map) return value.values.cast<Object?>().toList();
    return const [];
  }

  /// Lista de textos no vacíos.
  static List<String> stringList(Object? value) => [
    for (final item in list(value)) ?string(item),
  ];

  /// Fecha desde segundos Unix (`1767139200` o `"1767139200"`). `0`, vacío
  /// o `null` significan "sin fecha".
  static DateTime? unixSeconds(Object? value) {
    final seconds = integer(value);
    if (seconds == null || seconds <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
  }
}
