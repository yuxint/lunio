// 加油记录数据层测试（ADR 0015 重定义模型）：CRUD 往返、同车同日两条
// 合法（无 {carId, date} 唯一约束）、排序口径（日期/id 升序）、校验拒绝、
// 容积派生落库（预留）、删车级联、清空数据清新表、不联动车辆当前里程。
import 'package:flutter_test/flutter_test.dart';
import 'package:lunio/core/date/local_date.dart';
import 'package:lunio/data/database/app_database.dart';
import 'package:lunio/data/preferences/app_preferences.dart';
import 'package:lunio/data/repositories/backup_repository.dart';
import 'package:lunio/data/repositories/fuel_repository.dart';
import 'package:lunio/data/repositories/lunio_repository.dart';
import 'package:lunio/domain/entities/car.dart';
import 'package:lunio/domain/entities/fuel_prediction.dart';
import 'package:lunio/domain/entities/fuel_price.dart';
import 'package:lunio/domain/entities/fuel_record.dart';
import 'package:lunio/domain/entities/maintenance_item.dart';
import 'package:lunio/domain/entities/sync_metadata.dart';

void main() {
  late AppDatabase database;
  late LunioRepository repository;
  late LunioPreferences preferences;
  late BackupRepository backupRepository;
  late FuelRepository fuelRepository;
  late SyncMetadata sync;

  setUp(() {
    database = AppDatabase.inMemory();
    preferences = LunioPreferences(database);
    backupRepository = BackupRepository(database, preferences);
    fuelRepository = FuelRepository(database, preferences);
    repository = LunioRepository(
      database,
      preferences: preferences,
      fuel: fuelRepository,
    );
    sync = SyncMetadata(status: SyncStatus.synced, updatedAt: DateTime(2026));
  });

  tearDown(() async {
    await database.close();
  });

  Future<int> seedCar({
    int currentMileageKm = 10000,
    // cars 表有 {brand, model, roadDate} 唯一约束：一个用例建多辆车时
    // 靠 model 区分。
    String model = '22款思域',
  }) async {
    // 建车规则要求至少一个启用项目（R26 口径），这里带一个最小项目。
    return repository.createCarWithMaintenanceItems(
      Car(
        brand: '本田',
        model: model,
        currentMileageKm: currentMileageKm,
        roadDate: const LocalDate(2023, 8, 12),
        sync: sync,
      ),
      [
        MaintenanceItem(
          carsId: 0,
          name: '机油',
          enabled: true,
          remindByMileage: true,
          remindByTime: false,
          mileageIntervalKm: 5000,
          timeIntervalMonths: null,
          notOverdueUpperLimit: 100,
          overdueUpperLimit: 125,
          sortOrder: 0,
          sync: sync,
        ),
      ],
    );
  }

  FuelRecord buildRecord(
    int carId, {
    required LocalDate date,
    FuelGrade grade = FuelGrade.gasoline92,
    required int unitPriceCents,
    required int payableCents,
    int? actualCents,
  }) {
    return FuelRecord(
      carId: carId,
      date: date,
      grade: grade,
      unitPriceCents: unitPriceCents,
      payableCents: payableCents,
      actualCents: actualCents,
      sync: sync,
    );
  }

  group('加油记录 CRUD', () {
    test('新增后读回：字段全量往返，返回雪花 id，容积按应付÷单价落库', () async {
      final carId = await seedCar();
      final recordId = await fuelRepository.saveFuelRecord(
        buildRecord(
          carId,
          date: const LocalDate(2026, 9, 10),
          unitPriceCents: 815,
          payableCents: 33415,
          actualCents: 30000,
        ),
      );

      final records = await fuelRepository.listFuelRecordsForCar(carId);
      expect(records, hasLength(1));
      final saved = records.single;
      expect(saved.id, recordId);
      expect(saved.carId, carId);
      expect(saved.date, const LocalDate(2026, 9, 10));
      expect(saved.grade, FuelGrade.gasoline92);
      expect(saved.unitPriceCents, 815);
      expect(saved.payableCents, 33415);
      expect(saved.actualCents, 30000);
      // 容积 = 33415 ÷ 815 = 41.0 升（实体派生、两位小数，预留字段）。
      expect(saved.volumeLiters, 41.0);
    });

    test('编辑按 id 整行更新，行数不变；carId 不随编辑挪车', () async {
      final carId = await seedCar();
      final otherCarId = await seedCar(model: '21款雅阁');
      final recordId = await fuelRepository.saveFuelRecord(
        buildRecord(
          carId,
          date: const LocalDate(2026, 9, 10),
          unitPriceCents: 815,
          payableCents: 30000,
        ),
      );

      // 草稿误带了别的车 id：编辑只更新业务字段，不把记录挪到别的车。
      await fuelRepository.updateFuelRecord(
        buildRecord(
          otherCarId,
          date: const LocalDate(2026, 9, 11),
          grade: FuelGrade.gasoline95,
          unitPriceCents: 855,
          payableCents: 26000,
          actualCents: 25000,
        ).copyWith(id: recordId),
      );

      final updated = await fuelRepository.listFuelRecordsForCar(carId);
      expect(updated, hasLength(1));
      expect(updated.single.carId, carId);
      expect(updated.single.date, const LocalDate(2026, 9, 11));
      expect(updated.single.grade, FuelGrade.gasoline95);
      expect(updated.single.unitPriceCents, 855);
      expect(updated.single.payableCents, 26000);
      expect(updated.single.actualCents, 25000);
    });

    test('编辑未入库记录（id 为 null）被拒绝', () async {
      final carId = await seedCar();
      expect(
        () => fuelRepository.updateFuelRecord(
          buildRecord(
            carId,
            date: const LocalDate(2026, 9, 10),
            unitPriceCents: 815,
            payableCents: 30000,
          ),
        ),
        throwsArgumentError,
      );
    });

    test('删除单条：目标行消失，其余不动', () async {
      final carId = await seedCar();
      final keepId = await fuelRepository.saveFuelRecord(
        buildRecord(
          carId,
          date: const LocalDate(2026, 9, 9),
          unitPriceCents: 815,
          payableCents: 30000,
        ),
      );
      final dropId = await fuelRepository.saveFuelRecord(
        buildRecord(
          carId,
          date: const LocalDate(2026, 9, 10),
          unitPriceCents: 815,
          payableCents: 30000,
        ),
      );

      await fuelRepository.deleteFuelRecord(dropId);

      final records = await fuelRepository.listFuelRecordsForCar(carId);
      expect(records, hasLength(1));
      expect(records.single.id, keepId);
    });

    test('没有记录的车返回空列表', () async {
      final carId = await seedCar();
      expect(await fuelRepository.listFuelRecordsForCar(carId), isEmpty);
    });
  });

  group('同日多条与排序口径', () {
    test('同车同日两条合法（无 {carId, date} 唯一约束，同日两箱）', () async {
      final carId = await seedCar();
      await fuelRepository.saveFuelRecord(
        buildRecord(
          carId,
          date: const LocalDate(2026, 9, 10),
          unitPriceCents: 815,
          payableCents: 20000,
        ),
      );
      await fuelRepository.saveFuelRecord(
        buildRecord(
          carId,
          date: const LocalDate(2026, 9, 10),
          unitPriceCents: 815,
          payableCents: 20000,
        ),
      );

      final records = await fuelRepository.listFuelRecordsForCar(carId);
      expect(records, hasLength(2));
    });

    test('列表按（日期、id）升序——同日两条按写入顺序排', () async {
      final carId = await seedCar();
      await fuelRepository.saveFuelRecord(
        buildRecord(
          carId,
          date: const LocalDate(2026, 9, 10),
          unitPriceCents: 815,
          payableCents: 30000,
        ),
      );
      await fuelRepository.saveFuelRecord(
        buildRecord(
          carId,
          date: const LocalDate(2026, 9, 9),
          unitPriceCents: 815,
          payableCents: 20000,
        ),
      );
      await fuelRepository.saveFuelRecord(
        buildRecord(
          carId,
          date: const LocalDate(2026, 9, 10),
          unitPriceCents: 815,
          payableCents: 10000,
        ),
      );

      final records = await fuelRepository.listFuelRecordsForCar(carId);
      expect(records.map((r) => r.date).toList(), [
        const LocalDate(2026, 9, 9),
        const LocalDate(2026, 9, 10),
        const LocalDate(2026, 9, 10),
      ]);
      // 同日 tie-break 走 id 升序（雪花 id 单调，保存顺序即 id 序）。
      expect(records[1].id! < records[2].id!, isTrue);
    });
  });

  group('校验与容积派生', () {
    test('0 单价与负单价被拒绝（单价必须 > 0）', () async {
      expect(
        () => buildRecord(
          0,
          date: const LocalDate(2026, 9, 10),
          unitPriceCents: 0,
          payableCents: 30000,
        ),
        throwsArgumentError,
      );
      expect(
        () => buildRecord(
          0,
          date: const LocalDate(2026, 9, 10),
          unitPriceCents: -815,
          payableCents: 30000,
        ),
        throwsArgumentError,
      );
    });

    test('0 应付与负应付被拒绝（应付必须 > 0）', () async {
      expect(
        () => buildRecord(
          0,
          date: const LocalDate(2026, 9, 10),
          unitPriceCents: 815,
          payableCents: 0,
        ),
        throwsArgumentError,
      );
      expect(
        () => buildRecord(
          0,
          date: const LocalDate(2026, 9, 10),
          unitPriceCents: 815,
          payableCents: -1,
        ),
        throwsArgumentError,
      );
    });

    test('负实付被拒绝；实付为 0（全额券）与大于应付合法', () async {
      expect(
        () => buildRecord(
          0,
          date: const LocalDate(2026, 9, 10),
          unitPriceCents: 815,
          payableCents: 30000,
          actualCents: -1,
        ),
        throwsArgumentError,
      );
      expect(
        buildRecord(
          0,
          date: const LocalDate(2026, 9, 10),
          unitPriceCents: 815,
          payableCents: 30000,
          actualCents: 0,
        ),
        isA<FuelRecord>(),
      );
      expect(
        buildRecord(
          0,
          date: const LocalDate(2026, 9, 10),
          unitPriceCents: 815,
          payableCents: 30000,
          actualCents: 31000,
        ),
        isA<FuelRecord>(),
      );
    });

    test('容积 = 应付÷单价 四舍五入两位小数；effectiveCost 实付优先', () async {
      // 30000 ÷ 815 = 36.8098… → 36.81。
      final withActual = buildRecord(
        0,
        date: const LocalDate(2026, 9, 10),
        unitPriceCents: 815,
        payableCents: 30000,
        actualCents: 27000,
      );
      expect(withActual.volumeLiters, 36.81);
      expect(withActual.effectiveCostCents, 27000);
      // 实付没填：统计口径取应付。
      final withoutActual = buildRecord(
        0,
        date: const LocalDate(2026, 9, 10),
        unitPriceCents: 815,
        payableCents: 30000,
      );
      expect(withoutActual.effectiveCostCents, 30000);
    });
  });

  group('级联与清空', () {
    test('删除车辆级联删除加油记录（与预测行走同一接缝）', () async {
      final carId = await seedCar();
      await fuelRepository.saveFuelPrediction(
        FuelPrediction(carId: carId, fuelPercent: 50),
      );
      await fuelRepository.saveFuelRecord(
        buildRecord(
          carId,
          date: const LocalDate(2026, 9, 10),
          unitPriceCents: 815,
          payableCents: 30000,
        ),
      );

      await repository.deleteCar(carId);

      expect(await database.select(database.fuelRecords).get(), isEmpty);
      expect(await database.select(database.fuelPredictions).get(), isEmpty);
    });

    test('删车只删本车的加油记录，他车不受影响', () async {
      final carId = await seedCar();
      final otherCarId = await seedCar(model: '21款雅阁');
      await fuelRepository.saveFuelRecord(
        buildRecord(
          carId,
          date: const LocalDate(2026, 9, 10),
          unitPriceCents: 815,
          payableCents: 30000,
        ),
      );
      await fuelRepository.saveFuelRecord(
        buildRecord(
          otherCarId,
          date: const LocalDate(2026, 9, 11),
          unitPriceCents: 815,
          payableCents: 20000,
        ),
      );

      await repository.deleteCar(carId);

      final remaining = await fuelRepository.listFuelRecordsForCar(otherCarId);
      expect(remaining, hasLength(1));
    });

    test('清空数据同时清掉加油记录表', () async {
      final carId = await seedCar();
      await fuelRepository.saveFuelRecord(
        buildRecord(
          carId,
          date: const LocalDate(2026, 9, 10),
          unitPriceCents: 815,
          payableCents: 30000,
        ),
      );

      await backupRepository.clearAllData();

      expect(await database.select(database.fuelRecords).get(), isEmpty);
    });
  });

  group('里程不联动', () {
    test('加油记录不回写车辆当前里程（保养记录是唯一写源）', () async {
      final carId = await seedCar(currentMileageKm: 10000);
      // 新增路径。
      final recordId = await fuelRepository.saveFuelRecord(
        buildRecord(
          carId,
          date: const LocalDate(2026, 9, 10),
          unitPriceCents: 815,
          payableCents: 30000,
        ),
      );
      // 编辑路径。
      await fuelRepository.updateFuelRecord(
        buildRecord(
          carId,
          date: const LocalDate(2026, 9, 11),
          unitPriceCents: 855,
          payableCents: 31000,
        ).copyWith(id: recordId),
      );

      final car = (await repository.listCars()).single;
      expect(car.currentMileageKm, 10000);
    });
  });
}
