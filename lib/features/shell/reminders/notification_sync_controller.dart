// 通知同步控制器：把"提醒数据变化 → 重排系统通知 / 弹应用内提醒"
// 从 AppShell 的 build 里抽出来的被动监听外壳（≈ Spring 的一个 @Service，
// 生命周期挂在主壳层 State 上）。
//
// 触发方式（R12 修复）：start() 对同步数据源清单（notificationSyncSources，
// 本文件顶层唯一声明 = 应用车辆数据束 + 通知设置 + 停车倒计时）逐个
// ref.listenManual（fireImmediately: true），任何一个变化（或首拍）就调
// syncFromProviders，不再依赖"build 里 watch + postFrame 副作用"的反
// 模式。这份清单同时是恢复备份屏障重算的等待名单来源
// （waitForNotificationSyncSources，动作层恢复编排经注入 read 调用），
// "同步引擎监听哪些数据源"只有这一份声明，两侧不会再各抄一份。
// 清单之外还有两条控制面订阅（原因各自见 start() 内注释）：停车实时
// 活动对账，与显式同步信号（恢复备份屏障重算后的强制补判轮，协调器
// bump 守卫模块的 notificationSyncSignalProvider、此处订阅重跑）。
//
// 同步策略（2026-11-15 收编）：变更判定与分发归 notification_sync_engine.dart
// 的 NotificationSyncEngine——每轮读一份「同步快照」（GLOSSARY 词条），
// 系统通知 / 应用内两条 lane 各自记住上次成功消费的快照，变了才调本文件
// 注入的两个 sink 执行，执行成功才记账（取代原先手拼字符串签名、开跑前
// 记账的写法）。本文件只保留被动监听外壳、生产接缝组装与两个执行体。
//
// 防竞态的分工（2026-09-25 收编，2026-11-15 随 engine 收编调整）：
//  - "这轮还作数吗"（同步代数 R8 + 写库中间态旗 2026-09-24 + disposed
//    R13）收进守卫模块 notification_sync_guard.dart：两个执行体开工时领
//    一张 SyncRun，每个不可逆副作用（排通知/弹弹窗）之前问一次
//    run.isValid——检查点不再手抄协议，语义单一事实来源在守卫模块；
//  - 重入与 pending 重跑（R3 丢更新修复）归 engine 的两个 per-lane
//    GuardedOp（guarded_op.dart 共享模块）：执行中来了新输入不丢弃，
//    本轮结束用最新输入重跑；成功才记账让重跑无需清签名；
//  - 权限协议与破坏性写库清扫的执行体在协调器（见 AGENTS.md 提醒目录
//    说明）；
//  - 应用内弹窗检查链的决策（静默过滤/弹窗动作分支/检查点/动作后重排
//    判定）在决策体模块 reminder_dialog_flow.dart（plain-Dart + 注入
//    接缝，可无 widget 单测），本类只绑定生产接缝；决策体回报
//    SyncLaneOutcome（aborted 不记账，engine 下一轮补判）。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/notifications/lunio_notification_service.dart' as bridge;
import 'notification_coordinator.dart';
import 'notification_sync_engine.dart';
import 'notification_sync_guard.dart';
import 'reminder_dialog_flow.dart';
import 'reminder_dialogs.dart' as bridge;
// 内容组装（通知清单/停车摘要）仍从 reminder_notifications.dart 来；
// ReminderViewData 类型引用已随弹窗检查链收编移入决策体模块
// reminder_dialog_flow.dart，本文件不再直接引用它。
import 'reminder_notifications.dart' as bridge;

/// 通知同步数据源清单：同步引擎"监听哪些数据源"的唯一声明（2026-10-01
/// 收编）。两个消费面都从这一份推导，增删/换数据源只改这里：
///  - [NotificationSyncController.start] 的 listenManual 订阅（数据变化
///    触发同步）；
///  - 恢复备份屏障重算的等待名单（[waitForNotificationSyncSources]，由
///    动作层恢复编排调用）——此前动作层手抄过这份名单（6 项收 3 项时
///    靠人肉对齐），属真实发生过事故的缝。
///
/// 类型取 [FutureProvider] 且擦到 `Object?`：屏障侧要统一逐个 await
/// `source.future`，清单成员必须是 Future 形态的 provider（三源现状皆是；
/// 非 Future 形态的数据源接入时类型会在此显式拦下）。数据束的就绪语义
/// （任一上游未就绪整体未就绪）使单等它即等于等齐车/项目/记录/生效
/// 今天四上游。
final List<FutureProvider<Object?>> notificationSyncSources = [
  notificationSettingsProvider,
  appliedCarBoardProvider,
  parkingCountdownProvider,
];

/// 等同步数据源全部重算落定：恢复备份屏障重算的"等待段"（整体编排见
/// 动作层 restoreBackupFromFile 与协调器 runBackupRestore——失效全量
/// provider 后、写库中间态旗还举着的窗口内调用本函数）。
///
/// 等待名单 = [notificationSyncSources] 本身（与 start() 的订阅同源，
/// 单一声明两处推导）。逐个 await、单读失败不拦收尾：provider 出错时
/// 同步控制器本来就走 null 早退，与屏障引入前（2026-09-26）的行为一致。
/// [read] 由调用方注入（生产 = `(source) => ref.read(source.future)`，
/// 测试注入假实现锁"两侧同源"）——等待语义留在引擎模块，读的手法归
/// 调用方。
Future<void> waitForNotificationSyncSources(
  Future<Object?> Function(FutureProvider<Object?> source) read,
) async {
  for (final source in notificationSyncSources) {
    try {
      await read(source);
    } catch (_) {}
  }
}

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

  /// 首启权限检查是否在执行中（防重入；无 pending 语义——权限链丢了
  /// 下一拍监听自会再来，不走 R3 强制重跑）。
  bool _checkingInitialSystemPermission = false;

  /// 控制器是否已销毁。
  bool _disposed = false;

  /// 变更判定与分发 module（notification_sync_engine.dart，2026-11-15
  /// 收编）：输入快照读取、两条 lane 的变更判定、执行分发、成功记账、
  /// 重入/pending 全在它里面；两个 sink 是本文件的两个执行体。
  late final NotificationSyncEngine _engine = NotificationSyncEngine(
    readSnapshot: _readSnapshot,
    isDataResetInFlight: () => _guard.isDataResetInFlight,
    isDisposed: () => _disposed,
    runSystemLane: _applySystemNotificationSchedule,
    runInAppLane: _showDueInAppNotifications,
  );

  /// 应用内弹窗链路的决策体（reminder_dialog_flow.dart，2026-10-15 收编）：
  /// 检查链的静默过滤/弹窗动作分支/检查点/重排判定都在它里面，这里只
  /// 组装生产接缝——静默读与"知道了"抑制写绑定通知协调器（每次 read，
  /// 与控制器其余协调器用法一致）、弹窗可展示性与呈现绑定主壳层
  /// context 与 reminder_dialogs、领票绑定守卫（带 disposed）、重排绑定
  /// engine.invalidateAllLanes()（失效两条 lane 并立即重跑）。
  late final InAppReminderDialogFlow _inAppDialogFlow = InAppReminderDialogFlow(
    acquireRun: () => _guard.acquire(isDisposed: () => _disposed),
    isSilencedForInAppDialog: (target, today) => ref
        .read(notificationCoordinatorProvider)
        .isSilencedForInAppDialog(target, today),
    canPresentDialog: () {
      final context = shellContext();
      return context != null && context.mounted;
    },
    showMaintenanceDialog:
        ({required car, required maintenanceNotices, required today}) {
      final context = shellContext();
      if (context == null || !context.mounted) {
        // 理论不可达：决策体恰在展示前经 canPresentDialog 同步检查过；
        // 防御返回 null（= 无动作，等价用户关闭，下一轮再查）。
        return Future<ReminderDialogAction?>.value(null);
      }
      return bridge.showMaintenanceReminderDialog(
        context: context,
        coordinator: ref.read(notificationCoordinatorProvider),
        car: car,
        maintenanceNotices: maintenanceNotices,
        today: today,
      );
    },
    showMileageDialog: ({required car, required today}) {
      final context = shellContext();
      if (context == null || !context.mounted) {
        return Future<ReminderDialogAction?>.value(null);
      }
      return bridge.showMileageUpdateReminderDialog(
        context: context,
        coordinator: ref.read(notificationCoordinatorProvider),
        car: car,
        today: today,
      );
    },
    acknowledgeMaintenanceItem: (itemId, today) => ref
        .read(notificationCoordinatorProvider)
        .acknowledgeMaintenanceItem(itemId, today),
    acknowledgeMileageUpdate: (carId, today) => ref
        .read(notificationCoordinatorProvider)
        .acknowledgeMileageUpdate(carId, today),
    onForceReschedule: () {
      if (_disposed) {
        return;
      }
      _engine.invalidateAllLanes();
    },
  );

  /// 启动：对同步数据源清单 [notificationSyncSources]（通知设置 + 应用
  /// 车辆数据束 + 停车倒计时，2026-10-01 起车/项目/记录/生效今天四路
  /// 由数据束一并触发）逐个 listenManual，任何一个变化（含首拍）都触发
  /// syncFromProviders。订阅集合从清单推导（单一声明，恢复备份屏障的
  /// 等待名单同源）；"没有清单之外的订阅"由本循环结构性保证。首拍口径
  /// 统一 fireImmediately：syncFromProviders 本就重读全部数据源、未就绪
  /// 即早退，启动时多出的首拍是无害空轮（快照判定幂等）。AppShell
  /// initState 调用。
  void start() {
    for (final source in notificationSyncSources) {
      _subscriptions.add(
        ref.listenManual(
          source,
          (_, _) => syncFromProviders(),
          fireImmediately: true,
        ),
      );
    }
    // 停车实时活动对账（ADR 0012）：倒计时偏好装载/变化时对一轮，兜住
    // "重启后活动丢失""到点后未切正计时"两类漂移。fireImmediately 兜住
    // "start() 时偏好已就绪"的时序；未就绪时 syncParkingLiveActivity
    // 自行跳过，等装载那一拍再对。这条订阅是实时活动对账、不是同步引擎
    // 的数据触发面（回调与守卫模型都不同），故不在清单内——屏障覆盖的
    // parkingCountdownProvider 本身已在清单里。
    _subscriptions.add(
      ref.listenManual(
        parkingCountdownProvider,
        (_, _) => syncParkingLiveActivity(),
        fireImmediately: true,
      ),
    );
    // 显式同步信号（守卫模块的 notificationSyncSignalProvider，2026-10-06）：
    // 恢复备份屏障重算后协调器经 bump 强制补判一轮——屏障窗口内 provider
    // 重算触发的同步轮全被入口早退丢弃、快照不记账，settle 后没有任何自然
    // 监听触发，靠这一拍用收敛后的最终数据补跑。它同样不是清单成员：信号
    // 是控制面触发不是数据源（清单类型擦到 FutureProvider<Object?>，屏障
    // 侧要逐个 await .future，Notifier 形态进不去也是防呆）；不发首拍——
    // 启动初始同步已由数据源清单的 fireImmediately 覆盖，信号首拍是无
    // 意义空轮。
    _subscriptions.add(
      ref.listenManual(
        notificationSyncSignalProvider,
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

  /// 回到前台：失效应用内 lane（强制重新检查弹窗，实现"用户处理完提醒
  /// 离开再回来，若又到期会再次提醒"）、对账停车实时活动；失效入口自带
  /// 一轮同步。
  void onAppResumed() {
    if (_disposed) {
      return;
    }
    syncParkingLiveActivity();
    _engine.invalidateInAppLane();
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

  /// 同步入口（本文件薄外壳）：首启权限链保持"每次入口一次"的节奏
  /// （请求过 → 对账系统真实开关；没请求过 → 请求），然后把变更判定与
  /// 分发交给 engine。入口的 disposed / 写库中间态 / 输入未就绪早退都在
  /// engine 里，这里不再重复表达。
  ///
  /// 权限链留在入口而不是系统 sink 内：sink 只在系统 lane 脏时执行，
  /// 而「请求过 → 对账系统真实开关」这半在回前台、数据完全没变时也要
  /// 跑（用户在系统设置里改过通知权限）。
  void syncFromProviders() {
    if (_disposed) {
      return;
    }
    final settings = ref
        .read(notificationSettingsProvider)
        .maybeWhen(data: (value) => value, orElse: () => null);
    if (settings != null && settings.systemNotificationsEnabled) {
      _ensureInitialSystemNotificationPermission();
    }
    _engine.sync();
  }

  /// 本轮输入快照（同步数据源三合一）：通知设置未就绪 / 数据束未就绪 /
  /// 无应用车辆 → null（engine 本轮不跑；无车短路保持 R1 语义——删最后
  /// 一辆车后的旧调度由删车模板显式取消）。停车倒计时 loading 按 null
  /// （= 没有倒计时）处理，与收编前的签名口径一致。
  NotificationSyncSnapshot? _readSnapshot() {
    final settings = ref
        .read(notificationSettingsProvider)
        .maybeWhen(data: (value) => value, orElse: () => null);
    if (settings == null) {
      return null;
    }
    final board = ref
        .read(appliedCarBoardProvider)
        .maybeWhen(data: (value) => value, orElse: () => null);
    final car = board?.car;
    if (board == null || car == null) {
      return null;
    }
    final parkingCountdown = ref
        .read(parkingCountdownProvider)
        .maybeWhen(data: (value) => value, orElse: () => null);
    return NotificationSyncSnapshot(
      settings: settings,
      car: car,
      items: board.items,
      records: board.records,
      today: board.today,
      parkingCountdown: parkingCountdown,
    );
  }

  /// 首启权限链（只跑一次，由偏好 systemNotificationPermissionRequested
  /// 把关；执行体已收编进通知协调器，本方法只负责防重入与授权后重排）：
  ///  1. 请求过 → 协调器对账系统真实开关，不一致才回写偏好并失效缓存
  ///     （用户可能在系统设置改过）；
  ///  2. 没请求过 → 协调器弹系统权限对话框并记录"已请求过"；被拒时回写
  ///     "系统通知关闭"并失效缓存。
  /// 真的弹了请求（返回 true）→ 失效系统通知 lane 强制重排（授权结果
  /// 影响通知内容）；偏好回写与失效已按需发生在协调器内部，此处不再
  /// 单独失效。
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
        _engine.invalidateSystemLane();
      }
    } finally {
      _checkingInitialSystemPermission = false;
    }
  }

  /// ★ 系统通知 lane 执行体（engine 的 sink，快照变化时被调用）。
  ///
  /// 守卫（2026-09-25 收编后）：开工向守卫领票，每个 await 之后、
  /// reschedule 前问 run.isValid——disposed / 写库中间态 / 代数变更三种
  /// 作废由一个谓词一并拦。重入与 pending 重跑归 engine 的 per-lane
  /// GuardedOp（2026-11-15 起），本方法不再持有执行中标志。
  ///
  /// 执行链：开关关 → 全部取消；权限协议委托协调器（查系统开关、必要时
  /// 补请求；权限没了回写偏好并取消）→ buildScheduledNotifications 组装
  /// 通知（身份来自槽位台账）→ Android 申请精确闹钟 → rescheduleNotifications
  /// （内部先精确取消旧计划再逐条 zonedSchedule，避开停车到点时刻）。
  ///
  /// 结果口径：票作废 → aborted（不记账，等下一轮补判）；权限暂不可调度
  /// → skipped（记账，等输入变化再试）；正常收尾 → applied。
  Future<SyncLaneOutcome> _applySystemNotificationSchedule(
    NotificationSyncSnapshot snapshot,
  ) async {
    final settings = snapshot.settings;
    final car = snapshot.car;
    final items = snapshot.items;
    final records = snapshot.records;
    final today = snapshot.today;
    final parkingCountdown = snapshot.parkingCountdown;
    final run = _guard.acquire(isDisposed: () => _disposed);
    if (!run.isValid) {
      return SyncLaneOutcome.aborted;
    }
    if (!settings.systemNotificationsEnabled) {
      await _notificationService.cancelLunioNotifications();
      return SyncLaneOutcome.applied;
    }
    // 权限协议在协调器内：查系统真实开关、必要时补请求、仍不可用则
    // 回写偏好为关并取消已排通知（此处直接返回即可）。
    final coordinator = ref.read(notificationCoordinatorProvider);
    final schedulable = await coordinator
        .ensureSystemNotificationsSchedulable();
    if (!run.isValid) {
      return SyncLaneOutcome.aborted;
    }
    if (!schedulable) {
      return SyncLaneOutcome.skipped;
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
      return SyncLaneOutcome.aborted;
    }
    if (notifications.isEmpty) {
      await _notificationService.rescheduleNotifications(
        notifications,
        reservedDateTimes: bridge.reservedNotificationDateTimes(
          parkingCountdown,
        ),
      );
      return SyncLaneOutcome.applied;
    }
    final exactAlarmGranted = await _notificationService
        .requestExactAlarmPermission();
    // reschedule 前最后一次作废检查：排队/请求权限期间发生恢复/清空
    // 就放弃，避免用旧数据覆盖新状态。
    if (!run.isValid) {
      return SyncLaneOutcome.aborted;
    }
    await _notificationService.rescheduleNotifications(
      notifications,
      exactAlarm: exactAlarmGranted,
      reservedDateTimes: bridge.reservedNotificationDateTimes(
        parkingCountdown,
      ),
    );
    return SyncLaneOutcome.applied;
  }

  /// ★ 应用内提醒 lane 执行体（engine 的 sink，快照变化时被调用）。
  ///
  /// 检查链的全部决策（到期清单静默过滤、弹窗动作分支、各检查点、动作
  /// 后强制重排）在决策体 [_inAppDialogFlow]（reminder_dialog_flow.dart，
  /// 2026-10-15 收编）里，可无 widget 单测；重入与 pending 重跑归 engine
  /// 的 per-lane GuardedOp（2026-11-15 起），本方法只转发快照字段并原样
  /// 返回决策体结果（aborted 不记账，engine 下一轮补判）。
  Future<SyncLaneOutcome> _showDueInAppNotifications(
    NotificationSyncSnapshot snapshot,
  ) {
    return _inAppDialogFlow.checkAndPresent(
      settings: snapshot.settings,
      car: snapshot.car,
      items: snapshot.items,
      records: snapshot.records,
      today: snapshot.today,
    );
  }
}
