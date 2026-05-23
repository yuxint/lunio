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
    required LocalDate today,
  }) {
    item.validate();

    final mileageProgress = _mileageProgress(
      item: item,
      latestRecord: latestRecord,
      currentMileageKm: currentMileageKm,
    );
    final timeProgress = _timeProgress(
      item: item,
      latestRecord: latestRecord,
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
  }) {
    if (!item.remindByMileage || item.mileageIntervalKm == null) {
      return const _Progress(0, 'mileage-disabled');
    }
    if (latestRecord == null) {
      return const _Progress(0, 'no-history');
    }
    final usedKm = currentMileageKm - latestRecord.mileageKm;
    final percent = usedKm <= 0 ? 0 : usedKm / item.mileageIntervalKm! * 100;
    return _Progress(percent.toDouble(), 'mileage');
  }

  static _Progress _timeProgress({
    required MaintenanceItem item,
    required MaintenanceRecord? latestRecord,
    required LocalDate today,
  }) {
    if (!item.remindByTime || item.timeIntervalMonths == null) {
      return const _Progress(0, 'time-disabled');
    }
    if (latestRecord == null) {
      return const _Progress(0, 'no-history');
    }
    final usedMonths = latestRecord.date.monthsUntil(today);
    final percent = usedMonths <= 0
        ? 0
        : usedMonths / item.timeIntervalMonths! * 100;
    return _Progress(percent.toDouble(), 'time');
  }
}

class _Progress {
  const _Progress(this.percent, this.reason);

  final double percent;
  final String reason;
}
