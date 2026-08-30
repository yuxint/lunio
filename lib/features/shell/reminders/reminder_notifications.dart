// 提醒业务的 view-data 层：领域计算结果 → UI/通知 展示模型的转换
// + 系统通知的内容组装 + snooze/ack 偏好机制。
//
// 被三处消费（同一套计算保证口径一致）：
//  1. 提醒列表 ReminderList（buildReminderRows）；
//  2. 英雄卡"到期概览"文案（dueOverviewText）；
//  3. 系统通知内容（buildScheduledNotifications，通知同步控制器调用）。
//
// ⚠ 本文件是 UI 目录却直接 import data 层的 LunioRepository
// （isSnoozed/isAcknowledgedToday 直连数据库读偏好），跨层依赖点。
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

/// 单个保养项目的提醒展示模型（≈ 前端 ViewModel）：
/// 项目 + 进度 + 最近记录，附展示用 getter（百分比/徽章文案/语义色/详情行）。
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

  int get displayPercent => _displayPercentForThresholds(
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
      details.add(_mileageReminderText(progress.mileageRemainingKm!));
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

/// 构建提醒列表行：只取启用且有 id 的项目 → 逐项算进度 → 排序。
/// 排序规则：状态越差越靠前（超期>到期>正常）→ 百分比降序 → sortOrder。
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

/// 组装系统通知清单（通知同步控制器重排时调用）：
///  - 到期项目 ≥1（snooze 过滤后）→ 一条汇总通知 id 8000"保养提醒"
///    （正文=最紧急项 + 到期数量）；
///  - 里程更新到期（且没 snooze）→ id 8900"更新车辆里程"（9:05 错峰）。
/// 无到期项返回空列表（重排等于全部取消）。
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
        // 重复频率直接取用户设置（原经 maintenanceRepeatFrequency 转发，
        // 该函数四个参数全未用，R30 死代码已删）。
        repeatFrequency: settings.dueRepeatFrequency,
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

/// 停车到点时刻（保养/里程通知调度时要避让的时间槽）。
List<DateTime> reservedNotificationDateTimes(
  ParkingCountdown? parkingCountdown,
) {
  if (parkingCountdown == null) {
    return const [];
  }
  return [parkingCountdown.endsAt];
}

/// 停车倒计时的签名片段（进系统通知总签名：倒计时变了要重排）。
String parkingCountdownReminderSignature(ParkingCountdown? parkingCountdown) {
  if (parkingCountdown == null) {
    return 'parking:none';
  }
  return 'parking:${parkingCountdown.endsAt.toIso8601String()}';
}

/// ★ 全量数据签名：把车辆/项目/记录的全部影响提醒的字段拼成一个大字符串。
/// 通知同步控制器在数据变化时调用，签名变了才重排系统通知
/// （原 AppShell 每帧 build 拼接的性能热点已随 R11/R12 修复移除）。
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

/// 里程更新提醒是否到期：上次里程更新日（= car.sync.updatedAt 的日期）
/// + 按记录频率推断的间隔 ≤ 今天。
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

/// 系统通知正文：品牌车型 + 到期数量 + 最紧急项目及其到期原因。
String maintenanceNoticeSummaryForRows(
  Car car,
  List<ReminderViewData> notices,
) {
  final first = notices.first;
  return '${car.brand} ${car.model}：到期 ${notices.length} 项。'
      '最紧急：${first.title}，${dueReasonText(first)}';
}

/// 到期原因短文案（通知用）。
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

/// 到期详情长文案（应用内弹窗用，含超期量）。
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

// ---- snooze / ack 偏好 key 与判定 ----
// snooze（15 天内不再提醒）：同时静默系统通知 + 应用内弹窗；
// ack（知道了）：只静默当天的应用内弹窗，系统通知照发。
// key 前缀引用 LunioRepository 上的静态常量（单一事实来源）：
// 恢复备份时按同一组前缀清除抑制键，两处不会各自漂移。

/// 里程更新 snooze key（按车辆）。
String mileageUpdateSnoozeKey(int carId) {
  return '${LunioRepository.mileageUpdateSnoozedUntilPrefix}$carId';
}

/// 里程更新当日 ack key。
String mileageUpdateInAppAcknowledgedKey(int carId) {
  return '${LunioRepository.mileageUpdateInAppAcknowledgedOnPrefix}$carId';
}

/// 保养项 snooze key（按项目）。
String maintenanceReminderSnoozeKey(int itemId) {
  return '${LunioRepository.maintenanceReminderSnoozedUntilPrefix}$itemId';
}

/// 保养项当日 ack key。
String maintenanceInAppReminderAcknowledgedKey(int itemId) {
  return '${LunioRepository.maintenanceInAppReminderAcknowledgedOnPrefix}'
      '$itemId';
}

/// snooze 截止日 = 今天 + 15 天（⚠ 跨 DST 时区天数会漂移，R34）。
LocalDate snoozeUntilDate(LocalDate today) {
  return LocalDate.fromDateTime(
    today.toDateTime().add(const Duration(days: 15)),
  );
}

/// 是否处于 snooze 期（截止日 ≥ 今天）。
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

/// 今天是否已 ack 过。
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

/// 到期项目清单（应用内弹窗与系统通知共用）。
/// 注意：没有任何记录时直接返回空——产品约定"没记录就不产生提醒"
/// （新车主不会被无历史基线的假超期轰炸）。
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

/// 单项是否到期（保养到期开关开着 且 状态为 warning/danger）。
bool noticeDueForRow(LunioNotificationSettings settings, ReminderViewData row) {
  if (!settings.maintenanceDueEnabled) {
    return false;
  }
  return row.progress.status == ReminderStatus.warning ||
      row.progress.status == ReminderStatus.danger;
}

/// 某项目最近一次记录：先比日期，同日比里程（取更大者作基线）。
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

/// 状态排序权重（越大越紧急）。
int reminderStatusRank(ReminderStatus status) {
  return switch (status) {
    ReminderStatus.normal => 0,
    ReminderStatus.warning => 1,
    ReminderStatus.danger => 2,
  };
}

/// 英雄卡"到期概览"文案：如"超期 1 / 到期 2"、"全部正常"、"暂无"。
/// 数据变化时重算（页面已无周期性 ticker，不再高频执行）。
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

// ---- 文件内私有格式化（§5.2 回收：仅本文件消费的函数不留公共面）----

/// 进度环显示百分比的四舍五入钳制：真实进度没到阈值时，
/// 显示值不允许"看起来已到阈值"（如 99.6% 显示 99% 而不是 100%）。
int _displayPercentForThresholds({
  required double percent,
  required double notOverdueUpperLimit,
  required double overdueUpperLimit,
}) {
  var display = percent.round();
  if (percent < notOverdueUpperLimit &&
      display >= notOverdueUpperLimit.ceil()) {
    display = notOverdueUpperLimit.ceil() - 1;
  }
  if (percent < overdueUpperLimit && display >= overdueUpperLimit.ceil()) {
    display = overdueUpperLimit.ceil() - 1;
  }
  return display;
}

/// 里程维剩余文案（提醒详情用）。
String _mileageReminderText(int remainingKm) {
  if (remainingKm > 0) {
    return '里程：距离下次约 ${formatNumber(remainingKm)} 公里';
  }
  if (remainingKm == 0) {
    return '里程：已到期';
  }
  return '里程：已超 ${formatNumber(remainingKm.abs())} 公里';
}
