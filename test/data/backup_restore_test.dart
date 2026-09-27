// 备份导出/恢复/清空数据层测试：全量往返、引用完整性与同车同日预检
// 拒绝（typed backupInvalidData）、carId 重映射、偏好保留口径（R2）、
// 清空名单与事务回滚。2026-09-26 测试夹具收编② 自 database_test.dart
// 按域拆出；仓库装配统一走 widget_app 的 TestRepositories。
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:lunio/core/date/local_date.dart';
import 'package:lunio/data/backup/backup_codec.dart';
import 'package:lunio/data/database/app_database.dart';
import 'package:lunio/data/preferences/app_preferences.dart';
import 'package:lunio/data/repositories/backup_repository.dart';
import 'package:lunio/data/repositories/built_in_catalog_repository.dart';
import 'package:lunio/data/repositories/entity_row_codec.dart'
    show maintenanceRecordCompanion;
import 'package:lunio/data/repositories/fuel_repository.dart';
import 'package:lunio/data/repositories/lunio_repository.dart';
import 'package:lunio/domain/entities/car.dart';
import 'package:lunio/domain/entities/fuel_price.dart';
import 'package:lunio/domain/entities/maintenance_item.dart';
import 'package:lunio/domain/entities/maintenance_record.dart';
import 'package:lunio/domain/entities/parking_countdown.dart';
import 'package:lunio/domain/entities/powertrain_type.dart';
import 'package:lunio/domain/entities/sync_metadata.dart';
import 'package:lunio/domain/entities/vehicle_default_maintenance_item.dart';
import 'package:lunio/domain/errors/lunio_error.dart';
import 'package:lunio/data/bootstrap/built_in_vehicle_catalog.dart';

import '../helpers/builders.dart';
import '../helpers/built_in_catalog_loader.dart'
    show loadBuiltInVehicleCatalogForTest;
import '../helpers/widget_app.dart';

void main() {
  late AppDatabase database;
  late TestRepositories repos;
  late LunioRepository repository;
  late LunioPreferences preferences;
  late BuiltInCatalogRepository catalogRepository;
  late BackupRepository backupRepository;
  late FuelRepository fuelRepository;
  late SyncMetadata sync;
  late BuiltInVehicleCatalog builtInCatalog;

  setUpAll(() {
    builtInCatalog = loadBuiltInVehicleCatalogForTest();
  });

  setUp(() {
    database = AppDatabase.inMemory();
    repos = testRepository(database);
    repository = repos.repository;
    preferences = repos.preferences;
    catalogRepository = repos.catalogRepository;
    backupRepository = repos.backupRepository;
    fuelRepository = repos.fuelRepository;
    sync = repos.sync;
  });

  tearDown(() async {
    await database.close();
  });

  test('backup restore keeps record item costs with remapped item ids',
      () async {
    final (carId, oilId) = await repos.seedCarAndItem();
    final filterId = await repos.saveItem(carId, '机滤', 2);
    await repository.saveMaintenanceRecord(
      defaultRecord(
        carId: carId,
        date: const LocalDate(2026, 5, 19),
        itemIds: [oilId, filterId],
        itemCosts: [
          RecordItemCost(
            itemId: oilId,
            materialCents: 15000,
            laborCents: 8000,
            costCents: 23000,
          ),
          RecordItemCost(itemId: filterId, costCents: 5000),
        ],
        costCents: 28000,
        mileageKm: 12000,
      ),
    );

    final backup = await backupRepository.exportBackupPayload();
    // 换新内存库恢复（车辆/项目 id 全部重映射为新雪花 id）。
    await database.close();
    database = AppDatabase.inMemory();
    preferences = LunioPreferences(database);
    backupRepository = BackupRepository(database, preferences);
    fuelRepository = FuelRepository(database, preferences);
    repository = LunioRepository(
      database,
      preferences: preferences,
      fuel: fuelRepository,
    );
    await backupRepository.restoreBackupPayload(backup);

    final restoredCar = (await database.select(database.cars).get()).single;
    final restoredItems = await repository.listMaintenanceItemsForCar(
      restoredCar.id,
    );
    final restoredRecords = await repository.listMaintenanceRecordsForCar(
      restoredCar.id,
    );
    expect(restoredRecords, hasLength(1));
    // itemId 已重映射、金额原样保留（项目费用为准，不做推导修正）。
    final costs = restoredRecords.single.itemCosts;
    expect(costs, hasLength(2));
    expect(
      costs.map((cost) => cost.itemId).toSet(),
      restoredItems.map((item) => item.id).toSet(),
    );
    expect(
      costs.map((cost) => cost.costCents).toSet(),
      {23000, 5000},
    );
    final oilCost = costs.firstWhere((cost) => cost.costCents == 23000);
    expect(oilCost.materialCents, 15000);
    expect(oilCost.laborCents, 8000);
  });

  test(
      'backup restore normalizes item costs missing cost field (invariant)',
      () async {
    final (carId, oilId) = await repos.seedCarAndItem();
    // 违规形态存量行：材料/工时有值、项目费用为空（不变量落地前写入的
    // 历史数据）。直插播种模拟——写 seam（关联行 companion）2026-09-25
    // 起单点补齐，经仓库保存已造不出违规行；而备份文件可能来自旧版本
    // 导出，修复点在恢复，不把违规数据带进新库。
    const legacyRecordId = 990001;
    await database.into(database.maintenanceRecords).insert(
      maintenanceRecordCompanion(
        defaultRecord(
          carId: carId,
          date: const LocalDate(2026, 5, 19),
          itemIds: [oilId],
          itemCosts: [
            RecordItemCost(
              itemId: oilId,
              materialCents: 15000,
              laborCents: 8000,
            ),
          ],
          costCents: 23000,
          mileageKm: 12000,
        ),
        legacyRecordId,
      ),
    );
    await database.into(database.maintenanceRecordItems).insert(
      // 裸 companion 绕过写 seam：还原"项目费用为空"的违规形态
      // （costCents 留空 = NULL）。
      MaintenanceRecordItemsCompanion.insert(
        id: const Value(990002),
        maintenanceRecordId: legacyRecordId,
        carId: carId,
        itemId: oilId,
        date: const LocalDate(2026, 5, 19).toString(),
        materialCostCents: const Value(15000),
        laborCostCents: const Value(8000),
      ),
    );

    final backup = await backupRepository.exportBackupPayload();
    // 换新内存库恢复（车辆/项目 id 全部重映射为新雪花 id）。
    await database.close();
    database = AppDatabase.inMemory();
    preferences = LunioPreferences(database);
    backupRepository = BackupRepository(database, preferences);
    fuelRepository = FuelRepository(database, preferences);
    repository = LunioRepository(
      database,
      preferences: preferences,
      fuel: fuelRepository,
    );
    await backupRepository.restoreBackupPayload(backup);

    final restoredCar = (await database.select(database.cars).get()).single;
    final restoredRecords = await repository.listMaintenanceRecordsForCar(
      restoredCar.id,
    );
    expect(restoredRecords, hasLength(1));
    final cost = restoredRecords.single.itemCosts.single;
    // 恢复时按"材料+工时"补齐项目费用（2026-09-20 数据不变量）。
    expect(cost.materialCents, 15000);
    expect(cost.laborCents, 8000);
    expect(cost.costCents, 23000);
  });
  test('backup export and restore round-trips database content', () async {
    final (carId, itemId) = await repos.seedCarAndItem();
    await preferences.setAppliedCarId(carId);
    await preferences.writeRaw('manualDateEnabled', 'true');
    await preferences.writeRaw('manualDate', '2026-05-23');
    await catalogRepository.saveVehicleDefaultMaintenanceItem(
      VehicleDefaultMaintenanceItem(
        powertrainType: PowertrainType.fuel,
        itemName: '机油',
        remindByMileage: true,
        remindByTime: true,
        mileageIntervalKm: 5000,
        timeIntervalMonths: 6,
        sortOrder: 1,
        sync: sync,
      ),
    );
    await repository.saveMaintenanceRecord(
      defaultRecord(
        carId: carId,
        date: const LocalDate(2026, 5, 19),
        itemIds: [itemId],
        costCents: 10000,
        mileageKm: 12000,
      ),
    );
    final fuelRecordId = await fuelRepository.saveFuelRecord(
      defaultFuelRecord(
        carId,
        date: const LocalDate(2026, 9, 10),
        unitPriceCents: 750,
        payableCents: 31200,
      ),
    );

    final backup = await backupRepository.exportBackupPayload();
    expect(const BackupCodec().encode(backup), isNot(contains('preferences')));
    expect(
      const BackupCodec().encode(backup),
      isNot(contains('defaultMaintenanceItems')),
    );
    expect(const BackupCodec().encode(backup), isNot(contains('isDefault')));
    expect(
      const BackupCodec().encode(backup),
      contains('"fuelRecords":[{"carId":'),
    );
    await database.close();
    database = AppDatabase.inMemory();
    preferences = LunioPreferences(database);
    catalogRepository = BuiltInCatalogRepository(
      database,
      loadBuiltInVehicleCatalog: () async => builtInCatalog,
    );
    backupRepository = BackupRepository(database, preferences);
    fuelRepository = FuelRepository(database, preferences);
    repository = LunioRepository(
      database,
      preferences: preferences,
      fuel: fuelRepository,
    );
    // 恢复前在本地写入偏好：主题/手动日期/停车倒计时应跨恢复保留（R2 口径），
    // 提醒抑制键（snooze）应被恢复清除。
    await preferences.writeRaw('themeMode', 'dark');
    await preferences.writeRaw('manualDate', '2026-05-23');
    await preferences.saveParkingCountdown(
      ParkingCountdown(
        startedAt: DateTime(2026, 6, 10, 10, 20, 15),
        durationSeconds: 1800,
      ),
    );
    await preferences.writeRaw(
      '${LunioPreferences.maintenanceReminderSnoozedUntilPrefix}42',
      '2026-06-01',
    );
    await preferences.writeRaw(
      '${LunioPreferences.mileageUpdateInAppAcknowledgedOnPrefix}42',
      '2026-05-23',
    );
    // 恢复前目标库已有一条残留加油记录（fuel_records 无外键，指向不
    // 存在的车也插得进）：恢复清表名单含新表后它应被一并清掉，不留
    // 孤儿行（ADR 0014 过渡窗口的回归点）。
    await fuelRepository.saveFuelRecord(
      defaultFuelRecord(
        999,
        date: const LocalDate(2026, 1, 1),
        unitPriceCents: 750,
        payableCents: 1000,
      ),
    );

    await backupRepository.restoreBackupPayload(backup);

    expect(await database.select(database.cars).get(), hasLength(1));
    expect(
      await database.select(database.vehicleDefaultMaintenanceItems).get(),
      isEmpty,
    );
    expect(
      await database.select(database.maintenanceItems).get(),
      hasLength(1),
    );
    expect(
      await database.select(database.maintenanceRecords).get(),
      hasLength(1),
    );
    expect(
      await database.select(database.maintenanceRecordItems).get(),
      hasLength(1),
    );
    final restoredCar = (await database.select(database.cars).get()).single;
    expect(restoredCar.id, isNot(carId));
    expect(await preferences.getAppliedCarId(), restoredCar.id);
    // 公开查询按新车辆 id 验证（此前回归：恢复循环主表插入漏换 carId，
    // 记录挂在备份里的旧 id 下，行数断言拦不住，恢复后历史全部不可见）。
    final restoredItems = await repository.listMaintenanceItemsForCar(
      restoredCar.id,
    );
    expect(restoredItems, hasLength(1));
    final restoredRecords = await repository.listMaintenanceRecordsForCar(
      restoredCar.id,
    );
    expect(restoredRecords, hasLength(1));
    expect(restoredRecords.single.date, const LocalDate(2026, 5, 19));
    expect(restoredRecords.single.costCents, 10000);
    // 关联表 itemIds 同样指向重映射后的新项目 id。
    expect(restoredRecords.single.itemIds, [restoredItems.single.id]);
    // 加油记录随备份恢复：carId 重映射为新车辆 id（漏换会让记录挂在
    // 备份里的旧 id 下，公开查询查不到），业务字段全量往返。
    expect(await database.select(database.fuelRecords).get(), hasLength(1));
    final restoredFuelRecords = await fuelRepository.listFuelRecordsForCar(
      restoredCar.id,
    );
    expect(restoredFuelRecords, hasLength(1));
    expect(restoredFuelRecords.single.id, isNot(fuelRecordId));
    expect(restoredFuelRecords.single.carId, restoredCar.id);
    expect(restoredFuelRecords.single.date, const LocalDate(2026, 9, 10));
    expect(restoredFuelRecords.single.grade, FuelGrade.gasoline92);
    expect(restoredFuelRecords.single.unitPriceCents, 750);
    expect(restoredFuelRecords.single.payableCents, 31200);
    expect(restoredFuelRecords.single.actualCents, isNull);
    // 容积由实体按 应付÷单价 重算：31200 ÷ 750 = 41.6（预留字段）。
    expect(restoredFuelRecords.single.volumeLiters, 41.6);
    // 偏好保留：恢复只替换三类业务数据。
    expect(await preferences.readRaw('themeMode'), 'dark');
    expect(await preferences.readRaw('manualDate'), '2026-05-23');
    expect(
      await preferences.getParkingCountdown(),
      ParkingCountdown(
        startedAt: DateTime(2026, 6, 10, 10, 20, 15),
        durationSeconds: 1800,
      ),
    );
    // 提醒抑制键按前缀清除：恢复出的车/项目是全新 id，旧抑制不再生效。
    expect(
      await preferences.readRaw(
        '${LunioPreferences.maintenanceReminderSnoozedUntilPrefix}42',
      ),
      isNull,
    );
    expect(
      await preferences.readRaw(
        '${LunioPreferences.mileageUpdateInAppAcknowledgedOnPrefix}42',
      ),
      isNull,
    );
  });

  test('backup restore rejects fuel record referencing missing car', () async {
    final (carId, _) = await repos.seedCarAndItem();
    final backup = await backupRepository.exportBackupPayload();
    // 篡改出一条指向不存在车辆的加油记录：引用完整性预校验应拒绝。
    final orphanFuelRecord = BackupPayload(
      schemaVersion: BackupCodec.currentSchemaVersion,
      cars: backup.cars,
      maintenanceItems: backup.maintenanceItems,
      records: backup.records,
      fuelRecords: [
        defaultFuelRecord(
          carId + 424242,
          date: const LocalDate(2026, 9, 10),
          unitPriceCents: 750,
        ),
      ],
    );

    expect(
      () => backupRepository.restoreBackupPayload(orphanFuelRecord),
      throwsArgumentError,
    );
    // 预校验在事务外执行：库未被改动（残留行一个都没有写入）。
    expect(await database.select(database.fuelRecords).get(), isEmpty);
  });

  test('backup restore rejects tampered business data before writing', () async {
    final (carId, itemId) = await repos.seedCarAndItem();
    final backup = await backupRepository.exportBackupPayload();
    expect(backup.cars, hasLength(1));

    MaintenanceRecord tamperedRecord({
      required int costCents,
      required int mileageKm,
      List<int> itemIds = const [],
    }) {
      return MaintenanceRecord(
        id: 1,
        carId: carId,
        date: const LocalDate(2026, 5, 19),
        itemIds: itemIds,
        costCents: costCents,
        mileageKm: mileageKm,
        sync: sync,
      );
    }

    final negativeCost = BackupPayload(
      schemaVersion: 1,
      cars: backup.cars,
      maintenanceItems: backup.maintenanceItems,
      records: [tamperedRecord(costCents: -1, mileageKm: 12000, itemIds: [itemId])],
    );
    final negativeMileage = BackupPayload(
      schemaVersion: 1,
      cars: backup.cars,
      maintenanceItems: backup.maintenanceItems,
      records: [tamperedRecord(costCents: 0, mileageKm: -1, itemIds: [itemId])],
    );
    final emptyItemIds = BackupPayload(
      schemaVersion: 1,
      cars: backup.cars,
      maintenanceItems: backup.maintenanceItems,
      records: [tamperedRecord(costCents: 0, mileageKm: 12000)],
    );
    final invalidItemInterval = BackupPayload(
      schemaVersion: 1,
      cars: backup.cars,
      maintenanceItems: [
        MaintenanceItem(
          id: itemId,
          carsId: carId,
          name: '机油',
          enabled: true,
          remindByMileage: true,
          remindByTime: false,
          mileageIntervalKm: null,
          sortOrder: 1,
          sync: sync,
        ),
      ],
      records: const [],
    );

    // R35 校验失败自 ADR 0009 修订节起 typed 化（backupInvalidData），
    // 不再是裸 ArgumentError。
    final rejectedAsInvalidData = throwsA(
      isA<LunioErrorException>().having(
        (error) => error.kind,
        'kind',
        LunioErrorKind.backupInvalidData,
      ),
    );
    expect(
      () => backupRepository.restoreBackupPayload(negativeCost),
      rejectedAsInvalidData,
    );
    expect(
      () => backupRepository.restoreBackupPayload(negativeMileage),
      rejectedAsInvalidData,
    );
    expect(
      () => backupRepository.restoreBackupPayload(emptyItemIds),
      rejectedAsInvalidData,
    );
    expect(
      () => backupRepository.restoreBackupPayload(invalidItemInterval),
      rejectedAsInvalidData,
    );
    // 预校验在事务外执行：库未被任何一次失败恢复改动。
    expect(await database.select(database.cars).get(), hasLength(1));
    expect(
      await database.select(database.maintenanceItems).get(),
      hasLength(1),
    );
    expect(
      await database.select(database.maintenanceRecords).get(),
      isEmpty,
    );
  });

  test('backup restore rejects same-car same-date duplicate records', () async {
    final (carId, itemId) = await repos.seedCarAndItem();
    final backup = await backupRepository.exportBackupPayload();
    final duplicated = BackupPayload(
      schemaVersion: 1,
      cars: backup.cars,
      maintenanceItems: backup.maintenanceItems,
      records: [
        MaintenanceRecord(
          id: 1,
          carId: carId,
          date: const LocalDate(2026, 5, 19),
          itemIds: [itemId],
          costCents: 10000,
          mileageKm: 12000,
          sync: sync,
        ),
        MaintenanceRecord(
          id: 2,
          carId: carId,
          date: const LocalDate(2026, 5, 19),
          itemIds: [itemId],
          costCents: 20000,
          mileageKm: 13000,
          sync: sync,
        ),
      ],
    );

    // 同车同日查重是表级唯一约束 {carId,date} 的业务前置检查：预校验
    // 拒绝（typed），不靠事务中途炸驱动层异常。注意 restoreBackupPayload
    // 的预校验在返回 Future 前同步抛出，须用闭包交给 throwsA。
    expect(
      () => backupRepository.restoreBackupPayload(duplicated),
      throwsA(
        isA<LunioErrorException>()
            .having(
              (error) => error.kind,
              'kind',
              LunioErrorKind.backupInvalidData,
            )
            .having(
              (error) => error.message,
              'message',
              allOf(contains('2026-05-19'), contains('有 2 条')),
            ),
      ),
    );
    // 预校验在事务外执行：库未被改动（整文件拒绝，零残留）。
    expect(await database.select(database.cars).get(), hasLength(1));
    expect(await database.select(database.maintenanceRecords).get(), isEmpty);
  });

  test('backup restore allows same date across different cars', () async {
    // 唯一约束是 {carId,date} 联合键：不同车同日各一条是合法数据，
    // 查重不得误伤。
    final payload = BackupPayload(
      schemaVersion: 1,
      cars: [
        Car(
          id: 99,
          brand: '本田',
          model: '思域（燃油版）',
          currentMileageKm: 12000,
          roadDate: const LocalDate(2024, 1, 1),
          sync: sync,
        ),
        Car(
          id: 100,
          brand: '东风日产',
          model: '轩逸（燃油版）',
          currentMileageKm: 20000,
          roadDate: const LocalDate(2024, 1, 1),
          sync: sync,
        ),
      ],
      maintenanceItems: [
        MaintenanceItem(
          id: 199,
          carsId: 99,
          name: '机油',
          enabled: true,
          remindByMileage: true,
          remindByTime: false,
          mileageIntervalKm: 5000,
          sortOrder: 1,
          sync: sync,
        ),
        MaintenanceItem(
          id: 198,
          carsId: 100,
          name: '机油',
          enabled: true,
          remindByMileage: true,
          remindByTime: false,
          mileageIntervalKm: 5000,
          sortOrder: 1,
          sync: sync,
        ),
      ],
      records: [
        MaintenanceRecord(
          id: 299,
          carId: 99,
          date: const LocalDate(2026, 5, 20),
          itemIds: const [199],
          costCents: 12000,
          mileageKm: 12000,
          sync: sync,
        ),
        MaintenanceRecord(
          id: 298,
          carId: 100,
          date: const LocalDate(2026, 5, 20),
          itemIds: const [198],
          costCents: 20000,
          mileageKm: 20000,
          sync: sync,
        ),
      ],
    );

    await backupRepository.restoreBackupPayload(payload);

    expect(
      await database.select(database.maintenanceRecords).get(),
      hasLength(2),
    );
  });

  test('backup restore allows same-car same-day duplicate fuel records', () async {
    // fuel_records 故意没有 {carId,date} 唯一约束（ADR 0014，同车同日
    // 多箱合法）：同日查重只属于保养记录，不得波及加油记录。
    final payload = BackupPayload(
      schemaVersion: BackupCodec.currentSchemaVersion,
      cars: [
        Car(
          id: 99,
          brand: '本田',
          model: '思域（燃油版）',
          currentMileageKm: 12000,
          roadDate: const LocalDate(2024, 1, 1),
          sync: sync,
        ),
      ],
      maintenanceItems: [
        MaintenanceItem(
          id: 199,
          carsId: 99,
          name: '机油',
          enabled: true,
          remindByMileage: true,
          remindByTime: false,
          mileageIntervalKm: 5000,
          sortOrder: 1,
          sync: sync,
        ),
      ],
      records: [
        MaintenanceRecord(
          id: 299,
          carId: 99,
          date: const LocalDate(2026, 5, 20),
          itemIds: const [199],
          costCents: 12000,
          mileageKm: 12000,
          sync: sync,
        ),
      ],
      fuelRecords: [
        defaultFuelRecord(
          99,
          date: const LocalDate(2026, 5, 20),
          unitPriceCents: 750,
        ),
        defaultFuelRecord(
          99,
          date: const LocalDate(2026, 5, 20),
          unitPriceCents: 752,
          payableCents: 37600,
        ),
      ],
    );

    await backupRepository.restoreBackupPayload(payload);

    expect(await database.select(database.fuelRecords).get(), hasLength(2));
  });

  test('parking countdown is temporary preference outside backup', () async {
    final countdown = ParkingCountdown(
      startedAt: DateTime(2026, 6, 10, 10, 20, 15),
      durationSeconds: 1800,
    );

    await preferences.saveParkingCountdown(countdown);

    expect(await preferences.getParkingCountdown(), countdown);
    expect(
      await preferences.readRaw('parkingCountdown'),
      contains('"durationSeconds":1800'),
    );
    final backup = await backupRepository.exportBackupPayload();
    expect(const BackupCodec().encode(backup), isNot(contains('parking')));

    await preferences.clearParkingCountdown();

    expect(await preferences.getParkingCountdown(), isNull);
  });

  test(
    'backup restore tolerates bootstrapped default items after clearing data',
    () async {
      final (carId, _) = await repos.seedCarAndItem();
      await preferences.setAppliedCarId(carId);
      await catalogRepository.ensureDefaultMaintenanceItems();
      final backup = await backupRepository.exportBackupPayload();

      await backupRepository.clearAllData();
      await catalogRepository.ensureDefaultMaintenanceItems();

      await backupRepository.restoreBackupPayload(backup);

      expect(await database.select(database.cars).get(), hasLength(1));
      expect(
        await database.select(database.vehicleDefaultMaintenanceItems).get(),
        isNotEmpty,
      );
      expect(
        await database.select(database.maintenanceItems).get(),
        hasLength(1),
      );
    },
  );

  test('backup restore replaces data and applies restored first car', () async {
    final (existingCarId, _) = await repos.seedCarAndItem();
    await preferences.setAppliedCarId(existingCarId);
    final backup = BackupPayload(
      schemaVersion: 1,
      cars: [
        Car(
          id: 99,
          brand: '东风日产',
          model: '轩逸（燃油版）',
          currentMileageKm: 20000,
          roadDate: const LocalDate(2024, 1, 1),
          sync: sync,
        ),
      ],
      maintenanceItems: [
        MaintenanceItem(
          id: 199,
          carsId: 99,
          name: '空调滤芯',
          enabled: true,
          remindByMileage: true,
          remindByTime: true,
          mileageIntervalKm: 20000,
          timeIntervalMonths: 12,
          sortOrder: 1,
          sync: sync,
        ),
      ],
      records: [
        MaintenanceRecord(
          id: 299,
          carId: 99,
          date: const LocalDate(2026, 5, 20),
          itemIds: const [199],
          costCents: 12000,
          mileageKm: 20000,
          sync: sync,
        ),
      ],
    );

    await backupRepository.restoreBackupPayload(backup);

    final cars = await database.select(database.cars).get();
    expect(cars, hasLength(1));
    expect(cars.single.brand, '东风日产');
    expect(cars.single.model, '轩逸（燃油版）');
    expect(
      await database.select(database.maintenanceItems).get(),
      hasLength(1),
    );
    expect(
      await database.select(database.maintenanceRecords).get(),
      hasLength(1),
    );
    expect(
      await database.select(database.maintenanceRecordItems).get(),
      hasLength(1),
    );
    expect(await preferences.getAppliedCarId(), cars.single.id);
  });

  test(
    'backup restore rejects invalid references before replacing data',
    () async {
      await repos.seedCarAndItem();
      final backup = await backupRepository.exportBackupPayload();
      final invalid = BackupPayload(
        schemaVersion: 1,
        cars: backup.cars,
        maintenanceItems: backup.maintenanceItems,
        records: [
          MaintenanceRecord(
            id: 1,
            carId: 999,
            date: const LocalDate(2026, 5, 19),
            itemIds: const [1],
            costCents: 10000,
            mileageKm: 12000,
            sync: sync,
          ),
        ],
      );

      expect(
        () => backupRepository.restoreBackupPayload(invalid),
        throwsArgumentError,
      );
      expect(await database.select(database.cars).get(), hasLength(1));
    },
  );

  test('backup restore rejects record items from another car', () async {
    final (carId, _) = await repos.seedCarAndItem();
    final otherCarId = await repos.insertCarForTest(defaultCar(
        brand: '日产',
        model: '22款轩逸',
        roadDate: const LocalDate(2024, 1, 1),
      ),
    );
    final otherItemId = await repository.saveMaintenanceItem(
      defaultOilItem(
        carsId: otherCarId,
        name: '空调滤芯',
        mileageIntervalKm: 20000,
        timeIntervalMonths: 12,
      ),
    );
    final backup = await backupRepository.exportBackupPayload();
    final invalid = BackupPayload(
      schemaVersion: 1,
      cars: backup.cars,
      maintenanceItems: backup.maintenanceItems,
      records: [
        MaintenanceRecord(
          id: 1,
          carId: carId,
          date: const LocalDate(2026, 5, 19),
          itemIds: [otherItemId],
          costCents: 10000,
          mileageKm: 12000,
          sync: sync,
        ),
      ],
    );

    expect(() => backupRepository.restoreBackupPayload(invalid), throwsArgumentError);
  });

  test('clear all data removes local rows', () async {
    final (carId, itemId) = await repos.seedCarAndItem();
    await preferences.setAppliedCarId(carId);
    await preferences.writeRaw('manualDateEnabled', 'true');
    await catalogRepository.ensureBootstrapData();
    final defaultItemsBeforeClear = await database
        .select(database.vehicleDefaultMaintenanceItems)
        .get();
    final vehicleModelsBeforeClear = await database
        .select(database.vehicleModels)
        .get();
    expect(defaultItemsBeforeClear, isNotEmpty);
    expect(vehicleModelsBeforeClear, isNotEmpty);
    await repository.saveMaintenanceRecord(
      defaultRecord(
        carId: carId,
        date: const LocalDate(2026, 5, 19),
        itemIds: [itemId],
        costCents: 10000,
        mileageKm: 12000,
      ),
    );

    await backupRepository.clearAllData();

    expect(await database.select(database.cars).get(), isEmpty);
    expect(await database.select(database.maintenanceItems).get(), isEmpty);
    expect(await database.select(database.maintenanceRecords).get(), isEmpty);
    expect(
      await database.select(database.maintenanceRecordItems).get(),
      isEmpty,
    );
    expect(await database.select(database.appPreferences).get(), isEmpty);
    expect(
      await database.select(database.vehicleDefaultMaintenanceItems).get(),
      hasLength(defaultItemsBeforeClear.length),
    );
    expect(
      await database.select(database.vehicleModels).get(),
      hasLength(vehicleModelsBeforeClear.length),
    );
  });

  test('backup restore rolls back when unique constraints fail', () async {
    final (carId, _) = await repos.seedCarAndItem();
    await preferences.setAppliedCarId(carId);
    final invalid = BackupPayload(
      schemaVersion: 1,
      cars: [
        Car(
          id: 99,
          brand: '本田',
          model: '22款思域',
          currentMileageKm: 12000,
          roadDate: const LocalDate(2023, 8, 12),
          sync: sync,
        ),
        Car(
          id: 100,
          brand: '本田',
          model: '22款思域',
          currentMileageKm: 13000,
          roadDate: const LocalDate(2023, 8, 12),
          sync: sync,
        ),
      ],
    );

    expect(() => backupRepository.restoreBackupPayload(invalid), throwsA(anything));
    expect(await database.select(database.cars).get(), hasLength(1));
    expect(await preferences.getAppliedCarId(), carId);
  });
}
