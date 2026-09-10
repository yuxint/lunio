// 提醒静默规则的单元测试：snooze 到期日边界、snooze 15 天的日历计算、
// "知道了"只静默当天应用内弹窗。
//
// 静默协议（"稍后提醒"/"知道了"）已收编进通知协调器
// notification_coordinator.dart，这里用内存数据库驱动协调器本体，
// 锁死以下语义：
//  - snooze 截止日当天仍静默（`until >= today` 的 >= 语义）；
//  - 截止日次日恢复提醒；
//  - +15 天走 LocalDate 日历加减（R34）；
//  - "知道了"只静默当天的应用内弹窗，系统通知照发。
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lunio/app/providers.dart';
import 'package:lunio/core/date/local_date.dart';
import 'package:lunio/data/database/app_database.dart';
import 'package:lunio/data/preferences/app_preferences.dart';
import 'package:lunio/domain/rules/maintenance_rules.dart';
import 'package:lunio/features/shell/reminders/notification_coordinator.dart';

void main() {
  late AppDatabase database;
  late ProviderContainer container;
  late LunioPreferences preferences;
  late LunioNotificationCoordinator coordinator;

  setUp(() {
    database = AppDatabase.inMemory();
    container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(database)],
    );
    preferences = container.read(lunioPreferencesProvider);
    coordinator = container.read(notificationCoordinatorProvider);
  });

  tearDown(() async {
    container.dispose();
    await database.close();
  });

  test('snooze keeps the reminder silent on the until day, resumes next day', () async {
    // 模拟 2026-05-19 点"稍后提醒"：截止日 = 今天 + 15 天 = 2026-06-03。
    await coordinator.snoozeMaintenanceItems([1], const LocalDate(2026, 5, 19));
    const target = MaintenanceItemTarget(1);

    // 截止期内（含截止日当天）系统通知一律静默。
    expect(
      await coordinator.isSilencedForSystemNotification(
        target,
        const LocalDate(2026, 5, 19),
      ),
      isTrue,
    );
    expect(
      await coordinator.isSilencedForSystemNotification(
        target,
        const LocalDate(2026, 6, 2),
      ),
      isTrue,
    );
    expect(
      await coordinator.isSilencedForSystemNotification(
        target,
        const LocalDate(2026, 6, 3),
      ),
      isTrue,
    );
    // 截止日次日恢复提醒。
    expect(
      await coordinator.isSilencedForSystemNotification(
        target,
        const LocalDate(2026, 6, 4),
      ),
      isFalse,
    );
    // 应用内弹窗在同一窗口内同样静默。
    expect(
      await coordinator.isSilencedForInAppDialog(
        target,
        const LocalDate(2026, 6, 3),
      ),
      isTrue,
    );
  });

  test('snoozed mileage update uses the per-car key and the same window', () async {
    await coordinator.snoozeMileageUpdate(9, const LocalDate(2026, 5, 19));
    const target = MileageUpdateTarget(9);

    expect(
      await coordinator.isSilencedForSystemNotification(
        target,
        const LocalDate(2026, 6, 3),
      ),
      isTrue,
    );
    expect(
      await coordinator.isSilencedForSystemNotification(
        target,
        const LocalDate(2026, 6, 4),
      ),
      isFalse,
    );
    // 项目与车辆的 key 互不影响。
    expect(
      await coordinator.isSilencedForSystemNotification(
        const MileageUpdateTarget(10),
        const LocalDate(2026, 5, 19),
      ),
      isFalse,
    );
  });

  test('silence reads return false without or with unparsable preference', () async {
    // 直接用 Repository 写入脏数据（模拟不可解析的偏好值），协调器读为 false。
    const unparsableKey =
        '${LunioPreferences.maintenanceReminderSnoozedUntilPrefix}2';
    expect(
      await coordinator.isSilencedForSystemNotification(
        const MaintenanceItemTarget(2),
        const LocalDate(2026, 6, 3),
      ),
      isFalse,
    );

    await preferences.writeRaw(unparsableKey, 'not-a-date');
    expect(
      await coordinator.isSilencedForSystemNotification(
        const MaintenanceItemTarget(2),
        const LocalDate(2026, 6, 3),
      ),
      isFalse,
    );
  });

  test('acknowledgement silences the in-app dialog for the day only', () async {
    await coordinator.acknowledgeMaintenanceItem(3, const LocalDate(2026, 6, 3));
    const target = MaintenanceItemTarget(3);

    // 当天：应用内弹窗静默，但系统通知照发（"知道了"不影响系统通知）。
    expect(
      await coordinator.isSilencedForInAppDialog(
        target,
        const LocalDate(2026, 6, 3),
      ),
      isTrue,
    );
    expect(
      await coordinator.isSilencedForSystemNotification(
        target,
        const LocalDate(2026, 6, 3),
      ),
      isFalse,
    );
    // 次日：应用内弹窗恢复。
    expect(
      await coordinator.isSilencedForInAppDialog(
        target,
        const LocalDate(2026, 6, 4),
      ),
      isFalse,
    );
  });

  group('displayPercentForThresholds clamps before thresholds', () {
    test('rounds down when a round-up would reach the not-overdue threshold', () {
      // 默认阈值 100/125：真实 99.6% 四舍五入是 100，会被钳回 99，
      // 避免"还没到期就显示 100%"。
      expect(
        MaintenanceRules.displayPercentForThresholds(
          percent: 99.6,
          notOverdueUpperLimit: 100,
          overdueUpperLimit: 125,
        ),
        99,
      );
      // 124.8 四舍五入 125，钳回 124（不越过到期阈值）。
      expect(
        MaintenanceRules.displayPercentForThresholds(
          percent: 124.8,
          notOverdueUpperLimit: 100,
          overdueUpperLimit: 125,
        ),
        124,
      );
    });

    test('keeps the value when it already reached or passed a threshold', () {
      // 恰好到阈值：不钳制（状态判定本身已归入 warning/danger）。
      expect(
        MaintenanceRules.displayPercentForThresholds(
          percent: 100,
          notOverdueUpperLimit: 100,
          overdueUpperLimit: 125,
        ),
        100,
      );
      // 已超期：不再受上限钳制。
      expect(
        MaintenanceRules.displayPercentForThresholds(
          percent: 150.4,
          notOverdueUpperLimit: 100,
          overdueUpperLimit: 125,
        ),
        150,
      );
    });

    test('keeps normal-range rounding as-is', () {
      expect(
        MaintenanceRules.displayPercentForThresholds(
          percent: 0,
          notOverdueUpperLimit: 100,
          overdueUpperLimit: 125,
        ),
        0,
      );
      expect(
        MaintenanceRules.displayPercentForThresholds(
          percent: 66.5,
          notOverdueUpperLimit: 100,
          overdueUpperLimit: 125,
        ),
        67,
      );
    });
  });
}
