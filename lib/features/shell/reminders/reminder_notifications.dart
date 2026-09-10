// 提醒通知域的内容组装：系统通知清单、应用内到期清单、全量数据签名。
//
// 在 App 中的位置：提醒的 UI 半边（视图模型/行组装/空态分类/英雄卡
// 概览）已拆到 reminder_rows.dart，本文件只保留通知同步控制器消费的
// 三块：
//  1. 系统通知清单组装（buildScheduledNotifications，控制器重排时调用）；
//  2. 应用内提醒弹窗的到期清单（maintenanceNotices，控制器过滤静默后
//     传给 reminder_dialogs）；
//  3. 全量数据签名（reminderNotificationDataSignature + 停车倒计时
//     摘要），签名变化才重排系统通知/弹应用内弹窗。
// 行组装与 UI 复用同一个 buildReminderRows（reminder_rows.dart），
// "界面看到的"和"通知里发的"来自同一次组装规则。
// snooze/ack 抑制协议（"稍后提醒"/"知道了"）已收编进通知协调器
// notification_coordinator.dart，本文件只经它的两个静默读方法过滤。

import '../../../core/date/local_date.dart';
import '../../../core/notifications/lunio_notification_service.dart';
import '../../../domain/entities/car.dart';
import '../../../domain/entities/maintenance_item.dart';
import '../../../domain/entities/maintenance_record.dart';
import '../../../domain/entities/notification_settings.dart';
import '../../../domain/entities/parking_countdown.dart';
import '../../../domain/entities/reminder.dart';
import '../../../domain/rules/maintenance_rules.dart';
import 'notification_coordinator.dart';
import 'reminder_rows.dart';

/// 组装系统通知清单（通知同步控制器重排时调用）：
///  - 到期项目 ≥1（"稍后提醒"过滤后）→ 一条汇总通知 id 8000"保养提醒"
///    （正文=最紧急项 + 到期数量）；
///  - 里程更新到期（且没"稍后提醒"）→ id 8900"更新车辆里程"（9:05 错峰）。
/// 无到期项返回空列表（重排等于全部取消）。
Future<List<LunioScheduledNotification>> buildScheduledNotifications({
  required LunioNotificationCoordinator coordinator,
  required LunioNotificationSettings settings,
  required Car car,
  required List<MaintenanceItem> items,
  required List<MaintenanceRecord> records,
  required LocalDate today,
}) async {
  final notifications = <LunioScheduledNotification>[];
  final activeMaintenanceNotices = <ReminderViewData>[];
  for (final notice in maintenanceNotices(
    car: car,
    items: items,
    records: records,
    today: today,
  )) {
    final itemId = notice.item.id;
    if (itemId == null) {
      continue;
    }
    if (!await coordinator.isSilencedForSystemNotification(
      MaintenanceItemTarget(itemId),
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
      !await coordinator.isSilencedForSystemNotification(
        MileageUpdateTarget(car.id!),
        today,
      )) {
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

/// 到期项目清单（应用内弹窗与系统通知共用）。
/// 注意：没有任何记录时直接返回空——产品约定"没记录就不产生提醒"
/// （新车主不会被无历史基线的假超期轰炸）。
List<ReminderViewData> maintenanceNotices({
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
    if (noticeDueForRow(row)) {
      notices.add(row);
    }
  }
  return notices;
}

/// 单项是否到期（状态为 warning/danger）。
/// 保养到期提醒是产品核心能力，无用户开关（R5，原 maintenanceDueEnabled
/// 偏好已移除）。
bool noticeDueForRow(ReminderViewData row) {
  return row.progress.status == ReminderStatus.warning ||
      row.progress.status == ReminderStatus.danger;
}
