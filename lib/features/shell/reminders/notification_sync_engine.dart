// 通知同步 engine（同步快照 / lane 结果 / 变更判定）：把"提醒数据变化 →
// 该不该重排系统通知 / 该不该弹应用内提醒"这组决策从
// NotificationSyncController（AppShell 装配的被动监听外壳）里收成一个
// plain-Dart module。
//
// 在 App 中的位置：notification_sync_controller.dart 逐源监听
// notificationSyncSources，每次触发把"本轮输入"交给本 module；本 module
// 按两条 lane（系统通知 / 应用内提醒）各自记住上次成功消费的快照，变了
// 才调注入的 sink 执行，执行成功才记账。守卫（同步代数 + 写库中间态旗，
// notification_sync_guard.dart）与 GuardedOp（重入/pending 重跑，
// guarded_op.dart）的协议不变：前者归守卫模块，后者的两个 per-lane 实例
// 归本 module。
//
// ≈ Java 的 @Service：输入读取、变更判定、调用执行体、记账时机都在这里；
// 执行体（排通知/弹窗）与平台依赖经构造注入，测试给假实现即可纯 Dart
// 驱动。与 RecordFormController 等决策体同一接法先例。
//
// 「同步快照」是 GLOSSARY 词条：两条通道在同一轮里共同消费的一份输入，
// 判定"变没变"与组装通知/弹窗消费同一份对象。
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/date/local_date.dart';
import '../../../domain/entities/car.dart';
import '../../../domain/entities/maintenance_item.dart';
import '../../../domain/entities/maintenance_record.dart';
import '../../../domain/entities/notification_settings.dart';
import '../../../domain/entities/parking_countdown.dart';
import 'guarded_op.dart';

/// 一条 lane 执行体的一轮结果（决定 engine 记不记账，见
/// [SyncLaneOutcomeRules.commitsSnapshot]）。
///
///  - [applied]：真正执行了（含开关关 / 无到期这类有意 no-op）；
///  - [skipped]：可恢复的外部状态挡路（权限暂不可调度等），本轮不做事，
///    但算"已消费"——同一个快照不再反复重试，等下一次输入变化；
///  - [aborted]：同步票作废 / 壳层已拆，本轮放弃且**不**记账，等下一轮
///    用最新数据补判；
///  - [failed]：执行异常，本轮不记账（下一次触发重试）。engine 自身捕获
///    异常时按本值处理，sink 不需要主动返回它。
enum SyncLaneOutcome { applied, skipped, aborted, failed }

/// 结果 → 记账判定：applied 与 skipped 记为"这个快照已消费"；aborted /
/// failed 不记，后续触发会重新判定。
extension SyncLaneOutcomeRules on SyncLaneOutcome {
  /// 本轮结果是否算"快照已消费"（engine 用它决定更新 last-applied）。
  bool get commitsSnapshot =>
      this == SyncLaneOutcome.applied || this == SyncLaneOutcome.skipped;
}

/// 同步快照（GLOSSARY 词条）：通知两条 lane 在一轮里共同消费的输入——
/// 当前应用车辆 / 项目 / 记录 / 生效今天 + 通知设置 + 停车倒计时。
///
/// 相等语义镜像本模块收编前的字符串签名（reminderNotificationDataSignature
/// 与停车摘要），字段清单与顺序有意保持一致（2026-11-15 拍板：只收编、
/// 不改口径）：
///  - 数据面：车 = id / 当前里程 / sync.updatedAt；项目 = id / carsId /
///    启用 / 两个提醒开关 / 两个间隔 / 两个阈值 / 排序 / sync 两字段；
///    记录 = id / carId / 日期 / 里程 / 项目 id 序列 / sync 两字段；生效
///    今天。品牌/型号/上路日期等其余字段的变更由所属行的 sync.updatedAt
///    覆盖（任何写路径都会盖同步章）。
///  - 系统通知 lane：开关关 → 投影折叠为「关」（其余输入变化不再触发）；
///    开 → 重复频率 + 停车到点时刻 + 数据面。
///  - 应用内 lane：应用内开关 + 数据面（开关关时数据变化仍会触发一轮，
///    与本模块收编前的签名口径一致）。
///
/// 静默 / 「知道了」状态不在快照内：它们改变时由动作后的强制重排
/// （invalidateAll）负责。
class NotificationSyncSnapshot {
  const NotificationSyncSnapshot({
    required this.settings,
    required this.car,
    required this.items,
    required this.records,
    required this.today,
    required this.parkingCountdown,
  });

  /// 通知设置（系统/应用内开关、重复频率；按 lane 取各自切片比较）。
  final LunioNotificationSettings settings;

  /// 当前应用车辆（无车的轮次不构造快照，由调用方返回 null）。
  final Car car;

  /// 当前应用车辆的保养项目清单（顺序参与比较）。
  final List<MaintenanceItem> items;

  /// 当前应用车辆的保养记录清单（顺序参与比较）。
  final List<MaintenanceRecord> records;

  /// 生效今天（手动日期优先）。
  final LocalDate today;

  /// 停车倒计时（null = 没有进行中的倒计时；只有到点时刻进比较）。
  final ParkingCountdown? parkingCountdown;

  /// 系统通知 lane 的输入是否等价（镜像收编前的 systemSignature）：
  /// 两端都关 → 恒等价（投影折叠为「关」）；一端开一端关 → 不等价；
  /// 都开 → 重复频率 + 停车到点时刻 + 数据面。
  bool sameSystemLane(NotificationSyncSnapshot other) {
    if (settings.systemNotificationsEnabled !=
        other.settings.systemNotificationsEnabled) {
      return false;
    }
    if (!settings.systemNotificationsEnabled) {
      return true;
    }
    return settings.dueRepeatFrequency ==
            other.settings.dueRepeatFrequency &&
        parkingCountdown?.endsAt == other.parkingCountdown?.endsAt &&
        sameData(other);
  }

  /// 应用内 lane 的输入是否等价（镜像收编前的 inAppSignature）：应用内
  /// 开关 + 数据面；开关关时数据变化仍算不等价（同收编前口径）。
  bool sameInAppLane(NotificationSyncSnapshot other) {
    return settings.inAppNotificationsEnabled ==
            other.settings.inAppNotificationsEnabled &&
        sameData(other);
  }

  /// 数据面是否等价（车 + 项目 + 记录 + 生效今天；字段清单见类注释）。
  bool sameData(NotificationSyncSnapshot other) {
    return _sameCar(car, other.car) &&
        _sameItems(items, other.items) &&
        _sameRecords(records, other.records) &&
        today == other.today;
  }

  static bool _sameCar(Car a, Car b) {
    return a.id == b.id &&
        a.currentMileageKm == b.currentMileageKm &&
        a.sync.updatedAt == b.sync.updatedAt;
  }

  static bool _sameItems(List<MaintenanceItem> a, List<MaintenanceItem> b) {
    if (a.length != b.length) {
      return false;
    }
    for (var index = 0; index < a.length; index++) {
      if (!_sameItem(a[index], b[index])) {
        return false;
      }
    }
    return true;
  }

  static bool _sameItem(MaintenanceItem a, MaintenanceItem b) {
    return a.id == b.id &&
        a.carsId == b.carsId &&
        a.enabled == b.enabled &&
        a.remindByMileage == b.remindByMileage &&
        a.remindByTime == b.remindByTime &&
        a.mileageIntervalKm == b.mileageIntervalKm &&
        a.timeIntervalMonths == b.timeIntervalMonths &&
        a.notOverdueUpperLimit == b.notOverdueUpperLimit &&
        a.overdueUpperLimit == b.overdueUpperLimit &&
        a.sortOrder == b.sortOrder &&
        a.sync.updatedAt == b.sync.updatedAt &&
        a.sync.version == b.sync.version;
  }

  static bool _sameRecords(List<MaintenanceRecord> a, List<MaintenanceRecord> b) {
    if (a.length != b.length) {
      return false;
    }
    for (var index = 0; index < a.length; index++) {
      if (!_sameRecord(a[index], b[index])) {
        return false;
      }
    }
    return true;
  }

  static bool _sameRecord(MaintenanceRecord a, MaintenanceRecord b) {
    return a.id == b.id &&
        a.carId == b.carId &&
        a.date == b.date &&
        a.mileageKm == b.mileageKm &&
        _sameInts(a.itemIds, b.itemIds) &&
        a.sync.updatedAt == b.sync.updatedAt &&
        a.sync.version == b.sync.version;
  }

  static bool _sameInts(List<int> a, List<int> b) {
    if (a.length != b.length) {
      return false;
    }
    for (var index = 0; index < a.length; index++) {
      if (a[index] != b[index]) {
        return false;
      }
    }
    return true;
  }
}

/// 通知同步 engine：`同步数据源变了 → 该不该干活`的唯一决策点。
///
/// 一轮同步 = 读一份输入快照 → 两条 lane 各自与自己上次成功消费的快照
/// 比较（[NotificationSyncSnapshot.sameSystemLane] /
/// [NotificationSyncSnapshot.sameInAppLane]）→ 不等价才调对应 sink 执行
/// → sink 回报 [SyncLaneOutcome] → [SyncLaneOutcomeRules.commitsSnapshot]
/// 为真才记账。
///
/// 防竞态分工（与守卫模块的边界不变）：
///  - 「这轮还作数吗」（同步代数 + 写库中间态旗 + disposed）归
///    notification_sync_guard.dart，sink 在每个不可逆副作用前问票；
///  - 「执行中来了新请求怎么办」归本 module 的两个 per-lane
///    [GuardedOp]：本轮结束用最新输入重跑。成功才记账让 pending 重跑不再
///    需要清签名——下次比较自然不等价。
///  - 入口早退（disposed / 写库中间态 / 输入未就绪）也在本 module：调用方
///    只管"什么时候来问"，不重复表达"能不能同步"。
///
/// 失效入口：[invalidateSystemLane] / [invalidateInAppLane] /
/// [invalidateAllLanes]——回前台（应用内通道要重新检查弹窗）、权限请求
/// 真的弹过（授权结果影响通知内容）、弹窗动作后强制重排。失效会推进该
/// lane 的代数：在途轮次即使成功也不记账，结束后按 pending 语义重跑。
///
/// ≈ Java 的 @Service：无 WidgetRef/BuildContext，全部依赖经构造注入；
/// 单测用假 sink/假读与 Completer 驱动 await 边界（2026-11-15 收编）。
class NotificationSyncEngine {
  NotificationSyncEngine({
    required this.readSnapshot,
    required this.isDataResetInFlight,
    required this.isDisposed,
    required this.runSystemLane,
    required this.runInAppLane,
  });

  /// 读当前输入快照（生产 = 控制器从三个 provider 读值组装）：
  /// null = 数据未就绪 / 无车 / 无应用车辆数据束——本轮不跑。
  final NotificationSyncSnapshot? Function() readSnapshot;

  /// 破坏性写库进行中（守卫模块的写库中间态旗）：入口早退，本轮不跑。
  final bool Function() isDataResetInFlight;

  /// 控制器/壳层是否已销毁（[GuardedOp] 与入口早退共用）。
  final bool Function() isDisposed;

  /// 系统通知 lane 执行体（生产 = 控制器排通知）。异常由 engine 捕获：
  /// 不记账、记日志，下一次输入变化重试。
  final Future<SyncLaneOutcome> Function(NotificationSyncSnapshot) runSystemLane;

  /// 应用内提醒 lane 执行体（生产 = 决策体 reminder_dialog_flow）。
  final Future<SyncLaneOutcome> Function(NotificationSyncSnapshot) runInAppLane;

  /// 系统通知 lane 上次成功消费的快照（记账时机 = sink 回报 applied /
  /// skipped；aborted / failed 不记）。
  NotificationSyncSnapshot? _lastSystem;

  /// 应用内 lane 上次成功消费的快照。
  NotificationSyncSnapshot? _lastInApp;

  /// 在途轮次的输入（比较用：同输入的重复触发不再记 pending）。
  NotificationSyncSnapshot? _inFlightSystem;
  NotificationSyncSnapshot? _inFlightInApp;

  /// 失效代数：失效发生时在途轮次即使成功也不记账（防吞掉强制重跑）。
  int _systemEpoch = 0;
  int _inAppEpoch = 0;

  /// 系统 lane 重入保护（R3 语义）：执行中来了新输入不丢弃，本轮结束用
  /// 最新输入重跑（重跑即再走一轮入口判定，无需清任何签名）。
  late final GuardedOp _systemOp = GuardedOp(
    isDisposed: isDisposed,
    onRerun: sync,
  );

  /// 应用内 lane 重入保护（同 R3；两条 lane 互相独立）。
  late final GuardedOp _inAppOp = GuardedOp(
    isDisposed: isDisposed,
    onRerun: sync,
  );

  /// 同步入口：入口早退 → 读快照 → 两条 lane 各自判定与分发。
  /// 供控制器的 `syncFromProviders()` 与各失效入口调用；幂等、可重入。
  void sync() {
    if (isDisposed() || isDataResetInFlight()) {
      return;
    }
    final snapshot = readSnapshot();
    if (snapshot == null) {
      return;
    }
    if (!_isKnown(snapshot, _lastSystem, _inFlightSystem,
        (a, b) => a.sameSystemLane(b))) {
      _dispatchSystem(snapshot);
    }
    if (!_isKnown(snapshot, _lastInApp, _inFlightInApp,
        (a, b) => a.sameInAppLane(b))) {
      _dispatchInApp(snapshot);
    }
  }

  /// 系统通知 lane 的显式失效（权限请求真的弹过 / 弹窗动作后重排）：
  /// 清记账、推进代数、立即重跑一轮。
  void invalidateSystemLane() {
    _systemEpoch++;
    _lastSystem = null;
    _inFlightSystem = null;
    sync();
  }

  /// 应用内 lane 的显式失效（回前台要重新检查弹窗）：清记账、推进代数、
  /// 立即重跑一轮。
  void invalidateInAppLane() {
    _inAppEpoch++;
    _lastInApp = null;
    _inFlightInApp = null;
    sync();
  }

  /// 两条 lane 一起失效（应用内弹窗动作后的强制重排）。
  void invalidateAllLanes() {
    _systemEpoch++;
    _inAppEpoch++;
    _lastSystem = null;
    _lastInApp = null;
    _inFlightSystem = null;
    _inFlightInApp = null;
    sync();
  }

  /// 快照是否已被该 lane 消费或在途：同输入的重复触发不算新请求。
  bool _isKnown(
    NotificationSyncSnapshot snapshot,
    NotificationSyncSnapshot? last,
    NotificationSyncSnapshot? inFlight,
    bool Function(NotificationSyncSnapshot, NotificationSyncSnapshot) same,
  ) {
    if (last != null && same(last, snapshot)) {
      return true;
    }
    return inFlight != null && same(inFlight, snapshot);
  }

  void _dispatchSystem(NotificationSyncSnapshot snapshot) {
    if (!_systemOp.enter()) {
      return;
    }
    _inFlightSystem = snapshot;
    unawaited(_runSystem(snapshot));
  }

  void _dispatchInApp(NotificationSyncSnapshot snapshot) {
    if (!_inAppOp.enter()) {
      return;
    }
    _inFlightInApp = snapshot;
    unawaited(_runInApp(snapshot));
  }

  Future<void> _runSystem(NotificationSyncSnapshot snapshot) async {
    final epoch = _systemEpoch;
    try {
      final outcome = await runSystemLane(snapshot);
      if (outcome.commitsSnapshot && epoch == _systemEpoch) {
        _lastSystem = snapshot;
      }
    } catch (error) {
      // 失败不记账：下一次输入变化重试；异常不再逃逸成未捕获异步错误。
      debugPrint('通知同步（系统通知 lane）执行失败：$error');
    } finally {
      if (identical(_inFlightSystem, snapshot)) {
        _inFlightSystem = null;
      }
      _systemOp.exit();
    }
  }

  Future<void> _runInApp(NotificationSyncSnapshot snapshot) async {
    final epoch = _inAppEpoch;
    try {
      final outcome = await runInAppLane(snapshot);
      if (outcome.commitsSnapshot && epoch == _inAppEpoch) {
        _lastInApp = snapshot;
      }
    } catch (error) {
      debugPrint('通知同步（应用内 lane）执行失败：$error');
    } finally {
      if (identical(_inFlightInApp, snapshot)) {
        _inFlightInApp = null;
      }
      _inAppOp.exit();
    }
  }
}

