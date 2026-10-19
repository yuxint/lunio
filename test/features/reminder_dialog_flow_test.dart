// InAppReminderDialogFlow（应用内提醒弹窗链路决策体）的 plain-Dart 单测：
// 静默过滤（生效到期清单）、入口判定、弹窗动作分支、检查点协议。
//
// 决策体的静默读取、弹窗呈现、抑制偏好写、强制重排全部经注入接缝，本
// 文件注入假实现 + 真守卫（ProviderContainer 装配
// notificationSyncGuardProvider），completer 驱动每个 await 边界——
// notification_sync_controller_test.dart 文件头此前"静默判定偏好读的
// 亚毫秒窗口打不出确定性用例、保养位点靠同构 + 评审保障"的验证洞由本
// 文件关上：await 边界可控、写库中间态可在弹窗挂起期间插入并被检查点
// 拦下，检查点位点可直接变异验证（见下方变异记录）。
//
// 检查点位点变异验证（2026-10-15，临时改源码跑本文件后还原）：
//  - 删"静默循环内检查点"（每轮静默读后的 isValid；2026-10-19 起该
//    位点物理上在生效清单单一出口 reminder_notifications.dart 的
//    buildActiveDueList 内、经决策体注入的 shouldAbort 接缝接线，
//    当日变异复验：删出口内循环 shouldAbort 调用本用例红、还原绿）→
//    「检查点（静默循环内）」红（第二轮静默读照样发生）；
//  - 删"保养弹窗后检查点"（showMaintenanceDialog 返回后的 isValid）→
//    「检查点（弹窗后）」红（ack 照写、重排照触发）；
//  - 删"里程展示前复查"（canPresent 后的 isValid）→
//    「检查点（里程展示前·旗半 / 代数半）」两用例红（里程弹窗照样弹出）；
//    null 动作的「纵深」用例保持绿——null 路径上"弹窗后检查点"与"里程
//    展示前复查"之间无 await、任一道存活即拦，该位点由 acknowledged
//    路径（ack 写 await 期间插入作废）独占杀伤。
//
// 数据形态复刻 notification_sync_controller_test 的 seedBaseline/
// addOverdueItem 高频事实：车 2020-01-01 上路、一条今天记录（12 个月
// 机油项正常）、36 个月无自身记录项必到期（danger）、车辆同步时间戳
// 拨老则里程更新提醒到期（单条记录推断频率 = 每月）。
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunio/core/date/local_date.dart';
import 'package:lunio/domain/entities/car.dart';
import 'package:lunio/domain/entities/maintenance_item.dart';
import 'package:lunio/domain/entities/notification_settings.dart';
import 'package:lunio/domain/entities/sync_metadata.dart';
import 'package:lunio/features/shell/reminders/notification_coordinator.dart';
import 'package:lunio/features/shell/reminders/notification_sync_guard.dart';
import 'package:lunio/features/shell/reminders/reminder_dialog_flow.dart';

import '../helpers/builders.dart';

/// 固定"今天"：全部用例确定性钉死，不依赖真实时钟。
const LocalDate _today = LocalDate(2026, 10, 15);

void main() {
  test('静默过滤：稍后提醒/知道了两档都不进清单，未静默项进',
      () async {
    final h = _newHarness()
      ..items = [
        _overdueItem(id: 11, name: '刹车油'),
        _overdueItem(id: 12, name: '变速箱油'),
        _overdueItem(id: 13, name: '空调滤芯'),
      ]
      ..silenced['item:11'] = true // 稍后提醒期内
      ..silenced['item:12'] = true; // 今天已点过"知道了"

    await h.runFlow();

    expect(h.maintenanceShown, [
      ['空调滤芯'],
    ], reason: '两个静默档（snooze/ack）过滤后只剩未静默项进弹窗清单');
    expect(h.reschedules, 0, reason: '无动作不重排');
    expect(h.ackedItemIds, isEmpty);
  });

  test('无到期不弹：全部静默且里程不到期，呈现与重排零调用', () async {
    final h = _newHarness()
      ..items = [_overdueItem(id: 11)]
      ..silenced['item:11'] = true;

    await h.runFlow();

    expect(h.maintenanceShown, isEmpty);
    expect(h.mileageShownCount, 0);
    expect(h.reschedules, 0);
  });

  test('应用内开关关：不做静默读取也不弹', () async {
    final h = _newHarness()
      ..items = [_overdueItem(id: 11)]
      ..settings = const LunioNotificationSettings(
        inAppNotificationsEnabled: false,
      );

    await h.runFlow();

    expect(h.silenceReads, 0);
    expect(h.maintenanceShown, isEmpty);
  });

  test('canPresent false（壳层 context 已拆）：整轮放弃', () async {
    final h = _newHarness()
      ..items = [_overdueItem(id: 11)]
      ..canPresent = false;

    await h.runFlow();

    expect(h.maintenanceShown, isEmpty);
    expect(h.reschedules, 0);
  });

  test('入口复查：领票时写库中间态旗已举，整轮不开始', () async {
    final h = _newHarness()..items = [_overdueItem(id: 11)];
    h.guard.beginDataReset();
    addTearDown(h.guard.settleDataReset);

    await h.runFlow();

    expect(h.silenceReads, 0, reason: '入口复查拦在静默判定之前');
    expect(h.maintenanceShown, isEmpty);
  });

  test('入口复查：票注入的 disposed 为真，整轮不开始', () async {
    final h = _newHarness()
      ..items = [_overdueItem(id: 11)]
      ..disposedFlag = true;

    await h.runFlow();

    expect(h.silenceReads, 0);
    expect(h.maintenanceShown, isEmpty);
  });

  test('动作分支 acknowledged：逐项写当日 ack 并强制重排', () async {
    final h = _newHarness()
      ..items = [
        _normalItem(), // 机油：今天刚保养，不到期，不进清单
        _overdueItem(id: 11, name: '刹车油'),
        _overdueItem(id: 12, name: '变速箱油'),
      ]
      ..maintenanceAction = ReminderDialogAction.acknowledged;

    await h.runFlow();

    expect(h.maintenanceShown, [
      ['刹车油', '变速箱油'],
    ]);
    expect(h.ackedItemIds, [11, 12], reason: '只有清单内到期项写当日 ack');
    expect(h.reschedules, 1);
  });

  test('动作分支 snoozed：不写 ack（偏好写归弹窗呈现闭包）、强制重排',
      () async {
    final h = _newHarness()
      ..items = [_overdueItem(id: 11)]
      ..maintenanceAction = ReminderDialogAction.snoozed;

    await h.runFlow();

    expect(h.ackedItemIds, isEmpty);
    expect(h.reschedules, 1, reason: 'snooze 改变抑制状态，系统通知要重排');
  });

  test('动作分支 null（遮罩关闭）：无偏好写、不重排；里程到期则继续弹里程',
      () async {
    final h = _newHarness()
      ..items = [_overdueItem(id: 11)]
      ..mileageDueCar = true
      ..maintenanceAction = null;

    await h.runFlow();

    expect(h.ackedItemIds, isEmpty);
    expect(h.reschedules, 0);
    expect(h.mileageShownCount, 1, reason: 'null 动作只跳过保养弹窗的副作用，里程弹窗继续');
  });

  test('里程弹窗 acknowledged：写里程 ack、强制重排', () async {
    final h = _newHarness()
      ..mileageDueCar = true
      ..mileageAction = ReminderDialogAction.acknowledged;

    await h.runFlow();

    expect(h.ackedMileageCarIds, [1]);
    expect(h.reschedules, 1);
  });

  test('里程弹窗 snoozed：强制重排、无 ack 写', () async {
    final h = _newHarness()
      ..mileageDueCar = true
      ..mileageAction = ReminderDialogAction.snoozed;

    await h.runFlow();

    expect(h.ackedMileageCarIds, isEmpty);
    expect(h.reschedules, 1);
  });

  test('检查点（静默循环内）：静默读挂起期间写库开始，循环内拦下整轮',
      () async {
    final h = _newHarness()
      ..items = [_overdueItem(id: 11), _overdueItem(id: 12)];
    final gate = Completer<void>();
    h.silenceGates.add(gate); // 挂住第一次静默读
    final done = h.runFlow();

    await _waitUntil(() => h.silenceReads == 1);
    h.guard.beginDataReset();
    gate.complete();
    await done;

    expect(h.silenceReads, 1, reason: '循环内检查点拦下，第二轮静默读不发生');
    expect(h.maintenanceShown, isEmpty);
    expect(h.reschedules, 0);
  });

  test('检查点（弹窗后）：弹窗挂起期间写库开始，不写 ack、不重排',
      () async {
    final h = _newHarness()
      ..items = [_overdueItem(id: 11)]
      ..maintenanceAction = ReminderDialogAction.acknowledged;
    final gate = Completer<void>();
    h.maintenanceGate = gate; // 挂住保养弹窗
    final done = h.runFlow();

    await _waitUntil(() => h.maintenanceShown.isNotEmpty);
    h.guard.beginDataReset();
    gate.complete();
    await done;

    expect(h.ackedItemIds, isEmpty, reason: '弹窗后检查点拦下，ack 不写');
    expect(h.reschedules, 0);
  });

  test('检查点（里程展示前·旗半）：ack 写挂起期间写库开始，里程弹窗不出',
      () async {
    final h = _newHarness()
      ..items = [_overdueItem(id: 11)]
      ..mileageDueCar = true
      ..maintenanceAction = ReminderDialogAction.acknowledged;
    final dialogGate = Completer<void>();
    final ackGate = Completer<void>();
    h.maintenanceGate = dialogGate;
    h.ackGate = ackGate;
    final done = h.runFlow();

    await _waitUntil(() => h.maintenanceShown.isNotEmpty);
    dialogGate.complete(); // 弹窗返回 acknowledged，弹窗后检查点此刻仍有效
    await _waitUntil(() => h.ackReads == 1); // ack 写挂起中
    h.guard.beginDataReset(); // 写库在 ack 写期间开始，尚未结束
    ackGate.complete();
    await done;

    expect(h.ackedItemIds, [11], reason: 'ack 写在作废前已发生，属已提交副作用');
    expect(h.mileageShownCount, 0, reason: 'showMileageReminder 是旧快照，弹前复查拦下');
    expect(h.reschedules, 0);
  });

  test('检查点（里程展示前·代数半）：ack 写挂起期间写库已结束，里程弹窗不出',
      () async {
    final h = _newHarness()
      ..items = [_overdueItem(id: 11)]
      ..mileageDueCar = true
      ..maintenanceAction = ReminderDialogAction.acknowledged;
    final dialogGate = Completer<void>();
    final ackGate = Completer<void>();
    h.maintenanceGate = dialogGate;
    h.ackGate = ackGate;
    final done = h.runFlow();

    await _waitUntil(() => h.maintenanceShown.isNotEmpty);
    dialogGate.complete();
    await _waitUntil(() => h.ackReads == 1);
    // 写库在 ack 写期间开始并结束：旗已关，代数比领票快照 +2。
    h.guard.beginDataReset();
    h.guard.settleDataReset();
    ackGate.complete();
    await done;

    expect(h.ackedItemIds, [11]);
    expect(h.mileageShownCount, 0, reason: '旗已关但代数已变，弹前复查靠代数半边拦下');
    expect(h.reschedules, 0);
  });

  test('纵深（null 动作 + 弹窗挂起期间写库开始）：后续里程弹窗不出',
      () async {
    // 场景本身合法（用户关掉弹窗、写库进行中，不该接着弹旧快照的里程
    // 弹窗）；null 路径上"弹窗后检查点"与"里程展示前复查"之间无 await，
    // 任一道存活即拦——本用例锁行为语义，独占变异杀伤归上两用例与
    // 弹窗后用例。
    final h = _newHarness()
      ..items = [_overdueItem(id: 11)]
      ..mileageDueCar = true
      ..maintenanceAction = null; // 遮罩关闭，无副作用
    final gate = Completer<void>();
    h.maintenanceGate = gate;
    final done = h.runFlow();

    await _waitUntil(() => h.maintenanceShown.isNotEmpty);
    h.guard.beginDataReset(); // 写库在保养弹窗挂起期间开始，尚未结束
    gate.complete();
    await done;

    expect(h.mileageShownCount, 0);
    expect(h.reschedules, 0);
  });

  test('写库收尾后重新检查：新调用领新票，正常补判一轮', () async {
    final h = _newHarness()
      ..items = [_overdueItem(id: 11)]
      ..maintenanceAction = ReminderDialogAction.acknowledged;
    h.guard.beginDataReset();
    h.guard.settleDataReset();

    await h.runFlow();

    expect(h.maintenanceShown, [
      ['刹车油'],
    ], reason: 'settle 后数据已收敛，新一轮检查照常执行');
    expect(h.ackedItemIds, [11]);
    expect(h.reschedules, 1);
  });
}

/// 构造 harness 并登记容器清理（每用例独立容器，互不串票）。
_Harness _newHarness() {
  final h = _Harness();
  addTearDown(h.dispose);
  return h;
}

/// 等待条件成立（纯 test 无 pump，用零时延让事件循环推进）；超时即红。
Future<void> _waitUntil(bool Function() condition) async {
  for (var i = 0; i < 1000 && !condition(); i++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(condition(), isTrue, reason: '等待条件超时（检查 await 边界是否真的挂住）');
}

/// 不到期的机油项（今天刚保养，12 个月间隔）。
MaintenanceItem _normalItem() => MaintenanceItem(
      id: 10,
      carsId: 1,
      name: '机油',
      enabled: true,
      remindByMileage: false,
      remindByTime: true,
      timeIntervalMonths: 12,
      sortOrder: 1,
      sync: testSync,
    );

/// 到期项（36 个月时间间隔、无自身记录：与控制器测试 addOverdueItem 同
/// 构——回退基线早已超期，必产生 danger 到期提醒）。
MaintenanceItem _overdueItem({required int id, String name = '刹车油'}) =>
    MaintenanceItem(
      id: id,
      carsId: 1,
      name: name,
      enabled: true,
      remindByMileage: false,
      remindByTime: true,
      timeIntervalMonths: 36,
      sortOrder: 9,
      sync: testSync,
    );

/// 决策体假件 harness：真守卫（ProviderContainer 装配）+ 可编程接缝。
/// 静默读经 [silenceGates] 逐个挂起、弹窗呈现经 [maintenanceGate]/
/// [mileageGate] 挂起，测试在挂起窗口内对真守卫插旗/升代数，演练各
/// 检查点位点。
class _Harness {
  _Harness() {
    container = ProviderContainer();
    guard = container.read(notificationSyncGuardProvider);
  }

  late final ProviderContainer container;
  late final NotificationSyncGuard guard;

  /// 当轮快照数据（测试按需覆盖）。
  List<MaintenanceItem> items = [];

  /// true = 车辆同步时间戳拨老（2026-01-01），单条记录推断频率 = 每月，
  /// 里程更新提醒到期；缺省时间戳 = 今天，里程不到期。
  bool mileageDueCar = false;

  LunioNotificationSettings settings = const LunioNotificationSettings();

  /// 静默判定表：`item:<id>` / `mileage:<carId>` → 是否静默（缺省不静默）。
  final Map<String, bool> silenced = {};

  /// 静默读挂起门：非空时每次静默读依次消费一个 completer 再返回。
  final List<Completer<void>> silenceGates = [];

  /// 保养/里程弹窗的返回动作与挂起门。
  ReminderDialogAction? maintenanceAction;
  Completer<void>? maintenanceGate;
  ReminderDialogAction? mileageAction;
  Completer<void>? mileageGate;

  /// "知道了"ack 写挂起门与进入计数（演练"ack 写 await 期间发生写库"
  /// ——里程展示前复查位点的独占杀伤场景）。
  Completer<void>? ackGate;
  int ackReads = 0;

  /// 弹窗可展示性（生产 = 主壳层 context 检查）。
  bool canPresent = true;

  /// 票注入的 disposed 旗。
  bool disposedFlag = false;

  // ---- 断言面 ----
  final List<List<String>> maintenanceShown = []; // 每次呈现收到的项目名
  int mileageShownCount = 0;
  int silenceReads = 0;
  final List<int> ackedItemIds = [];
  final List<int> ackedMileageCarIds = [];
  int reschedules = 0;

  String _key(ReminderTarget target) => switch (target) {
        MaintenanceItemTarget(:final itemId) => 'item:$itemId',
        MileageUpdateTarget(:final carId) => 'mileage:$carId',
      };

  /// 跑一轮决策体检查链（车/记录固定为控制器测试 seedBaseline 同款）。
  Future<void> runFlow() {
    final car = Car(
      id: 1,
      brand: '本田',
      model: '思域',
      currentMileageKm: 100000,
      roadDate: const LocalDate(2020, 1, 1),
      sync: SyncMetadata(
        status: SyncStatus.synced,
        updatedAt: mileageDueCar ? DateTime(2026, 1, 1) : DateTime(2026, 10, 15),
      ),
    );
    final records = [
      defaultRecord(
        id: 100,
        carId: 1,
        date: _today,
        itemIds: const [10],
        costCents: 0,
        mileageKm: 99000,
      ),
    ];
    return _buildFlow().checkAndPresent(
      settings: settings,
      car: car,
      items: items,
      records: records,
      today: _today,
    );
  }

  /// 组装被测决策体（接缝注入假实现，领票接缝绑定真守卫）。
  InAppReminderDialogFlow _buildFlow() {
    return InAppReminderDialogFlow(
      acquireRun: () => guard.acquire(isDisposed: () => disposedFlag),
      isSilencedForInAppDialog: (target, today) async {
        silenceReads++;
        final gate = silenceGates.isEmpty ? null : silenceGates.removeAt(0);
        if (gate != null) {
          await gate.future;
        }
        return silenced[_key(target)] ?? false;
      },
      canPresentDialog: () => canPresent,
      showMaintenanceDialog:
          ({required car, required maintenanceNotices, required today}) async {
        maintenanceShown
            .add([for (final notice in maintenanceNotices) notice.item.name]);
        final gate = maintenanceGate;
        if (gate != null) {
          await gate.future;
        }
        return maintenanceAction;
      },
      showMileageDialog: ({required car, required today}) async {
        mileageShownCount++;
        final gate = mileageGate;
        if (gate != null) {
          await gate.future;
        }
        return mileageAction;
      },
      acknowledgeMaintenanceItem: (itemId, today) async {
        ackReads++;
        final gate = ackGate;
        if (gate != null) {
          await gate.future;
        }
        ackedItemIds.add(itemId);
      },
      acknowledgeMileageUpdate: (carId, today) async {
        ackedMileageCarIds.add(carId);
      },
      onForceReschedule: () => reschedules++,
    );
  }

  void dispose() => container.dispose();
}
