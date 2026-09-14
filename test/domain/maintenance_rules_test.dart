import 'package:flutter_test/flutter_test.dart';
import 'package:lunio/core/date/local_date.dart';
import 'package:lunio/domain/entities/maintenance_item.dart';
import 'package:lunio/domain/entities/maintenance_record.dart';
import 'package:lunio/domain/entities/notification_settings.dart';
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
      id: 1,
      carsId: 1,
      name: '机油',
      enabled: true,
      remindByMileage: byMileage,
      remindByTime: byTime,
      mileageIntervalKm: mileageIntervalKm,
      timeIntervalMonths: timeIntervalMonths,
      notOverdueUpperLimit: 100,
      overdueUpperLimit: 125,
      sortOrder: 1,
      sync: sync,
    );
  }

  MaintenanceRecord record({required LocalDate date, required int mileageKm}) {
    return MaintenanceRecord(
      id: 1,
      carId: 1,
      date: date,
      itemIds: const [1],
      costCents: 10000,
      mileageKm: mileageKm,
      sync: sync,
    );
  }

  test('uses the higher progress between mileage and time', () {
    final progress = MaintenanceRules.progressForItem(
      item: item(),
      latestRecord: record(
        date: const LocalDate(2025, 5, 19),
        mileageKm: 10000,
      ),
      currentMileageKm: 15000,
      noHistoryBaselineDate: const LocalDate(2023, 8, 12),
      today: const LocalDate(2026, 5, 19),
    );

    expect(progress.percent, 100);
    expect(progress.status, ReminderStatus.warning);
    expect(progress.mileageRemainingKm, 5000);
    expect(progress.daysRemaining, 0);
  });

  test('mileage-only reminder can become danger', () {
    final progress = MaintenanceRules.progressForItem(
      item: item(byTime: false, timeIntervalMonths: null),
      latestRecord: record(date: const LocalDate(2026, 1, 1), mileageKm: 10000),
      currentMileageKm: 22500,
      noHistoryBaselineDate: const LocalDate(2023, 8, 12),
      today: const LocalDate(2026, 5, 19),
    );

    expect(progress.percent, 125);
    expect(progress.status, ReminderStatus.danger);
  });

  test('no history uses vehicle road date and zero mileage as baseline', () {
    final progress = MaintenanceRules.progressForItem(
      item: item(byTime: false, timeIntervalMonths: null),
      latestRecord: null,
      currentMileageKm: 5000,
      noHistoryBaselineDate: const LocalDate(2026, 1, 1),
      today: const LocalDate(2026, 5, 19),
    );

    expect(progress.percent, 50);
    expect(progress.mileageRemainingKm, 5000);
  });

  test('time progress uses natural day ratio instead of whole months', () {
    final progress = MaintenanceRules.progressForItem(
      item: item(
        byMileage: false,
        mileageIntervalKm: null,
        timeIntervalMonths: 1,
      ),
      latestRecord: record(date: const LocalDate(2026, 1, 1), mileageKm: 0),
      currentMileageKm: 0,
      noHistoryBaselineDate: const LocalDate(2026, 1, 1),
      today: const LocalDate(2026, 1, 16),
    );
    expect(progress.percent, closeTo(48.38, 0.01));
  });

  test('mileage update frequency defaults monthly with sparse records', () {
    expect(
      MaintenanceRules.mileageUpdateFrequencyForRecords(const []),
      ReminderRepeatFrequency.monthly,
    );
    expect(
      MaintenanceRules.mileageUpdateFrequencyForRecords([
        record(date: const LocalDate(2026, 5, 1), mileageKm: 10000),
      ]),
      ReminderRepeatFrequency.monthly,
    );
  });

  test('mileage update frequency follows recent maintenance cadence', () {
    expect(
      MaintenanceRules.mileageUpdateFrequencyForRecords([
        record(date: const LocalDate(2026, 5, 29), mileageKm: 40000),
        record(date: const LocalDate(2026, 5, 22), mileageKm: 35000),
        record(date: const LocalDate(2026, 5, 15), mileageKm: 30000),
      ]),
      ReminderRepeatFrequency.weekly,
    );
    expect(
      MaintenanceRules.mileageUpdateFrequencyForRecords([
        record(date: const LocalDate(2026, 5, 29), mileageKm: 40000),
        record(date: const LocalDate(2026, 5, 15), mileageKm: 30000),
      ]),
      ReminderRepeatFrequency.everyTwoWeeks,
    );
    expect(
      MaintenanceRules.mileageUpdateFrequencyForRecords([
        record(date: const LocalDate(2026, 5, 29), mileageKm: 40000),
        record(date: const LocalDate(2026, 5, 8), mileageKm: 30000),
      ]),
      ReminderRepeatFrequency.everyThreeWeeks,
    );
    expect(
      MaintenanceRules.mileageUpdateFrequencyForRecords([
        record(date: const LocalDate(2026, 5, 29), mileageKm: 40000),
        record(date: const LocalDate(2026, 4, 1), mileageKm: 30000),
      ]),
      ReminderRepeatFrequency.monthly,
    );
  });

  test('mileage update reminder is due from last mileage updated date', () {
    expect(
      MaintenanceRules.mileageUpdateDue(
        lastMileageUpdatedDate: const LocalDate(2026, 5, 1),
        frequency: ReminderRepeatFrequency.weekly,
        today: const LocalDate(2026, 5, 7),
      ),
      isFalse,
    );
    expect(
      MaintenanceRules.mileageUpdateDue(
        lastMileageUpdatedDate: const LocalDate(2026, 5, 1),
        frequency: ReminderRepeatFrequency.weekly,
        today: const LocalDate(2026, 5, 8),
      ),
      isTrue,
    );
    expect(
      MaintenanceRules.mileageUpdateDue(
        lastMileageUpdatedDate: const LocalDate(2026, 1, 31),
        frequency: ReminderRepeatFrequency.monthly,
        today: const LocalDate(2026, 2, 28),
      ),
      isTrue,
    );
  });

  test('validateIntervals checks only enabled axes, mileage wins first', () {
    // 里程轴开启但值非法（null / 0）→ 里程问题优先。
    expect(
      MaintenanceRules.validateIntervals(
        remindByMileage: true,
        remindByTime: true,
        mileageIntervalKm: null,
        timeIntervalMonths: null,
      ),
      MaintenanceIntervalProblem.mileage,
    );
    expect(
      MaintenanceRules.validateIntervals(
        remindByMileage: true,
        remindByTime: true,
        mileageIntervalKm: 0,
        timeIntervalMonths: 6,
      ),
      MaintenanceIntervalProblem.mileage,
    );
    // 里程轴合法、时间轴非法 → 时间问题。
    expect(
      MaintenanceRules.validateIntervals(
        remindByMileage: true,
        remindByTime: true,
        mileageIntervalKm: 5000,
        timeIntervalMonths: -1,
      ),
      MaintenanceIntervalProblem.time,
    );
    // 两轴都合法 → null。
    expect(
      MaintenanceRules.validateIntervals(
        remindByMileage: true,
        remindByTime: true,
        mileageIntervalKm: 5000,
        timeIntervalMonths: 6,
      ),
      isNull,
    );
    // 未开启的轴即使值为 null 也不校验。
    expect(
      MaintenanceRules.validateIntervals(
        remindByMileage: false,
        remindByTime: false,
        mileageIntervalKm: null,
        timeIntervalMonths: null,
      ),
      isNull,
    );
  });

  test('intervalProblemText renders with and without item name prefix', () {
    expect(
      MaintenanceRules.intervalProblemText(MaintenanceIntervalProblem.mileage),
      '里程间隔必须填写正整数',
    );
    expect(
      MaintenanceRules.intervalProblemText(
        MaintenanceIntervalProblem.time,
        itemName: '机油',
      ),
      '机油 的时间间隔必须填写正整数',
    );
  });
}
