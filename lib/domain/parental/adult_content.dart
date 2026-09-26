import '../entities/catalog.dart';

/// Detección de contenido para adultos (control parental).
///
/// Una categoría es de adultos si el panel la marca (`is_adult`) o si su
/// nombre contiene alguna de [keywords] como palabra completa, sin
/// distinguir mayúsculas ni tildes ("Hot" sí, "Hotel" no). Un canal,
/// película o serie es de adultos si el panel lo marca o si su categoría lo
/// es.
abstract final class AdultContent {
  /// Palabras y frases que marcan una categoría como de adultos. Ajustar
  /// aquí: es la única lista (se comparan ya normalizadas, sin tildes y en
  /// minúsculas).
  static const List<String> keywords = [
    'xxx',
    'adult',
    'adults',
    'adulto',
    'adultos',
    '+18',
    '18+',
    'porn',
    'porno',
    'erotic',
    'erotico',
    'eroticos',
    'for adults',
    'hot',
  ];

  static final List<List<String>> _phrases = [
    for (final k in keywords) _words(_normalize(k)),
  ];

  /// `true` si el nombre de la categoría la marca como de adultos.
  static bool isAdultName(String name) {
    final words = _words(_normalize(name));
    if (words.isEmpty) return false;
    for (final phrase in _phrases) {
      if (phrase.isEmpty || phrase.length > words.length) continue;
      for (var i = 0; i + phrase.length <= words.length; i++) {
        var match = true;
        for (var j = 0; j < phrase.length; j++) {
          if (words[i + j] != phrase[j]) {
            match = false;
            break;
          }
        }
        if (match) return true;
      }
    }
    return false;
  }

  /// Minúsculas y sin tildes.
  static String _normalize(String s) {
    final lower = s.toLowerCase();
    final out = StringBuffer();
    for (final rune in lower.runes) {
      final c = String.fromCharCode(rune);
      out.write(_accents[c] ?? c);
    }
    return out.toString();
  }

  static const Map<String, String> _accents = {
    'á': 'a', 'à': 'a', 'ä': 'a', 'â': 'a', 'ã': 'a', //
    'é': 'e', 'è': 'e', 'ë': 'e', 'ê': 'e', //
    'í': 'i', 'ì': 'i', 'ï': 'i', 'î': 'i', //
    'ó': 'o', 'ò': 'o', 'ö': 'o', 'ô': 'o', 'õ': 'o', //
    'ú': 'u', 'ù': 'u', 'ü': 'u', 'û': 'u', //
    'ñ': 'n', 'ç': 'c',
  };

  /// Palabras: letras y dígitos, conservando un `+` pegado a un número
  /// ("+18", "18+"). Todo lo demás separa ("XXX|Adultos", "[HOT]").
  static List<String> _words(String s) => [
    for (final m in _word.allMatches(s)) m.group(0)!,
  ];

  static final RegExp _word = RegExp(r'\+?[a-z0-9]+\+?');
}

/// Qué ocultar mientras el contenido adulto está bloqueado. Con el control
/// desbloqueado se usa [HiddenContent.none].
class HiddenContent {
  const HiddenContent({
    this.categories = const {},
    this.adultItems = const {},
    this.active = true,
  });

  /// Nada oculto (control desbloqueado).
  static const HiddenContent none = HiddenContent(active: false);

  /// `true` si oculta algo: bloqueado oculta al menos lo marcado como de
  /// adultos; desbloqueado ([none]), nada.
  final bool active;

  /// Categorías ocultas por tipo (de adultos o bloqueadas por el usuario).
  final Map<ContentKind, Set<String>> categories;

  /// Elementos marcados como de adultos por el panel, por tipo (aunque su
  /// categoría no lo sea).
  final Map<ContentKind, Set<String>> adultItems;

  bool hidesCategory(ContentKind kind, String? categoryId) =>
      active &&
      categoryId != null &&
      (categories[kind]?.contains(categoryId) ?? false);

  /// Un elemento se oculta si es de adultos o si su categoría está oculta.
  bool hidesItem(
    ContentKind kind,
    String id, {
    String? categoryId,
    bool adult = false,
  }) =>
      active &&
      (adult ||
          (adultItems[kind]?.contains(id) ?? false) ||
          hidesCategory(kind, categoryId));
}
