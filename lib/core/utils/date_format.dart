/// Formato de fechas en español sin dependencias externas.
abstract final class DateFormatEs {
  static String _two(int n) => n.toString().padLeft(2, '0');

  /// `31/12/2026`, en hora local.
  static String date(DateTime value) {
    final d = value.toLocal();
    return '${_two(d.day)}/${_two(d.month)}/${d.year}';
  }

  /// `18:05`, en hora local.
  static String time(DateTime value) {
    final d = value.toLocal();
    return '${_two(d.hour)}:${_two(d.minute)}';
  }

  /// `31/12/2026 18:05`, en hora local.
  static String dateTime(DateTime value) {
    final d = value.toLocal();
    return '${date(d)} ${_two(d.hour)}:${_two(d.minute)}';
  }

  /// "vence hoy", "en 1 día", "en 23 días", "hace 3 días".
  static String relativeDays(DateTime value, {DateTime? now}) {
    final today = _day(now ?? DateTime.now());
    final target = _day(value.toLocal());
    final diff = target.difference(today).inDays;
    if (diff == 0) return 'hoy';
    if (diff == 1) return 'mañana';
    if (diff == -1) return 'ayer';
    if (diff > 0) return 'en $diff días';
    return 'hace ${-diff} días';
  }

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Duración de reproducción: `1:05:09` o `5:09`.
  static String clock(Duration d) {
    final total = d.isNegative ? 0 : d.inSeconds;
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final sec = total % 60;
    return h > 0 ? '$h:${_two(m)}:${_two(sec)}' : '$m:${_two(sec)}';
  }

  /// Duración legible: `1 h 45 min` o `50 min`.
  static String runtime(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    if (h == 0) return '$m min';
    return m == 0 ? '$h h' : '$h h $m min';
  }
}
