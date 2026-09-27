// 数据库与核心 CRUD 数据层测试：schema/索引/雪花 id、车辆/保养项目/
// 保养记录 CRUD 与业务校验（唯一约束、里程只增、至少一启用项）、
// 记录-项目费用不变量（写 seam 单点补齐）。目录/模板域见
// catalog_bootstrap_test.dart，备份域见 backup_restore_test.dart；
// 仓库装配统一走 widget_app 的 TestRepositories（2026-09-26 拆分）。
import 'package:flutter_test/flutter_test.dart';
import 'package:lunio/core/date/local_date.dart';
import 'package:lunio/data/database/app_database.dart';
import 'package:lunio/data/preferences/app_preferences.dart';
import 'package:lunio/data/repositories/built_in_catalog_repository.dart';
import 'package:lunio/data/repositories/lunio_repository.dart';
import 'package:lunio/domain/entities/car.dart';
import 'package:lunio/domain/entities/maintenance_item.dart';
import 'package:lunio/domain/entities/maintenance_record.dart';
import 'package:lunio/domain/entities/sync_metadata.dart';
import 'package:lunio/domain/errors/lunio_error.dart';

import '../helpers/builders.dart';
import '../helpers/widget_app.dart';

void main() {
  late AppDatabase database;
  late TestRepositories repos;
  late LunioRepository repository;
  late LunioPreferences preferences;
  late BuiltInCatalogRepository catalogRepository;
  late SyncMetadata sync;

  setUp(() {
    database = AppDatabase.inMemory();
    repos = testRepository(database);
    repository = repos.repository;
    preferences = repos.preferences;
    catalogRepository = repos.catalogRepository;
    sync = repos.sync;
  });

  tearDown(() async {
    await database.close();
  });

  test('creates schema and persists car data', () async {
    await repos.seedCarAndItem();

    final cars = await repository.listCars();

    expect(cars, hasLength(1));
    expect(cars.single.id, isNotNull);
    expect(cars.single.brand, '本田');
    expect(cars.single.model, '22款思域');
  });

  test('v6 schema creates business table indexes', () async {
    // 全新安装路径：建表时随 @TableIndex 创建三个普通索引（R16）。
    final indexRows = await database.customSelect(
      "SELECT name FROM sqlite_master WHERE type = 'index' "
      "AND name IN ('idx_maintenance_items_cars_id', "
      "'idx_maintenance_records_car_id', "
      "'idx_maintenance_record_items_record_id')",
    ).get();
    expect(indexRows.map((row) => row.read<String>('name')), {
      'idx_maintenance_items_cars_id',
      'idx_maintenance_records_car_id',
      'idx_maintenance_record_items_record_id',
    });
  });

  test('allows same brand and model with different road dates', () async {
    await repos.insertCarForTest(
      defaultCar(
        model: '思域（燃油版）',
        roadDate: const LocalDate(2021, 10, 31),
      ),
    );
    await repos.insertCarForTest(
      defaultCar(
        model: '思域（燃油版）',
        currentMileageKm: 0,
        roadDate: const LocalDate(2026, 6, 2),
      ),
    );

    final cars = await repository.listCars();

    expect(cars, hasLength(2));
    expect(
      cars.map((car) => car.roadDate),
      containsAll([const LocalDate(2021, 10, 31), const LocalDate(2026, 6, 2)]),
    );
  });

  test('rejects same brand model and road date', () async {
    final car = defaultCar(
      model: '思域（燃油版）',
      roadDate: const LocalDate(2021, 10, 31),
    );

    await repos.insertCarForTest(car);

    expect(repos.insertCarForTest(car), throwsA(isA<Object>()));
  });

  test('writes snowflake ids for all local tables', () async {
    await catalogRepository.ensureBootstrapData();
    final carId = await createCarWithDefaultItems(
      database,
      defaultCar(model: '思域（燃油版）'),
    );
    final item = (await repository.listMaintenanceItemsForCar(carId)).first;
    await repository.saveMaintenanceRecord(
      defaultRecord(
        carId: carId,
        date: const LocalDate(2026, 5, 19),
        itemIds: [item.id!],
        costCents: 10000,
        mileageKm: 12000,
      ),
    );
    await preferences.writeRaw('manualDate', '2026-05-19');

    final ids = <int>[
      ...(await database.select(database.cars).get()).map((row) => row.id),
      ...(await database.select(database.vehicleDefaultMaintenanceItems).get())
          .map((row) => row.id),
      ...(await database.select(database.vehicleModels).get()).map(
        (row) => row.id,
      ),
      ...(await database.select(database.maintenanceItems).get()).map(
        (row) => row.id,
      ),
      ...(await database.select(database.maintenanceRecords).get()).map(
        (row) => row.id,
      ),
      ...(await database.select(database.maintenanceRecordItems).get()).map(
        (row) => row.id,
      ),
      ...(await database.select(database.appPreferences).get()).map(
        (row) => row.id,
      ),
    ];

    expect(ids, everyElement(greaterThan(0)));
  });
  test('applied car falls back to first available car', () async {
    final firstCarId = await repos.insertCarForTest(defaultCar());
    await repos.insertCarForTest(
      defaultCar(
        brand: '日产',
        model: '22款轩逸',
        currentMileageKm: 8000,
        roadDate: const LocalDate(2024, 1, 1),
      ),
    );
    await preferences.setAppliedCarId(999);

    final appliedCar = await repository.getAppliedCar();

    expect(appliedCar?.id, firstCarId);
    expect(await preferences.getAppliedCarId(), firstCarId);
  });

  test(
    'creates car with configured maintenance items in one transaction',
    () async {
      final carId = await repository.createCarWithMaintenanceItems(
        defaultCar(
          model: '思域（燃油版）',
          currentMileageKm: 0,
          roadDate: const LocalDate(2026, 5, 19),
        ),
        [
          defaultOilItem(),
          defaultOilItem(
            name: '玻璃水',
            enabled: false,
            remindByTime: false,
            timeIntervalMonths: null,
            mileageIntervalKm: 3000,
            sortOrder: 2,
          ),
        ],
      );

      final cars = await repository.listCars();
      final items = await repository.listMaintenanceItemsForCar(carId);

      expect(cars.single.currentMileageKm, 0);
      expect(
        items.map((item) => '${item.name}:${item.carsId}:${item.enabled}'),
        ['机油:$carId:true', '玻璃水:$carId:false'],
      );
      expect(await preferences.getAppliedCarId(), carId);

      final secondCarId = await repository.createCarWithMaintenanceItems(
        defaultCar(
          brand: '日产',
          model: '22款轩逸',
          currentMileageKm: 0,
          roadDate: const LocalDate(2026, 5, 19),
        ),
        [defaultOilItem()],
      );

      expect(secondCarId, isNot(carId));
      expect(await preferences.getAppliedCarId(), carId);
    },
  );

  test('cannot create car without enabled maintenance items', () async {
    expect(
      () => repository.createCarWithMaintenanceItems(
        defaultCar(
          model: '思域（燃油版）',
          currentMileageKm: 0,
          roadDate: const LocalDate(2026, 5, 19),
        ),
        [defaultOilItem(enabled: false)],
      ),
      throwsA(
        isA<LunioErrorException>().having(
          (e) => e.kind,
          'kind',
          LunioErrorKind.lastEnabledMaintenanceItem,
        ),
      ),
    );
  });
  test('updates car mileage and road date', () async {
    final carId = await repos.insertCarForTest(defaultCar());

    // 更新构造带 id：重建整行语义，保持实体构造器（builder 只管造新数据）。
    await repository.updateCar(
      Car(
        id: carId,
        brand: '本田',
        model: '22款思域',
        currentMileageKm: 18000,
        roadDate: const LocalDate(2023, 9, 1),
        sync: sync,
      ),
    );

    final car = (await repository.listCars()).single;
    expect(car.currentMileageKm, 18000);
    expect(car.roadDate, const LocalDate(2023, 9, 1));
  });

  test('delete applied car switches preference to remaining car', () async {
    final firstCarId = await repos.insertCarForTest(defaultCar());
    final secondCarId = await repos.insertCarForTest(
      defaultCar(
        brand: '日产',
        model: '22款轩逸',
        currentMileageKm: 8000,
        roadDate: const LocalDate(2024, 1, 1),
      ),
    );
    await preferences.setAppliedCarId(firstCarId);

    await repository.deleteCar(firstCarId);

    expect(await preferences.getAppliedCarId(), secondCarId);
  });

  test('same car and date is unique', () async {
    final (carId, itemId) = await repos.seedCarAndItem();
    final first = defaultRecord(
      carId: carId,
      date: const LocalDate(2026, 5, 19),
      itemIds: [itemId],
      costCents: 10000,
      mileageKm: 12000,
    );
    final duplicateDay = defaultRecord(
      carId: carId,
      date: const LocalDate(2026, 5, 19),
      itemIds: [itemId],
      costCents: 10000,
      mileageKm: 13000,
    );

    await repository.saveMaintenanceRecord(first);

    expect(
      () => repository.saveMaintenanceRecord(duplicateDay),
      throwsA(
        isA<LunioErrorException>().having(
          (e) => e.kind,
          'kind',
          LunioErrorKind.duplicateMaintenanceRecord,
        ),
      ),
    );
  });

  test('same car and date rejects a record with different items too', () async {
    // R4 收紧：同车同日只允许一条记录，即使项目不同也拦截
    // （此前业务层放行、插入时撞表级唯一约束抛 SqliteException）。
    final (carId, firstItemId) = await repos.seedCarAndItem();
    final secondItemId = await repository.saveMaintenanceItem(
      defaultOilItem(carsId: carId, name: '机滤', sortOrder: 2),
    );
    final first = defaultRecord(
      carId: carId,
      date: const LocalDate(2026, 5, 19),
      itemIds: [firstItemId],
      costCents: 10000,
      mileageKm: 12000,
    );
    final differentItemsSameDay = defaultRecord(
      carId: carId,
      date: const LocalDate(2026, 5, 19),
      itemIds: [secondItemId],
      costCents: 20000,
      mileageKm: 12500,
    );

    await repository.saveMaintenanceRecord(first);

    await expectLater(
      repository.saveMaintenanceRecord(differentItemsSameDay),
      throwsA(
        isA<LunioErrorException>()
            .having((e) => e.kind, 'kind',
                LunioErrorKind.duplicateMaintenanceRecord)
            .having((e) => e.message, 'message', '这辆车当天已有保养记录，请编辑原记录'),
      ),
    );
    expect(
      await repository.listMaintenanceRecordsForCar(carId),
      hasLength(1),
    );
  });

  test('lists updates and deletes maintenance records', () async {
    final (carId, itemId) = await repos.seedCarAndItem();
    final recordId = await repository.saveMaintenanceRecord(
      defaultRecord(
        carId: carId,
        date: const LocalDate(2026, 5, 19),
        itemIds: [itemId],
        costCents: 10000,
        mileageKm: 12000,
      ),
    );

    expect(await repository.listMaintenanceRecordsForCar(carId), hasLength(1));

    await repository.updateMaintenanceRecord(
      defaultRecord(
        id: recordId,
        carId: carId,
        date: const LocalDate(2026, 5, 20),
        itemIds: [itemId],
        costCents: 12000,
        mileageKm: 13000,
        note: '更新',
      ),
    );
    final updated = (await repository.listMaintenanceRecordsForCar(
      carId,
    )).single;
    expect(updated.date, const LocalDate(2026, 5, 20));
    expect(updated.costCents, 12000);
    expect(updated.note, '更新');

    await repository.deleteMaintenanceRecord(recordId);

    expect(await repository.listMaintenanceRecordsForCar(carId), isEmpty);
    expect(
      await database.select(database.maintenanceRecordItems).get(),
      isEmpty,
    );
  });

  test('saves lists and updates record item costs', () async {
    final (carId, oilId) = await repos.seedCarAndItem();
    final filterId = await repos.saveItem(carId, '机滤', 2);
    final recordId = await repository.saveMaintenanceRecord(
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

    final stored = (await repository.listMaintenanceRecordsForCar(
      carId,
    )).single;
    expect(stored.itemCosts, hasLength(2));
    expect(stored.itemCosts.first.materialCents, 15000);
    expect(stored.itemCosts.first.laborCents, 8000);
    expect(stored.itemCosts.first.costCents, 23000);
    expect(stored.itemCosts.last.costCents, 5000);

    // 编辑：机油费用清空（重新落库为三列 null）、机滤改成不一致价
    // （项目费用 2000 ≠ 材料 3000，合法数据原样落库，ADR 0010）。
    await repository.updateMaintenanceRecord(
      defaultRecord(
        id: recordId,
        carId: carId,
        date: const LocalDate(2026, 5, 19),
        itemIds: [oilId, filterId],
        itemCosts: [
          RecordItemCost(itemId: filterId, materialCents: 3000, costCents: 2000),
        ],
        costCents: 28000,
        mileageKm: 12000,
      ),
    );
    final updated = (await repository.listMaintenanceRecordsForCar(
      carId,
    )).single;
    expect(updated.itemCosts, hasLength(1));
    expect(updated.itemCosts.single.itemId, filterId);
    expect(updated.itemCosts.single.materialCents, 3000);
    expect(updated.itemCosts.single.costCents, 2000);
    // 关联行还在两行（费用清空 ≠ 项目被移除）。
    expect(
      await database.select(database.maintenanceRecordItems).get(),
      hasLength(2),
    );
  });

  test('save enforces item cost invariant at the write seam', () async {
    final (carId, oilId) = await repos.seedCarAndItem();
    // 调用方不做任何预处理的极端形态：材料/工时有值、项目费用为空。
    // "材料/工时任一有值 ⇒ 项目费用必有值"由关联行 companion 单点
    // 兜住（2026-09-25 收编，取代表单/恢复两写点的上游调用）——
    // 还原 companion 内置 normalize 必须让本用例失败（变异验证）。
    await repository.saveMaintenanceRecord(
      defaultRecord(
        carId: carId,
        date: const LocalDate(2026, 5, 19),
        itemIds: [oilId],
        itemCosts: [
          RecordItemCost(itemId: oilId, materialCents: 15000, laborCents: 8000),
        ],
        costCents: 23000,
        mileageKm: 12000,
      ),
    );

    final stored =
        (await repository.listMaintenanceRecordsForCar(carId)).single;
    final cost = stored.itemCosts.single;
    expect(cost.materialCents, 15000);
    expect(cost.laborCents, 8000);
    expect(cost.costCents, 23000);
  });

  test(
    'saves maintenance record and item intervals in one transaction',
    () async {
      final (carId, itemId) = await repos.seedCarAndItem();

      await repository.saveMaintenanceRecordWithItemUpdates(
        record: defaultRecord(
          carId: carId,
          date: const LocalDate(2026, 5, 19),
          itemIds: [itemId],
          costCents: 10000,
          mileageKm: 12000,
        ),
        itemUpdates: [
          MaintenanceItem(
            id: itemId,
            carsId: carId,
            name: '机油',
            enabled: true,
            remindByMileage: true,
            remindByTime: true,
            mileageIntervalKm: 8000,
            timeIntervalMonths: 9,
            notOverdueUpperLimit: 100,
            overdueUpperLimit: 125,
            sortOrder: 1,
            sync: SyncMetadata(
              status: SyncStatus.pendingUpdate,
              updatedAt: DateTime(2026, 5, 19),
            ),
          ),
        ],
      );

      final item = (await repository.listMaintenanceItemsForCar(carId)).single;
      expect(item.mileageIntervalKm, 8000);
      expect(item.timeIntervalMonths, 9);
      expect(item.sync.status, SyncStatus.pendingUpdate);
      expect(
        await repository.listMaintenanceRecordsForCar(carId),
        hasLength(1),
      );
    },
  );

  test('removes one item from multi-item maintenance record', () async {
    final (carId, oilId) = await repos.seedCarAndItem();
    final filterId = await repos.saveItem(carId, '机滤', 2);
    final recordId = await repository.saveMaintenanceRecord(
      defaultRecord(
        carId: carId,
        date: const LocalDate(2026, 5, 19),
        itemIds: [oilId, filterId],
        costCents: 10000,
        mileageKm: 12000,
      ),
    );

    final deletedWholeRecord = await repository.removeMaintenanceRecordItem(
      recordId: recordId,
      itemId: oilId,
    );

    expect(deletedWholeRecord, isFalse);
    final record = (await repository.listMaintenanceRecordsForCar(
      carId,
    )).single;
    expect(record.itemIds, [filterId]);
    expect(
      await database.select(database.maintenanceRecordItems).get(),
      hasLength(1),
    );
  });

  test('removing the last item deletes the whole maintenance record', () async {
    final (carId, itemId) = await repos.seedCarAndItem();
    final recordId = await repository.saveMaintenanceRecord(
      defaultRecord(
        carId: carId,
        date: const LocalDate(2026, 5, 19),
        itemIds: [itemId],
        costCents: 10000,
        mileageKm: 12000,
      ),
    );

    final deletedWholeRecord = await repository.removeMaintenanceRecordItem(
      recordId: recordId,
      itemId: itemId,
    );

    expect(deletedWholeRecord, isTrue);
    expect(await repository.listMaintenanceRecordsForCar(carId), isEmpty);
    expect(
      await database.select(database.maintenanceRecordItems).get(),
      isEmpty,
    );
  });

  test('record can only increase car mileage', () async {
    final (carId, itemId) = await repos.seedCarAndItem();
    final initialUpdatedAt =
        (await database.select(database.cars).get()).single.updatedAt;
    await repository.saveMaintenanceRecord(
      defaultRecord(
        carId: carId,
        date: const LocalDate(2026, 5, 19),
        itemIds: [itemId],
        costCents: 10000,
        mileageKm: 9000,
      ),
    );
    expect((await repository.listCars()).single.currentMileageKm, 10000);
    expect(
      (await database.select(database.cars).get()).single.updatedAt,
      initialUpdatedAt,
    );

    await repository.saveMaintenanceRecord(
      defaultRecord(
        carId: carId,
        date: const LocalDate(2026, 6, 19),
        itemIds: [itemId],
        costCents: 10000,
        mileageKm: 13000,
      ),
    );
    expect((await repository.listCars()).single.currentMileageKm, 13000);
    expect(
      (await database.select(database.cars).get()).single.updatedAt,
      isNot(initialUpdatedAt),
    );
  });

  test('delete car removes related local records and items', () async {
    final (carId, itemId) = await repos.seedCarAndItem();
    await preferences.setAppliedCarId(carId);
    await repository.saveMaintenanceRecord(
      defaultRecord(
        carId: carId,
        date: const LocalDate(2026, 5, 19),
        itemIds: [itemId],
        costCents: 10000,
        mileageKm: 12000,
      ),
    );

    await repository.deleteCar(carId);

    expect(await database.select(database.cars).get(), isEmpty);
    expect(await database.select(database.maintenanceItems).get(), isEmpty);
    expect(await database.select(database.maintenanceRecords).get(), isEmpty);
    expect(
      await database.select(database.maintenanceRecordItems).get(),
      isEmpty,
    );
    expect(await database.select(database.appPreferences).get(), isEmpty);
  });

  test('record rejects missing item ids', () async {
    final (carId, _) = await repos.seedCarAndItem();

    expect(
      () => repository.saveMaintenanceRecord(
        defaultRecord(
          carId: carId,
          date: const LocalDate(2026, 5, 19),
          itemIds: const [999],
          costCents: 10000,
          mileageKm: 12000,
        ),
      ),
      throwsA(
        isA<LunioErrorException>().having(
          (e) => e.kind,
          'kind',
          LunioErrorKind.missingRecordItems,
        ),
      ),
    );
  });

  test('record rejects items from another car', () async {
    final (carId, _) = await repos.seedCarAndItem();
    final otherCarId = await repos.insertCarForTest(
      defaultCar(
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

    expect(
      () => repository.saveMaintenanceRecord(
        defaultRecord(
          carId: carId,
          date: const LocalDate(2026, 5, 19),
          itemIds: [otherItemId],
          costCents: 10000,
          mileageKm: 12000,
        ),
      ),
      throwsA(
        isA<LunioErrorException>().having(
          (e) => e.kind,
          'kind',
          LunioErrorKind.itemFromAnotherCar,
        ),
      ),
    );
  });

  test('updates maintenance item settings', () async {
    final (carId, itemId) = await repos.seedCarAndItem();

    await repository.updateMaintenanceItem(
      MaintenanceItem(
        id: itemId,
        carsId: carId,
        name: '机油',
        enabled: true,
        remindByMileage: true,
        remindByTime: false,
        mileageIntervalKm: 8000,
        sortOrder: 1,
        sync: sync,
      ),
    );

    final item = (await repository.listMaintenanceItemsForCar(carId)).single;
    expect(item.remindByTime, isFalse);
    expect(item.mileageIntervalKm, 8000);
  });

  test('cannot disable the last enabled maintenance item', () async {
    final (_, itemId) = await repos.seedCarAndItem();

    expect(
      () => repository.setMaintenanceItemEnabled(
        itemId: itemId,
        enabled: false,
        sync: sync,
      ),
      throwsA(
        isA<LunioErrorException>().having(
          (e) => e.kind,
          'kind',
          LunioErrorKind.lastEnabledMaintenanceItem,
        ),
      ),
    );
  });

  test('deletes custom item without history', () async {
    final (carId, _) = await repos.seedCarAndItem();
    final customItemId = await repository.saveMaintenanceItem(
      defaultOilItem(
        carsId: carId,
        name: '玻璃水',
        remindByTime: false,
        timeIntervalMonths: null,
        mileageIntervalKm: 3000,
        sortOrder: 2,
      ),
    );

    await repository.deleteMaintenanceItem(customItemId);

    expect(
      (await repository.listMaintenanceItemsForCar(
        carId,
      )).map((item) => item.name),
      isNot(contains('玻璃水')),
    );
  });

  test('deletes item without history', () async {
    final (carId, itemId) = await repos.seedCarAndItem();
    await repository.saveMaintenanceItem(
      defaultOilItem(
        carsId: carId,
        name: '机滤',
        remindByTime: false,
        timeIntervalMonths: null,
        sortOrder: 2,
      ),
    );

    await repository.deleteMaintenanceItem(itemId);

    expect(
      (await repository.listMaintenanceItemsForCar(
        carId,
      )).map((item) => item.name),
      isNot(contains('机油')),
    );
  });

  test('does not delete item with history', () async {
    final (carId, itemId) = await repos.seedCarAndItem();
    final customItemId = await repository.saveMaintenanceItem(
      defaultOilItem(
        carsId: carId,
        name: '玻璃水',
        remindByTime: false,
        timeIntervalMonths: null,
        mileageIntervalKm: 3000,
        sortOrder: 2,
      ),
    );
    await repository.saveMaintenanceRecord(
      defaultRecord(
        carId: carId,
        date: const LocalDate(2026, 5, 19),
        itemIds: [itemId],
        costCents: 1000,
        mileageKm: 12000,
      ),
    );

    expect(
      () => repository.deleteMaintenanceItem(itemId),
      throwsA(
        isA<LunioErrorException>().having(
          (e) => e.kind,
          'kind',
          LunioErrorKind.maintenanceItemHasHistory,
        ),
      ),
    );
    await repository.deleteMaintenanceItem(customItemId);
  });
}
