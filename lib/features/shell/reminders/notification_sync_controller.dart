// 通知同步控制器：把"提醒数据变化 → 重排系统通知 / 弹应用内提醒"
// 从 AppShell 的 build 里抽出来的独立协调器（≈ Spring 的一个 @Service，
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
//  - 重入与 pending 重跑（R3 丢更新修复）是本文件自己的事：两组防护
//    用 reminders 域共享模块 guarded_op.dart 的 GuardedOp（2026-10-06
//    起从本文件私有 _GuardedOp 收编，与小组件快照控制器同一份实现），
//    重跑时各自清自己的签名；
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
import 'guarded_op.dart';
import 'notification_coordinator.dart';
import 'notification_sync_guard.dart';
import 'reminder_dialogs.dart' as bridge;
// ReminderViewData 类型已随 UI 半边拆到 reminder_rows.dart（内容组装
// 函数仍在 reminder_notifications.dart）；两个 import 共用 bridge 别名。
import 'reminder_notifications.dart' as bridge;
import 'reminder_rows.dart' as bridge;

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
  late final GuardedOp _systemReschedule = GuardedOp(
    isDisposed: () => _disposed,
    onRerun: () {
      _systemNotificationSignature = null;
      syncFromProviders();
    },
  );

  /// 应用内提醒检查的重入保护（R3 同款，弹窗路径此前没有，2026-09-24
  /// 补齐——否则"弹窗开着时数据变化"的那一拍检查被永久丢掉）：重跑时
  /// 清应用内签名。
  late final GuardedOp _inAppCheck = GuardedOp(
    isDisposed: () => _disposed,
    onRerun: () {
      _inAppNotificationSignature = null;
      syncFromProviders();
    },
  );

  /// 启动：对同步数据源清单 [notificationSyncSources]（通知设置 + 应用
  /// 车辆数据束 + 停车倒计时，2026-10-01 起车/项目/记录/生效今天四路
  /// 由数据束一并触发）逐个 listenManual，任何一个变化（含首拍）都触发
  /// syncFromProviders。订阅集合从清单推导（单一声明，恢复备份屏障的
  /// 等待名单同源）；"没有清单之外的订阅"由本循环结构性保证。首拍口径
  /// 统一 fireImmediately：syncFromProviders 本就重读全部数据源、未就绪
  /// 即早退，启动时多出的首拍是无害空轮（签名守卫幂等）。AppShell
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
    // 重算触发的同步轮全被入口早退丢弃、签名不动，settle 后没有任何自然
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

  /// 同步入口：从同步数据源清单读当前值（数据束 + 通知设置 + 停车倒计时，
  /// loading 中的当 null / 数据束整体未就绪即 null），数据就绪后按两个
  /// 签名分别触发系统通知重排 / 应用内弹窗。数据束未就绪就不做同步。
  void syncFromProviders() {
    if (_disposed) {
      return;
    }
    // 中间态守卫：破坏性写库（恢复/清空/删车）事务进行中，provider 读到
    // 的是未提交的半成品数据（记录已插入、关联表还没插到之类的瞬态），
    // 此时算出的到期清单是假的。直接丢弃且签名不动——最终数据与中间态
    // 签名必然不同，补判由"事务提交后的失效触发的最终一轮"或"恢复模板
    // 屏障重算后的强制补判轮"用收敛后的数据补上（2026-09-24 恢复备份弹
    // 假到期弹窗事故；2026-09-26 屏障重算，见协调器 runBackupRestore）。
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
    // 车/项目/记录/生效今天经应用车辆数据束一次拿齐：数据束未就绪
    // （任一上游 loading/error）return——所以刚装 App 或恢复备份后，
    // 等 provider 全部就绪那一拍才触发首次通知同步。
    final board = ref
        .read(appliedCarBoardProvider)
        .maybeWhen(data: (value) => value, orElse: () => null);
    if (board == null) {
      return;
    }
    // 无车短路（R1 语义保持）：删最后一辆车后不重排，旧调度由删车
    // 模板显式取消。
    final car = board.car;
    if (car == null) {
      return;
    }
    final items = board.items;
    final records = board.records;
    final today = board.today;
    final parkingCountdown = ref
        .read(parkingCountdownProvider)
        .maybeWhen(data: (value) => value, orElse: () => null);
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
  /// 通知（身份来自槽位台账）→ Android 申请精确闹钟 → rescheduleNotifications
  /// （内部先精确取消旧计划再逐条 zonedSchedule，避开停车到点时刻）。
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
