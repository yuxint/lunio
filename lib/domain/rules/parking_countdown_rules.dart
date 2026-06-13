import '../entities/parking_countdown.dart';
import '../entities/reminder.dart';

class ParkingCountdownRules {
  const ParkingCountdownRules._();

  static ParkingCountdownProgress progress({
    required ParkingCountdown countdown,
    required DateTime now,
  }) {
    final totalSeconds = countdown.durationSeconds;
    final remainingMilliseconds = countdown.endsAt
        .difference(now)
        .inMilliseconds;
    if (remainingMilliseconds <= 0) {
      final expiredMilliseconds = now
          .difference(countdown.endsAt)
          .inMilliseconds;
      return ParkingCountdownProgress(
        remainingSeconds: 0,
        expiredSeconds: (expiredMilliseconds / Duration.millisecondsPerSecond)
            .ceil(),
        percentRemaining: 0,
        status: ReminderStatus.danger,
      );
    }
    final remainingSeconds =
        (remainingMilliseconds / Duration.millisecondsPerSecond).ceil();
    final percentRemaining =
        remainingMilliseconds /
        (totalSeconds * Duration.millisecondsPerSecond) *
        100;
    return ParkingCountdownProgress(
      remainingSeconds: remainingSeconds,
      expiredSeconds: 0,
      percentRemaining: percentRemaining,
      status: percentRemaining <= 20
          ? ReminderStatus.warning
          : ReminderStatus.normal,
    );
  }
}

class ParkingCountdownProgress {
  const ParkingCountdownProgress({
    required this.remainingSeconds,
    required this.expiredSeconds,
    required this.percentRemaining,
    required this.status,
  });

  final int remainingSeconds;
  final int expiredSeconds;
  final double percentRemaining;
  final ReminderStatus status;
}
