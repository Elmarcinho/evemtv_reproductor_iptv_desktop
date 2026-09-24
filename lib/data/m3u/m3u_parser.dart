import 'dart:convert';

/// Tipo de contenido deducido de una entrada M3U.
enum M3uKind { live, movie, series }

/// Una entrada de la lista (`#EXTINF` + URL).
class M3uEntry {
  const M3uEntry({
    required this.name,
    required this.url,
    required this.kind,
    this.group,
    this.logoUrl,
    this.tvgId,
    this.channelNumber,
  });

  final String name;

  /// URL del stream. Puede contener credenciales: no registrar.
  final Uri url;
  final M3uKind kind;
  final String? group;
  final String? logoUrl;
  final String? tvgId;
  final int? channelNumber;
}

class M3uPlaylist {
  const M3uPlaylist({required this.entries, this.epgUrl});

  final List<M3uEntry> entries;

  /// Guía XMLTV declarada en la cabecera (`url-tvg` / `x-tvg-url`), para la
  /// EPG completa de la Fase 6.
  final Uri? epgUrl;
}

/// Parser tolerante de listas M3U/M3U8 extendidas.
///
/// Acepta CRLF, BOM, atributos con o sin comillas, `#EXTGRP`, líneas
/// desconocidas y entradas sin `#EXTINF`. Una línea rota se omite; nunca
/// rompe la lista completa.
abstract final class M3uParser {
  static final RegExp _attribute = RegExp(
    r'''([A-Za-z0-9_-]+)=(?:"([^"]*)"|'([^']*)'|([^\s,]+))''',
  );

  static const _vodExtensions = {
    'mp4', 'mkv', 'avi', 'mov', 'm4v', 'wmv', 'webm', 'mpg', 'mpeg', //
  };

  static const _allowedSchemes = {
    'http',
    'https',
    'rtmp',
    'rtsp',
    'udp',
    'rtp',
  };

  static M3uPlaylist parse(String text) {
    final entries = <M3uEntry>[];
    Uri? epgUrl;
    _Pending? pending;
    String? pendingGroup;

    for (final raw in const LineSplitter().convert(text)) {
      final line = raw.replaceFirst('﻿', '').trim();
      if (line.isEmpty) continue;
      final upper = line.toUpperCase();

      if (upper.startsWith('#EXTM3U')) {
        final attrs = _attributes(line);
        epgUrl ??= _httpUri(attrs['url-tvg'] ?? attrs['x-tvg-url']);
      } else if (upper.startsWith('#EXTINF:')) {
        pending = _parseExtinf(line);
      } else if (upper.startsWith('#EXTGRP:')) {
        pendingGroup = _clean(line.substring('#EXTGRP:'.length));
      } else if (line.startsWith('#')) {
        continue; // #EXTVLCOPT, #KODIPROP y otras directivas: se ignoran.
      } else {
        final url = _streamUri(line);
        if (url != null) {
          entries.add(_entry(url, pending, pendingGroup));
        }
        pending = null;
        pendingGroup = null;
      }
    }
    return M3uPlaylist(entries: entries, epgUrl: epgUrl);
  }

  static M3uEntry _entry(Uri url, _Pending? info, String? extgrp) {
    final attrs = info?.attributes ?? const <String, String>{};
    final name =
        _clean(info?.title) ?? _clean(attrs['tvg-name']) ?? _nameFromUrl(url);
    return M3uEntry(
      name: name,
      url: url,
      kind: guessKind(url),
      group: _clean(attrs['group-title']) ?? extgrp,
      logoUrl: _httpUri(attrs['tvg-logo'])?.toString(),
      tvgId: _clean(attrs['tvg-id']),
      channelNumber: int.tryParse(attrs['tvg-chno'] ?? ''),
    );
  }

  /// `#EXTINF:-1 tvg-id="a" group-title="b, c",Nombre del canal`.
  /// El título empieza en la primera coma que no está dentro de comillas.
  static _Pending _parseExtinf(String line) {
    final body = line.substring('#EXTINF:'.length);
    var inQuotes = false;
    String? quote;
    var comma = -1;
    for (var i = 0; i < body.length; i++) {
      final c = body[i];
      if (inQuotes) {
        if (c == quote) inQuotes = false;
      } else if (c == '"' || c == "'") {
        inQuotes = true;
        quote = c;
      } else if (c == ',') {
        comma = i;
        break;
      }
    }
    final head = comma < 0 ? body : body.substring(0, comma);
    final title = comma < 0 ? null : body.substring(comma + 1);
    return _Pending(attributes: _attributes(head), title: title);
  }

  static Map<String, String> _attributes(String text) => {
    for (final m in _attribute.allMatches(text))
      m.group(1)!.toLowerCase(): (m.group(2) ?? m.group(3) ?? m.group(4))!,
  };

  /// Deduce si es vivo, película o serie por la URL (rutas estilo Xtream o
  /// extensión de archivo de video).
  static M3uKind guessKind(Uri url) {
    final path = url.path.toLowerCase();
    if (path.contains('/series/')) return M3uKind.series;
    if (path.contains('/movie/')) return M3uKind.movie;
    final dot = path.lastIndexOf('.');
    if (dot >= 0 && _vodExtensions.contains(path.substring(dot + 1))) {
      return M3uKind.movie;
    }
    return M3uKind.live;
  }

  static Uri? _streamUri(String line) {
    final uri = Uri.tryParse(line);
    if (uri == null || !_allowedSchemes.contains(uri.scheme.toLowerCase())) {
      return null;
    }
    return uri;
  }

  static Uri? _httpUri(String? value) {
    final text = _clean(value);
    if (text == null) return null;
    final uri = Uri.tryParse(text);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      return null;
    }
    return uri;
  }

  static String? _clean(String? value) {
    final text = value?.trim();
    return (text == null || text.isEmpty) ? null : text;
  }

  /// Último segmento sin extensión. Nunca la URL completa (puede tener
  /// credenciales).
  static String _nameFromUrl(Uri url) {
    final String? last;
    try {
      last = url.pathSegments.where((s) => s.isNotEmpty).lastOrNull;
    } on FormatException {
      return 'Canal sin nombre';
    }
    if (last == null) return 'Canal sin nombre';
    final dot = last.lastIndexOf('.');
    return dot > 0 ? last.substring(0, dot) : last;
  }
}

class _Pending {
  const _Pending({required this.attributes, this.title});

  final Map<String, String> attributes;
  final String? title;
}
