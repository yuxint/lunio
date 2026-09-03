// 通知同步控制器：把"提醒数据变化 → 重排系统通知 / 弹应用内提醒"
// 从 AppShell 的 build 里抽出来的独立协调器（≈ Spring 的一个 @Service，
// 生命周期挂在主壳层 State 上）。
//
// 触发方式（R12 修复）：start() 对 6 个数据 provider ref.listenManual
// （fireImmediately: true）——数据一变（或首拍）就调 syncFromProviders，
// 不再依赖"build 里 watch + postFrame 副作用"的反模式。
//
// 同步策略（沿用签名比对）：
//  - 系统通知签名 = 提醒频率 + 停车倒计时摘要 + 全量数据签名；
//  - 应用内签名 = 应用内开关 + 到期开关 + 全量数据签名；
//  - 签名变化才做真正的调度/弹窗，避免重复 I/O。
//
// 防竞态三层：
//  1. 代数（notificationSyncGenerationProvider）：恢复/清空时 bump，
//     在途任务比对快照代数，不一致即放弃（R8）；
//  2. 执行中标志 + pending 重跑：系统通知重排执行中又来了新签名时
//     不再丢弃，而是置 pending，本轮 finally 里用最新数据强制重排
//     一轮（R3 丢更新修复）；
//  3. _disposed 检查：所有 await 之后确认控制器还活着才继续（R13）。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/date/local_date.dart';
import '../../../core/notifications/lunio_notification_service.dart' as bridge;
import '../../../domain/entities/car.dart';
import '../../../domain/entities/maintenance_item.dart';
import '../../../domain/entities/maintenance_record.dart';
import '../../../domain/entities/notification_settings.dart';
import '../../../domain/entities/parking_countdown.dart';
import 'notification_coordinator.dart';
import 'reminder_dialogs.dart' as bridge;
import 'reminder_notifications.dart' as bridge;

/// 通知同步控制器。由 AppShell 的 State 创建/销毁：
///  - [ref]：主壳层的 WidgetRef（读 provider、listenManual）；
///  - [shellContext]：取主壳层 BuildContext 的回调（已卸载返回 null，
///    弹应用内提醒前用它确认页面还在）；
///  - [isAlive]：主壳层是否仍挂载（mounted 的回调版）。
class NotificationSyncController {
  NotificationSyncController({
    required this.ref,
    required this.shellContext,
    required this.isAlive,
  });

  final WidgetRef ref;
  final BuildContext? Function() shellContext;
  final bool Function() isAlive;

  /// listenManual 订阅句柄（dispose 时统一关闭）。
  final List<ProviderSubscription> _subscriptions = [];

  /// 上次系统通知调度的签名（null = 从未同步过，首拍必触发）。
  String? _systemNotificationSignature;

  /// 上次应用内提醒弹窗的签名。
  String? _inAppNotificationSignature;

  /// 系统通知重排是否在执行中（防并发重入）。
  bool _syncingSystemNotifications = false;

  /// 执行中又有新签名到来时置 true：本轮结束后用最新数据强制重跑
  /// 一轮（R3：不再直接丢弃新签名）。
  bool _pendingSystemNotificationSync = false;

  /// 应用内提醒检查是否在执行中。
  bool _checkingInAppNotifications = false;

  /// 首启权限检查是否在执行中（防重入）。
  bool _checkingInitialSystemPermission = false;

  /// 控制器是否已销毁。
  bool _disposed = false;

  /// 启动：订阅 6 个数据 provider，任何一个变化（含首拍）都触发
  /// syncFromProviders。AppShell initState 调用。
  void start() {
    _subscriptions.add(
      ref.listenManual(
        notificationSettingsProvider,
        (_, _) => syncFromProviders(),
        fireImmediately: true,
      ),
    );
    _subscriptions.add(
      ref.listenManual(appliedCarProvider, (_, _) => syncFromProviders()),
    );
    _subscriptions.add(
      ref.listenManual(
        appliedCarMaintenanceItemsProvider,
        (_, _) => syncFromProviders(),
      ),
    );
    _subscriptions.add(
      ref.listenManual(
        appliedCarRecordsProvider,
        (_, _) => syncFromProviders(),
      ),
    );
    _subscriptions.add(
      ref.listenManual(effectiveTodayProvider, (_, _) => syncFromProviders()),
    );
    _subscriptions.add(
      ref.listenManual(
        parkingCountdownProvider,
        (_, _) => syncFromProviders(),
      ),
    );
  }

  /// 销毁：AppShell dispose 调用。关闭订阅；置 _disposed 后所有在途
  /// 任务在下一个 await 检查点自动放弃。
  void dispose() {
    _disposed = true;
    for (final subscription in _subscriptions) {
      subscription.close();
    }
    _subscriptions.clear();
  }

  /// 回到前台：清空应用内提醒签名（强制重新检查弹窗，实现"用户处理完
  /// 提醒离开再回来，若又到期会再次提醒"）并立即重跑一轮同步。
  void onAppResumed() {
    if (_disposed) {
      return;
    }
    _inAppNotificationSignature = null;
    syncFromProviders();
  }

  /// 同步入口：从 6 个 provider 读当前值（loading 中的当 null），
  /// 数据就绪后按两个签名分别触发系统通知重排 / 应用内弹窗。
  /// car/items/records/today 任一还在加载就不做同步——所以刚装 App
  /// 或恢复备份后，等 provider 全部就绪那一拍才触发首次通知同步。
  void syncFromProviders() {
    if (_disposed) {
      return;
    }
    final settings = ref
        .read(notificationSettingsProvider)
        .maybeWhen(data: (value) => value, orElse: () => null);
    if (settings == null) {
      return;
    }
    if (settings.systemNotificationsEnabled) {
      _ensureInitialSystemNotificationPermission();
    }
    final car = ref
        .read(appliedCarProvider)
        .maybeWhen(data: (value) => value, orElse: () => null);
    final items = ref
        .read(appliedCarMaintenanceItemsProvider)
        .maybeWhen(data: (value) => value, orElse: () => null);
    final records = ref
        .read(appliedCarRecordsProvider)
        .maybeWhen(data: (value) => value, orElse: () => null);
    final today = ref
        .read(effectiveTodayProvider)
        .maybeWhen(data: (value) => value, orElse: () => null);
    final parkingCountdown = ref
        .read(parkingCountdownProvider)
        .maybeWhen(data: (value) => value, orElse: () => null);
    if (car == null || items == null || records == null || today == null) {
      return;
    }
    final dataSignature = bridge.reminderNotificationDataSignature(
      car: car,
      items: items,
      records: records,
      today: today,
    );
    final systemSignature = settings.systemNotificationsEnabled
        ? '${settings.dueRepeatFrequency.value}:'
              '${bridge.parkingCountdownReminderSignature(parkingCountdown)}:'
              '$dataSignature'
        : 'system-off';
    if (_systemNotificationSignature != systemSignature) {
      _systemNotificationSignature = systemSignature;
      _applySystemNotificationSchedule(
        settings: settings,
        car: car,
        items: items,
        records: records,
        today: today,
        parkingCountdown: parkingCountdown,
      );
    }
    final inAppSignature =
        '${settings.inAppNotificationsEnabled}:$dataSignature';
    if (_inAppNotificationSignature != inAppSignature) {
      _inAppNotificationSignature = inAppSignature;
      _showDueInAppNotifications(
        settings: settings,
        car: car,
        items: items,
        records: records,
        today: today,
      );
    }
  }

  /// 首启权限链（只跑一次，由偏好 systemNotificationPermissionRequested
  /// 把关；执行体已收编进通知协调器，本方法只负责防重入与授权后重排）：
  ///  1. 请求过 → 协调器对账系统真实开关，不一致才回写偏好并失效缓存
  ///     （用户可能在系统设置改过）；
  ///  2. 没请求过 → 协调器弹系统权限对话框并记录"已请求过"；被拒时回写
  ///     "系统通知关闭"并失效缓存。
  /// 真的弹了请求（返回 true）→ 本方法清空系统通知签名强制重排（授权
  /// 结果影响通知内容）；偏好回写与失效已按需发生在协调器内部，此处
  /// 不再单独失效。
  Future<void> _ensureInitialSystemNotificationPermission() async {
    if (_checkingInitialSystemPermission || _disposed) {
      return;
    }
    _checkingInitialSystemPermission = true;
    try {
      final requestedNow = await ref
          .read(notificationCoordinatorProvider)
          .ensureInitialSystemNotificationPermission();
      if (_disposed) {
        return;
      }
      if (requestedNow) {
        _systemNotificationSignature = null;
        syncFromProviders();
      }
    } finally {
      _checkingInitialSystemPermission = false;
    }
  }

  /// ★ 系统通知重排（真正的调度执行体，签名变化时被调用）。
  ///
  /// 守卫（R3/R8 修复后）：
  ///  - 代数已变（恢复/清空作废）→ 放弃；
  ///  - 已在执行中 → 置 pending 不丢弃，本轮 finally 里置空签名并
  ///    用最新数据重跑一轮；
  ///  - reschedule 前再查一次代数，变了就放弃（防止排队期间被作废）。
  ///
  /// 执行链：开关关 → 全部取消；权限协议委托协调器（查系统开关、必要时
  /// 补请求；权限没了回写偏好并取消）→ buildScheduledNotifications 组装
  /// 通知（8000/8900）→ Android 申请精确闹钟 → rescheduleNotifications
  /// （内部先 cancel 1000 个 id 再逐条 zonedSchedule，避开停车到点时刻）。
  Future<void> _applySystemNotificationSchedule({
    required LunioNotificationSettings settings,
    required Car car,
    required List<MaintenanceItem> items,
    required List<MaintenanceRecord> records,
    required LocalDate today,
    required ParkingCountdown? parkingCountdown,
  }) async {
    final syncGeneration = ref.read(notificationSyncGenerationProvider);
    if (_syncingSystemNotifications || _disposed) {
      _pendingSystemNotificationSync = !_disposed;
      return;
    }
    _syncingSystemNotifications = true;
    try {
      if (_disposed) {
        return;
      }
      if (!settings.systemNotificationsEnabled) {
        await bridge.LunioNotificationService.instance
            .cancelLunioNotifications();
        return;
      }
      // 权限协议在协调器内：查系统真实开关、必要时补请求、仍不可用则
      // 回写偏好为关并取消已排通知（此处直接返回即可）。
      final coordinator = ref.read(notificationCoordinatorProvider);
      final schedulable = await coordinator
          .ensureSystemNotificationsSchedulable();
      if (_disposed) {
        return;
      }
      if (!schedulable) {
        return;
      }
      final notifications = await bridge.buildScheduledNotifications(
        coordinator: coordinator,
        settings: settings,
        car: car,
        items: items,
        records: records,
        today: today,
      );
      if (_disposed) {
        return;
      }
      if (notifications.isEmpty) {
        await bridge.LunioNotificationService.instance
            .rescheduleNotifications(
              notifications,
              reservedDateTimes: bridge.reservedNotificationDateTimes(
                parkingCountdown,
              ),
            );
        return;
      }
      final exactAlarmGranted = await bridge.LunioNotificationService.instance
          .requestExactAlarmPermission();
      if (_disposed) {
        return;
      }
      // reschedule 前最后一次代数检查：排队/请求权限期间发生恢复/清空
      // 就放弃，避免用旧数据覆盖新状态。
      if (ref.read(notificationSyncGenerationProvider) != syncGeneration) {
        return;
      }
      await bridge.LunioNotificationService.instance.rescheduleNotifications(
        notifications,
        exactAlarm: exactAlarmGranted,
        reservedDateTimes: bridge.reservedNotificationDateTimes(
          parkingCountdown,
        ),
      );
    } finally {
      _syncingSystemNotifications = false;
      if (_pendingSystemNotificationSync && !_disposed) {
        _pendingSystemNotificationSync = false;
        // 置空签名 → syncFromProviders 必然重排一轮（用最新数据）。
        _systemNotificationSignature = null;
        syncFromProviders();
      }
    }
  }

  /// ★ 应用内提醒弹窗（应用内签名变化时被调用）。
  ///
  /// 收集两类到期提醒：保养项目（经协调器静默判定过滤）+ 里程更新
  /// （按推断频率判断是否到期）。有到期项则依次弹窗：
  ///  - "知道了" → 协调器写当日 ack 偏好（今天不再弹）；
  ///  - "15 天内不再提醒" → 协调器写 snooze 偏好（系统通知也一并静默）。
  /// 弹窗有动作 → 清空两个签名并立即重跑同步（snooze 影响通知内容）。
  Future<void> _showDueInAppNotifications({
    required LunioNotificationSettings settings,
    required Car car,
    required List<MaintenanceItem> items,
    required List<MaintenanceRecord> records,
    required LocalDate today,
  }) async {
    if (_checkingInAppNotifications ||
        !settings.inAppNotificationsEnabled ||
        _disposed) {
      return;
    }
    _checkingInAppNotifications = true;
    try {
      final coordinator = ref.read(notificationCoordinatorProvider);
      final dueNotices = <bridge.ReminderViewData>[];
      for (final notice in bridge.maintenanceNotices(
        car: car,
        items: items,
        records: records,
        today: today,
      )) {
        final itemId = notice.item.id;
        if (itemId == null) {
          continue;
        }
        if (!await coordinator.isSilencedForInAppDialog(
          MaintenanceItemTarget(itemId),
          today,
        )) {
          dueNotices.add(notice);
        }
        if (_disposed) {
          return;
        }
      }
      final showMileageReminder =
          car.id != null &&
          bridge.mileageUpdateReminderDue(car: car, records: records, today: today) &&
          !await coordinator.isSilencedForInAppDialog(
            MileageUpdateTarget(car.id!),
            today,
          );
      if (_disposed) {
        return;
      }
      if (dueNotices.isEmpty && !showMileageReminder) {
        return;
      }
      var changedSystemSchedule = false;
      if (dueNotices.isNotEmpty) {
        final context = shellContext();
        if (context == null || !context.mounted) {
          return;
        }
        final action = await bridge.showMaintenanceReminderDialog(
          context: context,
          coordinator: coordinator,
          car: car,
          maintenanceNotices: dueNotices,
          today: today,
        );
        if (_disposed) {
          return;
        }
        if (action == bridge.ReminderDialogAction.snoozed) {
          changedSystemSchedule = true;
        }
        if (action != null) {
          changedSystemSchedule = true;
          if (action == bridge.ReminderDialogAction.acknowledged) {
            for (final notice in dueNotices) {
              final itemId = notice.item.id;
              if (itemId != null) {
                await coordinator.acknowledgeMaintenanceItem(itemId, today);
              }
            }
          }
        }
      }
      if (showMileageReminder) {
        final context = shellContext();
        if (context == null || !context.mounted) {
          return;
        }
        final action = await bridge.showMileageUpdateReminderDialog(
          context: context,
          coordinator: coordinator,
          car: car,
          today: today,
        );
        if (_disposed) {
          return;
        }
        if (action == bridge.ReminderDialogAction.snoozed) {
          changedSystemSchedule = true;
        }
        if (action != null) {
          changedSystemSchedule = true;
          final carId = car.id;
          if (action == bridge.ReminderDialogAction.acknowledged &&
              carId != null) {
            await coordinator.acknowledgeMileageUpdate(carId, today);
          }
        }
      }
      if (changedSystemSchedule && !_disposed) {
        _systemNotificationSignature = null;
        _inAppNotificationSignature = null;
        syncFromProviders();
      }
    } finally {
      _checkingInAppNotifications = false;
    }
  }
}
