enum ReminderStatus { normal, warning, danger }

class ReminderProgress {
  const ReminderProgress({
    required this.percent,
    required this.status,
    required this.reason,
    this.mileageRemainingKm,
    this.daysRemaining,
  });

  final double percent;
  final ReminderStatus status;
  final String reason;
  final int? mileageRemainingKm;
  final int? daysRemaining;
}
