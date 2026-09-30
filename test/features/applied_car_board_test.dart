// 应用车辆数据束机制测试（.scratch/arch-1001 票据 01）：锁就绪语义与
// 无车空态——2026-10-01 收编"当前应用车辆 + 项目清单 + 保养记录 +
// 生效今天"四件套为单一数据接缝（appliedCarBoardProvider）后，这是
// 新机制的测试面（仿 preferences_epoch_test 形态：内存库 +
// ProviderContainer 驱动真实装配）。
//
// 锁三件事：
//  1. 就绪语义：任一上游未就绪（这里用 Completer 挂起应用车辆）→
//     数据束整体 loading；就绪后四件套一次拿齐（items/records 带库里
//     播种数据、today 为生效今天）——四条上游取数行删任何一条，用例
//     拿不到播种数据即红；
//  2. 失效传导：上游（applied 记录派生）失效后数据束自动重算出新值
//     ——锁"watch 上游"不许改成 read（read 不建立订阅，失效不传导，
//     数据束会缓存住旧记录）；
//  3. 边界（无车空态负控制）：应用车辆为 null 是合法 data 态（空表 +
//     今天），不是 loading/error——新车主不阻塞页面，也不抛错。
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunio/app/providers.dart';
import 'package:lunio/core/date/local_date.dart';
import 'package:lunio/data/database/app_database.dart';
import 'package:lunio/domain/entities/car.dart';

import '../helpers/builders.dart';

/// 带 id 的车辆（Completer 完成与 family 取数都要真实 id；实体构造器
/// 手法同 widget_snapshot_controller_test 的 _car）。
Car _carWithId(int id) => Car(
  id: id,
  brand: '本田',
  model: '22款思域',
  currentMileageKm: 10000,
  roadDate: const LocalDate(2023, 8, 12),
  sync: testSync,
);

void main() {
  late AppDatabase database;
  late ProviderContainer container;

  setUp(() {
    database = AppDatabase.inMemory();
  });

  tearDown(() async {
    container.dispose();
    await database.close();
  });

  /// 在给定容器里播种一辆车（含机油项目）+ 一条记录，返回 (carId,
  /// itemId)。播种只走仓库（不触碰 applied 链），临时容器用后即弃。
  Future<(int, int)> seedCarWithRecord(ProviderContainer seedContainer) async {
    final repository = seedContainer.read(lunioRepositoryProvider);
    final carId = await repository.createCarWithMaintenanceItems(
      defaultCar(),
      [defaultOilItem()],
    );
    final itemId = await repository.saveMaintenanceItem(
      defaultOilItem(carsId: carId, name: '刹车油', sortOrder: 2),
    );
    await repository.saveMaintenanceRecord(
      defaultRecord(
        carId: carId,
        date: const LocalDate(2026, 9, 1),
        itemIds: [itemId],
        costCents: 10000,
        mileageKm: 5000,
      ),
    );
    return (carId, itemId);
  }

  group('应用车辆数据束', () {
    test('任一上游未就绪整体未就绪；就绪后四件套一次拿齐', () async {
      final carHolder = Completer<Car?>();
      container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          // 挂起应用车辆：数据束的第一个上游不就绪。
          appliedCarProvider.overrideWith((ref) => carHolder.future),
        ],
      );
      final (carId, _) = await seedCarWithRecord(container);

      final boardFuture = container.read(appliedCarBoardProvider.future);
      expect(container.read(appliedCarBoardProvider).isLoading, isTrue);

      carHolder.complete(_carWithId(carId));
      final board = await boardFuture;

      expect(board.car?.id, carId);
      // items/records 带库里播种数据：数据束确实经 applied 派生 → 按车
      // family → 库这一条链取数（取数行被删/改空即红）。
      expect(board.items.map((item) => item.name), contains('机油'));
      expect(
        board.records.map((record) => record.date),
        contains(const LocalDate(2026, 9, 1)),
      );
      // 无手动日期时 today = 系统今天（与仓库其他测试同竞态水平）。
      expect(board.today, LocalDate.fromDateTime(DateTime.now()));
    });

    test('上游失效传导：记录派生失效后数据束重算出新值（watch 不许改成 read）',
        () async {
      // 先用临时容器播种拿 id（播种不依赖 applied 链）。
      final seedContainer = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWithValue(database)],
      );
      final (carId, itemId) = await seedCarWithRecord(seedContainer);
      seedContainer.dispose();

      container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          appliedCarProvider.overrideWith((ref) async => _carWithId(carId)),
        ],
      );
      final first = await container.read(appliedCarBoardProvider.future);
      expect(first.records, hasLength(1));

      // 再写一条记录 → 只失效按车 family（不碰数据束本身，与动作层
      // invalidateVehicleProviders 的家族整族逐出同口径）：watch 在位则
      // 失效沿 family → applied 派生 → 数据束传导，重算带出新值。
      await container.read(lunioRepositoryProvider).saveMaintenanceRecord(
        defaultRecord(
          carId: carId,
          date: const LocalDate(2026, 9, 10),
          itemIds: [itemId],
          costCents: 20000,
          mileageKm: 6000,
        ),
      );
      container.invalidate(recordsForCarProvider);
      final second = await container.read(appliedCarBoardProvider.future);
      expect(second.records, hasLength(2));
    });

    test('无车是合法空态：data 态空束，不是 loading/error', () async {
      container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          // 无车（还没建车）：空库 + 应用车辆 null。
          appliedCarProvider.overrideWith((ref) async => null),
        ],
      );
      final board = await container.read(appliedCarBoardProvider.future);

      expect(board.car, isNull);
      expect(board.items, isEmpty);
      expect(board.records, isEmpty);
      expect(board.today, LocalDate.fromDateTime(DateTime.now()));
    });
  });
}
