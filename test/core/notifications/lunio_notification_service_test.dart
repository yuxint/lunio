import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lunio/core/notifications/lunio_notification_service.dart';
import 'package:lunio/domain/entities/notification_settings.dart';
import 'package:lunio/domain/entities/parking_countdown.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const notificationsChannel = MethodChannel(
    'dexterous.com/flutter/local_notifications',
  );
  const timezoneChannel = MethodChannel('flutter_timezone');

  late List<MethodCall> notificationCalls;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    notificationCalls = <MethodCall>[];

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
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notificationsChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(timezoneChannel, null);
  });

  test(
    'Android notification permission status is read from the system',
    () async {
      await LunioNotificationService.instance.notificationsEnabled();

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

    final enabled = await LunioNotificationService.instance
        .notificationsEnabled();

    expect(enabled, isTrue);
    expect(
      notificationCalls.map((call) => call.method),
      contains('checkPermissions'),
    );
  });

  test('reminder notifications use alert channel at precise 9:00', () async {
    await LunioNotificationService.instance.rescheduleNotifications([
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
    await LunioNotificationService.instance.rescheduleNotifications(
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

      await LunioNotificationService.instance
          .scheduleParkingCountdownNotification(countdown);

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
      await LunioNotificationService.instance
          .cancelParkingCountdownNotification();

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
