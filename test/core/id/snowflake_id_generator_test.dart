import 'package:flutter_test/flutter_test.dart';
import 'package:lunio/core/id/snowflake_id_generator.dart';

void main() {
  test('generates positive unique 64-bit numeric ids', () {
    var now = DateTime.utc(2026, 5, 28, 10);
    final generator = SnowflakeIdGenerator(now: () => now);

    final ids = List.generate(128, (_) => generator.next());

    expect(ids.toSet(), hasLength(ids.length));
    expect(ids.every((id) => id > 0), isTrue);
    expect(ids.every((id) => id < 0x7fffffffffffffff), isTrue);
  });

  test('keeps ids increasing when system clock moves backwards', () {
    var now = DateTime.utc(2026, 5, 28, 10);
    final generator = SnowflakeIdGenerator(now: () => now);

    final first = generator.next();
    now = DateTime.utc(2026);
    final second = generator.next();

    expect(second, greaterThan(first));
  });
}
