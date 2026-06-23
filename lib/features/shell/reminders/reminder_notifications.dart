// ignore_for_file: use_key_in_widget_constructors, library_private_types_in_public_api

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/date/local_date.dart';
import '../../../core/notifications/lunio_notification_service.dart';
import '../../../core/widgets/lunio_components.dart';
import '../../../data/repositories/lunio_repository.dart';
import '../../../domain/entities/car.dart';
import '../../../domain/entities/maintenance_item.dart';
import '../../../domain/entities/maintenance_record.dart';
import '../../../domain/entities/notification_settings.dart';
import '../../../domain/entities/parking_countdown.dart';
import '../../../domain/entities/reminder.dart';
import '../../../domain/rules/maintenance_rules.dart';
import '../shared/shell_shared.dart';

class ReminderViewData {
  const ReminderViewData({
    required this.item,
    required this.progress,
    required this.latestRecord,
  });

  final MaintenanceItem item;
  final ReminderProgress progress;
  final MaintenanceRecord? latestRecord;

  String get title => item.name;

  int get displayPercent => displayPercentForThresholds(
    percent: progress.percent,
    notOverdueUpperLimit: item.notOverdueUpperLimit,
    overdueUpperLimit: item.overdueUpperLimit,
  );

  String get percentText => formatPercent(displayPercent);

  LunioStatusTone get tone {
    return switch (progress.status) {
      ReminderStatus.normal => LunioStatusTone.normal,
      ReminderStatus.warning => LunioStatusTone.warning,
      ReminderStatus.danger => LunioStatusTone.danger,
    };
  }

  String get badge {
    return switch (progress.status) {
      ReminderStatus.normal => '正常',
      ReminderStatus.warning => '到期',
      ReminderStatus.danger => '超期',
    };
  }

  List<String> get detailTexts {
    final details = <String>[];
    if (item.remindByMileage && progress.mileageRemainingKm != null) {
      details.add(mileageReminderText(progress.mileageRemainingKm!));
    }
    if (item.remindByTime && progress.daysRemaining != null) {
      details.add(timeReminderText(progress.daysRemaining!));
    }
    if (details.isEmpty) {
      details.add('未设置提醒规则');
    }
    return details;
  }
}

List<ReminderViewData> buildReminderRows({
  required Car car,
  required List<MaintenanceItem> items,
  required List<MaintenanceRecord> records,
  required LocalDate today,
}) {
  final rows = <ReminderViewData>[];
  for (final item in items.where((item) => item.enabled && item.id != null)) {
    final latestRecord = latestRecordForItem(records, item.id!);
    final progress = MaintenanceRules.progressForItem(
      item: item,
      latestRecord: latestRecord,
      currentMileageKm: car.currentMileageKm,
      noHistoryBaselineDate: car.roadDate,
      today: today,
    );
    rows.add(
      ReminderViewData(
        item: item,
        progress: progress,
        latestRecord: latestRecord,
      ),
    );
  }
  rows.sort((left, right) {
    final statusCompare = reminderStatusRank(
      right.progress.status,
    ).compareTo(reminderStatusRank(left.progress.status));
    if (statusCompare != 0) {
      return statusCompare;
    }
    final progressCompare = right.progress.percent.compareTo(
      left.progress.percent,
    );
    if (progressCompare != 0) {
      return progressCompare;
    }
    return left.item.sortOrder.compareTo(right.item.sortOrder);
  });
  return rows;
}

Future<List<LunioScheduledNotification>> buildScheduledNotifications({
  required WidgetRef ref,
  required LunioNotificationSettings settings,
  required Car car,
  required List<MaintenanceItem> items,
  required List<MaintenanceRecord> records,
  required LocalDate today,
}) async {
  final repository = ref.read(lunioRepositoryProvider);
  final notifications = <LunioScheduledNotification>[];
  final activeMaintenanceNotices = <ReminderViewData>[];
  for (final notice in maintenanceNotices(
    settings: settings,
    car: car,
    items: items,
    records: records,
    today: today,
  )) {
    final itemId = notice.item.id;
    if (itemId == null) {
      continue;
    }
    if (!await isSnoozed(
      repository,
      maintenanceReminderSnoozeKey(itemId),
      today,
    )) {
      activeMaintenanceNotices.add(notice);
    }
  }
  if (activeMaintenanceNotices.isNotEmpty) {
    notifications.add(
      LunioScheduledNotification(
        id: 8000,
        title: '保养提醒',
        body: maintenanceNoticeSummaryForRows(car, activeMaintenanceNotices),
        repeatFrequency: maintenanceRepeatFrequency(
          settings: settings,
          car: car,
          items: items,
          records: records,
          today: today,
        ),
      ),
    );
  }
  if (car.id != null &&
      mileageUpdateReminderDue(car: car, records: records, today: today) &&
      !await isSnoozed(repository, mileageUpdateSnoozeKey(car.id!), today)) {
    notifications.add(
      LunioScheduledNotification(
        id: 8900,
        title: '更新车辆里程',
        body: '建议更新 ${car.brand} ${car.model} 的当前里程。',
        repeatFrequency: MaintenanceRules.mileageUpdateFrequencyForRecords(
          records,
        ),
        scheduledMinuteOffset: 5,
        androidChannelId: 'lunio_mileage_update_heads_up',
        androidChannelName: 'Lunio 里程更新提醒',
      ),
    );
  }
  return notifications;
}

List<DateTime> reservedNotificationDateTimes(
  ParkingCountdown? parkingCountdown,
) {
  if (parkingCountdown == null) {
    return const [];
  }
  return [parkingCountdown.endsAt];
}

String parkingCountdownReminderSignature(ParkingCountdown? parkingCountdown) {
  if (parkingCountdown == null) {
    return 'parking:none';
  }
  return 'parking:${parkingCountdown.endsAt.toIso8601String()}';
}

String reminderNotificationDataSignature({
  required Car car,
  required List<MaintenanceItem> items,
  required List<MaintenanceRecord> records,
  required LocalDate today,
}) {
  final itemSignature = items
      .map((item) {
        return [
          item.id,
          item.carsId,
          item.enabled,
          item.remindByMileage,
          item.remindByTime,
          item.mileageIntervalKm,
          item.timeIntervalMonths,
          item.notOverdueUpperLimit,
          item.overdueUpperLimit,
          item.sortOrder,
          item.sync.updatedAt.toIso8601String(),
          item.sync.version,
        ].join(',');
      })
      .join('|');
  final recordSignature = records
      .map((record) {
        return [
          record.id,
          record.carId,
          record.date,
          record.mileageKm,
          record.itemIds.join('+'),
          record.sync.updatedAt.toIso8601String(),
          record.sync.version,
        ].join(',');
      })
      .join('|');
  return [
    car.id,
    car.currentMileageKm,
    car.sync.updatedAt.toIso8601String(),
    today,
    itemSignature,
    recordSignature,
  ].join(';');
}

bool mileageUpdateReminderDue({
  required Car car,
  required List<MaintenanceRecord> records,
  required LocalDate today,
}) {
  final frequency = MaintenanceRules.mileageUpdateFrequencyForRecords(records);
  return MaintenanceRules.mileageUpdateDue(
    lastMileageUpdatedDate: LocalDate.fromDateTime(car.sync.updatedAt),
    frequency: frequency,
    today: today,
  );
}

ReminderRepeatFrequency maintenanceRepeatFrequency({
  required LunioNotificationSettings settings,
  required Car car,
  required List<MaintenanceItem> items,
  required List<MaintenanceRecord> records,
  required LocalDate today,
}) {
  return settings.dueRepeatFrequency;
}

String maintenanceNoticeSummaryForRows(
  Car car,
  List<ReminderViewData> notices,
) {
  final first = notices.first;
  return '${car.brand} ${car.model}：到期 ${notices.length} 项。'
      '最紧急：${first.title}，${dueReasonText(first)}';
}

String dueReasonText(ReminderViewData row) {
  final mileageDue =
      row.item.remindByMileage &&
      row.progress.mileageRemainingKm != null &&
      row.progress.mileageRemainingKm! <= 0;
  final timeDue =
      row.item.remindByTime &&
      row.progress.daysRemaining != null &&
      row.progress.daysRemaining! <= 0;
  if (mileageDue && timeDue) {
    return '里程和时间到期';
  }
  if (mileageDue) {
    return '里程到期';
  }
  if (timeDue) {
    return '时间到期';
  }
  return '到期';
}

String dueNoticeText(ReminderViewData row) {
  final details = <String>[];
  final daysRemaining = row.progress.daysRemaining;
  if (row.item.remindByTime && daysRemaining != null && daysRemaining <= 0) {
    details.add(
      daysRemaining == 0
          ? '时间今日到期'
          : '已超 ${formatReminderDuration(daysRemaining.abs())}',
    );
  }
  final mileageRemaining = row.progress.mileageRemainingKm;
  if (row.item.remindByMileage &&
      mileageRemaining != null &&
      mileageRemaining <= 0) {
    details.add(
      mileageRemaining == 0
          ? '里程已到期'
          : '已超 ${formatNumber(mileageRemaining.abs())}km',
    );
  }
  if (details.isEmpty) {
    return dueReasonText(row);
  }
  return details.join(' · ');
}

String mileageUpdateSnoozeKey(int carId) {
  return 'mileageUpdateSnoozedUntil:$carId';
}

String mileageUpdateInAppAcknowledgedKey(int carId) {
  return 'mileageUpdateInAppAcknowledgedOn:$carId';
}

String maintenanceReminderSnoozeKey(int itemId) {
  return 'maintenanceReminderSnoozedUntil:$itemId';
}

String maintenanceInAppReminderAcknowledgedKey(int itemId) {
  return 'maintenanceInAppReminderAcknowledgedOn:$itemId';
}

LocalDate snoozeUntilDate(LocalDate today) {
  return LocalDate.fromDateTime(
    today.toDateTime().add(const Duration(days: 15)),
  );
}

Future<bool> isSnoozed(
  LunioRepository repository,
  String key,
  LocalDate today,
) async {
  final value = await repository.getPreferenceValue(key);
  if (value == null) {
    return false;
  }
  final until = LocalDate.tryParse(value);
  if (until == null) {
    return false;
  }
  return until.compareTo(today) >= 0;
}

Future<bool> isAcknowledgedToday(
  LunioRepository repository,
  String key,
  LocalDate today,
) async {
  final value = await repository.getPreferenceValue(key);
  if (value == null) {
    return false;
  }
  final acknowledgedOn = LocalDate.tryParse(value);
  if (acknowledgedOn == null) {
    return false;
  }
  return acknowledgedOn == today;
}

List<ReminderViewData> maintenanceNotices({
  required LunioNotificationSettings settings,
  required Car car,
  required List<MaintenanceItem> items,
  required List<MaintenanceRecord> records,
  required LocalDate today,
}) {
  if (records.isEmpty) {
    return const [];
  }
  final rows = buildReminderRows(
    car: car,
    items: items,
    records: records,
    today: today,
  );
  final notices = <ReminderViewData>[];
  for (final row in rows) {
    if (noticeDueForRow(settings, row)) {
      notices.add(row);
    }
  }
  return notices;
}

bool noticeDueForRow(LunioNotificationSettings settings, ReminderViewData row) {
  if (!settings.maintenanceDueEnabled) {
    return false;
  }
  return row.progress.status == ReminderStatus.warning ||
      row.progress.status == ReminderStatus.danger;
}

MaintenanceRecord? latestRecordForItem(
  List<MaintenanceRecord> records,
  int itemId,
) {
  MaintenanceRecord? latest;
  for (final record in records) {
    if (!record.itemIds.contains(itemId)) {
      continue;
    }
    if (latest == null ||
        record.date.compareTo(latest.date) > 0 ||
        (record.date == latest.date && record.mileageKm > latest.mileageKm)) {
      latest = record;
    }
  }
  return latest;
}

int reminderStatusRank(ReminderStatus status) {
  return switch (status) {
    ReminderStatus.normal => 0,
    ReminderStatus.warning => 1,
    ReminderStatus.danger => 2,
  };
}

String dueOverviewText(
  AsyncValue<List<MaintenanceItem>> items,
  AsyncValue<List<MaintenanceRecord>> records,
  Car car,
  LocalDate today,
) {
  if (items.isLoading || records.isLoading) {
    return '计算中';
  }
  if (items.hasError || records.hasError) {
    return '加载失败';
  }
  if ((records.value ?? const <MaintenanceRecord>[]).isEmpty) {
    return '暂无';
  }
  final rows = buildReminderRows(
    car: car,
    items: items.value ?? const [],
    records: records.value ?? const [],
    today: today,
  );
  if (rows.isEmpty) {
    return '无项目';
  }
  final overdueCount = rows
      .where((row) => row.progress.status == ReminderStatus.danger)
      .length;
  final dueCount = rows
      .where((row) => row.progress.status == ReminderStatus.warning)
      .length;
  if (overdueCount > 0 && dueCount > 0) {
    return '超期 $overdueCount / 到期 $dueCount';
  }
  if (overdueCount > 0) {
    return '超期 $overdueCount';
  }
  if (dueCount > 0) {
    return '到期 $dueCount';
  }
  return '全部正常';
}
