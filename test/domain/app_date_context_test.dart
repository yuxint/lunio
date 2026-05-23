import 'package:flutter_test/flutter_test.dart';
import 'package:lunio/core/date/app_date_context.dart';
import 'package:lunio/core/date/local_date.dart';

void main() {
  test('manual date overrides system date', () {
    final context = AppDateContext(
      readSystemNow: () => DateTime(2026, 5, 19, 22, 30),
      manualDate: const LocalDate(2026, 1, 2),
    );

    expect(context.today().toString(), '2026-01-02');
  });

  test('local date uses yyyy-MM-dd and rejects invalid format', () {
    expect(const LocalDate(2026, 5, 9).toString(), '2026-05-09');
    expect(() => LocalDate.parse('2026-5-9'), throwsFormatException);
    expect(() => LocalDate.parse('2026-02-30'), throwsFormatException);
    expect(() => LocalDate.parse('2026-13-01'), throwsFormatException);
    expect(() => LocalDate.parse('2026-00-01'), throwsFormatException);
  });

  test('add months clamps to last valid day of target month', () {
    expect(const LocalDate(2026, 1, 31).addMonths(1).toString(), '2026-02-28');
  });
}
