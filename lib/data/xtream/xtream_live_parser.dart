import 'dart:convert';

import '../../core/utils/json_read.dart';
import '../../domain/entities/live.dart';

/// Interpreta las respuestas de TV en vivo de Xtream de forma tolerante:
/// los elementos que no se pueden usar se omiten, nunca rompen la lista.
abstract final class XtreamLiveParser {
  /// `get_live_categories` → `[{category_id, category_name, parent_id}]`.
  static List<ContentCategory> categories(Object? json) => [
    for (final item in JsonRead.list(json)) ?_category(JsonRead.map(item)),
  ];

  static ContentCategory? _category(Map<String, Object?>? m) {
    if (m == null) return null;
    final id = JsonRead.string(m['category_id']);
    if (id == null) return null;
    return ContentCategory(
      id: id,
      name: JsonRead.string(m['category_name']) ?? 'Sin nombre',
    );
  }

  /// `get_live_streams` → canales. Se omiten los que no tienen `stream_id`.
  static List<LiveChannel> channels(Object? json) => [
    for (final item in JsonRead.list(json)) ?_channel(JsonRead.map(item)),
  ];

  static LiveChannel? _channel(Map<String, Object?>? m) {
    if (m == null) return null;
    final id = JsonRead.integer(m['stream_id']);
    if (id == null || id < 0) return null;
    return LiveChannel(
      id: '$id',
      name: JsonRead.string(m['name']) ?? 'Canal $id',
      number: JsonRead.integer(m['num']),
      logoUrl: _httpUrl(JsonRead.string(m['stream_icon'])),
      categoryId: JsonRead.string(m['category_id']),
      epgChannelId: JsonRead.string(m['epg_channel_id']),
      hasArchive: JsonRead.boolean(m['tv_archive']),
    );
  }

  /// `get_short_epg` → `{"epg_listings": [...]}` con título y descripción en
  /// base64 y horarios como timestamps Unix. Ordena por inicio y descarta
  /// entradas sin horario válido.
  static List<EpgEntry> shortEpg(Object? json) {
    final root = JsonRead.map(json);
    final entries = <EpgEntry>[
      for (final item in JsonRead.list(root?['epg_listings']))
        ?_epg(JsonRead.map(item)),
    ]..sort((a, b) => a.start.compareTo(b.start));
    return entries;
  }

  static EpgEntry? _epg(Map<String, Object?>? m) {
    if (m == null) return null;
    final start = JsonRead.unixSeconds(m['start_timestamp']);
    final end =
        JsonRead.unixSeconds(m['stop_timestamp']) ??
        JsonRead.unixSeconds(m['end_timestamp']);
    if (start == null || end == null || !end.isAfter(start)) return null;
    return EpgEntry(
      title: decodeText(JsonRead.string(m['title'])) ?? 'Sin título',
      description: decodeText(JsonRead.string(m['description'])),
      start: start,
      end: end,
    );
  }

  /// Los paneles envían los textos de la EPG en base64, pero no todos. Se
  /// decodifica solo si el resultado es UTF-8 válido y sin caracteres de
  /// control; si no, se usa el texto tal cual.
  static String? decodeText(String? raw) {
    if (raw == null) return null;
    try {
      final decoded = utf8.decode(base64.decode(base64.normalize(raw))).trim();
      if (decoded.isEmpty) return null;
      if (decoded.runes.any((r) => r < 0x20 && r != 0x0A && r != 0x09)) {
        return raw;
      }
      return decoded;
    } on FormatException {
      return raw;
    }
  }

  /// Solo URLs http(s): un logo con otro esquema (file:, data:) se ignora.
  static String? _httpUrl(String? url) {
    if (url == null) return null;
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      return null;
    }
    return url;
  }
}
