/// Tipo de fuente de contenido de un perfil.
enum SourceType {
  xtream('Xtream Codes'),
  m3u('Lista M3U');

  const SourceType(this.label);
  final String label;
}

/// Perfil guardado en el equipo. Solo contiene datos no sensibles: las
/// credenciales viven en el almacén seguro, indexadas por [id].
class Profile {
  const Profile({
    required this.id,
    required this.name,
    required this.type,
    required this.createdAt,
    this.lastUsedAt,
  });

  final int id;
  final String name;
  final SourceType type;
  final DateTime createdAt;
  final DateTime? lastUsedAt;
}
