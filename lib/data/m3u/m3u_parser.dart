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
    final title = _clean(info?.title) ?? _clean(attrs['tvg-name']);
    final kind = guessKind(url, title);
    return M3uEntry(
      // Sin título: nombre genérico. NUNCA algo derivado de la URL (el
      // último segmento puede ser un token), ni en pantalla ni en favoritos.
      name: title ?? untitled(kind),
      url: url,
      kind: kind,
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
  ///
  /// Un nombre de episodio (`S01E02`, `1x02`) indica serie aunque la ruta no
  /// tenga `/series/`, salvo que la URL sea claramente de vivo (`/live/`,
  /// `.m3u8`, `.ts`).
  static M3uKind guessKind(Uri url, [String? name]) {
    final path = url.path.toLowerCase();
    if (path.contains('/series/')) return M3uKind.series;
    final dot = path.lastIndexOf('.');
    final ext = dot < 0 ? '' : path.substring(dot + 1);
    final looksLive = path.contains('/live/') || ext == 'm3u8' || ext == 'ts';
    if (name != null && !looksLive && episodePattern.hasMatch(name.trim())) {
      return M3uKind.series;
    }
    if (path.contains('/movie/')) return M3uKind.movie;
    if (_vodExtensions.contains(ext)) return M3uKind.movie;
    return M3uKind.live;
  }

  /// `Nombre S01E02`, `Nombre - S1 E2 - Título`, `Nombre 1x02`.
  /// Grupos: 1 serie, 2/4 temporada, 3/5 episodio, 6 título.
  static final RegExp episodePattern = RegExp(
    r'^(.*?)[\s._\-–|:]*(?:[Ss](\d{1,2})[\s._-]*[Ee](\d{1,4})|(\d{1,2})x(\d{1,4}))\b[\s._\-–|:]*(.*)$',
  );

  /// Nombre genérico para entradas sin título.
  static String untitled(M3uKind kind) => switch (kind) {
    M3uKind.live => 'Canal sin nombre',
    M3uKind.movie => 'Película sin título',
    M3uKind.series => 'Serie sin título',
  };

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
}

class _Pending {
  const _Pending({required this.attributes, this.title});

  final Map<String, String> attributes;
  final String? title;
}
