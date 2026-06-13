import 'package:flutter_test/flutter_test.dart';
import 'package:lunio/domain/entities/parking_countdown.dart';
import 'package:lunio/domain/entities/reminder.dart';
import 'package:lunio/domain/rules/parking_countdown_rules.dart';

void main() {
  group('ParkingCountdownRules', () {
    test('calculates active countdown progress', () {
      final countdown = ParkingCountdown(
        startedAt: DateTime(2026, 6, 10, 10, 20),
        durationSeconds: 7200,
      );

      final progress = ParkingCountdownRules.progress(
        countdown: countdown,
        now: DateTime(2026, 6, 10, 10, 50),
      );

      expect(progress.remainingSeconds, 5400);
      expect(progress.percentRemaining, 75);
      expect(progress.status, ReminderStatus.normal);
      expect(progress.expiredSeconds, 0);
    });

    test('marks countdown as warning in the final twenty percent', () {
      final countdown = ParkingCountdown(
        startedAt: DateTime(2026, 6, 10, 10),
        durationSeconds: 3600,
      );

      final progress = ParkingCountdownRules.progress(
        countdown: countdown,
        now: DateTime(2026, 6, 10, 10, 50),
      );

      expect(progress.remainingSeconds, 600);
      expect(progress.status, ReminderStatus.warning);
    });

    test('marks expired countdown as danger', () {
      final countdown = ParkingCountdown(
        startedAt: DateTime(2026, 6, 10, 10),
        durationSeconds: 1800,
      );

      final progress = ParkingCountdownRules.progress(
        countdown: countdown,
        now: DateTime(2026, 6, 10, 10, 42),
      );

      expect(progress.remainingSeconds, 0);
      expect(progress.expiredSeconds, 720);
      expect(progress.percentRemaining, 0);
      expect(progress.status, ReminderStatus.danger);
    });

    test('keeps percent moving at second precision', () {
      final countdown = ParkingCountdown(
        startedAt: DateTime(2026, 6, 10, 10),
        durationSeconds: 1800,
      );

      final progress = ParkingCountdownRules.progress(
        countdown: countdown,
        now: DateTime(2026, 6, 10, 10, 0, 1),
      );

      expect(progress.remainingSeconds, 1799);
      expect(progress.percentRemaining, closeTo(99.94, 0.01));
    });

    test('keeps percent moving evenly between seconds', () {
      final countdown = ParkingCountdown(
        startedAt: DateTime(2026, 6, 10, 10),
        durationSeconds: 1800,
      );

      final progress = ParkingCountdownRules.progress(
        countdown: countdown,
        now: DateTime(2026, 6, 10, 10, 0, 0, 500),
      );

      expect(progress.remainingSeconds, 1800);
      expect(progress.percentRemaining, closeTo(99.97, 0.01));
    });

    test('rejects non-positive durations', () {
      expect(
        () => ParkingCountdown(
          startedAt: DateTime(2026, 6, 10),
          durationSeconds: 0,
        ),
        throwsArgumentError,
      );
    });
  });
}
