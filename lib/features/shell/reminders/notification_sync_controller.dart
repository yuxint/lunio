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
// 防竞态的分工（2026-09-25 收编）：
//  - "这轮还作数吗"（同步代数 R8 + 写库中间态旗 2026-09-24 + disposed
//    R13）收进守卫模块 notification_sync_guard.dart：各异步方法开工时
//    领一张 SyncRun，每个不可逆副作用（排通知/弹弹窗）之前问一次
//    run.isValid——检查点不再手抄协议，语义单一事实来源在守卫模块；
//  - 重入与 pending 重跑（R3 丢更新修复）是本文件自己的事：两组
//    "执行中标志 + pending" 收成私有 _GuardedOp，重跑时各自清自己的
//    签名；
//  - 权限协议与破坏性写库清扫的执行体在协调器（见 AGENTS.md 提醒目录
//    说明）。
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
import 'notification_sync_guard.dart';
import 'reminder_dialogs.dart' as bridge;
// ReminderViewData 类型已随 UI 半边拆到 reminder_rows.dart（内容组装
// 函数仍在 reminder_notifications.dart）；两个 import 共用 bridge 别名。
import 'reminder_notifications.dart' as bridge;
import 'reminder_rows.dart' as bridge;

/// 通知同步控制器。由 AppShell 的 State 创建/销毁：
///  - [ref]：主壳层的 WidgetRef（读 provider、listenManual）；
///  - [shellContext]：取主壳层 BuildContext 的回调（已卸载返回 null，
///    弹应用内提醒前用它确认页面还在）。
class NotificationSyncController {
  NotificationSyncController({required this.ref, required this.shellContext});

  final WidgetRef ref;
  final BuildContext? Function() shellContext;

  /// 通知同步守卫（代数 + 写库中间态旗的唯一拥有者，票从这里领；
  /// provider 每容器一份，read 多少次都是同一实例）。
  NotificationSyncGuard get _guard => ref.read(notificationSyncGuardProvider);

  /// 通知服务经 provider 获取（生产=全局单例；测试逐用例覆盖为新实例）。
  bridge.LunioNotificationService get _notificationService =>
      ref.read(lunioNotificationServiceProvider);

  /// listenManual 订阅句柄（dispose 时统一关闭）。
  final List<ProviderSubscription> _subscriptions = [];

  /// 上次系统通知调度的签名（null = 从未同步过，首拍必触发）。
  String? _systemNotificationSignature;

  /// 上次应用内提醒弹窗的签名。
  String? _inAppNotificationSignature;

  /// 首启权限检查是否在执行中（防重入；无 pending 语义——权限链丢了
  /// 下一拍监听自会再来，不走 R3 强制重跑）。
  bool _checkingInitialSystemPermission = false;

  /// 控制器是否已销毁。
  bool _disposed = false;

  /// 系统通知重排的重入保护（R3）：执行中来了新签名不丢弃，置 pending
  /// 在 finally 里清系统签名并强制重跑一轮。
  late final _GuardedOp _systemReschedule = _GuardedOp(
    isDisposed: () => _disposed,
    onRerun: () {
      _systemNotificationSignature = null;
      syncFromProviders();
    },
  );

  /// 应用内提醒检查的重入保护（R3 同款，弹窗路径此前没有，2026-09-24
  /// 补齐——否则"弹窗开着时数据变化"的那一拍检查被永久丢掉）：重跑时
  /// 清应用内签名。
  late final _GuardedOp _inAppCheck = _GuardedOp(
    isDisposed: () => _disposed,
    onRerun: () {
      _inAppNotificationSignature = null;
      syncFromProviders();
    },
  );

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
    // 停车实时活动对账（ADR 0012）：倒计时偏好装载/变化时对一轮，兜住
    // "重启后活动丢失""到点后未切正计时"两类漂移。fireImmediately 兜住
    // "start() 时偏好已就绪"的时序；未就绪时 syncParkingLiveActivity
    // 自行跳过，等装载那一拍再对。
    _subscriptions.add(
      ref.listenManual(
        parkingCountdownProvider,
        (_, _) => syncParkingLiveActivity(),
        fireImmediately: true,
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
  /// 提醒离开再回来，若又到期会再次提醒"）、对账停车实时活动，并立即
  /// 重跑一轮通知同步。
  void onAppResumed() {
    if (_disposed) {
      return;
    }
    _inAppNotificationSignature = null;
    syncParkingLiveActivity();
    syncFromProviders();
  }

  /// 停车实时活动对账（ADR 0012，执行体在通知协调器）：倒计时 provider
  /// 还在加载时跳过——等它装载触发上面 listenManual 再补；读偏好抛异常
  /// 时 provider 停在 AsyncError（hasValue 为 false），同样跳过、活动不
  /// 动。对账内部的倒计时真值由协调器直读偏好表（不走本方法的 provider
  /// 读数——invalidate 后的旧快照曾把刚启动的活动当"偏好无"误撤，
  /// 2026-09-16 真机日志实锤，见协调器注释）。
  Future<void> syncParkingLiveActivity() async {
    if (_disposed) {
      return;
    }
    final parkingAsync = ref.read(parkingCountdownProvider);
    if (!parkingAsync.hasValue) {
      return;
    }
    await ref
        .read(notificationCoordinatorProvider)
        .reconcileParkingLiveActivity();
  }

  /// 同步入口：从 6 个 provider 读当前值（loading 中的当 null），
  /// 数据就绪后按两个签名分别触发系统通知重排 / 应用内弹窗。
  /// car/items/records/today 任一还在加载就不做同步——所以刚装 App
  /// 或恢复备份后，等 provider 全部就绪那一拍才触发首次通知同步。
  void syncFromProviders() {
    if (_disposed) {
      return;
    }
    // 中间态守卫：破坏性写库（恢复/清空/删车）事务进行中，流查询读到
    // 的是未提交的半成品数据（记录已插入、关联表还没插到之类的瞬态），
    // 此时算出的到期清单是假的。直接丢弃且签名不动——最终数据与中间态
    // 签名必然不同，事务提交后调用方失效 provider 家族，自然补上正确的
    // 一轮（2026-09-24 恢复备份弹假到期弹窗事故）。
    if (_guard.isDataResetInFlight) {
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
  /// 守卫（2026-09-25 收编后）：
  ///  - 开工向守卫领票，每个 await 之后、reschedule 前问 run.isValid——
  ///    disposed / 写库中间态 / 代数变更三种作废由一个谓词一并拦；
  ///  - 已在执行中 → _systemReschedule 记 pending 不丢弃，本轮 finally
  ///    里置空系统签名并用最新数据重跑一轮（R3）。
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
    final run = _guard.acquire(isDisposed: () => _disposed);
    if (!_systemReschedule.enter()) {
      return;
    }
    try {
      if (!run.isValid) {
        return;
      }
      if (!settings.systemNotificationsEnabled) {
        await _notificationService.cancelLunioNotifications();
        return;
      }
      // 权限协议在协调器内：查系统真实开关、必要时补请求、仍不可用则
      // 回写偏好为关并取消已排通知（此处直接返回即可）。
      final coordinator = ref.read(notificationCoordinatorProvider);
      final schedulable = await coordinator
          .ensureSystemNotificationsSchedulable();
      if (!run.isValid) {
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
      if (!run.isValid) {
        return;
      }
      if (notifications.isEmpty) {
        await _notificationService.rescheduleNotifications(
          notifications,
          reservedDateTimes: bridge.reservedNotificationDateTimes(
            parkingCountdown,
          ),
        );
        return;
      }
      final exactAlarmGranted = await _notificationService
          .requestExactAlarmPermission();
      // reschedule 前最后一次作废检查：排队/请求权限期间发生恢复/清空
      // 就放弃，避免用旧数据覆盖新状态。
      if (!run.isValid) {
        return;
      }
      await _notificationService.rescheduleNotifications(
        notifications,
        exactAlarm: exactAlarmGranted,
        reservedDateTimes: bridge.reservedNotificationDateTimes(
          parkingCountdown,
        ),
      );
    } finally {
      _systemReschedule.exit();
    }
  }

  /// ★ 应用内提醒弹窗（应用内签名变化时被调用）。
  ///
  /// 收集两类到期提醒：保养项目（经协调器静默判定过滤）+ 里程更新
  /// （按推断频率判断是否到期）。有到期项则依次弹窗：
  ///  - "知道了" → 协调器写当日 ack 偏好（今天不再弹）；
  ///  - "15 天内不再提醒" → 协调器写 snooze 偏好（系统通知也一并静默）。
  /// 弹窗有动作 → 清空两个签名并立即重跑同步（snooze 影响通知内容）。
  ///
  /// 中间态守卫（2026-09-24）：开工领票，两处展示弹窗前（与展示调用之间
  /// 无 await，无竞态窗口）问一次 run.isValid——旗真说明写库仍在进行、
  /// 手里的清单是半成品；代数变了说明写库在本次运行期间已开始并结束、
  /// 数据过期；disposed 说明壳层已拆。都放弃，等最终一轮补判。检查点
  /// 协议的语义单一事实来源在守卫模块文件头。
  Future<void> _showDueInAppNotifications({
    required LunioNotificationSettings settings,
    required Car car,
    required List<MaintenanceItem> items,
    required List<MaintenanceRecord> records,
    required LocalDate today,
  }) async {
    final run = _guard.acquire(isDisposed: () => _disposed);
    if (!_inAppCheck.enter()) {
      return;
    }
    try {
      final coordinator = ref.read(notificationCoordinatorProvider);
      // 入口复查：写库进行中读到的 items/records 是未提交的半成品，算都
      // 不要算（syncFromProviders 入口早退只挡"检查开始时写库已在跑"的
      // 那一半，这里挡"检查开始后写库才开始"的另一半）。
      if (!run.isValid) {
        return;
      }
      if (!settings.inAppNotificationsEnabled) {
        return;
      }
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
        if (!run.isValid) {
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
      if (dueNotices.isEmpty && !showMileageReminder) {
        return;
      }
      // 展示前复查第一道（保养弹窗，与下方展示调用之间无 await，无竞态
      // 窗口）：旗真 = 写库仍在进行，清单是半成品；代数变了 = 写库在本次
      // 检查期间已开始并结束，数据过期；disposed = 壳层已拆。都放弃，
      // 等最终一轮补判。
      if (!run.isValid) {
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
        if (!run.isValid) {
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
        // 展示前复查第二道（里程弹窗，与下方展示调用之间无 await）：保养
        // 弹窗挂起与 ack 写偏好都是 await，破坏性写库可能在期间开始并
        // 结束，showMileageReminder 是旧快照算出来的，弹前必须再问一次票
        // （2026-09-25 补齐，审查：此前只有保养弹窗前一道）。
        if (!run.isValid) {
          return;
        }
        final action = await bridge.showMileageUpdateReminderDialog(
          context: context,
          coordinator: coordinator,
          car: car,
          today: today,
        );
        if (!run.isValid) {
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
      // R3 同款：执行期间来过新检查请求（被置 pending），这里清空签名
      // 强制重跑一轮，用最新数据补判（含入口中间态守卫的时序，由它
      // 自行把关）。
      _inAppCheck.exit();
    }
  }
}

/// 重入保护（R3）：一组"执行中标志 + pending 重跑"。执行中又来新请求时
/// 不丢弃，记 pending；本轮 finally 里用最新数据强制重跑一轮（重跑动作
/// 由实例的 [onRerun] 定义——系统通知重排清系统签名、应用内检查清应用内
/// 签名）。disposed 后不再记 pending、不再重跑。协议语义见守卫模块
/// （notification_sync_guard.dart）文件头的第 4 层说明。
class _GuardedOp {
  _GuardedOp({required this.isDisposed, required this.onRerun});

  final bool Function() isDisposed;
  final void Function() onRerun;

  bool _busy = false;
  bool _pending = false;

  /// 开始一轮：已在执行中则记 pending 并返回 false（调用方直接返回）。
  bool enter() {
    if (_busy) {
      _pending = !isDisposed();
      return false;
    }
    _busy = true;
    return true;
  }

  /// 结束一轮（配对 finally 调用）：执行中标志复位；期间来过新请求则
  /// 强制重跑一轮。
  void exit() {
    _busy = false;
    if (_pending && !isDisposed()) {
      _pending = false;
      onRerun();
    }
  }
}
