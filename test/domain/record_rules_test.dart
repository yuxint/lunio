import 'package:flutter_test/flutter_test.dart';
import 'package:lunio/domain/rules/record_rules.dart';

void main() {
  test('record item ids are deduplicated and keep first-seen order', () {
    expect(RecordRules.uniqueItemIds(['a', 'b', 'a', '', 'c']), [
      'a',
      'b',
      'c',
    ]);
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

  test('cycle item key uses car date and item id instead of item name', () {
    expect(
      RecordRules.cycleItemKey(
        carId: 'car',
        date: '2026-05-19',
        itemId: 'item',
      ),
      'car::2026-05-19::item',
    );
  });
}
