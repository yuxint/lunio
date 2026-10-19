// 提醒通知域的内容组装：系统通知清单、到期/生效清单、全量数据签名。
//
// 在 App 中的位置：提醒的 UI 半边（视图模型/行组装/空态分类/英雄卡
// 概览）已拆到 reminder_rows.dart，本文件保留通知域消费的四块：
//  1. 系统通知清单组装（buildScheduledNotifications，控制器重排时调用）；
//  2. 应用内提醒弹窗的到期清单（maintenanceNotices，"没记录不产生
//     提醒"产品约定的单一实现）；
//  3. 生效到期清单单一出口（buildActiveDueList，GLOSSARY 词条）：到期
//     清单减去静默后的生效部分 + 里程更新提醒生效性，系统通知与应用
//     内弹窗两通道经它取同一份（2026-10-19 收编，此前两处各手抄一份
//     同形循环）；
//  4. 全量数据签名（reminderNotificationDataSignature + 停车倒计时
//     摘要），签名变化才重排系统通知/弹应用内弹窗。
// 行组装与 UI 复用同一个 buildReminderRows（reminder_rows.dart），
// "界面看到的"和"通知里发的"来自同一次组装规则。
// snooze/ack 抑制协议（"稍后提醒"/"知道了"）已收编进通知协调器
// notification_coordinator.dart，本文件只经它的两个静默读方法过滤
// （两通道静默语义的差异归协调器单一拥有，出口只收"用哪个判定"）。

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
///  - 到期项目 ≥1（"稍后提醒"过滤后）→ 一条汇总通知（maintenanceSummary
///    槽位，id 8000，正文=最紧急项 + 到期数量）；
///  - 里程更新到期（且没"稍后提醒"）→ 里程更新提醒（mileageUpdate 槽位，
///    id 8900，9:05 错峰）。
/// 无到期项返回空列表（重排等于全部取消）。身份（id/渠道/重复次数/payload）
/// 全部来自 LunioNotificationSlot 槽位台账，这里只给标题/正文/重复频率。
Future<List<LunioScheduledNotification>> buildScheduledNotifications({
  required LunioNotificationCoordinator coordinator,
  required LunioNotificationSettings settings,
  required Car car,
  required List<MaintenanceItem> items,
  required List<MaintenanceRecord> records,
  required LocalDate today,
}) async {
  final notifications = <LunioScheduledNotification>[];
  // 生效到期清单（单一出口 buildActiveDueList）：系统通知通道的静默
  // 语义 = 只认"稍后提醒"（"知道了"不影响系统通知），绑定协调器
  // isSilencedForSystemNotification。本通道不传 shouldAbort——检查点
  // 在调用方（控制器 await 本函数返回后问同步票）。
  final active = await buildActiveDueList(
    car: car,
    items: items,
    records: records,
    today: today,
    isSilenced: coordinator.isSilencedForSystemNotification,
  );
  if (active == null) {
    // 理论不可达：本通道不传 shouldAbort，出口不会中止；防御按"无生效
    // 提醒"处理（返回空清单 = 重排等于全部取消，与无到期同语义）。
    return notifications;
  }
  if (active.maintenanceNotices.isNotEmpty) {
    notifications.add(
      LunioScheduledNotification(
        slot: LunioNotificationSlot.maintenanceSummary,
        title: '保养提醒',
        body: maintenanceNoticeSummaryForRows(car, active.maintenanceNotices),
        // 重复频率直接取用户设置（原经 maintenanceRepeatFrequency 转发，
        // 该函数四个参数全未用，R30 死代码已删）。
        repeatFrequency: settings.dueRepeatFrequency,
      ),
    );
  }
  if (active.mileageUpdate) {
    notifications.add(
      LunioScheduledNotification(
        slot: LunioNotificationSlot.mileageUpdate,
        title: '更新车辆里程',
        body: '建议更新 ${car.brand} ${car.model} 的当前里程。',
        repeatFrequency: MaintenanceRules.mileageUpdateFrequencyForRecords(
          records,
        ),
      ),
    );
  }
  return notifications;
}

/// 静默判定读取接缝：`(目标, 今天) → 是否静默`。生产只有两个绑定，
/// 都在通知协调器上（语义差异归协调器单一拥有，GLOSSARY「通知协调器」）：
///  - isSilencedForSystemNotification：系统通知，只认"稍后提醒"；
///  - isSilencedForInAppDialog：应用内弹窗，"稍后提醒"期内或今天已
///    点过"知道了"。
/// 生效到期清单出口（buildActiveDueList）按传入的判定过滤、不重复拥有
/// 规则；决策体 reminder_dialog_flow 的静默读接缝同用本类型（注入假
/// 实现即可在测试里控制 await 边界）。
typedef ReminderSilenceRead
    = Future<bool> Function(ReminderTarget target, LocalDate today);

/// 生效到期清单（GLOSSARY 词条）：到期清单减去静默后的生效部分，
/// 外加里程更新提醒的生效性——"哪些提醒真正要发/要弹"的一份快照。
class ActiveDueList {
  const ActiveDueList({
    required this.maintenanceNotices,
    required this.mileageUpdate,
  });

  /// 生效的保养到期提醒行（已过滤静默、已跳过无 id 项目；顺序保持
  /// maintenanceNotices 的紧迫度排序）。
  final List<ReminderViewData> maintenanceNotices;

  /// 里程更新提醒是否生效（carId 存在 && 到期 && 未静默）。
  final bool mileageUpdate;

  /// 两类生效提醒都为空（消费方"无生效提醒"的短路口径）。
  bool get isEmpty => maintenanceNotices.isEmpty && !mileageUpdate;
}

/// ★ 生效到期清单单一出口（2026-10-19 收编）：到期清单
/// （maintenanceNotices，"没记录不产生提醒"产品约定在其中）逐项过
/// 静默判定、跳过无 id 项目，再判里程更新提醒的到期与静默——循环
/// 形状、无 id 跳过规则、里程处理只此一份。系统通知
/// （buildScheduledNotifications）与应用内弹窗（reminder_dialog_flow）
/// 两个通道都经本函数取生效清单，静默语义按通道由 [isSilenced] 参数化
/// （生产绑定见 [ReminderSilenceRead]）；将来第三个消费方（如小组件
/// 到期摘要）出现时取同一份，不再手抄第三遍。
///
/// [shouldAbort]（可选）：每次静默读的 await 之后问一次，true = 整轮
/// 作废、返回 null。应用内弹窗通道传"同步票已作废"谓词——静默读是
/// await，期间可能发生破坏性写库，这是检查点协议在循环内的位点（协议
/// 归守卫模块、谓词由调用方注入，本函数不拥有守卫状态）；系统通知通道
/// 不传（检查点在调用方控制器 await 本函数的消费方返回之后）。
Future<ActiveDueList?> buildActiveDueList({
  required Car car,
  required List<MaintenanceItem> items,
  required List<MaintenanceRecord> records,
  required LocalDate today,
  required ReminderSilenceRead isSilenced,
  bool Function()? shouldAbort,
}) async {
  final active = <ReminderViewData>[];
  for (final notice in maintenanceNotices(
    car: car,
    items: items,
    records: records,
    today: today,
  )) {
    final itemId = notice.item.id;
    if (itemId == null) {
      // 无 id 项目（尚未落库的瞬态对象）跳过：静默判定与后续呈现都
      // 需要稳定的持久 id。
      continue;
    }
    if (!await isSilenced(MaintenanceItemTarget(itemId), today)) {
      active.add(notice);
    }
    if (shouldAbort != null && shouldAbort()) {
      return null;
    }
  }
  final carId = car.id;
  final mileageUpdate = carId != null &&
      mileageUpdateReminderDue(car: car, records: records, today: today) &&
      !await isSilenced(MileageUpdateTarget(carId), today);
  if (shouldAbort != null && shouldAbort()) {
    return null;
  }
  return ActiveDueList(
    maintenanceNotices: active,
    mileageUpdate: mileageUpdate,
  );
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
