/// Categoría de contenido (grupo de canales, películas o series).
class ContentCategory {
  const ContentCategory({required this.id, required this.name});

  final String id;
  final String name;

  @override
  bool operator ==(Object other) =>
      other is ContentCategory && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(id, name);
}

/// Canal de TV en vivo.
///
/// [id] identifica el canal dentro de su fuente: el `stream_id` en Xtream o
/// un hash de la URL en M3U. Nunca contiene credenciales, así puede
/// guardarse más adelante (favoritos, último canal).
class LiveChannel {
  const LiveChannel({
    required this.id,
    required this.name,
    this.number,
    this.logoUrl,
    this.categoryId,
    this.epgChannelId,
    this.hasArchive = false,
  });

  final String id;
  final String name;
  final int? number;
  final String? logoUrl;
  final String? categoryId;
  final String? epgChannelId;

  /// El panel guarda grabaciones (catch-up, Fase 6).
  final bool hasArchive;

  @override
  bool operator ==(Object other) => other is LiveChannel && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Programa de la guía.
class EpgEntry {
  const EpgEntry({
    required this.title,
    required this.start,
    required this.end,
    this.description,
  });

  final String title;
  final String? description;
  final DateTime start;
  final DateTime end;

  bool isLiveAt(DateTime now) => !now.isBefore(start) && now.isBefore(end);

  /// Avance del programa entre 0 y 1.
  double progressAt(DateTime now) {
    final total = end.difference(start).inSeconds;
    if (total <= 0) return 0;
    final elapsed = now.difference(start).inSeconds;
    return (elapsed / total).clamp(0.0, 1.0);
  }
}

/// URLs candidatas para reproducir un canal, en orden de preferencia. El
/// reproductor prueba la siguiente si una falla (p. ej. `.m3u8` → `.ts`).
///
/// Contienen credenciales: nunca se registran ni se muestran.
class PlaybackCandidates {
  const PlaybackCandidates(this.urls) : assert(urls.length > 0);

  final List<Uri> urls;
}
