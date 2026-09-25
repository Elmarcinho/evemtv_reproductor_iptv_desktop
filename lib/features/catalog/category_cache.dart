import 'dart:collection';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show KeepAliveLink;

import '../auth/application/session.dart';

/// Listas de categorías (canales, películas, series) que se conservan en
/// memoria: solo las [capacity] usadas más recientemente. Las demás se
/// liberan y, si se vuelven a abrir, se piden de nuevo al servidor.
///
/// Cada lista que termina de cargar se registra con su `KeepAliveLink`.
/// Usarla (ganar o perder su última pantalla que la muestra) la pasa al
/// final de la cola; al superar [capacity] se cierra el vínculo de la más
/// antigua. Si esa lista todavía se está mostrando, no se pierde: se libera
/// recién cuando deja de verse.
class CategoryListCache {
  CategoryListCache({this.capacity = 10});

  final int capacity;
  final LinkedHashMap<Object, KeepAliveLink> _links = LinkedHashMap();

  /// Claves conservadas, de la más antigua a la más reciente (para tests).
  List<Object> get keys => List.unmodifiable(_links.keys);

  void register(Object key, KeepAliveLink link) {
    _links.remove(key);
    _links[key] = link;
    _evict();
  }

  /// La lista se volvió a usar (o dejó de mostrarse): pasa a ser la más
  /// reciente.
  void touch(Object key) {
    final link = _links.remove(key);
    if (link != null) _links[key] = link;
  }

  void unregister(Object key, KeepAliveLink link) {
    if (identical(_links[key], link)) _links.remove(key);
  }

  void _evict() {
    while (_links.length > capacity) {
      final oldest = _links.keys.first;
      _links.remove(oldest)!.close();
    }
  }
}

/// Una por sesión: se descarta con ella.
final categoryListCacheProvider = Provider<CategoryListCache>((ref) {
  ref.watch(sessionContextProvider);
  return CategoryListCache();
}, dependencies: [sessionContextProvider]);

/// Conserva la lista de [ref] (ya cargada) según [CategoryListCache].
void keepRecentCategory(Ref ref, Object key) {
  final cache = ref.read(categoryListCacheProvider);
  final link = ref.keepAlive();
  cache.register(key, link);
  ref
    ..onResume(() => cache.touch(key))
    ..onCancel(() => cache.touch(key))
    ..onDispose(() => cache.unregister(key, link));
}
