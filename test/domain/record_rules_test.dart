import 'package:flutter_test/flutter_test.dart';
import 'package:lunio/domain/rules/record_rules.dart';

void main() {
  test('record item ids are deduplicated and keep first-seen order', () {
    expect(RecordRules.uniqueItemIds([1, 2, 1, 3]), [1, 2, 3]);
  });

  test('record mileage can only lift car mileage', () {
    expect(
      RecordRules.mileageAfterRecord(
        currentMileageKm: 100,
        recordMileageKm: 90,
      ),
      100,
    );
    expect(
      RecordRules.mileageAfterRecord(
        currentMileageKm: 100,
        recordMileageKm: 120,
      ),
      120,
    );
  });
}
