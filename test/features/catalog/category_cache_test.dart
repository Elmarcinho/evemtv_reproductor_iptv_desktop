// Solo las últimas categorías usadas quedan en memoria. Datos ficticios.
import 'package:evemtv/domain/entities/vod.dart';
import 'package:evemtv/features/auth/application/session.dart';
import 'package:evemtv/features/catalog/catalog_providers.dart';
import 'package:evemtv/features/catalog/category_cache.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fakes.dart';
import '../player/live_playback_controller_test.dart' show FakeSource;

class _CountingSource extends FakeSource {
  final requested = <String?>[];

  @override
  Future<List<VodItem>> vodItems({String? categoryId}) async {
    requested.add(categoryId);
    return [VodItem(id: 'm$categoryId', name: 'Película $categoryId')];
  }
}

void main() {
  test('se conservan las 10 últimas; las demás se liberan', () async {
    final source = _CountingSource();
    final c = ProviderContainer.test(
      overrides: [
        sessionContextProvider.overrideWithValue(testSessionContext()),
        contentSourceProvider.overrideWithValue(source),
      ],
    );
    // Se abren 12 categorías, de a una (como al recorrer la lista).
    for (var i = 1; i <= 12; i++) {
      final sub = c.listen(vodItemsProvider('$i'), (_, _) {});
      await c.read(vodItemsProvider('$i').future);
      sub.close();
      await pumpEventQueue();
    }
    final cache = c.read(categoryListCacheProvider);
    expect(cache.keys, [for (var i = 3; i <= 12; i++) ('vod', '$i')]);

    // La 12 sigue en memoria: no se vuelve a pedir.
    await c.read(vodItemsProvider('12').future);
    expect(source.requested.where((r) => r == '12'), hasLength(1));

    // La 1 se liberó: al volver, se pide de nuevo al servidor.
    final sub = c.listen(vodItemsProvider('1'), (_, _) {});
    await c.read(vodItemsProvider('1').future);
    sub.close();
    expect(source.requested.where((r) => r == '1'), hasLength(2));
  });

  test('una categoría que se vuelve a usar pasa a ser la más reciente', () {
    final cache = CategoryListCache(capacity: 2);
    final c = ProviderContainer.test();
    final links = <Object>[];
    final p = Provider.autoDispose.family<int, int>((ref, i) {
      final link = ref.keepAlive();
      links.add(link);
      cache.register(i, link);
      return i;
    });
    c
      ..read(p(1))
      ..read(p(2));
    cache.touch(1);
    c.read(p(3));
    expect(cache.keys, [1, 3]);
  });
}
