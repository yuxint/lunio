// 车辆数据纪元机制测试（.scratch/arch-0928 票据 01，ADR 0017 修订节）：
// 车辆/项目/记录/加油记录四张业务表的派生 provider watch 车辆数据纪元、
// 写点 bump 后自动重查库——2026-10-06 取代手工失效名单
// （providers.dart 的 invalidateVehicleProviders）后，这是新机制的测试面。
//
// 与偏好纪元（preferences_epoch_test）同构的 Notifier 模式，这里锁三件事：
//  1. bump 一次，列表域抽样 provider（carsProvider）重查库；
//  2. bump 一次，family 域抽样 provider（recordsForCarProvider(carId)）
//     重查库并读到写库后的新值——锁住 family build 首行的 watch 行不许删
//     （删了则写库后统计页等按车消费者缓存住旧记录，本用例即红）；
//  3. 边界保持（grilling Q6 拍板）：parkingCountdownProvider 不随车辆
//     数据纪元重算——它是"写点直失效自己"模型（动作层 saveParkingCountdown
//     / clearParkingCountdown 各自逐出），车辆写库不该牵动停车卡。
//
// 依赖可替换：内存数据库 + 计数主仓库子类（spy）+ ProviderContainer 驱动
// 真实装配（与 preferences_epoch_test / applied_car_board_test 同手法）。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunio/app/providers.dart';
import 'package:lunio/core/date/local_date.dart';
import 'package:lunio/data/database/app_database.dart';
import 'package:lunio/data/repositories/built_in_catalog_repository.dart';
import 'package:lunio/data/repositories/lunio_repository.dart';
import 'package:lunio/domain/entities/car.dart';
import 'package:lunio/domain/entities/maintenance_record.dart';
import 'package:lunio/domain/entities/parking_countdown.dart';

import '../helpers/builders.dart';
import '../helpers/built_in_catalog_loader.dart';

/// 计数主仓库：只统计两个抽样方法的读次数，读写都透传真实现
/// （与 preferences_epoch_test 的 _CountingPreferences 同款 spy 手法）。
class _CountingRepository extends LunioRepository {
  _CountingRepository(super.database);

  int carsReads = 0;
  int recordsReads = 0;

  @override
  Future<List<Car>> listCars() async {
    carsReads++;
    return super.listCars();
  }

  @override
  Future<List<MaintenanceRecord>> listMaintenanceRecordsForCar(
    int carId,
  ) async {
    recordsReads++;
    return super.listMaintenanceRecordsForCar(carId);
  }
}

void main() {
  late AppDatabase database;
  late _CountingRepository repository;
  late ProviderContainer container;

  setUp(() {
    database = AppDatabase.inMemory();
    repository = _CountingRepository(database);
    container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(database),
      // 目录仓库注入测试加载器（微任务即完成）：默认加载器走 rootBundle
      // 资产通道，纯 Dart 测试里等不到通道回包，bootstrap→cars 链会挂死
      // （与 widget_app.dart 的 pumpApp 同一手法，教训见其注释）。
      builtInCatalogRepositoryProvider.overrideWithValue(
        BuiltInCatalogRepository(
          database,
          loadBuiltInVehicleCatalog: () async =>
              loadBuiltInVehicleCatalogForTest(),
        ),
      ),
      lunioRepositoryProvider.overrideWithValue(repository),
    ]);
  });

  tearDown(() async {
    container.dispose();
    await database.close();
  });

  /// 在临时容器里播种一辆车（含机油项目）+ 一条记录，返回 (carId,
  /// itemId)。播种只走写方法（不触碰被计数的读方法），临时容器用后即弃
  /// （手法同 applied_car_board_test 的 seedCarWithRecord）。
  Future<(int, int)> seedCarWithRecord() async {
    final seedContainer = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(database)],
    );
    final seedRepository = seedContainer.read(lunioRepositoryProvider);
    final carId = await seedRepository.createCarWithMaintenanceItems(
      defaultCar(),
      [defaultOilItem()],
    );
    final itemId = await seedRepository.saveMaintenanceItem(
      defaultOilItem(carsId: carId, name: '刹车油', sortOrder: 2),
    );
    await seedRepository.saveMaintenanceRecord(
      defaultRecord(
        carId: carId,
        date: const LocalDate(2026, 9, 1),
        itemIds: [itemId],
        costCents: 10000,
        mileageKm: 5000,
      ),
    );
    seedContainer.dispose();
    return (carId, itemId);
  }

  group('车辆数据纪元', () {
    test('bump 后列表域抽样 provider（carsProvider）重查库', () async {
      await container.read(carsProvider.future);
      expect(repository.carsReads, 1);

      container.read(vehicleDataEpochProvider.notifier).bump();
      await container.read(carsProvider.future);

      expect(repository.carsReads, 2);
    });

    test('bump 后 family 域抽样 provider（recordsForCarProvider）重查库，'
        '锁 family 的 watch 行不许删', () async {
      final (carId, itemId) = await seedCarWithRecord();
      await container.read(recordsForCarProvider(carId).future);
      expect(repository.recordsReads, 1);

      // 再写一条记录（绕过动作层直写仓库，模拟写点写完库）→ bump 纪元：
      // watch 行在位则 family 重查并读到两条记录；watch 行被删则 family
      // 缓存住旧值（读次停在 1、列表停在 1 条），两条断言即红。
      await repository.saveMaintenanceRecord(
        defaultRecord(
          carId: carId,
          date: const LocalDate(2026, 9, 10),
          itemIds: [itemId],
          costCents: 20000,
          mileageKm: 6000,
        ),
      );
      container.read(vehicleDataEpochProvider.notifier).bump();
      final records = await container.read(recordsForCarProvider(carId).future);

      expect(repository.recordsReads, 2);
      expect(records, hasLength(2));
    });

    test('parkingCountdownProvider 不随车辆数据纪元重算（写点直失效模型，'
        '边界保持）', () async {
      final countdown = ParkingCountdown(
        startedAt: DateTime(2026, 10, 6, 10),
        durationSeconds: 3600,
      );
      await container
          .read(lunioPreferencesProvider)
          .saveParkingCountdown(countdown);
      final first = await container.read(parkingCountdownProvider.future);

      // 绕过动作层直接改库再 bump 车辆数据纪元：停车卡片不该被车辆写库
      // 牵动，它的刷新只属于自己的写点（动作层显式 invalidate）。
      await container
          .read(lunioPreferencesProvider)
          .saveParkingCountdown(
            ParkingCountdown(
              startedAt: DateTime(2026, 10, 6, 11),
              durationSeconds: 7200,
            ),
          );
      container.read(vehicleDataEpochProvider.notifier).bump();
      final second = await container.read(parkingCountdownProvider.future);

      expect(second, same(first));
    });
  });
}
