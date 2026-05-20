import 'package:flutter_test/flutter_test.dart';
import 'package:lunio/core/date/local_date.dart';
import 'package:lunio/domain/entities/maintenance_item.dart';
import 'package:lunio/domain/entities/maintenance_record.dart';
import 'package:lunio/domain/entities/reminder.dart';
import 'package:lunio/domain/entities/sync_metadata.dart';
import 'package:lunio/domain/rules/maintenance_rules.dart';

void main() {
  final sync = SyncMetadata(
    status: SyncStatus.synced,
    updatedAt: DateTime(2026),
  );

  MaintenanceItem item({
    bool byMileage = true,
    bool byTime = true,
    int? mileageIntervalKm = 10000,
    int? timeIntervalMonths = 12,
  }) {
    return MaintenanceItem(
      id: 'item-1',
      ownerCarId: 'car-1',
      name: '机油',
      isDefault: true,
      enabled: true,
      remindByMileage: byMileage,
      remindByTime: byTime,
      mileageIntervalKm: mileageIntervalKm,
      timeIntervalMonths: timeIntervalMonths,
      warningThresholdPercent: 100,
      dangerThresholdPercent: 125,
      sortOrder: 1,
      sync: sync,
    );
  }

  MaintenanceRecord record({required LocalDate date, required int mileageKm}) {
    return MaintenanceRecord(
      id: 'record-1',
      carId: 'car-1',
      date: date,
      itemIds: const ['item-1'],
      costCents: 10000,
      mileageKm: mileageKm,
      sync: sync,
    );
  }

  test('status threshold uses normal warning and danger boundaries', () {
    expect(MaintenanceRules.statusForPercent(99.9), ReminderStatus.normal);
    expect(MaintenanceRules.statusForPercent(100), ReminderStatus.warning);
    expect(MaintenanceRules.statusForPercent(124.9), ReminderStatus.warning);
    expect(MaintenanceRules.statusForPercent(125), ReminderStatus.danger);
  });

  test('uses the higher progress between mileage and time', () {
    final progress = MaintenanceRules.progressForItem(
      item: item(),
      latestRecord: record(
        date: const LocalDate(2025, 5, 19),
        mileageKm: 10000,
      ),
      currentMileageKm: 15000,
      today: const LocalDate(2026, 5, 19),
    );

    expect(progress.percent, 100);
    expect(progress.reason, 'time');
    expect(progress.status, ReminderStatus.warning);
  });

  test('mileage-only reminder can become danger', () {
    final progress = MaintenanceRules.progressForItem(
      item: item(byTime: false, timeIntervalMonths: null),
      latestRecord: record(date: const LocalDate(2026, 1, 1), mileageKm: 10000),
      currentMileageKm: 22500,
      today: const LocalDate(2026, 5, 19),
    );

    expect(progress.percent, 125);
    expect(progress.status, ReminderStatus.danger);
  });
}
