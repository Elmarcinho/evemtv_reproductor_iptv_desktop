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

  /// Mayor entero que un `double` representa con exactitud (2^53). Más allá
  /// la conversión pierde precisión o, en el caso extremo, lanza.
  static const int _maxSafeInteger = 9007199254740992;

  /// Entero desde `int`, `double`, `"12"`, `"12.0"` o `true`/`false`.
  /// `NaN`, infinitos y valores fuera de ±2^53 devuelven `null`.
  static int? integer(Object? value) {
    if (value is int) return value;
    if (value is double) return _fromDouble(value);
    if (value is bool) return value ? 1 : 0;
    final text = string(value);
    if (text == null) return null;
    return int.tryParse(text) ?? _fromDouble(double.tryParse(text));
  }

  static int? _fromDouble(double? value) {
    if (value == null || !value.isFinite) return null;
    if (value.abs() > _maxSafeInteger) return null;
    return value.toInt();
  }

  /// Decimal desde número o texto (`"7.5"`, `"7,5"`). `NaN` e infinitos
  /// devuelven `null`.
  static double? decimal(Object? value) {
    final double? parsed;
    if (value is num) {
      parsed = value.toDouble();
    } else {
      parsed = double.tryParse(string(value)?.replaceAll(',', '.') ?? '');
    }
    return (parsed == null || !parsed.isFinite) ? null : parsed;
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

  /// Límite de `DateTime` (±8,64e15 ms) expresado en segundos.
  static const int _maxUnixSeconds = 8640000000000;

  /// Fecha desde segundos Unix (`1767139200` o `"1767139200"`). `0`, vacío,
  /// `null` y valores fuera del rango de fechas significan "sin fecha".
  /// Se comprueba el rango **antes** de multiplicar para evitar desbordes.
  static DateTime? unixSeconds(Object? value) {
    final seconds = integer(value);
    if (seconds == null || seconds <= 0 || seconds > _maxUnixSeconds) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
  }
}
