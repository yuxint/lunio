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
    this.scheduledMinuteOffset = 0,
    this.androidChannelId = 'lunio_maintenance_due_heads_up',
    this.androidChannelName = 'Lunio 保养到期提醒',
    this.occurrenceCount = 8,
  });

  final int id;
  final String title;
  final String body;
  final ReminderRepeatFrequency repeatFrequency;
  final int scheduledMinuteOffset;
  final String androidChannelId;
  final String androidChannelName;
  final int occurrenceCount;
}

class LunioNotificationService {
  LunioNotificationService._();

  static const _androidNotificationIcon = 'ic_lunio_notification';
  static const _parkingCountdownNotificationId = 9001;
  static const _parkingCountdownOngoingNotificationId = 9002;

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
      android: AndroidInitializationSettings(_androidNotificationIcon),
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

  Future<bool> notificationsEnabled() async {
    await initialize();
    final iosPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    if (iosPlugin != null) {
      return (await iosPlugin.checkPermissions())?.isEnabled ?? false;
    }
    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (androidPlugin != null) {
      return await androidPlugin.areNotificationsEnabled() ?? false;
    }
    return !kIsWeb;
  }

  Future<bool> requestExactAlarmPermission() async {
    await initialize();
    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (androidPlugin == null) {
      return true;
    }
    final canScheduleExact =
        await androidPlugin.canScheduleExactNotifications() ?? false;
    if (canScheduleExact) {
      return true;
    }
    return await androidPlugin.requestExactAlarmsPermission() ?? false;
  }

  Future<void> rescheduleNotifications(
    List<LunioScheduledNotification> notifications, {
    bool exactAlarm = true,
    List<DateTime> reservedDateTimes = const [],
  }) async {
    await initialize();
    await cancelLunioNotifications();
    final occupiedScheduleSlots = reservedDateTimes
        .map(_scheduleSlotKey)
        .toSet();
    for (final notification in notifications) {
      var scheduledDate = _nextScheduleDate(
        notification.repeatFrequency,
        minuteOffset: notification.scheduledMinuteOffset,
      );
      for (var index = 0; index < notification.occurrenceCount; index++) {
        final adjustedDate = _firstAvailableScheduleDate(
          scheduledDate,
          occupiedScheduleSlots,
        );
        await _plugin.zonedSchedule(
          id: notification.id + index,
          title: notification.title,
          body: notification.body,
          scheduledDate: adjustedDate,
          notificationDetails: NotificationDetails(
            android: AndroidNotificationDetails(
              notification.androidChannelId,
              notification.androidChannelName,
              channelDescription: '车辆保养和里程更新提醒',
              importance: Importance.max,
              priority: Priority.max,
              category: AndroidNotificationCategory.reminder,
              icon: _androidNotificationIcon,
            ),
            iOS: DarwinNotificationDetails(
              presentAlert: true,
              presentBadge: true,
              presentSound: true,
            ),
          ),
          androidScheduleMode: exactAlarm
              ? AndroidScheduleMode.exactAllowWhileIdle
              : AndroidScheduleMode.inexactAllowWhileIdle,
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
    ParkingCountdown countdown, {
    bool exactAlarm = true,
  }) async {
    await initialize();
    await cancelParkingCountdownNotification();
    final scheduledDate = tz.TZDateTime.from(countdown.endsAt, tz.local);
    if (!scheduledDate.isAfter(tz.TZDateTime.now(tz.local))) {
      return;
    }
    await _showAndroidParkingCountdownNotification(countdown);
    await _plugin.zonedSchedule(
      id: _parkingCountdownNotificationId,
      title: '停车倒计时',
      body: '免费停车时间已到，记得及时离场。',
      scheduledDate: scheduledDate,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'lunio_parking_due_heads_up',
          'Lunio 停车到点提醒',
          channelDescription: '停车倒计时到点提醒',
          importance: Importance.max,
          priority: Priority.max,
          category: AndroidNotificationCategory.alarm,
          audioAttributesUsage: AudioAttributesUsage.alarm,
          icon: _androidNotificationIcon,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      androidScheduleMode: exactAlarm
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle,
      payload: 'lunio:parkingCountdown',
    );
  }

  Future<void> cancelParkingCountdownNotification() async {
    await initialize();
    await _plugin.cancel(id: _parkingCountdownNotificationId);
    await _plugin.cancel(id: _parkingCountdownOngoingNotificationId);
  }

  Future<void> _showAndroidParkingCountdownNotification(
    ParkingCountdown countdown,
  ) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    final remainingMilliseconds = countdown.endsAt
        .difference(DateTime.now())
        .inMilliseconds;
    if (remainingMilliseconds <= 0) {
      return;
    }
    await _plugin.show(
      id: _parkingCountdownOngoingNotificationId,
      title: '停车倒计时',
      body: '免费离场时间 ${_formatClock(countdown.endsAt)}',
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          'lunio_parking_ongoing',
          'Lunio 停车倒计时',
          channelDescription: '停车倒计时进行中的常驻提醒',
          importance: Importance.low,
          priority: Priority.low,
          autoCancel: false,
          ongoing: true,
          silent: true,
          onlyAlertOnce: true,
          showWhen: true,
          when: countdown.endsAt.millisecondsSinceEpoch,
          icon: _androidNotificationIcon,
          usesChronometer: true,
          chronometerCountDown: true,
          timeoutAfter: remainingMilliseconds,
          visibility: NotificationVisibility.public,
        ),
      ),
      payload: 'lunio:parkingCountdown',
    );
  }

  String _formatClock(DateTime dateTime) {
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final second = dateTime.second.toString().padLeft(2, '0');
    return '$hour:$minute:$second';
  }

  Future<void> _configureLocalTimezone() async {
    try {
      final timezone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(timezone.identifier));
    } catch (_) {
      tz.setLocalLocation(tz.UTC);
    }
  }

  tz.TZDateTime _nextScheduleDate(
    ReminderRepeatFrequency frequency, {
    int minuteOffset = 0,
  }) {
    final now = tz.TZDateTime.now(tz.local);
    var next = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      9,
    ).add(Duration(minutes: minuteOffset));
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

  tz.TZDateTime _firstAvailableScheduleDate(
    tz.TZDateTime date,
    Set<String> occupiedSlots,
  ) {
    var candidate = date;
    while (occupiedSlots.contains(_scheduleSlotKey(candidate))) {
      candidate = candidate.add(const Duration(minutes: 5));
    }
    occupiedSlots.add(_scheduleSlotKey(candidate));
    return candidate;
  }

  String _scheduleSlotKey(DateTime dateTime) {
    final localDateTime = tz.TZDateTime.from(dateTime, tz.local);
    return '${localDateTime.year}-'
        '${localDateTime.month.toString().padLeft(2, '0')}-'
        '${localDateTime.day.toString().padLeft(2, '0')} '
        '${localDateTime.hour.toString().padLeft(2, '0')}:'
        '${localDateTime.minute.toString().padLeft(2, '0')}';
  }
}
