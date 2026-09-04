// 通知服务单元测试（原 core/ 与 core/notifications/ 两个文件合并，
// 脚手架统一为"每个用例新建服务实例 + 默认 happy-path 通道 mock"）。
//
// 覆盖面：
//  - 通道行为：权限查询（Android/iOS）、9:00 精确调度、停车倒计时
//    到点闹钟 + Android 常驻倒计时、成对取消、精确闹钟被拒降级非精确；
//  - 降级：初始化失败（R15）与 markInitializationFailed 后全部 no-op；
//  - 纯函数：月度重复的月末钳制（R18）、日历步进保墙钟（R34）；
//  - 时区回退：系统时区查询失败回退 Asia/Shanghai（R34/R14）。
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

  late LunioNotificationService service;
  late List<MethodCall> notificationCalls;

  /// 默认通道 mock：Android 平台 + 全部授权/允许（happy path）。
  /// 需要特殊行为的用例在用例内重新注册同名 handler 覆盖。
  void mockDefaultHandlers() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(timezoneChannel, (call) async {
          if (call.method == 'getLocalTimezone') {
            return 'Asia/Shanghai';
          }
          return null;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notificationsChannel, (call) async {
          notificationCalls.add(call);
          return switch (call.method) {
            'initialize' => true,
            'requestNotificationsPermission' => true,
            'areNotificationsEnabled' => true,
            'canScheduleExactNotifications' => true,
            'requestExactAlarmsPermission' => true,
            _ => null,
          };
        });
  }

  void registerAndroidPlatform() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
  }

  setUp(() {
    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.UTC);
    registerAndroidPlatform();
    notificationCalls = <MethodCall>[];
    // 每个用例新建实例：实例间不共享初始化状态，无需 resetForTest。
    service = LunioNotificationService();
    mockDefaultHandlers();
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notificationsChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(timezoneChannel, null);
  });

  // ---------------- 通道行为 ----------------

  test(
    'Android notification permission status is read from the system',
    () async {
      await service.notificationsEnabled();

      expect(
        notificationCalls.map((call) => call.method),
        contains('areNotificationsEnabled'),
      );
    },
  );

  test('iOS notification permission status is read from the system', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    IOSFlutterLocalNotificationsPlugin.registerWith();
    notificationCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notificationsChannel, (call) async {
          notificationCalls.add(call);
          return switch (call.method) {
            'initialize' => true,
            'checkPermissions' => {
              'isEnabled': true,
              'isSoundEnabled': true,
              'isAlertEnabled': true,
              'isBadgeEnabled': true,
              'isProvisionalEnabled': false,
              'isCriticalEnabled': false,
            },
            _ => null,
          };
        });

    final enabled = await service.notificationsEnabled();

    expect(enabled, isTrue);
    expect(
      notificationCalls.map((call) => call.method),
      contains('checkPermissions'),
    );
  });

  test('reminder notifications use alert channel at precise 9:00', () async {
    await service.rescheduleNotifications([
      const LunioScheduledNotification(
        id: 8000,
        title: '保养提醒',
        body: '测试车辆有保养项目到期。',
        repeatFrequency: ReminderRepeatFrequency.weekly,
        occurrenceCount: 1,
      ),
      const LunioScheduledNotification(
        id: 8900,
        title: '更新车辆里程',
        body: '建议更新测试车辆的当前里程。',
        repeatFrequency: ReminderRepeatFrequency.monthly,
        scheduledMinuteOffset: 5,
        androidChannelId: 'lunio_mileage_update_heads_up',
        androidChannelName: 'Lunio 里程更新提醒',
        occurrenceCount: 1,
      ),
    ]);

    final scheduledCalls = notificationCalls
        .where((call) => call.method == 'zonedSchedule')
        .toList();
    expect(scheduledCalls, hasLength(2));
    final scheduledByTitle = <String, DateTime>{};
    final channelByTitle = <String, String>{};
    for (final scheduledCall in scheduledCalls) {
      final arguments = scheduledCall.arguments as Map<Object?, Object?>;
      final scheduledDate = DateTime.parse(
        arguments['scheduledDateTime'] as String,
      );
      expect(scheduledDate.second, 0);
      final title = arguments['title'] as String;
      scheduledByTitle[title] = scheduledDate;
      final specifics = arguments['platformSpecifics'] as Map<Object?, Object?>;
      channelByTitle[title] = specifics['channelId'] as String;
      expect(specifics['importance'], 5);
      expect(specifics['priority'], 2);
      expect(specifics['category'], 'reminder');
      expect(specifics['fullScreenIntent'], isFalse);
      expect(specifics['scheduleMode'], 'exactAllowWhileIdle');
    }
    expect(scheduledByTitle['保养提醒']!.hour, 9);
    expect(scheduledByTitle['保养提醒']!.minute, 0);
    expect(channelByTitle['保养提醒'], 'lunio_maintenance_due_heads_up');
    expect(scheduledByTitle['更新车辆里程']!.hour, 9);
    expect(scheduledByTitle['更新车辆里程']!.minute, 5);
    expect(channelByTitle['更新车辆里程'], 'lunio_mileage_update_heads_up');
  });

  test('reminder notifications avoid parking countdown due time', () async {
    await service.rescheduleNotifications(
      [
        const LunioScheduledNotification(
          id: 8000,
          title: '保养提醒',
          body: '测试车辆有保养项目到期。',
          repeatFrequency: ReminderRepeatFrequency.weekly,
          occurrenceCount: 1,
        ),
        const LunioScheduledNotification(
          id: 8900,
          title: '更新车辆里程',
          body: '建议更新测试车辆的当前里程。',
          repeatFrequency: ReminderRepeatFrequency.monthly,
          scheduledMinuteOffset: 5,
          androidChannelId: 'lunio_mileage_update_heads_up',
          androidChannelName: 'Lunio 里程更新提醒',
          occurrenceCount: 1,
        ),
      ],
      reservedDateTimes: [_nextReminderDate()],
    );

    final scheduledByTitle = <String, DateTime>{};
    for (final scheduledCall in notificationCalls.where(
      (call) => call.method == 'zonedSchedule',
    )) {
      final arguments = scheduledCall.arguments as Map<Object?, Object?>;
      scheduledByTitle[arguments['title'] as String] = DateTime.parse(
        arguments['scheduledDateTime'] as String,
      );
    }
    expect(scheduledByTitle['保养提醒']!.hour, 9);
    expect(scheduledByTitle['保养提醒']!.minute, 5);
    expect(scheduledByTitle['更新车辆里程']!.hour, 9);
    expect(scheduledByTitle['更新车辆里程']!.minute, 10);
  });

  test(
    'parking countdown schedules due alert and Android ongoing timer',
    () async {
      final startedAt = DateTime.now();
      final countdown = ParkingCountdown(
        startedAt: startedAt,
        durationSeconds: 1800,
      );
      final leaveTime = _formatClock(countdown.endsAt);

      await service.scheduleParkingCountdownNotification(countdown);

      expect(
        notificationCalls.map((call) => call.method),
        containsAllInOrder(<String>[
          'cancel',
          'cancel',
          'show',
          'zonedSchedule',
        ]),
      );

      final showCall = notificationCalls.singleWhere(
        (call) => call.method == 'show',
      );
      final showArguments = showCall.arguments as Map<Object?, Object?>;
      expect(showArguments['title'], '停车倒计时');
      expect(showArguments['body'], '免费离场时间 $leaveTime');
      expect(showArguments['payload'], 'lunio:parkingCountdown');
      final showSpecifics =
          showArguments['platformSpecifics'] as Map<Object?, Object?>;
      expect(showSpecifics['channelId'], 'lunio_parking_ongoing');
      expect(showSpecifics['icon'], 'ic_lunio_notification');
      expect(showSpecifics['ongoing'], isTrue);
      expect(showSpecifics['autoCancel'], isFalse);
      expect(showSpecifics['silent'], isTrue);
      expect(showSpecifics['showWhen'], isTrue);
      expect(showSpecifics['when'], countdown.endsAt.millisecondsSinceEpoch);
      expect(showSpecifics['usesChronometer'], isTrue);
      expect(showSpecifics['chronometerCountDown'], isTrue);
      expect(showSpecifics['timeoutAfter'], isA<int>());
      expect(showSpecifics['timeoutAfter'] as int, greaterThan(0));
      expect(showSpecifics['timeoutAfter'] as int, lessThanOrEqualTo(1800000));

      final scheduledCall = notificationCalls.singleWhere(
        (call) => call.method == 'zonedSchedule',
      );
      final scheduleArguments =
          scheduledCall.arguments as Map<Object?, Object?>;
      expect(scheduleArguments['title'], '停车倒计时');
      expect(scheduleArguments['body'], '免费停车时间已到，记得及时离场。');
      final scheduleSpecifics =
          scheduleArguments['platformSpecifics'] as Map<Object?, Object?>;
      expect(scheduleSpecifics['channelId'], 'lunio_parking_due_heads_up');
      expect(scheduleSpecifics['icon'], 'ic_lunio_notification');
      expect(scheduleSpecifics['importance'], 5);
      expect(scheduleSpecifics['priority'], 2);
      expect(scheduleSpecifics['category'], 'alarm');
      expect(scheduleSpecifics['audioAttributesUsage'], 4);
      expect(scheduleSpecifics['fullScreenIntent'], isFalse);
      expect(scheduleSpecifics['scheduleMode'], 'exactAllowWhileIdle');
    },
  );

  test(
    'parking countdown cancellation clears due alert and ongoing timer',
    () async {
      await service.cancelParkingCountdownNotification();

      final cancelCalls = notificationCalls
          .where((call) => call.method == 'cancel')
          .map((call) => call.arguments as Map<Object?, Object?>)
          .toList();
      expect(cancelCalls, hasLength(2));
      expect(
        cancelCalls.map((arguments) => arguments['id']),
        containsAll([9001, 9002]),
      );
    },
  );

  test('exact alarm denial degrades reminders to inexact scheduling', () async {
    // 精确闹钟权限被拒：canScheduleExactNotifications false 且用户
    // 拒绝授权 → 请求返回 false，重排降级为 inexactAllowWhileIdle
    // （§7 测试缺口：此前 mock 恒 true，降级分支无覆盖）。
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notificationsChannel, (call) async {
          notificationCalls.add(call);
          return switch (call.method) {
            'initialize' => true,
            'canScheduleExactNotifications' => false,
            'requestExactAlarmsPermission' => false,
            _ => null,
          };
        });

    final granted = await service.requestExactAlarmPermission();
    expect(granted, isFalse);

    await service.rescheduleNotifications([
      const LunioScheduledNotification(
        id: 8000,
        title: '保养提醒',
        body: '测试车辆有保养项目到期。',
        repeatFrequency: ReminderRepeatFrequency.weekly,
        occurrenceCount: 1,
      ),
    ], exactAlarm: granted);

    final scheduledCall = notificationCalls.singleWhere(
      (call) => call.method == 'zonedSchedule',
    );
    final specifics =
        (scheduledCall.arguments as Map<Object?, Object?>)['platformSpecifics']
            as Map<Object?, Object?>;
    expect(specifics['scheduleMode'], 'inexactAllowWhileIdle');
  });

  // ---------------- 降级（R15）----------------

  testWidgets('service degrades to no-op after initialization failure', (
    tester,
  ) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(timezoneChannel, (call) async => 'UTC');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notificationsChannel, (call) async {
          if (call.method == 'initialize') {
            throw PlatformException(code: 'unavailable');
          }
          fail('初始化失败后不应再有通道调用：${call.method}');
        });

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
    // testWidgets 结束前必须复位平台覆写（框架不变量检查在 tearDown 前）。
    debugDefaultTargetPlatformOverride = null;
  });

  test('markInitializationFailed forces degraded mode', () async {
    service.markInitializationFailed();
    expect(await service.notificationsEnabled(), isFalse);
    expect(await service.requestNotificationPermission(), isFalse);
  });

  // ---------------- 纯函数（R18 / R34）----------------

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
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(timezoneChannel, (call) async {
          return 'UTC';
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notificationsChannel, (call) async {
          notificationCalls.add(call);
          return switch (call.method) {
            'initialize' => true,
            'canScheduleExactNotifications' => true,
            _ => null,
          };
        });

    await service.rescheduleNotifications([
      const LunioScheduledNotification(
        id: 8000,
        title: '保养提醒',
        body: '测试',
        repeatFrequency: ReminderRepeatFrequency.monthly,
      ),
    ]);

    final scheduledDates = notificationCalls
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
    debugDefaultTargetPlatformOverride = null;
  });

  test('addCalendarDays steps by calendar fields keeping wall clock', () {
    // R34：日/周步进不再用 24 小时 Duration 相加，改为字段构造——
    // 墙钟时刻（时/分）保持不变，跨月/跨年由构造器归一化。
    // 月末进位：1 月 31 日 + 1 天 → 2 月 1 日。
    final jan31 = tz.TZDateTime(tz.local, 2026, 1, 31, 9, 5);
    final feb1 = LunioNotificationService.addCalendarDays(jan31, 1);
    expect(feb1.year, 2026);
    expect(feb1.month, 2);
    expect(feb1.day, 1);
    expect(feb1.hour, 9);
    expect(feb1.minute, 5);

    // 年末进位：12 月 31 日 + 1 天 → 次年 1 月 1 日。
    final dec31 = tz.TZDateTime(tz.local, 2026, 12, 31, 9);
    final nextJan1 = LunioNotificationService.addCalendarDays(dec31, 1);
    expect(nextJan1.year, 2027);
    expect(nextJan1.month, 1);
    expect(nextJan1.day, 1);

    // 三周步进：3 月 15 日 + 21 天 → 4 月 5 日（跨月归一化正确）。
    final mar15 = tz.TZDateTime(tz.local, 2026, 3, 15, 9);
    final apr5 = LunioNotificationService.addCalendarDays(mar15, 21);
    expect(apr5.month, 4);
    expect(apr5.day, 5);

    // 负数回退：3 月 1 日 - 1 天 → 2 月 28 日（平年）。
    final mar1 = tz.TZDateTime(tz.local, 2026, 3, 1, 9);
    final back = LunioNotificationService.addCalendarDays(mar1, -1);
    expect(back.month, 2);
    expect(back.day, 28);
  });

  // ---------------- 时区回退（R34/R14）----------------

  testWidgets('timezone lookup failure falls back to Asia/Shanghai', (
    tester,
  ) async {
    // R34 步骤 1：获取系统时区失败时回退 Asia/Shanghai（目标市场时区、
    // 固定 +8 无夏令时），不再回退 UTC（避免通知时刻整体偏移一个时区差）。
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(timezoneChannel, (call) async {
          throw PlatformException(code: 'unavailable');
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notificationsChannel, (call) async {
          return switch (call.method) {
            'initialize' => true,
            _ => null,
          };
        });

    await service.initialize();
    debugDefaultTargetPlatformOverride = null;

    expect(tz.local.name, 'Asia/Shanghai');
  });
}

String _formatClock(DateTime dateTime) {
  final hour = dateTime.hour.toString().padLeft(2, '0');
  final minute = dateTime.minute.toString().padLeft(2, '0');
  final second = dateTime.second.toString().padLeft(2, '0');
  return '$hour:$minute:$second';
}

DateTime _nextReminderDate() {
  final now = DateTime.now();
  var next = DateTime(now.year, now.month, now.day, 9);
  if (!next.isAfter(now)) {
    next = next.add(const Duration(days: 1));
  }
  return next;
}
