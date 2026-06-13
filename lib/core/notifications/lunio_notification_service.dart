import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../../domain/entities/notification_settings.dart';
import '../../domain/entities/parking_countdown.dart';

class LunioScheduledNotification {
  const LunioScheduledNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.repeatFrequency,
    this.occurrenceCount = 8,
  });

  final int id;
  final String title;
  final String body;
  final ReminderRepeatFrequency repeatFrequency;
  final int occurrenceCount;
}

class LunioNotificationService {
  LunioNotificationService._();

  static const _parkingCountdownNotificationId = 9001;

  static final LunioNotificationService instance = LunioNotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    tz_data.initializeTimeZones();
    await _configureLocalTimezone();
    const initializationSettings = InitializationSettings(
      android: AndroidInitializationSettings('ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
        defaultPresentAlert: true,
        defaultPresentBadge: true,
        defaultPresentSound: true,
        defaultPresentBanner: true,
        defaultPresentList: true,
      ),
    );
    await _plugin.initialize(settings: initializationSettings);
    _initialized = true;
  }

  Future<bool> requestNotificationPermission() async {
    await initialize();
    final iosPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    if (iosPlugin != null) {
      return await iosPlugin.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
    }
    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (androidPlugin != null) {
      return await androidPlugin.requestNotificationsPermission() ?? false;
    }
    return !kIsWeb;
  }

  Future<void> rescheduleNotifications(
    List<LunioScheduledNotification> notifications,
  ) async {
    await initialize();
    await cancelLunioNotifications();
    for (final notification in notifications) {
      var scheduledDate = _nextScheduleDate(notification.repeatFrequency);
      for (var index = 0; index < notification.occurrenceCount; index++) {
        await _plugin.zonedSchedule(
          id: notification.id + index,
          title: notification.title,
          body: notification.body,
          scheduledDate: scheduledDate,
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              'lunio_reminders',
              'Lunio 提醒',
              channelDescription: '车辆保养和里程更新提醒',
              importance: Importance.high,
              priority: Priority.high,
            ),
            iOS: DarwinNotificationDetails(
              presentAlert: true,
              presentBadge: true,
              presentSound: true,
            ),
          ),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          payload: 'lunio:${notification.id}',
        );
        scheduledDate = _nextOccurrence(
          scheduledDate,
          notification.repeatFrequency,
        );
      }
    }
  }

  Future<void> cancelLunioNotifications() async {
    await initialize();
    for (var id = 8000; id < 9000; id++) {
      await _plugin.cancel(id: id);
    }
  }

  Future<void> scheduleParkingCountdownNotification(
    ParkingCountdown countdown,
  ) async {
    await initialize();
    await cancelParkingCountdownNotification();
    final scheduledDate = tz.TZDateTime.from(countdown.endsAt, tz.local);
    if (!scheduledDate.isAfter(tz.TZDateTime.now(tz.local))) {
      return;
    }
    await _plugin.zonedSchedule(
      id: _parkingCountdownNotificationId,
      title: '停车倒计时',
      body: '免费停车时间已到，记得及时离场。',
      scheduledDate: scheduledDate,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'lunio_parking',
          'Lunio 停车计时',
          channelDescription: '停车倒计时到点提醒',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: 'lunio:parkingCountdown',
    );
  }

  Future<void> cancelParkingCountdownNotification() async {
    await initialize();
    await _plugin.cancel(id: _parkingCountdownNotificationId);
  }

  Future<void> _configureLocalTimezone() async {
    try {
      final timezone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(timezone.identifier));
    } catch (_) {
      tz.setLocalLocation(tz.UTC);
    }
  }

  tz.TZDateTime _nextScheduleDate(ReminderRepeatFrequency frequency) {
    final now = tz.TZDateTime.now(tz.local);
    var next = tz.TZDateTime(tz.local, now.year, now.month, now.day, 9);
    if (!next.isAfter(now)) {
      next = next.add(const Duration(days: 1));
    }
    return switch (frequency) {
      ReminderRepeatFrequency.daily => next,
      ReminderRepeatFrequency.weekly => next,
      ReminderRepeatFrequency.everyTwoWeeks => next,
      ReminderRepeatFrequency.everyThreeWeeks => next,
      ReminderRepeatFrequency.monthly => next,
    };
  }

  tz.TZDateTime _nextOccurrence(
    tz.TZDateTime date,
    ReminderRepeatFrequency frequency,
  ) {
    return switch (frequency) {
      ReminderRepeatFrequency.daily => date.add(const Duration(days: 1)),
      ReminderRepeatFrequency.weekly => date.add(const Duration(days: 7)),
      ReminderRepeatFrequency.everyTwoWeeks => date.add(
        const Duration(days: 14),
      ),
      ReminderRepeatFrequency.everyThreeWeeks => date.add(
        const Duration(days: 21),
      ),
      ReminderRepeatFrequency.monthly => tz.TZDateTime(
        tz.local,
        date.year,
        date.month + 1,
        date.day,
        date.hour,
        date.minute,
      ),
    };
  }
}
