// 停车倒计时进度规则（纯静态工具类）。
//
// 输入停车倒计时 + 当前真实时刻，输出剩余秒数/已超时秒数/剩余百分比/状态。
// 由提醒页 ParkingCountdownCard 每 250ms 调用一次刷新进度环
// （真实时间驱动，不受开发者模式手动日期影响）。
import '../entities/parking_countdown.dart';
import '../entities/reminder.dart';

class ParkingCountdownRules {
  const ParkingCountdownRules._();

  /// 计算倒计时进度。
  ///
  /// 状态语义（复用保养提醒的三态色）：
  ///  - normal（绿）：剩余 > 20%；
  ///  - warning（黄）：剩余 ≤ 20%（快到免费时长了）；
  ///  - danger（红）：已到期，此时 remainingSeconds=0、
  ///    expiredSeconds 为已超时秒数（UI 改为正计时"已超时 xx:xx"）。
  static ParkingCountdownProgress progress({
    required ParkingCountdown countdown,
    required DateTime now,
  }) {
    final totalSeconds = countdown.durationSeconds;
    final remainingMilliseconds = countdown.endsAt
        .difference(now)
        .inMilliseconds;
    if (remainingMilliseconds <= 0) {
      // 已到期分支：算已超时秒数（向上取整，保证到点即显示 1 秒超时）。
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

/// 倒计时进度结果 DTO。
class ParkingCountdownProgress {
  const ParkingCountdownProgress({
    required this.remainingSeconds,
    required this.expiredSeconds,
    required this.percentRemaining,
    required this.status,
  });

  /// 剩余秒数（到期后为 0）。
  final int remainingSeconds;

  /// 已超时秒数（未到期为 0）。
  final int expiredSeconds;

  /// 剩余百分比 0~100（进度环用）。
  final double percentRemaining;

  /// normal / warning / danger。
  final ReminderStatus status;
}
