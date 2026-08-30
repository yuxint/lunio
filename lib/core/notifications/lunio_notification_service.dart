// 系统通知服务：对 flutter_local_notifications 插件的封装（单例）。
//
// 负责三类通知的调度与取消：
//  1. 保养到期/里程更新提醒 —— 由 AppShell 的签名比对触发重排（见
//     features/shell/app_shell.dart 的 _applySystemNotificationSchedule），
//     id 段 8000~8999（8000 系保养、8900 系里程，每个通知排 8 次）；
//  2. 停车到点闹钟 —— id 9001（channel lunio_parking_due_heads_up）；
//  3. Android 停车进行中常驻通知 —— id 9002（low priority +
//     chronometer 倒计时显示，到点自动消失）。
//
// 通知 id 分配表（改动会影响取消逻辑，见审查报告）：
//  8000-8007  保养到期汇总通知的 8 次重复
//  8900-8907  里程更新提醒的 8 次重复
//  9001       停车到点闹钟
//  9002       Android 停车常驻通知
//
// 时区：初始化时把 tz.local 设为设备时区（失败回退 UTC——非 UTC 设备
// 通知时刻会整体偏移，见审查报告 R14）；所有调度时刻用 TZDateTime。
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../../domain/entities/notification_settings.dart';
import '../../domain/entities/parking_countdown.dart';

/// 一条"待调度的提醒通知"的描述（由 reminder_notifications.dart 组装）。
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

  /// 通知基础 id（第 i 次重复的实际 id = id + i）。
  final int id;
  final String title;
  final String body;

  /// 重复频率（决定 8 次重复各自的间隔）。
  final ReminderRepeatFrequency repeatFrequency;

  /// 在每天 9:00 基础上偏移的分钟数（里程提醒用 5 分钟错峰）。
  final int scheduledMinuteOffset;
  final String androidChannelId;
  final String androidChannelName;

  /// 排多少次重复提醒。
  final int occurrenceCount;
}

class LunioNotificationService {
  /// 私有构造 + static instance：饿汉单例（≈ Java 的 Singleton）。
  LunioNotificationService._();

  static const _androidNotificationIcon = 'ic_lunio_notification';

  /// 停车到点闹钟 / Android 常驻通知的固定 id（取消时成对取消）。
  static const _parkingCountdownNotificationId = 9001;
  static const _parkingCountdownOngoingNotificationId = 9002;

  static final LunioNotificationService instance = LunioNotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  /// 初始化（幂等）：时区数据库 + 本地时区 + 插件初始化。
  /// main() 里 runApp 之前 await 一次。
  /// iOS 初始化不弹权限框（requestXxxPermission 全 false）——
  /// 权限统一由 [requestNotificationPermission] 在合适时机请求。
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

  /// 请求通知权限（iOS 弹系统对话框；Android 13+ 运行时权限）。
  /// 返回是否获得授权。
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

  /// 查询系统层通知开关（用户可能在系统设置里关掉）。
  /// 通知设置 sheet 打开时用它回写真实状态。
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

  /// Android 精确闹钟权限（SCHEDULE_EXACT_ALARM）：到点提醒走精确调度。
  /// 已授权直接返回；未授权发起请求；非 Android 平台视为已授权。
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

  /// 全量重排保养/里程提醒。每次调用：
  ///  1. 先 cancelLunioNotifications() 清掉旧计划（⚠ 串行 cancel 8000~8999
  ///     共 1000 次，实际只用到 16 个 id，是性能放大器，见 R10）；
  ///  2. 每条通知从"下一个 9:00 + minuteOffset"开始排 occurrenceCount 次，
  ///     id = 基础 id + 序号；exactAlarm 决定 Android 精确/非精确调度；
  ///  3. reservedDateTimes：停车到点时刻——若撞上则以 5 分钟为步长后移
  ///     （避免保养提醒盖掉停车闹钟的错峰机制）。
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

  /// 取消全部保养/里程提醒：⚠ 按段循环 cancel 8000~8999（1000 次串行
  /// platform channel 调用）。不碰 9001/9002（停车通知单独取消）。
  Future<void> cancelLunioNotifications() async {
    await initialize();
    for (var id = 8000; id < 9000; id++) {
      await _plugin.cancel(id: id);
    }
  }

  /// 调度停车倒计时通知（保存/开始倒计时时调用）：
  ///  1. 先成对取消旧 9001/9002；
  ///  2. ⚠ 若到点时刻已过直接 return——此时既无闹钟也无常驻通知，
  ///     且数据库里的倒计时仍在（无提示的静默状态，见 R17）；
  ///  3. Android 先发常驻倒计时通知（9002），再调度到点闹钟（9001，
  ///     alarm 类 channel，精确调度）。
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

  /// 成对取消停车通知（9001 闹钟 + 9002 常驻）。
  /// 结束倒计时、以及理论上恢复备份/清空数据时都应调用（后者当前缺失，R1）。
  Future<void> cancelParkingCountdownNotification() async {
    await initialize();
    await _plugin.cancel(id: _parkingCountdownNotificationId);
    await _plugin.cancel(id: _parkingCountdownOngoingNotificationId);
  }

  /// Android 专属：停车进行中的常驻通知（9002）。
  /// 特性：low importance（不响铃不打断）+ ongoing（不可滑掉）+ silent +
  /// usesChronometer/chronometerCountDown（系统级倒计时秒表，锁屏可见）+
  /// when/timeoutAfter（到点时刻自毁）。iOS 无对应能力，直接跳过。
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

  /// 时刻格式化 HH:mm:ss。
  /// ⚠ 与 parking_countdown.dart 里的 _formatClock 重复实现（R32）。
  String _formatClock(DateTime dateTime) {
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final second = dateTime.second.toString().padLeft(2, '0');
    return '$hour:$minute:$second';
  }

  /// 把 tz.local 设为设备实际时区；失败回退 UTC（⚠ 无日志，
  /// 非 UTC 设备的通知时刻会整体偏移一个时区，R14）。
  Future<void> _configureLocalTimezone() async {
    try {
      final timezone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(timezone.identifier));
    } catch (_) {
      tz.setLocalLocation(tz.UTC);
    }
  }

  /// 计算首次调度时刻：今天/明天（取较晚者）的 9:00 + minuteOffset。
  /// 已过今天 9:00 则顺延到明天 9:00。frequency 参数目前不影响首日
  /// （只影响后续重复的步进）。
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

  /// 按频率步进到下一次重复时刻。
  /// ⚠ monthly 分支用 TZDateTime(y, month+1, day) 无月末钳制：
  /// 1.31 排的月度提醒会漂到 3.3（与 LocalDate.addMonths 行为不一致，R18）。
  /// 日/周步进用 Duration 相加，跨 DST 时区的小时会漂（目标市场无 DST）。
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

  /// 错峰算法：候选时刻若被停车到点时刻占用，以 5 分钟步长后移，
  /// 直到空位；选中后立即登记占用（同一停车时刻不会被两条提醒抢占）。
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

  /// 槽位键：yyyy-MM-dd HH:mm（分钟粒度），用于错峰比对。
  String _scheduleSlotKey(DateTime dateTime) {
    final localDateTime = tz.TZDateTime.from(dateTime, tz.local);
    return '${localDateTime.year}-'
        '${localDateTime.month.toString().padLeft(2, '0')}-'
        '${localDateTime.day.toString().padLeft(2, '0')} '
        '${localDateTime.hour.toString().padLeft(2, '0')}:'
        '${localDateTime.minute.toString().padLeft(2, '0')}';
  }
}
