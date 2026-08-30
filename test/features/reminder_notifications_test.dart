// 提醒 view 规则的单元测试：snooze 到期日边界、snooze 15 天的日历计算。
//
// isSnoozed / snoozeUntilDate 定义在 reminder_notifications.dart（view 层
// 的纯判断函数），这里用内存数据库直接驱动，锁死以下语义：
//  - snooze 截止日当天仍静默（`until >= today` 的 >= 语义）；
//  - 截止日次日恢复提醒；
//  - +15 天走 LocalDate 日历加减（R34）。
import 'package:flutter_test/flutter_test.dart';
import 'package:lunio/core/date/local_date.dart';
import 'package:lunio/data/database/app_database.dart';
import 'package:lunio/data/repositories/lunio_repository.dart';
import 'package:lunio/domain/rules/maintenance_rules.dart';
import 'package:lunio/features/shell/reminders/reminder_notifications.dart';

void main() {
  late AppDatabase database;
  late LunioRepository repository;

  setUp(() {
    database = AppDatabase.inMemory();
    repository = LunioRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  test('snooze keeps the reminder silent on the until day, resumes next day', () async {
    const key = '${LunioRepository.maintenanceReminderSnoozedUntilPrefix}1';
    // 模拟 2026-05-19 点"稍后提醒"：截止日 = 今天 + 15 天 = 2026-06-03。
    await repository.setPreferenceValue(
      key,
      snoozeUntilDate(const LocalDate(2026, 5, 19)).toString(),
    );

    // 截止期内（含截止日当天）一律静默。
    expect(await isSnoozed(repository, key, const LocalDate(2026, 5, 19)), isTrue);
    expect(await isSnoozed(repository, key, const LocalDate(2026, 6, 2)), isTrue);
    expect(await isSnoozed(repository, key, const LocalDate(2026, 6, 3)), isTrue);
    // 截止日次日恢复提醒。
    expect(await isSnoozed(repository, key, const LocalDate(2026, 6, 4)), isFalse);
  });

  test('isSnoozed returns false without or with unparsable preference', () async {
    const key = '${LunioRepository.maintenanceReminderSnoozedUntilPrefix}2';
    expect(
      await isSnoozed(repository, key, const LocalDate(2026, 6, 3)),
      isFalse,
    );

    await repository.setPreferenceValue(key, 'not-a-date');
    expect(
      await isSnoozed(repository, key, const LocalDate(2026, 6, 3)),
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
