// 提醒状态枚举 + 提醒进度结果对象（≈ Java 的枚举与结果 DTO）。
//
// normal/warning/danger 三态贯穿提醒列表、停车倒计时卡片、
// 应用内提醒弹窗——UI 用同一套语义色（绿/黄/红）渲染。
// 状态 → 语义色的映射只有下面 extension 这一份（过去
// reminder_notifications 与 parking_countdown 各写了一遍 switch）。
import '../../core/widgets/lunio_components.dart' show LunioStatusTone;

enum ReminderStatus { normal, warning, danger }

extension ReminderStatusTone on ReminderStatus {
  /// 三态对应的 UI 语义色（提醒卡片 / 停车倒计时共用）。
  LunioStatusTone get tone {
    return switch (this) {
      ReminderStatus.normal => LunioStatusTone.normal,
      ReminderStatus.warning => LunioStatusTone.warning,
      ReminderStatus.danger => LunioStatusTone.danger,
    };
  }
}

/// 一个保养项目的提醒计算结果（由 rules/maintenance_rules.dart 产出）。
class ReminderProgress {
  const ReminderProgress({
    required this.percent,
    required this.status,
    this.mileageRemainingKm,
    this.daysRemaining,
  });

  /// 消耗进度百分比（0 起，可超 100 表示超期）。里程/时间两维取较大者。
  final double percent;

  /// normal / warning / danger，按项目自身的上下阈值判定。
  final ReminderStatus status;

  /// 里程维剩余公里数（该维未启用时为 null）。
  final int? mileageRemainingKm;

  /// 时间维剩余天数（该维未启用时为 null；负数表示已超期）。
  final int? daysRemaining;
}
