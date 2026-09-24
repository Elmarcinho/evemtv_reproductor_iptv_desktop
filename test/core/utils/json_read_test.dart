import 'package:evemtv/core/utils/json_read.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('string', () {
    expect(JsonRead.string(' hola '), 'hola');
    expect(JsonRead.string(12), '12');
    expect(JsonRead.string(''), isNull);
    expect(JsonRead.string('null'), isNull);
    expect(JsonRead.string(const []), isNull);
  });

  test('integer', () {
    expect(JsonRead.integer(5), 5);
    expect(JsonRead.integer('5'), 5);
    expect(JsonRead.integer('5.0'), 5);
    expect(JsonRead.integer(2.9), 2);
    expect(JsonRead.integer(true), 1);
    expect(JsonRead.integer('abc'), isNull);
    expect(JsonRead.integer(null), isNull);
    expect(JsonRead.integer(double.nan), isNull);
  });

  test('boolean', () {
    expect(JsonRead.boolean('1'), isTrue);
    expect(JsonRead.boolean(1), isTrue);
    expect(JsonRead.boolean('true'), isTrue);
    expect(JsonRead.boolean('0'), isFalse);
    expect(JsonRead.boolean(null), isFalse);
    expect(JsonRead.boolean('raro', fallback: true), isTrue);
  });

  test('map acepta [] como ausente y convierte claves', () {
    expect(JsonRead.map(const []), isNull);
    expect(JsonRead.map({1: 'a'}), {'1': 'a'});
  });

  test('list acepta objeto con claves numéricas', () {
    expect(JsonRead.list({'0': 'ts', '1': 'm3u8'}), ['ts', 'm3u8']);
    expect(JsonRead.list('x'), isEmpty);
    expect(JsonRead.stringList(['ts', null, '', 5]), ['ts', '5']);
  });

  test('unixSeconds', () {
    expect(JsonRead.unixSeconds('1767225600'), DateTime.utc(2026, 1, 1));
    expect(JsonRead.unixSeconds('0'), isNull);
    expect(JsonRead.unixSeconds(null), isNull);
    expect(JsonRead.unixSeconds('nunca'), isNull);
  });
}
