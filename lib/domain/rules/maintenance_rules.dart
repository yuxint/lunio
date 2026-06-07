import '../../core/date/local_date.dart';
import '../entities/maintenance_item.dart';
import '../entities/maintenance_record.dart';
import '../entities/notification_settings.dart';
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
      mileageRemainingKm: mileageProgress.remaining,
      daysRemaining: timeProgress.remaining,
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
    final remaining = item.mileageIntervalKm! - (usedKm <= 0 ? 0 : usedKm);
    return _Progress(
      percent.toDouble(),
      latestRecord == null ? 'mileage-no-history' : 'mileage',
      remaining,
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

LocalDate _addDays(LocalDate date, int days) {
  return LocalDate.fromDateTime(date.toDateTime().add(Duration(days: days)));
}

class _Progress {
  const _Progress(this.percent, this.reason, [this.remaining]);

  final double percent;
  final String reason;
  final int? remaining;
}
