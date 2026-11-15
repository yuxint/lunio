// 同步快照（NotificationSyncSnapshot）相等语义的直接单测（2026-11-15，
// 通知同步 engine 收编第一步）。
//
// 锁两件事：
//  1. 数据面字段覆盖：车 / 项目 / 记录 / 生效今天里每一个进入通知口径的
//     字段翻转都要让快照变"不等价"——清单镜像收编前的字符串签名
//     （reminderNotificationDataSignature），漏一个字段即红；
//  2. 两条 lane 的投影：系统 lane 关时折叠为「关」、应用内 lane 开关关时
//    数据变化仍触发一轮（与收编前签名口径一致）。
//
// 快照是纯值对象，本文件零 widget、零容器。
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lunio/core/date/local_date.dart';
import 'package:lunio/domain/entities/car.dart';
import 'package:lunio/domain/entities/maintenance_item.dart';
import 'package:lunio/domain/entities/maintenance_record.dart';
import 'package:lunio/domain/entities/notification_settings.dart';
import 'package:lunio/domain/entities/parking_countdown.dart';
import 'package:lunio/domain/entities/sync_metadata.dart';
import 'package:lunio/features/shell/reminders/notification_sync_engine.dart';

import '../helpers/builders.dart';

final _baseCar = Car(
  id: 1,
  brand: '本田',
  model: '22款思域',
  currentMileageKm: 10000,
  roadDate: const LocalDate(2023, 8, 12),
  sync: testSync,
);

final _baseItem = defaultOilItem(carsId: 1).copyWith(id: 10);

final _baseRecord = defaultRecord(
  id: 100,
  carId: 1,
  date: const LocalDate(2026, 4, 1),
  itemIds: const [10],
  costCents: 0,
  mileageKm: 9000,
);

const _today = LocalDate(2026, 5, 19);

NotificationSyncSnapshot snapshot({
  LunioNotificationSettings settings = const LunioNotificationSettings(),
  Car? car,
  List<MaintenanceItem>? items,
  List<MaintenanceRecord>? records,
  LocalDate? today,
  ParkingCountdown? parkingCountdown,
}) {
  return NotificationSyncSnapshot(
    settings: settings,
    car: car ?? _baseCar,
    items: items ?? [_baseItem],
    records: records ?? [_baseRecord],
    today: today ?? _today,
    parkingCountdown: parkingCountdown,
  );
}

void main() {
  group('sameData：数据面字段覆盖（镜像收编前的全量数据签名）', () {
    test('同一输入等价', () {
      expect(snapshot().sameData(snapshot()), isTrue);
    });

    test('车字段逐项翻转', () {
      final flips = <String, Car>{
        'id': Car(
          id: 2,
          brand: _baseCar.brand,
          model: _baseCar.model,
          currentMileageKm: _baseCar.currentMileageKm,
          roadDate: _baseCar.roadDate,
          sync: _baseCar.sync,
        ),
        'currentMileageKm': _baseCar.copyWith(currentMileageKm: 10001),
        'sync.updatedAt': _baseCar.copyWith(
          sync: SyncMetadata(
            status: SyncStatus.synced,
            updatedAt: DateTime(2026, 1, 2),
          ),
        ),
      };
      flips.forEach((name, car) {
        expect(
          snapshot(car: car).sameData(snapshot()),
          isFalse,
          reason: '车字段 $name 翻转后应不等价',
        );
      });
    });

    test('项目字段逐项翻转', () {
      final flips = <String, MaintenanceItem>{
        'id': _baseItem.copyWith(id: 11),
        'carsId': _baseItem.copyWith(carsId: 2),
        'enabled': _baseItem.copyWith(enabled: false),
        'remindByMileage': _baseItem.copyWith(remindByMileage: false),
        'remindByTime': _baseItem.copyWith(remindByTime: false),
        'mileageIntervalKm': _baseItem.copyWith(mileageIntervalKm: 6000),
        'timeIntervalMonths': _baseItem.copyWith(timeIntervalMonths: 12),
        'notOverdueUpperLimit': _baseItem.copyWith(notOverdueUpperLimit: 90),
        'overdueUpperLimit': _baseItem.copyWith(overdueUpperLimit: 120),
        'sortOrder': _baseItem.copyWith(sortOrder: 2),
        'sync.updatedAt': _baseItem.copyWith(
          sync: SyncMetadata(
            status: SyncStatus.synced,
            updatedAt: DateTime(2026, 1, 2),
          ),
        ),
        'sync.version': _baseItem.copyWith(
          sync: SyncMetadata(
            status: SyncStatus.synced,
            updatedAt: DateTime(2026),
            version: 2,
          ),
        ),
      };
      flips.forEach((name, item) {
        expect(
          snapshot(items: [item]).sameData(snapshot()),
          isFalse,
          reason: '项目字段 $name 翻转后应不等价',
        );
      });
    });

    test('记录字段逐项翻转', () {
      MaintenanceRecord record({
        int? id,
        int? carId,
        LocalDate? date,
        int? mileageKm,
        List<int>? itemIds,
        DateTime? updatedAt,
        int? version,
      }) {
        return defaultRecord(
          id: id ?? _baseRecord.id,
          carId: carId ?? _baseRecord.carId,
          date: date ?? _baseRecord.date,
          itemIds: itemIds ?? _baseRecord.itemIds,
          costCents: _baseRecord.costCents,
          mileageKm: mileageKm ?? _baseRecord.mileageKm,
          sync: SyncMetadata(
            status: SyncStatus.synced,
            updatedAt: updatedAt ?? _baseRecord.sync.updatedAt,
            version: version ?? _baseRecord.sync.version,
          ),
        );
      }

      final flips = <String, MaintenanceRecord>{
        'id': record(id: 101),
        'carId': record(carId: 2),
        'date': record(date: const LocalDate(2026, 4, 2)),
        'mileageKm': record(mileageKm: 9001),
        'itemIds': record(itemIds: const [11]),
        'sync.updatedAt': record(updatedAt: DateTime(2026, 1, 2)),
        'sync.version': record(version: 2),
      };
      flips.forEach((name, flipped) {
        expect(
          snapshot(records: [flipped]).sameData(snapshot()),
          isFalse,
          reason: '记录字段 $name 翻转后应不等价',
        );
      });
    });

    test('列表长度、顺序与生效今天参与比较', () {
      final otherItem = defaultOilItem(carsId: 1, name: '刹车油')
          .copyWith(id: 11, sortOrder: 2);
      expect(snapshot(items: [_baseItem, otherItem]).sameData(snapshot()),
          isFalse);
      expect(
        snapshot(items: [otherItem, _baseItem]).sameData(
          snapshot(items: [_baseItem, otherItem]),
        ),
        isFalse,
        reason: '项目顺序变化应不等价（镜像 join 顺序敏感的口径）',
      );
      final otherRecord = defaultRecord(
        id: 101,
        carId: 1,
        date: const LocalDate(2026, 4, 2),
        itemIds: const [10],
        costCents: 0,
        mileageKm: 9001,
      );
      expect(
        snapshot(records: [otherRecord, _baseRecord]).sameData(
          snapshot(records: [_baseRecord, otherRecord]),
        ),
        isFalse,
        reason: '记录顺序变化应不等价',
      );
      expect(
        snapshot(today: const LocalDate(2026, 5, 20)).sameData(snapshot()),
        isFalse,
      );
    });

    test('未入签名的字段不参与比较（由行的 sync.updatedAt 覆盖）', () {
      final renamedCar = Car(
        id: _baseCar.id,
        brand: '丰田',
        model: '卡罗拉',
        currentMileageKm: _baseCar.currentMileageKm,
        roadDate: const LocalDate(2024, 1, 1),
        sync: _baseCar.sync,
      );
      final renamedItem = _baseItem.copyWith(name: '全合成机油');
      final editedRecord = defaultRecord(
        id: _baseRecord.id,
        carId: _baseRecord.carId,
        date: _baseRecord.date,
        itemIds: _baseRecord.itemIds,
        costCents: 12345,
        mileageKm: _baseRecord.mileageKm,
        note: '换了备注',
        sync: _baseRecord.sync,
      );
      expect(
        snapshot(
          car: renamedCar,
          items: [renamedItem],
          records: [editedRecord],
        ).sameData(snapshot()),
        isTrue,
      );
    });
  });

  group('lane 投影', () {
    test('系统 lane：同一输入等价；应用内开关不参与', () {
      expect(snapshot().sameSystemLane(snapshot()), isTrue);
      expect(
        snapshot(
          settings: const LunioNotificationSettings(
            inAppNotificationsEnabled: false,
          ),
        ).sameSystemLane(snapshot()),
        isTrue,
      );
    });

    test('系统 lane：两端都关时折叠为「关」，其余输入变化不再触发', () {
      const off = LunioNotificationSettings(systemNotificationsEnabled: false);
      expect(
        snapshot(
          settings: const LunioNotificationSettings(
            systemNotificationsEnabled: false,
            inAppNotificationsEnabled: false,
            dueRepeatFrequency: ReminderRepeatFrequency.daily,
          ),
          car: Car(
            id: 9,
            brand: '丰田',
            model: '卡罗拉',
            currentMileageKm: 1,
            roadDate: const LocalDate(2020, 1, 1),
            sync: testSync,
          ),
          today: const LocalDate(2026, 1, 1),
          parkingCountdown: ParkingCountdown(
            startedAt: DateTime(2026, 1, 1, 10),
            durationSeconds: 3600,
          ),
        ).sameSystemLane(snapshot(settings: off)),
        isTrue,
      );
    });

    test('系统 lane：开关、重复频率、停车到点时刻、数据面参与比较', () {
      expect(
        snapshot(
          settings: const LunioNotificationSettings(
            systemNotificationsEnabled: false,
          ),
        ).sameSystemLane(snapshot()),
        isFalse,
      );
      expect(
        snapshot(
          settings: const LunioNotificationSettings(
            dueRepeatFrequency: ReminderRepeatFrequency.monthly,
          ),
        ).sameSystemLane(snapshot()),
        isFalse,
      );
      final parking = ParkingCountdown(
        startedAt: DateTime(2026, 5, 19, 10),
        durationSeconds: 3600,
      );
      expect(
        snapshot(parkingCountdown: parking).sameSystemLane(snapshot()),
        isFalse,
      );
      expect(
        snapshot(
          parkingCountdown: parking,
        ).sameSystemLane(
          snapshot(
            parkingCountdown: ParkingCountdown(
              startedAt: DateTime(2026, 5, 19, 10),
              durationSeconds: 1800,
            ),
          ),
        ),
        isFalse,
        reason: '到点时刻不同应不等价',
      );
      expect(
        snapshot(car: _baseCar.copyWith(currentMileageKm: 10001))
            .sameSystemLane(snapshot()),
        isFalse,
      );
    });

    test('应用内 lane：开关与数据面参与；系统侧设置不参与', () {
      expect(snapshot().sameInAppLane(snapshot()), isTrue);
      expect(
        snapshot(
          settings: const LunioNotificationSettings(
            inAppNotificationsEnabled: false,
          ),
        ).sameInAppLane(snapshot()),
        isFalse,
      );
      expect(
        snapshot(
          settings: const LunioNotificationSettings(
            systemNotificationsEnabled: false,
            dueRepeatFrequency: ReminderRepeatFrequency.monthly,
          ),
        ).sameInAppLane(snapshot()),
        isTrue,
      );
      expect(
        snapshot(car: _baseCar.copyWith(currentMileageKm: 10001))
            .sameInAppLane(snapshot()),
        isFalse,
      );
    });

    test('应用内 lane：开关关时数据变化仍算不等价（收编前签名口径）', () {
      const off = LunioNotificationSettings(inAppNotificationsEnabled: false);
      expect(
        snapshot(
          settings: off,
          car: _baseCar.copyWith(currentMileageKm: 10001),
        ).sameInAppLane(snapshot(settings: off)),
        isFalse,
      );
    });
  });

  group('SyncLaneOutcome 记账判定', () {
    test('applied / skipped 记账，aborted / failed 不记账', () {
      expect(SyncLaneOutcome.applied.commitsSnapshot, isTrue);
      expect(SyncLaneOutcome.skipped.commitsSnapshot, isTrue);
      expect(SyncLaneOutcome.aborted.commitsSnapshot, isFalse);
      expect(SyncLaneOutcome.failed.commitsSnapshot, isFalse);
    });
  });

  group('NotificationSyncEngine', () {
    test('入口早退：输入未就绪 / 写库中间态 / 已销毁都不调 sink', () async {
      final h = _EngineHarness();
      h.current = null;
      h.engine.sync();
      await pumpEventQueue();
      expect(h.system.calls, isEmpty);
      expect(h.inApp.calls, isEmpty);

      h.current = snapshot();
      h.dataResetInFlight = true;
      h.engine.sync();
      await pumpEventQueue();
      expect(h.system.calls, isEmpty);

      h.dataResetInFlight = false;
      h.disposed = true;
      h.engine.sync();
      await pumpEventQueue();
      expect(h.system.calls, isEmpty);
    });

    test('首轮两条 lane 各跑一次；同一快照再次触发不重跑', () async {
      final h = _EngineHarness();
      h.engine.sync();
      await pumpEventQueue();
      expect(h.system.calls, hasLength(1));
      expect(h.inApp.calls, hasLength(1));

      h.engine.sync();
      await pumpEventQueue();
      expect(h.system.calls, hasLength(1));
      expect(h.inApp.calls, hasLength(1));
    });

    test('数据变化两条 lane 都重跑；lane 各自只认自己的投影', () async {
      final h = _EngineHarness();
      h.engine.sync();
      await pumpEventQueue();
      expect(h.system.calls, hasLength(1));
      expect(h.inApp.calls, hasLength(1));

      h.current = snapshot(car: _baseCar.copyWith(currentMileageKm: 10001));
      h.engine.sync();
      await pumpEventQueue();
      expect(h.system.calls, hasLength(2));
      expect(h.inApp.calls, hasLength(2));

      // 系统侧设置变化：只有系统 lane 重跑。
      h.current = snapshot(
        car: _baseCar.copyWith(currentMileageKm: 10001),
        settings: const LunioNotificationSettings(
          dueRepeatFrequency: ReminderRepeatFrequency.monthly,
        ),
      );
      h.engine.sync();
      await pumpEventQueue();
      expect(h.system.calls, hasLength(3));
      expect(h.inApp.calls, hasLength(2));

      // 应用内开关变化：只有应用内 lane 重跑。
      h.current = snapshot(
        car: _baseCar.copyWith(currentMileageKm: 10001),
        settings: const LunioNotificationSettings(
          dueRepeatFrequency: ReminderRepeatFrequency.monthly,
          inAppNotificationsEnabled: false,
        ),
      );
      h.engine.sync();
      await pumpEventQueue();
      expect(h.system.calls, hasLength(3));
      expect(h.inApp.calls, hasLength(3));
    });

    test('系统开关关：数据变化不再触发系统 lane（投影折叠为「关」）', () async {
      const off = LunioNotificationSettings(systemNotificationsEnabled: false);
      final h = _EngineHarness();
      h.current = snapshot(settings: off);
      h.engine.sync();
      await pumpEventQueue();
      expect(h.system.calls, hasLength(1));

      h.current = snapshot(
        settings: off,
        car: _baseCar.copyWith(currentMileageKm: 10001),
      );
      h.engine.sync();
      await pumpEventQueue();
      expect(h.system.calls, hasLength(1), reason: '系统 lane 已折叠');
      expect(h.inApp.calls, hasLength(2));
    });

    test('aborted 不记账：同一快照下一次触发继续重试', () async {
      final h = _EngineHarness();
      h.system.outcome = SyncLaneOutcome.aborted;
      h.engine.sync();
      await pumpEventQueue();
      expect(h.system.calls, hasLength(1));

      h.engine.sync();
      await pumpEventQueue();
      expect(h.system.calls, hasLength(2));

      h.system.outcome = SyncLaneOutcome.applied;
      h.engine.sync();
      await pumpEventQueue();
      expect(h.system.calls, hasLength(3));
    });

    test('skipped 记账：同一快照不再重试', () async {
      final h = _EngineHarness();
      h.system.outcome = SyncLaneOutcome.skipped;
      h.engine.sync();
      await pumpEventQueue();
      expect(h.system.calls, hasLength(1));

      h.engine.sync();
      await pumpEventQueue();
      expect(h.system.calls, hasLength(1));
    });

    test('执行异常不记账、不逃逸：下一次触发重试', () async {
      final h = _EngineHarness();
      h.system.throws = true;
      h.engine.sync();
      await pumpEventQueue();
      expect(h.system.calls, hasLength(1));

      h.system.throws = false;
      h.engine.sync();
      await pumpEventQueue();
      expect(h.system.calls, hasLength(2));
    });

    test('失效入口：应用内只重跑应用内，invalidateAll 两条都重跑', () async {
      final h = _EngineHarness();
      h.engine.sync();
      await pumpEventQueue();
      expect(h.system.calls, hasLength(1));
      expect(h.inApp.calls, hasLength(1));

      h.engine.invalidateInAppLane();
      await pumpEventQueue();
      expect(h.system.calls, hasLength(1));
      expect(h.inApp.calls, hasLength(2));

      h.engine.invalidateAllLanes();
      await pumpEventQueue();
      expect(h.system.calls, hasLength(2));
      expect(h.inApp.calls, hasLength(3));
    });

    test('执行中新输入不丢弃：本轮结束用最新快照重跑（pending）', () async {
      final h = _EngineHarness();
      h.system.gated = true;
      h.engine.sync();
      expect(h.system.calls, hasLength(1));

      h.current = snapshot(car: _baseCar.copyWith(currentMileageKm: 10001));
      h.engine.sync();
      expect(h.system.calls, hasLength(1), reason: '在途期间只记 pending');

      h.system.release();
      await pumpEventQueue();
      expect(h.system.calls, hasLength(2));
      expect(h.system.calls.last.car.currentMileageKm, 10001);

      h.system.release();
      await pumpEventQueue();
      h.engine.sync();
      await pumpEventQueue();
      expect(h.system.calls, hasLength(2), reason: '最新快照已记账');
    });

    test('失效发生在途：旧轮次成功也不记账，结束后强制重跑', () async {
      final h = _EngineHarness();
      h.system.gated = true;
      h.engine.sync();
      expect(h.system.calls, hasLength(1));

      h.engine.invalidateSystemLane();
      expect(h.system.calls, hasLength(1), reason: '在途中只记 pending');

      h.system.release();
      await pumpEventQueue();
      expect(h.system.calls, hasLength(2), reason: '失效代数作废旧轮记账并重跑');

      h.system.release();
      await pumpEventQueue();
      h.engine.sync();
      await pumpEventQueue();
      expect(h.system.calls, hasLength(2));
    });
  });
}

/// lane 执行体替身：记录调用；可返回值、抛异常或挂门闩（pending 用例）。
class _LaneFake {
  final calls = <NotificationSyncSnapshot>[];
  SyncLaneOutcome outcome = SyncLaneOutcome.applied;
  bool throws = false;
  bool gated = false;
  final _gates = <Completer<SyncLaneOutcome>>[];

  Future<SyncLaneOutcome> call(NotificationSyncSnapshot snapshot) async {
    calls.add(snapshot);
    if (throws) {
      throw StateError('lane boom');
    }
    if (!gated) {
      return outcome;
    }
    final gate = Completer<SyncLaneOutcome>();
    _gates.add(gate);
    return gate.future;
  }

  /// 放行最早一个挂起的轮次。
  void release([SyncLaneOutcome result = SyncLaneOutcome.applied]) {
    _gates.removeAt(0).complete(result);
  }
}

/// engine 装具：可变快照 + 入口旗 + 两个 lane 替身。
class _EngineHarness {
  _EngineHarness() {
    engine = NotificationSyncEngine(
      readSnapshot: () => current,
      isDataResetInFlight: () => dataResetInFlight,
      isDisposed: () => disposed,
      runSystemLane: system.call,
      runInAppLane: inApp.call,
    );
  }

  final system = _LaneFake();
  final inApp = _LaneFake();
  NotificationSyncSnapshot? current = snapshot();
  bool dataResetInFlight = false;
  bool disposed = false;
  late final NotificationSyncEngine engine;
}
