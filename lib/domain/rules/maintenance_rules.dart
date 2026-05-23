import '../../core/date/local_date.dart';
import '../entities/maintenance_item.dart';
import '../entities/maintenance_record.dart';
import '../entities/reminder.dart';

class MaintenanceRules {
  const MaintenanceRules._();

  static ReminderStatus statusForPercent(double percent) {
    if (percent >= 125) {
      return ReminderStatus.danger;
    }
    if (percent >= 100) {
      return ReminderStatus.warning;
    }
    return ReminderStatus.normal;
  }

  static ReminderProgress progressForItem({
    required MaintenanceItem item,
    required MaintenanceRecord? latestRecord,
    required int currentMileageKm,
    required LocalDate noHistoryBaselineDate,
    required LocalDate today,
    int noHistoryBaselineMileageKm = 0,
  }) {
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

    final progress = mileageProgress.percent >= timeProgress.percent
        ? mileageProgress
        : timeProgress;
    return ReminderProgress(
      percent: progress.percent,
      status: _statusForItem(item, progress.percent),
      reason: progress.reason,
    );
  }

  static ReminderStatus _statusForItem(MaintenanceItem item, double percent) {
    if (percent >= item.overdueUpperLimit) {
      return ReminderStatus.danger;
    }
    if (percent >= item.notOverdueUpperLimit) {
      return ReminderStatus.warning;
    }
    return ReminderStatus.normal;
  }

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
    return _Progress(
      percent.toDouble(),
      latestRecord == null ? 'mileage-no-history' : 'mileage',
    );
  }

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
    final percent = totalDays <= 0 || usedDays <= 0
        ? 0
        : usedDays / totalDays * 100;
    return _Progress(
      percent.toDouble(),
      latestRecord == null ? 'time-no-history' : 'time',
    );
  }
}

class _Progress {
  const _Progress(this.percent, this.reason);

  final double percent;
  final String reason;
}
