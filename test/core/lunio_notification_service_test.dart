// 通知服务单元测试：初始化失败降级（R15）与月度重复的月末钳制（R18）。
//
// 说明：
//  - 服务是进程级单例，每个用例先 resetForTest 重置状态；
//  - "初始化失败"用 mock 通道对 initialize 抛 PlatformException 模拟；
//  - 月末钳制直接测 nextMonthlyOccurrence（visibleForTesting 静态方法），
//    并通过 rescheduleNotifications 的通道参数做一次集成断言。
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunio/core/notifications/lunio_notification_service.dart';
import 'package:lunio/domain/entities/notification_settings.dart';
import 'package:lunio/domain/entities/parking_countdown.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const notificationsChannel = MethodChannel(
    'dexterous.com/flutter/local_notifications',
  );
  const timezoneChannel = MethodChannel('flutter_timezone');

  setUp(() {
    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.UTC);
    LunioNotificationService.instance.resetForTest();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notificationsChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(timezoneChannel, null);
  });

  /// testWidgets 的不变量检查要求平台覆写在用例内复位，
  /// 所以 android 平台注册放在用例体内成对开关。
  void registerAndroidPlatform() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
  }

  void unregisterAndroidPlatform() {
    debugDefaultTargetPlatformOverride = null;
  }

  test('monthly occurrence clamps to end of shorter month', () {
    // 平年：1 月 31 日 → 2 月 28 日。
    final jan31 = tz.TZDateTime(tz.local, 2026, 1, 31, 9);
    final feb = LunioNotificationService.nextMonthlyOccurrence(jan31);
    expect(feb.year, 2026);
    expect(feb.month, 2);
    expect(feb.day, 28);
    expect(feb.hour, 9);

    // 闰年：1 月 31 日 → 2 月 29 日。
    final jan31Leap = tz.TZDateTime(tz.local, 2024, 1, 31, 9);
    final febLeap = LunioNotificationService.nextMonthlyOccurrence(jan31Leap);
    expect(febLeap.month, 2);
    expect(febLeap.day, 29);

    // 连续钳制：1.31 → 2.28 → 3.28（day 已被钳小后继续沿用）。
    final march = LunioNotificationService.nextMonthlyOccurrence(feb);
    expect(march.month, 3);
    expect(march.day, 28);

    // 年末进位：12 月 31 日 → 次年 1 月 31 日。
    final dec31 = tz.TZDateTime(tz.local, 2026, 12, 31, 9, 5);
    final nextJan = LunioNotificationService.nextMonthlyOccurrence(dec31);
    expect(nextJan.year, 2027);
    expect(nextJan.month, 1);
    expect(nextJan.day, 31);
    expect(nextJan.minute, 5);
  });

  testWidgets('rescheduleNotifications steps monthly with clamped days', (
    tester,
  ) async {
    registerAndroidPlatform();
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(timezoneChannel, (call) async {
          return 'UTC';
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notificationsChannel, (call) async {
          calls.add(call);
          return switch (call.method) {
            'initialize' => true,
            'canScheduleExactNotifications' => true,
            _ => null,
          };
        });

    await LunioNotificationService.instance.rescheduleNotifications([
      const LunioScheduledNotification(
        id: 8000,
        title: '保养提醒',
        body: '测试',
        repeatFrequency: ReminderRepeatFrequency.monthly,
      ),
    ]);
    unregisterAndroidPlatform();

    final scheduledDates = calls
        .where((call) => call.method == 'zonedSchedule')
        .map(
          (call) => DateTime.parse(
            (call.arguments as Map<Object?, Object?>)['scheduledDateTimeISO8601']
                as String,
          ),
        )
        .toList();
    expect(scheduledDates, hasLength(8));
    for (var index = 1; index < scheduledDates.length; index++) {
      final previous = scheduledDates[index - 1];
      final current = scheduledDates[index];
      // 每次步进恰好一个月（年进位 +12）。
      final monthDelta =
          (current.year - previous.year) * 12 + current.month - previous.month;
      expect(monthDelta, 1);
      // day 钳制：不大于上月 day，也不超过目标月天数。
      final lastDayOfCurrent =
          DateTime(current.year, current.month + 1, 0).day;
      expect(current.day, lessThanOrEqualTo(previous.day));
      expect(current.day, lessThanOrEqualTo(lastDayOfCurrent));
    }
  });

  testWidgets('service degrades to no-op after initialization failure', (
    tester,
  ) async {
    registerAndroidPlatform();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(timezoneChannel, (call) async => 'UTC');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notificationsChannel, (call) async {
          if (call.method == 'initialize') {
            throw PlatformException(code: 'unavailable');
          }
          fail('初始化失败后不应再有通道调用：${call.method}');
        });

    final service = LunioNotificationService.instance;
    await service.initialize();
    // 初始化失败不外抛，服务进入降级态。
    await service.cancelLunioNotifications();
    await service.cancelParkingCountdownNotification();
    await service.scheduleParkingCountdownNotification(
      ParkingCountdown(startedAt: DateTime.now(), durationSeconds: 1800),
    );
    expect(await service.notificationsEnabled(), isFalse);
    expect(await service.requestNotificationPermission(), isFalse);
    expect(await service.requestExactAlarmPermission(), isFalse);
    unregisterAndroidPlatform();
  });

  test('markInitializationFailed forces degraded mode', () async {
    final service = LunioNotificationService.instance;
    service.markInitializationFailed();
    expect(await service.notificationsEnabled(), isFalse);
    expect(await service.requestNotificationPermission(), isFalse);
  });
}
