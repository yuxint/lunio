// 系统通知服务：对 flutter_local_notifications 插件的封装（单例）。
//
// 负责三类通知的调度与取消：
//  1. 保养到期/里程更新提醒 —— 由通知同步控制器的签名比对触发重排
//     （见 features/shell/reminders/notification_sync_controller.dart 的
//     _applySystemNotificationSchedule），每个通知排 8 次重复，取消时
//     精确取消在用的 16 个 id（见 R10）；
//  2. 停车倒计时通知族 —— 到点闹钟、剩余时长预警、Android 停车进行中
//     常驻通知（low priority + chronometer 倒计时显示，到点自动消失）。
//
// 通知身份（id、Android 渠道、payload、重复次数、错峰偏移）全部登记在
// 下方 LunioNotificationSlot 槽位台账——它是全 App 通知 id 的唯一事实源，
// 排通知与取消通知从同一张表推导。id 数值冻结：同一 id 已排进用户设备，
// 改号会让旧调度变成取消不掉的孤儿通知。
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
// HH:mm:ss 时刻格式化在 core 内部（core/format/clock.dart），
// 与停车倒计时卡片共用，不再反向依赖 features 层。
import '../format/clock.dart' show formatClock;

/// 通知槽位台账（CONTEXT.md 词汇：通知槽位）：App 内每一条系统通知的
/// 身份登记——基础 id、重复次数、Android 渠道、payload、错峰偏移。
///
/// 它是通知 id 的唯一事实源：排通知（rescheduleNotifications /
/// scheduleParkingCountdownNotification）与取消通知
/// （cancelLunioNotifications / cancelParkingCountdownNotification）都从
/// 这张表推导，调用方不再裸写 id 与渠道串——过去"调用方排 8000/8900、
/// 服务另存一份并行清单才能取消"的约定（R10）由此变成类型保证。
///
/// id 数值冻结：同一 id 已排进用户设备的通知中心，改号会让旧调度变成
/// 取消不掉的孤儿通知。家族归属与 payload 用穷举 switch 且刻意不写
/// default——新增槽位漏归族/漏定 payload 直接编译失败。
enum LunioNotificationSlot {
  /// 保养到期汇总通知（每天 9:00 起，按用户设置重复）。
  maintenanceSummary(
    baseId: 8000,
    occurrenceCount: 8,
    androidChannelId: 'lunio_maintenance_due_heads_up',
    androidChannelName: 'Lunio 保养到期提醒',
    androidChannelDescription: '车辆保养和里程更新提醒',
    scheduledMinuteOffset: 0,
  ),

  /// 里程更新提醒（9:05 错峰，避免与汇总通知同刻）。
  mileageUpdate(
    baseId: 8900,
    occurrenceCount: 8,
    androidChannelId: 'lunio_mileage_update_heads_up',
    androidChannelName: 'Lunio 里程更新提醒',
    androidChannelDescription: '车辆保养和里程更新提醒',
    scheduledMinuteOffset: 5,
  ),

  /// 停车倒计时到点闹钟（alarm 渠道，精确调度）。
  parkingAlarm(
    baseId: 9001,
    occurrenceCount: 1,
    androidChannelId: 'lunio_parking_due_heads_up',
    androidChannelName: 'Lunio 停车提醒',
    androidChannelDescription: '停车倒计时到点与剩余时长预警提醒',
    scheduledMinuteOffset: 0,
  ),

  /// Android 停车进行中常驻通知（chronometer 倒计时，到点自毁）。
  parkingOngoing(
    baseId: 9002,
    occurrenceCount: 1,
    androidChannelId: 'lunio_parking_ongoing',
    androidChannelName: 'Lunio 停车倒计时',
    androidChannelDescription: '停车倒计时进行中的常驻提醒',
    scheduledMinuteOffset: 0,
  ),

  /// 停车预警：剩余 15 分钟（与到点闹钟同渠道）。
  parkingWarning15(
    baseId: 9003,
    occurrenceCount: 1,
    androidChannelId: 'lunio_parking_due_heads_up',
    androidChannelName: 'Lunio 停车提醒',
    androidChannelDescription: '停车倒计时到点与剩余时长预警提醒',
    scheduledMinuteOffset: 0,
  ),

  /// 停车预警：剩余 5 分钟（与到点闹钟同渠道）。
  parkingWarning5(
    baseId: 9004,
    occurrenceCount: 1,
    androidChannelId: 'lunio_parking_due_heads_up',
    androidChannelName: 'Lunio 停车提醒',
    androidChannelDescription: '停车倒计时到点与剩余时长预警提醒',
    scheduledMinuteOffset: 0,
  );

  const LunioNotificationSlot({
    required this.baseId,
    required this.occurrenceCount,
    required this.androidChannelId,
    required this.androidChannelName,
    required this.androidChannelDescription,
    required this.scheduledMinuteOffset,
  });

  /// 通知基础 id（第 i 次重复的实际 id = baseId + i；单发槽位恒用它）。
  final int baseId;

  /// 该槽位一次排期占用的 id 个数（提醒族 8 次重复，停车族单发）。
  final int occurrenceCount;

  final String androidChannelId;
  final String androidChannelName;
  final String androidChannelDescription;

  /// 在每天 9:00 基础上偏移的分钟数（里程提醒 9:05 错峰；停车族不走
  /// 重排管线、按绝对时刻调度，恒为 0）。
  final int scheduledMinuteOffset;

  /// 点击通知带给系统的 payload：提醒族嵌基础 id，停车族共用固定 token。
  /// （预留点击路由用——当前 App 内尚无解析方，写而不读。）
  String get payload => switch (this) {
        LunioNotificationSlot.maintenanceSummary ||
        LunioNotificationSlot.mileageUpdate => 'lunio:$baseId',
        LunioNotificationSlot.parkingAlarm ||
        LunioNotificationSlot.parkingOngoing ||
        LunioNotificationSlot.parkingWarning15 ||
        LunioNotificationSlot.parkingWarning5 => 'lunio:parkingCountdown',
      };

  /// 是否提醒族（随数据重排被 cancelLunioNotifications 整体取消；停车族
  /// 单独成组取消）。穷举不写 default：新增槽位漏归族即编译失败。
  bool get isReminderFamily => switch (this) {
        LunioNotificationSlot.maintenanceSummary ||
        LunioNotificationSlot.mileageUpdate => true,
        LunioNotificationSlot.parkingAlarm ||
        LunioNotificationSlot.parkingOngoing ||
        LunioNotificationSlot.parkingWarning15 ||
        LunioNotificationSlot.parkingWarning5 => false,
      };
}

/// 一条"待调度的提醒通知"的描述（由 reminder_notifications.dart 组装）：
/// 身份（id/渠道/重复次数/错峰/payload）从 [slot] 的槽位台账推导，
/// 调用方只提供内容（标题/正文/重复频率）。
class LunioScheduledNotification {
  const LunioScheduledNotification({
    required this.slot,
    required this.title,
    required this.body,
    required this.repeatFrequency,
  });

  /// 通知身份取自哪个槽位。
  final LunioNotificationSlot slot;
  final String title;
  final String body;

  /// 重复频率（决定每次重复的间隔步进）。
  final ReminderRepeatFrequency repeatFrequency;
}

class LunioNotificationService {
  /// 公有构造：服务是普通可实例化类（依赖注入的插件连接封装），
  /// 测试每个用例 new 一个，互不污染。生产代码统一走 [instance]
  /// 单例（≈ Spring 里一个默认单例 Bean，类本身仍可 new）。
  LunioNotificationService();

  static const _androidNotificationIcon = 'ic_lunio_notification';

  static final LunioNotificationService instance = LunioNotificationService();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  /// 服务是否可用（false = 初始化失败后的降级态）。降级后：
  /// 权限/开关查询一律返回 false，调度/取消全部安全 no-op，
  /// 保证通知子系统故障不拖垮 App 主流程（R15）。
  bool _available = true;

  /// 初始化（幂等）：时区数据库 + 本地时区 + 插件初始化。
  /// main() 里 runApp 之前 await 一次。
  /// iOS 初始化不弹权限框（requestXxxPermission 全 false）——
  /// 权限统一由 [requestNotificationPermission] 在合适时机请求。
  /// 初始化抛异常（插件缺失/原生未注册等）时不外抛：标记服务不可用，
  /// 通知能力整体降级为 no-op，App 照常启动（R15）。
  Future<void> initialize() async {
    if (_initialized || !_available) {
      return;
    }
    try {
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
    } catch (error) {
      _available = false;
      debugPrint('LunioNotificationService 初始化失败，通知能力降级：$error');
    }
  }

  /// 显式标记服务不可用（main.dart 对 initialize 兜底 try/catch 时调用）。
  void markInitializationFailed() {
    _available = false;
  }

  /// 请求通知权限（iOS 弹系统对话框；Android 13+ 运行时权限）。
  /// 返回是否获得授权。服务不可用时返回 false。
  Future<bool> requestNotificationPermission() async {
    await initialize();
    if (!_available) {
      return false;
    }
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
  /// 通知设置 sheet 打开时用它回写真实状态。服务不可用时返回 false。
  Future<bool> notificationsEnabled() async {
    await initialize();
    if (!_available) {
      return false;
    }
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
  /// 服务不可用时返回 false（走非精确调度也排不出通知，等价拒绝）。
  Future<bool> requestExactAlarmPermission() async {
    await initialize();
    if (!_available) {
      return false;
    }
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
  ///  1. 先 cancelLunioNotifications() 清掉旧计划（精确取消 16 个在用
  ///     id，R10 收紧后不再是整段 1000 次）；
  ///  2. 每条通知从"下一个 9:00 + 槽位错峰偏移"开始排槽位登记的次数，
  ///     id = 槽位基础 id + 序号；exactAlarm 决定 Android 精确/非精确调度；
  ///  3. reservedDateTimes：停车到点时刻——若撞上则以 5 分钟为步长后移
  ///     （避免保养提醒盖掉停车闹钟的错峰机制）。
  Future<void> rescheduleNotifications(
    List<LunioScheduledNotification> notifications, {
    bool exactAlarm = true,
    List<DateTime> reservedDateTimes = const [],
  }) async {
    await initialize();
    if (!_available) {
      return;
    }
    await cancelLunioNotifications();
    final occupiedScheduleSlots = reservedDateTimes
        .map(_scheduleSlotKey)
        .toSet();
    for (final notification in notifications) {
      var scheduledDate = _nextScheduleDate(
        notification.repeatFrequency,
        minuteOffset: notification.slot.scheduledMinuteOffset,
      );
      for (var index = 0; index < notification.slot.occurrenceCount; index++) {
        final adjustedDate = _firstAvailableScheduleDate(
          scheduledDate,
          occupiedScheduleSlots,
        );
        await _plugin.zonedSchedule(
          id: notification.slot.baseId + index,
          title: notification.title,
          body: notification.body,
          scheduledDate: adjustedDate,
          notificationDetails: NotificationDetails(
            android: AndroidNotificationDetails(
              notification.slot.androidChannelId,
              notification.slot.androidChannelName,
              channelDescription: notification.slot.androidChannelDescription,
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
          payload: notification.slot.payload,
        );
        scheduledDate = _nextOccurrence(
          scheduledDate,
          notification.repeatFrequency,
        );
      }
    }
  }

  /// 取消全部保养/里程提醒：按槽位台账精确取消在用的 16 个 id
  /// （8000-8007 保养、8900-8907 里程；R10 收紧，不再串行扫 8000~8999
  /// 共 1000 个）。不碰停车族（成组取消走 cancelParkingCountdownNotification）。
  /// 服务不可用时安全 no-op。
  Future<void> cancelLunioNotifications() async {
    await initialize();
    if (!_available) {
      return;
    }
    for (final slot in LunioNotificationSlot.values) {
      if (!slot.isReminderFamily) {
        continue;
      }
      for (var index = 0; index < slot.occurrenceCount; index++) {
        await _plugin.cancel(id: slot.baseId + index);
      }
    }
  }

  /// 调度停车倒计时通知族（保存/开始倒计时时调用）：
  ///  1. 先成组取消旧停车族；
  ///  2. ⚠ 若到点时刻已过直接 return——此时没有任何通知，
  ///     且数据库里的倒计时仍在（无提示的静默状态，见 R17）；
  ///  3. Android 先发常驻倒计时通知（parkingOngoing 槽位），再调度到点
  ///     闹钟（parkingAlarm 槽位，alarm 类 channel，精确调度）；
  ///  4. 预警通知（parkingWarning15 / parkingWarning5 槽位）：按 [evaluatedAt]
  ///     （保存时刻，缺省用当前时刻）算剩余时长，≥ 30 分钟才成对调度，
  ///     剩余不足 30 分钟只有到点闹钟（CONTEXT.md 词汇：停车预警通知）。
  ///
  /// [evaluatedAt] 由调用方在保存动作入口先取好再走权限弹窗等异步链，
  /// 弹窗停留时间不挤占临界倒计时的剩余时长。
  Future<void> scheduleParkingCountdownNotification(
    ParkingCountdown countdown, {
    bool exactAlarm = true,
    DateTime? evaluatedAt,
  }) async {
    await initialize();
    if (!_available) {
      return;
    }
    await cancelParkingCountdownNotification();
    final scheduledDate = tz.TZDateTime.from(countdown.endsAt, tz.local);
    final referenceNow = tz.TZDateTime.from(
      evaluatedAt ?? tz.TZDateTime.now(tz.local),
      tz.local,
    );
    if (!scheduledDate.isAfter(referenceNow)) {
      return;
    }
    await _showAndroidParkingCountdownNotification(countdown);
    await _scheduleParkingAlarmNotification(
      slot: LunioNotificationSlot.parkingAlarm,
      scheduledDate: scheduledDate,
      body: '免费停车时间已到，记得及时离场。',
      exactAlarm: exactAlarm,
    );
    // 门槛按整分钟向上取整比较：表单默认入场时间截秒到整分，"整 30 分钟"
    // 的倒计时到真正调度时严格比较只剩 29 分多，向上取整让临界倒计时
    // 仍算"还剩 30 分钟"；剩余不足 29 分钟的短倒计时两条预警都不发。
    final remainingMinutes =
        scheduledDate.difference(referenceNow).inMilliseconds /
            Duration.millisecondsPerMinute;
    if (remainingMinutes.ceil() >= 30) {
      await _scheduleParkingAlarmNotification(
        slot: LunioNotificationSlot.parkingWarning15,
        scheduledDate: scheduledDate.subtract(const Duration(minutes: 15)),
        body: '免费停车还剩 15 分钟，请准备离场。',
        exactAlarm: exactAlarm,
      );
      await _scheduleParkingAlarmNotification(
        slot: LunioNotificationSlot.parkingWarning5,
        scheduledDate: scheduledDate.subtract(const Duration(minutes: 5)),
        body: '免费停车还剩 5 分钟，请尽快离场。',
        exactAlarm: exactAlarm,
      );
    }
  }

  /// 调度一条停车类闹钟通知（到点闹钟与预警共用）：alarm 渠道、精确/非
  /// 精确调度跟随 [exactAlarm]、单次不重复。到点与预警槽位在台账里登记
  /// 同一渠道（显示名"Lunio 停车提醒"）。
  Future<void> _scheduleParkingAlarmNotification({
    required LunioNotificationSlot slot,
    required tz.TZDateTime scheduledDate,
    required String body,
    required bool exactAlarm,
  }) async {
    await _plugin.zonedSchedule(
      id: slot.baseId,
      title: '停车倒计时',
      body: body,
      scheduledDate: scheduledDate,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          slot.androidChannelId,
          slot.androidChannelName,
          channelDescription: slot.androidChannelDescription,
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
      payload: slot.payload,
    );
  }

  /// 成组取消停车族通知（到点闹钟 + Android 常驻 + 两条预警，台账停车族
  /// 四槽位）。服务不可用时安全 no-op。结束倒计时、恢复备份/清空数据时
  /// 都会调用。
  Future<void> cancelParkingCountdownNotification() async {
    await initialize();
    if (!_available) {
      return;
    }
    for (final slot in LunioNotificationSlot.values) {
      if (slot.isReminderFamily) {
        continue;
      }
      await _plugin.cancel(id: slot.baseId);
    }
  }

  /// Android 专属：停车进行中的常驻通知（parkingOngoing 槽位）。
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
    final slot = LunioNotificationSlot.parkingOngoing;
    await _plugin.show(
      id: slot.baseId,
      title: '停车倒计时',
      body: '免费离场时间 ${formatClock(countdown.endsAt)}',
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          slot.androidChannelId,
          slot.androidChannelName,
          channelDescription: slot.androidChannelDescription,
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
      payload: slot.payload,
    );
  }

  /// 把 tz.local 设为设备实际时区；失败回退 Asia/Shanghai（R34：目标
  /// 市场时区、固定 +8 无夏令时——不再回退 UTC，避免非 UTC 设备的通知
  /// 时刻整体偏移一个时区差）并打日志（R14：不再静默吞异常）。
  Future<void> _configureLocalTimezone() async {
    try {
      final timezone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(timezone.identifier));
    } catch (error) {
      debugPrint(
        'LunioNotificationService: 获取系统时区失败($error)，'
        '回退为 Asia/Shanghai',
      );
      tz.setLocalLocation(tz.getLocation('Asia/Shanghai'));
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
      next = addCalendarDays(next, 1);
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
  /// monthly 分支做月末钳制：1 月 31 日排的月度提醒，下月没有 31 日就
  /// 钳到当月最后一天（2 月 28/29 日），与 LocalDate.addMonths 行为
  /// 一致（否则 TZDateTime(y, m+1, 31) 会溢出进位漂到 3 月初，R18）。
  /// 日/两周/三周分支走 [addCalendarDays] 日历加减（R34：不再用 24 小时
  /// Duration 相加，避免跨 DST 时区漂移墙钟时刻）。
  tz.TZDateTime _nextOccurrence(
    tz.TZDateTime date,
    ReminderRepeatFrequency frequency,
  ) {
    return switch (frequency) {
      ReminderRepeatFrequency.daily => addCalendarDays(date, 1),
      ReminderRepeatFrequency.weekly => addCalendarDays(date, 7),
      ReminderRepeatFrequency.everyTwoWeeks => addCalendarDays(date, 14),
      ReminderRepeatFrequency.everyThreeWeeks => addCalendarDays(date, 21),
      ReminderRepeatFrequency.monthly => nextMonthlyOccurrence(date),
    };
  }

  /// 按日历加 n 天（可为负）：保持墙钟时刻（时/分）不变，day 字段 +n
  /// 由 TZDateTime 构造器归一化跨月/跨年，与 Java 的
  /// ZonedDateTime.plusDays 思路一致（R34：替代 Duration 24 小时累加）。
  /// static + visibleForTesting 便于直接单测锁定该行为。
  @visibleForTesting
  static tz.TZDateTime addCalendarDays(tz.TZDateTime date, int days) {
    return tz.TZDateTime(
      tz.local,
      date.year,
      date.month,
      date.day + days,
      date.hour,
      date.minute,
    );
  }

  /// 月度步进 + 月末钳制：目标年月进位后，day 超过目标月天数时钳到
  /// 当月最后一天（如 1 月 31 日 → 2 月 28/29 日、12 月 31 日 → 次年
  /// 1 月 31 日）。static + visibleForTesting 便于直接单测锁定该行为。
  @visibleForTesting
  static tz.TZDateTime nextMonthlyOccurrence(tz.TZDateTime date) {
    // month 从 0 计，12 月 +1 自然进位到次年 1 月。
    final targetYear = date.month == 12 ? date.year + 1 : date.year;
    final targetMonth = date.month == 12 ? 1 : date.month + 1;
    // DateTime(y, m+1, 0).day 是"当月最后一天"的惯用取法。
    final lastDayOfMonth = DateTime(targetYear, targetMonth + 1, 0).day;
    final clampedDay = date.day < lastDayOfMonth ? date.day : lastDayOfMonth;
    return tz.TZDateTime(
      tz.local,
      targetYear,
      targetMonth,
      clampedDay,
      date.hour,
      date.minute,
    );
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
