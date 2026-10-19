// 生效到期清单单一出口（buildActiveDueList，reminder_notifications.dart）
// 的机制测试：循环形状（静默过滤 + 无 id 跳过）、里程生效性判定、
// shouldAbort 中止、两通道静默语义差异。
//
// 2026-10-19 收编：此前系统通知（buildScheduledNotifications）与应用内
// 弹窗（reminder_dialog_flow）各手抄一份同形循环——取到期清单、逐项问
// 静默、跳过无 id 项目、里程到期+静默判定，收编后两通道经同一出口，
// 静默语义按通道由传入的判定闭包参数化（差异本身归协调器两个同名单
// 方法单一拥有，见 notification_silence_rules_test）。
//
// 本文件两套接法：
//  - fake 静默判定表（Map<targetKey, bool>）：锁循环形状、无 id 跳过、
//    里程三态、中止谓词；
//  - 真协调器 + 内存数据库（同 notification_silence_rules_test 的装配）：
//    锁两通道语义差异——snooze 两通道都滤、"知道了"只滤应用内。
//
// 检查点存活（静默循环内的 shouldAbort 位点）由
// reminder_dialog_flow_test「检查点（静默循环内）」端到端锁死：删本出口
// 内的 shouldAbort 调用该测试即红（2026-10-19 变异复验：删循环内调用红、
// 还原绿，见该文件头部变异记录）。
//
// 数据形态复刻 reminder_dialog_flow_test 的高频事实：车 2020-01-01 上路、
// 一条今天记录（12 个月机油项正常）、36 个月无自身记录项必到期
// （danger）、车辆同步时间戳拨老则里程更新提醒到期（单条记录推断
// 频率 = 每月）。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunio/app/providers.dart';
import 'package:lunio/core/date/local_date.dart';
import 'package:lunio/data/database/app_database.dart';
import 'package:lunio/domain/entities/car.dart';
import 'package:lunio/domain/entities/maintenance_item.dart';
import 'package:lunio/domain/entities/maintenance_record.dart';
import 'package:lunio/domain/entities/sync_metadata.dart';
import 'package:lunio/features/shell/reminders/notification_coordinator.dart';
import 'package:lunio/features/shell/reminders/reminder_notifications.dart';

import '../helpers/builders.dart';

/// 固定"今天"：全部用例确定性钉死，不依赖真实时钟。
const LocalDate _today = LocalDate(2026, 10, 19);

void main() {
  // ---- fake 静默判定表：循环形状与里程判定 ----

  test('无到期为空：项目不到期 + 里程不到期 → isEmpty', () async {
    final active = await _build(
      items: [_normalItem()],
      silenced: const {},
    );

    expect(active, isNotNull);
    expect(active!.maintenanceNotices, isEmpty);
    expect(active.mileageUpdate, isFalse, reason: '车辆同步时间戳是今天，里程不到期');
    expect(active.isEmpty, isTrue);
  });

  test('无记录不产生提醒：必到期项目但无任何记录 → 到期清单为空（产品约定）',
      () async {
    final active = await _build(
      items: [_overdueItem(id: 11)],
      silenced: const {},
      emptyRecords: true,
    );

    expect(active, isNotNull);
    expect(active!.maintenanceNotices, isEmpty,
        reason: '新车主不被无历史基线的假超期轰炸');
    expect(active.isEmpty, isTrue);
  });

  test('部分静默过滤：静默项被滤掉、未静默项进清单', () async {
    final active = await _build(
      items: [
        _overdueItem(id: 11, name: '刹车油'),
        _overdueItem(id: 12, name: '变速箱油'),
        _overdueItem(id: 13, name: '空调滤芯'),
      ],
      silenced: const {'item:12': true},
    );

    expect(
      active!.maintenanceNotices.map((row) => row.item.name),
      ['刹车油', '空调滤芯'],
    );
    expect(active.isEmpty, isFalse);
  });

  test('无 id 项目跳过：不进清单也不问静默判定', () async {
    var reads = 0;
    final active = await _build(
      items: [_overdueItem(id: null), _overdueItem(id: 11)],
      isSilenced: (target, today) async {
        reads++;
        return false;
      },
    );

    expect(active!.maintenanceNotices.map((row) => row.item.id), [11]);
    expect(reads, 1, reason: '无 id 项目在静默判定之前就被跳过');
  });

  test('里程三态：到期未静默为真 / 到期已静默为假 / 无 carId 不读静默',
      () async {
    // 到期且未静默 → 生效。
    var reads = 0;
    var active = await _build(
      mileageDueCar: true,
      isSilenced: (target, today) async {
        reads++;
        return false;
      },
    );
    expect(active!.mileageUpdate, isTrue);

    // 到期但已静默 → 不生效。
    active = await _build(
      mileageDueCar: true,
      silenced: const {'mileage:1': true},
    );
    expect(active!.mileageUpdate, isFalse);

    // 无 carId（车未落库）→ 不生效且不问静默（目标需要持久 id）。
    reads = 0;
    active = await _build(
      carId: null,
      mileageDueCar: true,
      isSilenced: (target, today) async {
        reads++;
        return false;
      },
    );
    expect(active!.mileageUpdate, isFalse);
    expect(reads, 0, reason: 'carId 为空时静默读被短路');
  });

  test('shouldAbort（保养位）：首轮静默读后中止 → 返回 null，不再继续',
      () async {
    var reads = 0;
    final active = await _build(
      items: [_overdueItem(id: 11), _overdueItem(id: 12)],
      isSilenced: (target, today) async {
        reads++;
        return false;
      },
      shouldAbort: () => reads >= 1,
    );

    expect(active, isNull, reason: '中止 = 整轮作废（调用方放弃本轮）');
    expect(reads, 1, reason: '第一轮静默读后的中止拦下了第二轮读');
  });

  test('shouldAbort（里程位）：保养段完成后在里程静默读后中止 → 返回 null',
      () async {
    var reads = 0;
    final active = await _build(
      items: [_overdueItem(id: 11)],
      mileageDueCar: true,
      isSilenced: (target, today) async {
        reads++;
        return false;
      },
      // 第 1 次 = 保养项静默读（放行），第 2 次 = 里程静默读（中止）。
      shouldAbort: () => reads >= 2,
    );

    expect(active, isNull);
    expect(reads, 2);
  });

  // ---- 真协调器 + 内存库：两通道静默语义差异 ----

  test('两通道语义差异（保养）：snooze 两通道都滤，"知道了"只滤应用内',
      () async {
    final coordinator = _newCoordinator();
    // 项目 11 点"稍后提醒"（+15 天）、项目 12 今天点"知道了"、13 未动。
    await coordinator.snoozeMaintenanceItems([11], _today);
    await coordinator.acknowledgeMaintenanceItem(12, _today);
    final items = [
      _overdueItem(id: 11, name: '刹车油'),
      _overdueItem(id: 12, name: '变速箱油'),
      _overdueItem(id: 13, name: '空调滤芯'),
    ];

    final systemChannel = await _build(
      items: items,
      isSilenced: coordinator.isSilencedForSystemNotification,
    );
    final inAppChannel = await _build(
      items: items,
      isSilenced: coordinator.isSilencedForInAppDialog,
    );

    expect(
      systemChannel!.maintenanceNotices.map((row) => row.item.id),
      [12, 13],
      reason: '"知道了"不影响系统通知，只滤掉 snooze 的 11',
    );
    expect(
      inAppChannel!.maintenanceNotices.map((row) => row.item.id),
      [13],
      reason: '应用内两档静默都滤，11 与 12 都不弹',
    );
  });

  test('两通道语义差异（里程）："知道了"只静默应用内弹窗，系统通知照发',
      () async {
    final coordinator = _newCoordinator();
    await coordinator.acknowledgeMileageUpdate(1, _today);

    final systemChannel = await _build(
      mileageDueCar: true,
      isSilenced: coordinator.isSilencedForSystemNotification,
    );
    final inAppChannel = await _build(
      mileageDueCar: true,
      isSilenced: coordinator.isSilencedForInAppDialog,
    );

    expect(systemChannel!.mileageUpdate, isTrue, reason: '系统通知只认"稍后提醒"');
    expect(inAppChannel!.mileageUpdate, isFalse, reason: '今天已"知道了"，应用内不弹');
  });
}

/// 构造一次出口调用。车/记录复刻 reminder_dialog_flow_test 的数据形状：
/// 一条今天记录（12 个月机油项正常）；[mileageDueCar] 把车辆同步时间戳
/// 拨老（2026-01-01）让里程更新提醒到期；[silenced] 是 fake 静默判定表
/// （`item:<id>` / `mileage:<carId>`，缺省不静默）。
Future<ActiveDueList?> _build({
  List<MaintenanceItem> items = const [],
  Map<String, bool> silenced = const {},
  ReminderSilenceRead? isSilenced,
  bool Function()? shouldAbort,
  bool mileageDueCar = false,
  int? carId = 1,
  bool emptyRecords = false,
}) {
  final car = Car(
    id: carId,
    brand: '本田',
    model: '思域',
    currentMileageKm: 100000,
    roadDate: const LocalDate(2020, 1, 1),
    sync: SyncMetadata(
      status: SyncStatus.synced,
      updatedAt: mileageDueCar ? DateTime(2026, 1, 1) : DateTime(2026, 10, 19),
    ),
  );
  final records = emptyRecords
      ? const <MaintenanceRecord>[]
      : [
          defaultRecord(
            id: 100,
            carId: 1,
            date: _today,
            itemIds: const [10],
            costCents: 0,
            mileageKm: 99000,
          ),
        ];
  return buildActiveDueList(
    car: car,
    items: items,
    records: records,
    today: _today,
    isSilenced: isSilenced ?? _tableSilenceRead(silenced),
    shouldAbort: shouldAbort,
  );
}

/// fake 静默判定表 → 判定闭包（缺省不静默）。
ReminderSilenceRead _tableSilenceRead(Map<String, bool> silenced) {
  return (target, today) async => silenced[_key(target)] ?? false;
}

String _key(ReminderTarget target) => switch (target) {
      MaintenanceItemTarget(:final itemId) => 'item:$itemId',
      MileageUpdateTarget(:final carId) => 'mileage:$carId',
    };

/// 真协调器（内存库装配同 notification_silence_rules_test，teardown 就地
/// 登记容器与数据库清理）。
LunioNotificationCoordinator _newCoordinator() {
  final database = AppDatabase.inMemory();
  final container = ProviderContainer(
    overrides: [appDatabaseProvider.overrideWithValue(database)],
  );
  addTearDown(() async {
    container.dispose();
    await database.close();
  });
  return container.read(notificationCoordinatorProvider);
}

/// 不到期的机油项（今天刚保养，12 个月间隔）——消费一条今天记录。
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

/// 到期项（36 个月时间间隔、无自身记录：回退基线早已超期，必产生
/// danger 到期提醒）——与 reminder_dialog_flow_test 的 _overdueItem 同构。
MaintenanceItem _overdueItem({required int? id, String name = '刹车油'}) =>
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
