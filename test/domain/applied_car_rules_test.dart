import 'package:flutter_test/flutter_test.dart';
import 'package:lunio/core/date/local_date.dart';
import 'package:lunio/domain/entities/car.dart';
import 'package:lunio/domain/entities/sync_metadata.dart';
import 'package:lunio/domain/rules/applied_car_rules.dart';

void main() {
  final sync = SyncMetadata(
    status: SyncStatus.synced,
    updatedAt: DateTime(2026),
  );
  final cars = [
    Car(
      id: 1,
      brand: '本田',
      model: '22款思域',
      currentMileageKm: 100,
      roadDate: const LocalDate(2023, 8, 12),
      sync: sync,
    ),
    Car(
      id: 2,
      brand: '日产',
      model: '22款轩逸',
      currentMileageKm: 200,
      roadDate: const LocalDate(2024, 1, 1),
      sync: sync,
    ),
  ];

  test('keeps stored applied car when it still exists', () {
    expect(AppliedCarRules.resolveAppliedCarId(cars: cars, storedCarId: 2), 2);
  });

  test('falls back to first car when stored id is invalid', () {
    expect(AppliedCarRules.resolveAppliedCarId(cars: cars, storedCarId: 99), 1);
  });
}
