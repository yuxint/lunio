// 保养提醒核心规则（纯静态工具类，无任何 UI/DB 依赖，可单测）。
//
// 三块业务：
//  1. 进度计算 progressForItem —— 提醒列表每个项目显示百分之多少、
//     什么状态、还剩多少公里/多少天；
//  2. 里程更新频率 mileageUpdateFrequencyForRecords —— 根据用户历史
//     记录习惯，推断"该多久提醒他更新一次里程"；
//  3. 里程更新是否到期 mileageUpdateDue / 下次提醒日。
//
// 输入的 today 一律是"生效日期"（开发者模式的手动日期 ?? 系统今天），
// 见 providers.dart 的 effectiveTodayProvider。
import '../../core/date/local_date.dart';
import '../entities/maintenance_item.dart';
import '../entities/maintenance_record.dart';
import '../entities/notification_settings.dart';
import '../entities/reminder.dart';

class MaintenanceRules {
  const MaintenanceRules._();

  /// 按固定阈值（100% 到期 / 125% 超期）判状态。
  ///
  /// 注意：生产代码走的是 [_statusForItem]（用项目自定义阈值），
  /// 本方法目前只有测试在用，属于双轨遗留（审查报告 R30）。
  static ReminderStatus statusForPercent(double percent) {
    if (percent >= 125) {
      return ReminderStatus.danger;
    }
    if (percent >= 100) {
      return ReminderStatus.warning;
    }
    return ReminderStatus.normal;
  }

  /// 根据历史记录推断里程更新提醒频率。
  ///
  /// 算法：记录日期去重 → 倒序取最近 5 个 → 相邻两两求间隔天数 →
  /// 求平均 → ≤10 天=每周 / ≤17 天=每 2 周 / ≤24 天=每 3 周 / 其余=每月。
  /// 少于 2 个不同日期时无法计算，默认每月。
  ///
  /// 业务含义：常开车（常记录）的人更频繁地被提醒更新里程。
  static ReminderRepeatFrequency mileageUpdateFrequencyForRecords(
    List<MaintenanceRecord> records,
  ) {
    final dates = records.map((record) => record.date).toSet().toList()
      ..sort((left, right) => right.compareTo(left));
    if (dates.length < 2) {
      return ReminderRepeatFrequency.monthly;
    }
    final recentDates = dates.take(5).toList();
    final intervals = <int>[];
    for (var index = 0; index < recentDates.length - 1; index++) {
      final interval = recentDates[index + 1].daysUntil(recentDates[index]);
      if (interval > 0) {
        intervals.add(interval);
      }
    }
    if (intervals.isEmpty) {
      return ReminderRepeatFrequency.monthly;
    }
    final averageDays =
        intervals.reduce((left, right) => left + right) / intervals.length;
    if (averageDays <= 10) {
      return ReminderRepeatFrequency.weekly;
    }
    if (averageDays <= 17) {
      return ReminderRepeatFrequency.everyTwoWeeks;
    }
    if (averageDays <= 24) {
      return ReminderRepeatFrequency.everyThreeWeeks;
    }
    return ReminderRepeatFrequency.monthly;
  }

  /// 里程更新提醒是否已到期：今天 ≥ 上次更新日 + 频率间隔。
  static bool mileageUpdateDue({
    required LocalDate lastMileageUpdatedDate,
    required ReminderRepeatFrequency frequency,
    required LocalDate today,
  }) {
    final nextReminderDate = nextMileageUpdateReminderDate(
      lastMileageUpdatedDate: lastMileageUpdatedDate,
      frequency: frequency,
    );
    return today.compareTo(nextReminderDate) >= 0;
  }

  /// 下次里程更新提醒日：按频率在"上次更新日"上加 1/7/14/21 天或 1 个月。
  /// monthly 走 LocalDate.addMonths（自动做月末钳制，1.31 + 1月 → 2.28）。
  static LocalDate nextMileageUpdateReminderDate({
    required LocalDate lastMileageUpdatedDate,
    required ReminderRepeatFrequency frequency,
  }) {
    return switch (frequency) {
      ReminderRepeatFrequency.daily => _addDays(lastMileageUpdatedDate, 1),
      ReminderRepeatFrequency.weekly => _addDays(lastMileageUpdatedDate, 7),
      ReminderRepeatFrequency.everyTwoWeeks => _addDays(
        lastMileageUpdatedDate,
        14,
      ),
      ReminderRepeatFrequency.everyThreeWeeks => _addDays(
        lastMileageUpdatedDate,
        21,
      ),
      ReminderRepeatFrequency.monthly => lastMileageUpdatedDate.addMonths(1),
    };
  }

  /// 计算单个保养项目的提醒进度（提醒列表与系统通知共用）。
  ///
  /// 参数：
  ///  - [item]             保养项目（含间隔与阈值）
  ///  - [latestRecord]     该项目最近一次保养记录（无历史时用基线兜底）
  ///  - [currentMileageKm] 车辆当前里程
  ///  - [noHistoryBaselineDate] 无历史记录时的时间基线（= 车辆上路日期）
  ///  - [today]            生效今天
  ///  - [noHistoryBaselineMileageKm] 无历史时的里程基线，默认 0
  ///    （注意：生产调用从不传该参数，二手高里程车会立刻算出超高进度，
  ///     属设计口径——按"从现在开始记录"理解，见审查报告 R37）
  ///
  /// 结果：里程/时间两维分别算百分比，取较大者作为展示进度；
  /// 但剩余公里/剩余天数分别来自各自维度（可能一正一负）。
  /// reason 标记进度来源，供 UI 区分"有记录"与"无历史估算"。
  static ReminderProgress progressForItem({
    required MaintenanceItem item,
    required MaintenanceRecord? latestRecord,
    required int currentMileageKm,
    required LocalDate noHistoryBaselineDate,
    required LocalDate today,
    int noHistoryBaselineMileageKm = 0,
  }) {
    // 先跑实体自校验（非法项目直接抛 ArgumentError，fail-fast）。
    item.validate();

    final mileageProgress = _mileageProgress(
      item: item,
      latestRecord: latestRecord,
      currentMileageKm: currentMileageKm,
      noHistoryBaselineMileageKm: noHistoryBaselineMileageKm,
    );
    final timeProgress = _timeProgress(
      item: item,
      latestRecord: latestRecord,
      noHistoryBaselineDate: noHistoryBaselineDate,
      today: today,
    );

    // 双维取大：哪个维度更接近到期，就按哪个展示。
    final progress = mileageProgress.percent >= timeProgress.percent
        ? mileageProgress
        : timeProgress;
    return ReminderProgress(
      percent: progress.percent,
      status: _statusForItem(item, progress.percent),
      reason: progress.reason,
      mileageRemainingKm: mileageProgress.remaining,
      daysRemaining: timeProgress.remaining,
    );
  }

  /// 按项目自身阈值判状态：≥overdueUpperLimit 超期红 /
  /// ≥notOverdueUpperLimit 到期黄 / 其余正常绿。
  static ReminderStatus _statusForItem(MaintenanceItem item, double percent) {
    if (percent >= item.overdueUpperLimit) {
      return ReminderStatus.danger;
    }
    if (percent >= item.notOverdueUpperLimit) {
      return ReminderStatus.warning;
    }
    return ReminderStatus.normal;
  }

  /// 里程维进度：基线里程 = 最近记录里程（无记录则用兜底基线）；
  /// 已用 = 当前里程 − 基线；百分比 = 已用/间隔×100（负数归 0）；
  /// 剩余 = 间隔 − max(已用, 0)。未启用该维时进度 0、reason=disabled。
  static _Progress _mileageProgress({
    required MaintenanceItem item,
    required MaintenanceRecord? latestRecord,
    required int currentMileageKm,
    required int noHistoryBaselineMileageKm,
  }) {
    if (!item.remindByMileage || item.mileageIntervalKm == null) {
      return const _Progress(0, 'mileage-disabled');
    }
    final baselineMileageKm =
        latestRecord?.mileageKm ?? noHistoryBaselineMileageKm;
    final usedKm = currentMileageKm - baselineMileageKm;
    final percent = usedKm <= 0 ? 0 : usedKm / item.mileageIntervalKm! * 100;
    final remaining = item.mileageIntervalKm! - (usedKm <= 0 ? 0 : usedKm);
    return _Progress(
      percent.toDouble(),
      latestRecord == null ? 'mileage-no-history' : 'mileage',
      remaining,
    );
  }

  /// 时间维进度：基线日 = 最近记录日期（无记录则用车辆上路日期）；
  /// 到期日 = 基线日 + 间隔月（addMonths 自动月末钳制）；
  /// 百分比 = 已用天数/总天数×100（任一 ≤0 时归 0，兼容"今天=基线日"
  /// 与防御未来日期基线）。剩余天数 = 今天 → 到期日（负数即已超期）。
  static _Progress _timeProgress({
    required MaintenanceItem item,
    required MaintenanceRecord? latestRecord,
    required LocalDate noHistoryBaselineDate,
    required LocalDate today,
  }) {
    if (!item.remindByTime || item.timeIntervalMonths == null) {
      return const _Progress(0, 'time-disabled');
    }
    final baselineDate = latestRecord?.date ?? noHistoryBaselineDate;
    final dueDate = baselineDate.addMonths(item.timeIntervalMonths!);
    final totalDays = baselineDate.daysUntil(dueDate);
    final usedDays = baselineDate.daysUntil(today);
    final remainingDays = today.daysUntil(dueDate);
    final percent = totalDays <= 0 || usedDays <= 0
        ? 0
        : usedDays / totalDays * 100;
    return _Progress(
      percent.toDouble(),
      latestRecord == null ? 'time-no-history' : 'time',
      remainingDays,
    );
  }
}

/// 顶层私有函数（下划线开头 = 仅本文件可见 ≈ Java 的 private static）。
LocalDate _addDays(LocalDate date, int days) {
  return LocalDate.fromDateTime(date.toDateTime().add(Duration(days: days)));
}

/// 单维进度的中间结果（私有 DTO）。
class _Progress {
  const _Progress(this.percent, this.reason, [this.remaining]);

  final double percent;
  final String reason;
  final int? remaining;
}
