// 费用统计页数据接缝机制测试（.scratch/arch-1001 票据 11）：锁
// costStatsDataProvider 的装载链——2026-10-01 并轨后，加油记录改经
// appliedCarFuelRecordsProvider 派生（与记录页头部汇总行、加油记录卡
// 同一条链，"当前应用车辆解析 + 无车空表"语义只有那一份），页面 watch
// 它一处单门卫收口。这是新接缝的测试面（仿 applied_car_board_test
// 形态：内存库 + ProviderContainer 驱动真实装配，provider 迁入
// providers.dart 后行为不变）。
//
// 锁四件事：
//  1. 五件套一次拿齐：车名/保养记录/加油记录/项目清单/生效今天都带
//     库里播种数据——加油取数行被删或改回直连页面内 family 即红；
//  2. 失效传导：加油按车 family 失效后 provider 自动重算出新值——
//     锁"watch 上游"不许改成 read（read 不建立订阅，失效不传导，
//     统计页会缓存住旧加油记录）；
//  3. 无车空态：应用车辆为 null 是合法 data 态（车名 null + 三份空表），
//     不是 loading/error——新车主不阻塞页面；
//  4. 上游 error 传导：数据束上游（应用车辆）失败传导为 provider 的
//     error 态——页面单门卫收口的机制保障（没有第二层门卫兜底）。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunio/app/providers.dart';
import 'package:lunio/core/date/local_date.dart';
import 'package:lunio/data/database/app_database.dart';
import 'package:lunio/domain/entities/car.dart';

import '../helpers/builders.dart';

/// 带 id 的车辆（family 取数要真实 id；defaultCar 不开放 id 直参——
/// 身份字段走 builder 直参的纪律，带 id 的构造用本地扩展，手法同
/// applied_car_board_test 的 _carWithId）。
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

  /// 在给定容器里播种一辆车（含机油项目）+ 一条保养记录 + 一条加油
  /// 记录，返回 (carId, itemId)。播种只走仓库（不触碰 applied 链），
  /// 临时容器用后即弃。
  Future<(int, int)> seedCarWithRecords(ProviderContainer seedContainer) async {
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
    await seedContainer.read(fuelRepositoryProvider).saveFuelRecord(
      defaultFuelRecord(carId, date: const LocalDate(2026, 9, 5)),
    );
    return (carId, itemId);
  }

  /// 固定应用车辆解析的容器（同 applied_car_board_test 手法：只替换
  /// appliedCarProvider，取数链保持真实装配）。
  ///
  /// [disableRetry] 供 error 传导用例关闭 Riverpod 3 的默认重试：生产
  /// 容器对 Exception 类错误做最多 10 次指数退避重试（provider 在重试
  /// 期间停在 retrying 的 loading 态、`.future` 不完成——widget 测试的
  /// fake async 能快进等完约 37s 退避链，真实时钟的单测等不完）；禁掉
  /// 才能锁"error 传导为 provider error 态"这一机制本身。页面行为与
  /// 重试策略正交：重试期间 loading、耗尽后错误页。
  ProviderContainer containerWithCar(
    Future<Car?> Function() car, {
    bool disableRetry = false,
  }) => ProviderContainer(
    overrides: [
      appDatabaseProvider.overrideWithValue(database),
      appliedCarProvider.overrideWith((ref) => car()),
    ],
    retry: disableRetry ? (_, _) => null : null,
  );

  group('费用统计页数据接缝', () {
    test('五件套一次拿齐：加油记录经 applied 派生链带出播种数据', () async {
      final seedContainer = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWithValue(database)],
      );
      final (carId, _) = await seedCarWithRecords(seedContainer);
      seedContainer.dispose();
      container = containerWithCar(() async => _carWithId(carId));

      final data = await container.read(costStatsDataProvider.future);

      expect(data.carName, '本田 22款思域');
      expect(
        data.records.map((record) => record.date),
        contains(const LocalDate(2026, 9, 1)),
      );
      // 加油记录确实经 appliedCarFuelRecordsProvider → 按车 family → 库
      // 这条链取数（装载行被删/改空即红；无手动日期时 today = 系统今天）。
      expect(
        data.fuelRecords.map((record) => record.date),
        contains(const LocalDate(2026, 9, 5)),
      );
      expect(data.items.map((item) => item.name), contains('机油'));
      expect(data.today, LocalDate.fromDateTime(DateTime.now()));
    });

    test('加油 family 失效传导：写记录后 provider 重算出新值（watch 不许改成 read）',
        () async {
      final seedContainer = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWithValue(database)],
      );
      final (carId, _) = await seedCarWithRecords(seedContainer);
      seedContainer.dispose();
      container = containerWithCar(() async => _carWithId(carId));
      final first = await container.read(costStatsDataProvider.future);
      expect(first.fuelRecords, hasLength(1));

      // 再写一条加油记录 → 只失效按车 family（与动作层
      // invalidateVehicleProviders 的家族整族逐出同口径）：watch 在位则
      // 失效沿 family → applied 派生 → 本 provider 传导，重算带出新值。
      await container.read(fuelRepositoryProvider).saveFuelRecord(
        defaultFuelRecord(carId, date: const LocalDate(2026, 9, 10)),
      );
      container.invalidate(fuelRecordsForCarProvider);
      final second = await container.read(costStatsDataProvider.future);
      expect(second.fuelRecords, hasLength(2));
    });

    test('无车是合法空态：data 态车名 null + 空表，不是 loading/error',
        () async {
      container = containerWithCar(() async => null);

      final data = await container.read(costStatsDataProvider.future);

      expect(data.carName, isNull);
      expect(data.records, isEmpty);
      expect(data.fuelRecords, isEmpty);
      expect(data.items, isEmpty);
    });

    test('上游 error 传导：应用车辆失败 → provider error 态（单门卫保障）',
        () async {
      // async 抛（rejected future）：真实链路的仓库查询失败都是异步异常
      //（widget 测试"车辆清单加载失败"同形态）。禁默认重试（见
      // containerWithCar 的 disableRetry 注释），锁传导机制本身。
      container = containerWithCar(
        () async => throw Exception('db down'),
        disableRetry: true,
      );

      // await future 会 rethrow 上游异常；再看 AsyncValue 斤两：error 态
      // 而不是停在 loading——页面唯一的门卫就是本 provider，error 传导
      // 断了页面会永久加载（widget 测试"车辆清单加载失败"锁页面行为，
      // 这里锁 provider 态本身）。
      try {
        await container.read(costStatsDataProvider.future);
        fail('上游失败必须传导为 error');
      } on Exception {
        // 预期路径：与页面 when 的 error 分支同源。
      }
      expect(container.read(costStatsDataProvider).hasError, isTrue);
    });
  });
}
