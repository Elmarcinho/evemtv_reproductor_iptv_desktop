// Recomendaciones de las fichas. Datos ficticios.
import 'package:evemtv/features/catalog/related.dart';
import 'package:flutter_test/flutter_test.dart';

typedef _Item = ({String id, String name, int? year, double? rating});

List<_Item> _related(_Item item, List<_Item> all) => relatedTo<_Item>(
  item,
  all,
  idOf: (i) => i.id,
  nameOf: (i) => i.name,
  yearOf: (i) => i.year,
  ratingOf: (i) => i.rating,
  posterOf: (i) => i.id == 'sin-poster' ? null : 'http://img.example.com/x',
);

void main() {
  test('palabras del título: sin tildes, año ni palabras vacías', () {
    expect(titleWords('La Canción del Fútbol (2026)'), {'cancion', 'futbol'});
    expect(titleWords('The Lord of the Rings'), {'lord', 'rings'});
  });

  test('primero la misma saga, después año cercano y puntaje', () {
    const actual = (
      id: 'a',
      name: 'Saga Galáctica 2 (2026)',
      year: 2026,
      rating: 7.0,
    );
    final all = <_Item>[
      actual,
      (id: 'lejana', name: 'Comedia Vieja', year: 1990, rating: 9.0),
      (id: 'cercana', name: 'Drama Nuevo', year: 2025, rating: 6.0),
      (id: 'saga', name: 'Saga Galáctica (2020)', year: 2020, rating: 5.0),
      (id: 'sin-poster', name: 'Saga Galáctica 3', year: 2026, rating: 8.0),
    ];
    final ids = _related(actual, all).map((i) => i.id).toList();
    expect(ids, ['saga', 'cercana', 'lejana']);
    // Nunca se recomienda a sí misma ni una sin póster.
    expect(ids, isNot(contains('a')));
    expect(ids, isNot(contains('sin-poster')));
  });
}
