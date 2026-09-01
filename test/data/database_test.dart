
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:lunio/core/date/local_date.dart';
import 'package:lunio/data/backup/backup_codec.dart';
import 'package:lunio/data/bootstrap/built_in_vehicle_catalog.dart';
import '../helpers/built_in_catalog_loader.dart' show loadBuiltInVehicleCatalogForTest;
import 'package:lunio/data/database/app_database.dart';
import 'package:lunio/data/repositories/lunio_repository.dart';
import 'package:lunio/domain/entities/car.dart';
import 'package:lunio/domain/entities/maintenance_item.dart';
import 'package:lunio/domain/entities/maintenance_record.dart';
import 'package:lunio/domain/entities/parking_countdown.dart';
import 'package:lunio/domain/entities/powertrain_type.dart';
import 'package:lunio/domain/entities/sync_metadata.dart';
import 'package:lunio/domain/entities/vehicle_default_maintenance_item.dart';
import 'package:lunio/domain/entities/vehicle_model.dart';
import 'package:lunio/features/shell/shared/formatters.dart' show maintenanceItemFromDefault;

void main() {
  late AppDatabase database;
  late LunioRepository repository;
  late SyncMetadata sync;
  late BuiltInVehicleCatalog builtInCatalog;

  setUpAll(() {
    builtInCatalog = loadBuiltInVehicleCatalogForTest();
  });

  setUp(() {
    database = AppDatabase.inMemory();
    repository = LunioRepository(
      database,
      loadBuiltInVehicleCatalog: () async => builtInCatalog,
    );
    sync = SyncMetadata(status: SyncStatus.synced, updatedAt: DateTime(2026));
  });

  tearDown(() async {
    await database.close();
  });

  test('vehicle catalog requires stable ids', () {
    expect(
      () => BuiltInVehicleCatalog.fromJson({
        'schemaVersion': 1,
        'templates': {
          'fuel': [
            {
              'id': 'engine-oil',
              'name': '机油',
              'remindByMileage': true,
              'remindByTime': false,
              'mileageIntervalKm': 5000,
            },
          ],
        },
        'vehicles': [
          {'brand': '日产', 'model': '轩逸（燃油版）', 'template': 'fuel'},
        ],
      }),
      throwsArgumentError,
    );
    expect(
      () => BuiltInVehicleCatalog.fromJson({
        'schemaVersion': 1,
        'templates': {
          'fuel': [
            {
              'id': 'engine-oil',
              'name': '机油',
              'remindByMileage': true,
              'remindByTime': false,
              'mileageIntervalKm': 5000,
            },
          ],
        },
        'vehicles': [
          {
            'id': 'nissan-sylphy-fuel',
            'brand': '日产',
            'model': '轩逸（燃油版）',
            'template': 'fuel',
          },
          {
            'id': 'nissan-sylphy-fuel',
            'brand': '日产',
            'model': '轩逸（混动版）',
            'template': 'fuel',
          },
        ],
      }),
      throwsArgumentError,
    );
    expect(
      () => BuiltInVehicleCatalog.fromJson({
        'schemaVersion': 1,
        'templates': {
          'fuel': [
            {
              'id': 'engine-oil',
              'name': '机油',
              'remindByMileage': true,
              'remindByTime': false,
              'mileageIntervalKm': 5000,
            },
            {
              'id': 'engine-oil',
              'name': '机油 Plus',
              'remindByMileage': true,
              'remindByTime': false,
              'mileageIntervalKm': 8000,
            },
          ],
        },
        'vehicles': [
          {
            'id': 'nissan-sylphy-fuel',
            'brand': '日产',
            'model': '轩逸（燃油版）',
            'template': 'fuel',
          },
        ],
      }),
      throwsArgumentError,
    );
  });

  /// 测试序号（测试替身生成车辆 id 用）。
  int testCarSeq = 0;

  /// 测试替身：等价已删除的 createCar（裸插车辆、无项目，R26 清理）。
  /// 直接走 database 插入——原 API 允许零项目，需绕开
  /// createCarWithMaintenanceItems 的"至少一个启用项目"业务校验。
  /// id 用自增序列（唯一正整数即可，与雪花 id 不冲突）。
  Future<int> createCar(LunioRepository repository, Car car) async {
    final carId = 900000 + ++testCarSeq;
    await database
        .into(database.cars)
        .insert(
          CarsCompanion.insert(
            id: Value(carId),
            brand: car.brand,
            model: car.model,
            currentMileageKm: car.currentMileageKm,
            roadDate: car.roadDate.toString(),
            syncStatus: Value(car.sync.status.name),
            updatedAt: car.sync.updatedAt.toIso8601String(),
            version: Value(car.sync.version),
          ),
        );
    return carId;
  }

  /// 测试替身：等价已删除的 createCarWithDefaultItems（按默认模板建车，
  /// R26 清理）——按车的动力类型查当前库里的模板 → 转车辆级项目实体 → 建车。
  /// 注意不主动 bootstrap：目录由调用方按需灌入（有的用例用自定义目录）。
  Future<int> createCarWithDefaultItems(
    LunioRepository repository,
    Car car,
  ) async {
    final defaults = await repository.listDefaultItemsForPowertrain(
      powertrainType: car.powertrainType,
    );
    return repository.createCarWithMaintenanceItems(
      car,
      [for (final item in defaults) maintenanceItemFromDefault(item, car.sync)],
    );
  }

  Future<(int, int)> seedCarAndItem() async {
    final carId = await createCar(repository, 
      Car(
        brand: '本田',
        model: '22款思域',
        currentMileageKm: 10000,
        roadDate: const LocalDate(2023, 8, 12),
        sync: sync,
      ),
    );
    final itemId = await repository.saveMaintenanceItem(
      MaintenanceItem(
        carsId: carId,
        name: '机油',
        enabled: true,
        remindByMileage: true,
        remindByTime: true,
        mileageIntervalKm: 5000,
        timeIntervalMonths: 6,
        notOverdueUpperLimit: 100,
        overdueUpperLimit: 125,
        sortOrder: 1,
        sync: sync,
      ),
    );
    return (carId, itemId);
  }

  Future<int> saveItem(int carId, String name, int sortOrder) {
    return repository.saveMaintenanceItem(
      MaintenanceItem(
        carsId: carId,
        name: name,
        enabled: true,
        remindByMileage: true,
        remindByTime: true,
        mileageIntervalKm: 5000,
        timeIntervalMonths: 6,
        notOverdueUpperLimit: 100,
        overdueUpperLimit: 125,
        sortOrder: sortOrder,
        sync: sync,
      ),
    );
  }

  test('creates schema and persists car data', () async {
    await seedCarAndItem();

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
    await createCar(repository, 
      Car(
        brand: '本田',
        model: '思域（燃油版）',
        currentMileageKm: 10000,
        roadDate: const LocalDate(2021, 10, 31),
        sync: sync,
      ),
    );
    await createCar(repository, 
      Car(
        brand: '本田',
        model: '思域（燃油版）',
        currentMileageKm: 0,
        roadDate: const LocalDate(2026, 6, 2),
        sync: sync,
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
    final car = Car(
      brand: '本田',
      model: '思域（燃油版）',
      currentMileageKm: 10000,
      roadDate: const LocalDate(2021, 10, 31),
      sync: sync,
    );

    await createCar(repository, car);

    expect(createCar(repository, car), throwsA(isA<Object>()));
  });

  test(
    'create car copies default maintenance items and applies first car',
    () async {
      await repository.ensureDefaultMaintenanceItems();

      final carId = await createCarWithDefaultItems(repository, 
        Car(
          brand: '本田',
          model: '思域（燃油版）',
          currentMileageKm: 10000,
          roadDate: const LocalDate(2023, 8, 12),
          sync: sync,
        ),
      );

      final items = await repository.listMaintenanceItemsForCar(carId);
      expect(
        items.map((item) => item.name),
        containsAll(['机油', '机滤', '空调滤芯', '汽油滤芯']),
      );
      // 燃油模板整组复制（10 项）。
      expect(items, hasLength(10));
      final oilItems = items.where(
        (item) => item.name == '机油' || item.name == '机滤',
      );
      expect(oilItems, hasLength(2));
      for (final item in oilItems) {
        expect(item.remindByMileage, isTrue);
        expect(item.remindByTime, isTrue);
        expect(item.mileageIntervalKm, 5000);
        expect(item.timeIntervalMonths, 6);
      }
      expect(await repository.getAppliedCarId(), '$carId');
    },
  );

  test(
    'bootstraps default maintenance items per powertrain type',
    () async {
      await repository.ensureDefaultMaintenanceItems();

      final fuelItems = await repository.listDefaultItemsForPowertrain(
        powertrainType: PowertrainType.fuel,
      );
      final hybridItems = await repository.listDefaultItemsForPowertrain(
        powertrainType: PowertrainType.hybrid,
      );
      final plugInItems = await repository.listDefaultItemsForPowertrain(
        powertrainType: PowertrainType.plugIn,
      );
      final extendedItems = await repository.listDefaultItemsForPowertrain(
        powertrainType: PowertrainType.extendedRange,
      );
      final evItems = await repository.listDefaultItemsForPowertrain(
        powertrainType: PowertrainType.electric,
      );

      expect(_defaultItemRules(fuelItems), _genericFuelRules);
      expect(_defaultItemRules(hybridItems), _genericHybridRules);
      expect(_defaultItemRules(plugInItems), _genericPlugInRules);
      // 增程与插混共用同一套保养内容（ADR 0003）。
      expect(_defaultItemRules(extendedItems), _genericPlugInRules);
      expect(_defaultItemRules(evItems), _genericEvRules);
      // 五组模板行数：fuel 10、hybrid 11、plugIn 9、extended 9、ev 7。
      expect(fuelItems, hasLength(10));
      expect(hybridItems, hasLength(11));
      expect(plugInItems, hasLength(9));
      expect(extendedItems, hasLength(9));
      expect(evItems, hasLength(7));
    },
  );

  test('civic uses its vehicle-specific civicFuel template (ADR 0004)', () async {
    await repository.ensureDefaultMaintenanceItems();

    // 目录解析：思域条目带 itemTemplate，civicFuel 组 14 项、首项燃油宝。
    final civic = builtInCatalog.findVehicle('本田', '思域');
    expect(civic, isNotNull);
    expect(civic!.itemTemplate, 'civicFuel');
    final civicTemplate = builtInCatalog.vehicleTemplateItems('civicFuel');
    expect(civicTemplate, hasLength(14));
    expect(civicTemplate!.first.name, '燃油宝');

    // 仓库按（品牌+车型+推荐动力类型一致）返回专属模板。
    final items = await repository.listDefaultItemsForVehicleModel(
      brand: '本田',
      model: '思域',
      selectedPowertrain: PowertrainType.fuel,
    );
    expect(items, hasLength(14));
    expect(items!.first.itemName, '燃油宝');
    expect(items.first.catalogId, 'vtpl:civicFuel:fuel-additive');
    expect(
      [for (final item in items) item.sortOrder],
      [for (var i = 1; i <= 14; i++) i],
    );

    // 专属模板不写 vehicle_default_maintenance_items 表：
    // 燃油通用组仍是 10 项、不含燃油宝。
    final fuelItems = await repository.listDefaultItemsForPowertrain(
      powertrainType: PowertrainType.fuel,
    );
    expect(fuelItems, hasLength(10));
    expect(fuelItems.any((item) => item.itemName == '燃油宝'), isFalse);
  });

  test('vehicle-specific template falls back when rules not met', () async {
    // 改选其他动力类型：专属模板不适用，返回 null（向导回退通用模板）。
    expect(
      await repository.listDefaultItemsForVehicleModel(
        brand: '本田',
        model: '思域',
        selectedPowertrain: PowertrainType.electric,
      ),
      isNull,
    );
    // 目录里没有专属模板的车型（本田 型格）→ null。
    expect(
      await repository.listDefaultItemsForVehicleModel(
        brand: '本田',
        model: '型格',
        selectedPowertrain: PowertrainType.fuel,
      ),
      isNull,
    );
    // 非目录自定义车型 → null。
    expect(
      await repository.listDefaultItemsForVehicleModel(
        brand: '自定义',
        model: '手工车',
        selectedPowertrain: PowertrainType.fuel,
      ),
      isNull,
    );
  });

  test('vehicle itemTemplate must reference vehicleTemplates', () {
    expect(
      () => BuiltInVehicleCatalog.fromJson({
        'schemaVersion': 1,
        'templates': {
          'fuel': [
            {
              'id': 'engine-oil',
              'name': '机油',
              'remindByMileage': true,
              'remindByTime': false,
              'mileageIntervalKm': 5000,
            },
          ],
        },
        'vehicleTemplates': {
          'civicFuel': [
            {
              'id': 'fuel-additive',
              'name': '燃油宝',
              'remindByMileage': true,
              'remindByTime': false,
              'mileageIntervalKm': 5000,
            },
          ],
        },
        'vehicles': [
          {
            'id': 'honda-civic-fuel',
            'brand': '本田',
            'model': '思域',
            'template': 'fuel',
            'itemTemplate': 'notExist',
          },
        ],
      }),
      throwsArgumentError,
    );
  });

  test('production asset loader keeps vehicleTemplates reachable', () async {
    // 回归：生产加载器 loadBuiltInVehicleCatalogAsset 手工拼目录 JSON，
    // 曾把 vehicleTemplates 字段丢掉，导致思域 itemTemplate 校验在真机
    // 启动时抛错、页面整体加载失败。其余测试走磁盘 helper（已透传该
    // 字段）或注入目录，抓不到这条路径，必须直连 rootBundle 验证。
    TestWidgetsFlutterBinding.ensureInitialized();
    final catalog = await loadBuiltInVehicleCatalogAsset();
    expect(catalog.findVehicle('本田', '思域')!.itemTemplate, 'civicFuel');
    expect(catalog.vehicleTemplateItems('civicFuel'), hasLength(14));
  });

  test('bootstrap updates stale template rows by catalog id', () async {
    // 旧版本模板行（同 catalogId、旧间隔）：bootstrap 对账后应被目录值覆盖。
    await repository.saveVehicleDefaultMaintenanceItem(
      VehicleDefaultMaintenanceItem(
        catalogId: 'tpl:fuel:engine-oil',
        powertrainType: PowertrainType.fuel,
        itemName: '机油',
        remindByMileage: true,
        remindByTime: true,
        mileageIntervalKm: 3000,
        timeIntervalMonths: 3,
        sortOrder: 99,
        sync: sync,
      ),
    );

    await repository.ensureDefaultMaintenanceItems();

    final items = await repository.listDefaultItemsForPowertrain(
      powertrainType: PowertrainType.fuel,
    );
    final oilItems = items.where((item) => item.itemName == '机油');
    expect(oilItems, hasLength(1));
    expect(_defaultItemRules(oilItems.toList()), ['机油|true|true|5000|6']);
  });

  test(
    'bootstrap adopts legacy built-in rows and updates them by catalog id',
    () async {
      await repository.saveVehicleModel(
        VehicleModel(
          brand: '日产',
          model: '轩逸',
          template: PowertrainType.fuel,
          sortOrder: 99,
          sync: sync,
        ),
      );
      await repository.saveVehicleDefaultMaintenanceItem(
        VehicleDefaultMaintenanceItem(
          catalogId: 'tpl:fuel:engine-oil',
          powertrainType: PowertrainType.fuel,
          itemName: '机油',
          remindByMileage: true,
          remindByTime: true,
          mileageIntervalKm: 3000,
          timeIntervalMonths: 3,
          sortOrder: 99,
          sync: sync,
        ),
      );

      final initialCatalog = BuiltInVehicleCatalog.fromJson({
        'schemaVersion': 1,
        'templates': {
          'fuel': [
            {
              'id': 'engine-oil',
              'name': '机油',
              'remindByMileage': true,
              'remindByTime': true,
              'mileageIntervalKm': 5000,
              'timeIntervalMonths': 6,
            },
          ],
        },
        'vehicles': [
          {
            'id': 'nissan-sylphy-fuel',
            'brand': '日产',
            'model': '轩逸',
            'template': 'fuel',
          },
        ],
      });
      await LunioRepository(
        database,
        loadBuiltInVehicleCatalog: () async => initialCatalog,
      ).ensureBootstrapData();

      final adoptedModel =
          (await database.select(database.vehicleModels).get()).single;
      final adoptedItem =
          (await database.select(database.vehicleDefaultMaintenanceItems).get())
              .single;
      expect(adoptedModel.catalogId, 'nissan-sylphy-fuel');
      expect(adoptedModel.sortOrder, 1);
      expect(adoptedModel.template, 'fuel');
      expect(adoptedItem.catalogId, 'tpl:fuel:engine-oil');
      expect(adoptedItem.mileageIntervalKm, 5000);
      expect(adoptedItem.timeIntervalMonths, 6);

      final updatedCatalog = BuiltInVehicleCatalog.fromJson({
        'schemaVersion': 1,
        'templates': {
          'fuel': [
            {
              'id': 'engine-oil',
              'name': '发动机机油',
              'remindByMileage': true,
              'remindByTime': true,
              'mileageIntervalKm': 8000,
              'timeIntervalMonths': 12,
            },
          ],
        },
        'vehicles': [
          {
            'id': 'nissan-sylphy-fuel',
            'brand': '日产',
            'model': '轩逸经典',
            'template': 'fuel',
          },
        ],
      });
      await LunioRepository(
        database,
        loadBuiltInVehicleCatalog: () async => updatedCatalog,
      ).ensureBootstrapData();

      final updatedModel =
          (await database.select(database.vehicleModels).get()).single;
      final updatedItem =
          (await database.select(database.vehicleDefaultMaintenanceItems).get())
              .single;
      expect(updatedModel.id, adoptedModel.id);
      expect(updatedModel.brand, '日产');
      expect(updatedModel.model, '轩逸经典');
      expect(updatedItem.id, adoptedItem.id);
      expect(updatedItem.powertrainType, 'fuel');
      expect(updatedItem.itemName, '发动机机油');
      expect(updatedItem.mileageIntervalKm, 8000);
      expect(updatedItem.timeIntervalMonths, 12);
    },
  );

  test(
    'bootstrap deletes removed catalog rows without touching user car items',
    () async {
      final initialCatalog = BuiltInVehicleCatalog.fromJson({
        'schemaVersion': 1,
        'templates': {
          'fuel': [
            {
              'id': 'engine-oil',
              'name': '机油',
              'remindByMileage': true,
              'remindByTime': false,
              'mileageIntervalKm': 5000,
            },
          ],
        },
        'vehicles': [
          {
            'id': 'nissan-sylphy-fuel',
            'brand': '日产',
            'model': '轩逸（燃油版）',
            'template': 'fuel',
          },
        ],
      });
      final seedRepository = LunioRepository(
        database,
        loadBuiltInVehicleCatalog: () async => initialCatalog,
      );
      await seedRepository.ensureBootstrapData();
      await repository.saveVehicleModel(
        VehicleModel(
          brand: '自定义品牌',
          model: '自定义车型',
          template: PowertrainType.fuel,
          sortOrder: 1,
          sync: sync,
        ),
      );
      await repository.saveVehicleDefaultMaintenanceItem(
        VehicleDefaultMaintenanceItem(
          // 放混动组：不混入下面按燃油建车的默认项，测试"目录条目删除
          // 不碰车辆级项目"的意图不变。
          powertrainType: PowertrainType.hybrid,
          itemName: '自定义项目',
          remindByMileage: true,
          remindByTime: false,
          mileageIntervalKm: 1000,
          sortOrder: 1,
          sync: sync,
        ),
      );
      final carId = await createCarWithDefaultItems(repository, 
        Car(
          brand: '日产',
          model: '轩逸（燃油版）',
          currentMileageKm: 10000,
          roadDate: const LocalDate(2024, 1, 1),
          sync: sync,
        ),
      );

      // "目录更新后条目被移除"：模板全撤、车型清空。
      // 注意默认项目按动力类型展开（与车型列表无关），所以这里
      // 模板也要清空，模板表才会被对账清到只剩用户自建行。
      final emptyCatalog = BuiltInVehicleCatalog.fromJson({
        'schemaVersion': 1,
        'templates': const <String, Object?>{},
        'vehicles': <Object?>[],
      });
      await LunioRepository(
        database,
        loadBuiltInVehicleCatalog: () async => emptyCatalog,
      ).ensureBootstrapData();

      expect(
        (await database.select(database.vehicleModels).get()).map(
          (row) => row.brand,
        ),
        ['自定义品牌'],
      );
      expect(
        (await database.select(database.vehicleDefaultMaintenanceItems).get())
            .map((row) => row.itemName),
        ['自定义项目'],
      );
      expect(await repository.listCars(), hasLength(1));
      expect(await repository.listMaintenanceItemsForCar(carId), hasLength(1));
    },
  );

  test('pure electric templates do not include fuel service items', () async {
    await repository.ensureDefaultMaintenanceItems();

    final items = await repository.listDefaultItemsForPowertrain(
      powertrainType: PowertrainType.electric,
    );
    final names = items.map((item) => item.itemName);

    expect(names, isNot(contains('机油')));
    expect(names, isNot(contains('机滤')));
    expect(names, isNot(contains('汽油滤芯')));
    expect(names, isNot(contains('火花塞')));
    expect(_defaultItemRules(items), _genericEvRules);
  });

  test('bootstraps selectable vehicle models for common brands', () async {
    await repository.ensureVehicleModels();

    final models = await repository.listVehicleModels();

    // 目录以懂车帝原始车系名为准（ADR 0003）；2026-09-01 起精简为
    // 每品牌最多 10 款热门车型，共 1223 条。
    expect(
      models.map((model) => '${model.brand} ${model.model}'),
      containsAll([
        '本田 思域',
        '丰田 卡罗拉',
        '丰田 凯美瑞',
        '日产 轩逸',
        '大众 速腾',
        '大众 帕萨特',
        '比亚迪 秦PLUS DM',
        '比亚迪 秦PLUS EV',
        '比亚迪 海鸥',
        '吉利汽车 帝豪',
        '长安 逸动',
        '哈弗 哈弗H6',
        '特斯拉 Model 3',
        'AITO问界 问界M9',
        '小米汽车 小米SU7',
        '宝马 宝马3系',
        '奥迪 奥迪A4L',
        '讴歌 讴歌ILX', // 停售条目也进目录
      ]),
    );
    // 推荐动力类型随车系给出（添加向导预选用）。
    final byName = {
      for (final model in models) '${model.brand} ${model.model}': model.template,
    };
    expect(byName['比亚迪 秦PLUS DM'], PowertrainType.plugIn);
    expect(byName['比亚迪 秦PLUS EV'], PowertrainType.electric);
    expect(byName['AITO问界 问界M9'], PowertrainType.extendedRange);
    expect(byName['特斯拉 Model 3'], PowertrainType.electric);
    expect(byName['丰田 卡罗拉'], PowertrainType.fuel);
    expect(models.length, greaterThan(1000));
  });

  test('bootstrap leaves existing brands unchanged', () async {
    await repository.saveVehicleModel(
      VehicleModel(
        brand: '东风日产',
        model: '轩逸',
        template: PowertrainType.fuel,
        sortOrder: 1,
        sync: sync,
      ),
    );

    await repository.ensureBootstrapData();

    final modelRows = await database.select(database.vehicleModels).get();
    final sylphyRows = modelRows
        .where((row) => row.model == '轩逸')
        .map((row) => row.brand)
        .toList();
    // 无 catalogId 的老行按（品牌, 车型）兜底认领，不被目录覆盖删除。
    expect(sylphyRows, contains('东风日产'));
    expect(sylphyRows.where((brand) => brand == '日产'), hasLength(1));
  });

  test('bootstrap leaves existing car brands unchanged', () async {
    final oldCarId = await createCar(repository, 
      Car(
        brand: '东风日产',
        model: '轩逸（燃油版）',
        currentMileageKm: 15000,
        roadDate: const LocalDate(2024, 1, 1),
        sync: sync,
      ),
    );
    await createCar(repository, 
      Car(
        brand: '日产',
        model: '轩逸（燃油版）',
        currentMileageKm: 20000,
        roadDate: const LocalDate(2024, 1, 1),
        sync: sync,
      ),
    );
    await repository.setAppliedCarId(oldCarId);

    await repository.ensureBootstrapData();

    final cars = await repository.listCars();
    expect(cars, hasLength(2));
    expect(cars.map((car) => car.brand), containsAll(['东风日产', '日产']));
    expect(await repository.getAppliedCarId(), '$oldCarId');
  });

  test('writes snowflake ids for all local tables', () async {
    await repository.ensureBootstrapData();
    final carId = await createCarWithDefaultItems(repository, 
      Car(
        brand: '本田',
        model: '思域（燃油版）',
        currentMileageKm: 10000,
        roadDate: const LocalDate(2023, 8, 12),
        sync: sync,
      ),
    );
    final item = (await repository.listMaintenanceItemsForCar(carId)).first;
    await repository.saveMaintenanceRecord(
      MaintenanceRecord(
        carId: carId,
        date: const LocalDate(2026, 5, 19),
        itemIds: [item.id!],
        costCents: 10000,
        mileageKm: 12000,
        sync: sync,
      ),
    );
    await repository.setPreferenceValue('manualDate', '2026-05-19');

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

  test('bootstraps selectable vehicle models', () async {
    await repository.ensureVehicleModels();

    final models = await repository.listVehicleModels();

    // 覆盖各字母分片的抽样（懂车帝原名，含动力拆分条目与停售条目）。
    expect(
      models.map((model) => '${model.brand} ${model.model}'),
      containsAll([
        '本田 思域',
        '本田 雅阁',
        '丰田 汉兰达',
        '日产 天籁',
        '大众 途观L',
        '大众 ID.4 CROZZ',
        '别克 别克GL8 PHEV',
        '福特 蒙迪欧',
        '比亚迪 海豹06DM',
        '比亚迪 汉EV',
        '腾势 腾势D9 DM',
        '方程豹 豹5',
        '吉利银河 星愿',
        '吉利银河 银河L6',
        '领克 领克08 EM-P',
        '奇瑞 瑞虎8',
        '长安启源 长安启源A07',
        '哈弗 哈弗H6',
        '坦克 坦克300 Hi4-T',
        '魏牌 高山',
        '五菱汽车 五菱宏光MINIEV',
        '广汽传祺 传祺M8',
        '理想汽车 理想L6',
        '蔚来 蔚来ET5',
        '小鹏汽车 小鹏MONA M03',
        '小米汽车 小米YU7',
        'AITO问界 问界M8',
        '特斯拉 Model Y',
        '宝马 宝马3系',
        '奔驰 奔驰C级',
        '奥迪 奥迪Q5L',
        '雷克萨斯 雷克萨斯ES',
        '马自达 马自达3 昂克赛拉',
        '路虎 揽胜极光',
        'MINI 电动MINI COOPER',
        'smart smart精灵#1',
        '欧拉 欧拉好猫',
        '极氪 ZEEKR 001',
        '智己汽车 智己LS6',
        '雪佛兰 科尔维特', // 停售、品牌仅在售目录外
        '道奇 挑战者', // 停售
        '讴歌 讴歌ILX', // 停售
      ]),
    );
    expect(models.map((model) => model.catalogId), everyElement(isNotNull));
    expect(
      models.map((model) => model.catalogId).toSet(),
      hasLength(models.length),
    );
    // 老目录带动力后缀的名字一条都不该再出现。
    expect(
      models.where((model) => model.model.endsWith('版）')),
      isEmpty,
    );
  });

  test('applied car falls back to first available car', () async {
    final firstCarId = await createCar(repository, 
      Car(
        brand: '本田',
        model: '22款思域',
        currentMileageKm: 10000,
        roadDate: const LocalDate(2023, 8, 12),
        sync: sync,
      ),
    );
    await createCar(repository, 
      Car(
        brand: '日产',
        model: '22款轩逸',
        currentMileageKm: 8000,
        roadDate: const LocalDate(2024, 1, 1),
        sync: sync,
      ),
    );
    await repository.setAppliedCarId(999);

    final appliedCar = await repository.getAppliedCar();

    expect(appliedCar?.id, firstCarId);
    expect(await repository.getAppliedCarId(), '$firstCarId');
  });

  test(
    'creates car with configured maintenance items in one transaction',
    () async {
      final carId = await repository.createCarWithMaintenanceItems(
        Car(
          brand: '本田',
          model: '思域（燃油版）',
          currentMileageKm: 0,
          roadDate: const LocalDate(2026, 5, 19),
          sync: sync,
        ),
        [
          MaintenanceItem(
            carsId: 0,
            name: '机油',
            enabled: true,
            remindByMileage: true,
            remindByTime: true,
            mileageIntervalKm: 5000,
            timeIntervalMonths: 6,
            sortOrder: 1,
            sync: sync,
          ),
          MaintenanceItem(
            carsId: 0,
            name: '玻璃水',
            enabled: false,
            remindByMileage: true,
            remindByTime: false,
            mileageIntervalKm: 3000,
            sortOrder: 2,
            sync: sync,
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
      expect(await repository.getAppliedCarId(), '$carId');

      final secondCarId = await repository.createCarWithMaintenanceItems(
        Car(
          brand: '日产',
          model: '22款轩逸',
          currentMileageKm: 0,
          roadDate: const LocalDate(2026, 5, 19),
          sync: sync,
        ),
        [
          MaintenanceItem(
            carsId: 0,
            name: '机油',
            enabled: true,
            remindByMileage: true,
            remindByTime: true,
            mileageIntervalKm: 5000,
            timeIntervalMonths: 6,
            sortOrder: 1,
            sync: sync,
          ),
        ],
      );

      expect(secondCarId, isNot(carId));
      expect(await repository.getAppliedCarId(), '$carId');
    },
  );

  test('cannot create car without enabled maintenance items', () async {
    expect(
      () => repository.createCarWithMaintenanceItems(
        Car(
          brand: '本田',
          model: '思域（燃油版）',
          currentMileageKm: 0,
          roadDate: const LocalDate(2026, 5, 19),
          sync: sync,
        ),
        [
          MaintenanceItem(
            carsId: 0,
            name: '机油',
            enabled: false,
            remindByMileage: true,
            remindByTime: true,
            mileageIntervalKm: 5000,
            timeIntervalMonths: 6,
            sortOrder: 1,
            sync: sync,
          ),
        ],
      ),
      throwsArgumentError,
    );
  });

  test('applied car falls back to first available car', () async {
    final firstCarId = await createCar(repository, 
      Car(
        brand: '本田',
        model: '22款思域',
        currentMileageKm: 10000,
        roadDate: const LocalDate(2023, 8, 12),
        sync: sync,
      ),
    );
    await createCar(repository, 
      Car(
        brand: '日产',
        model: '22款轩逸',
        currentMileageKm: 8000,
        roadDate: const LocalDate(2024, 1, 1),
        sync: sync,
      ),
    );
    await repository.setAppliedCarId(999);

    final appliedCar = await repository.getAppliedCar();

    expect(appliedCar?.id, firstCarId);
    expect(await repository.getAppliedCarId(), '$firstCarId');
  });

  test('updates car mileage and road date', () async {
    final carId = await createCar(repository, 
      Car(
        brand: '本田',
        model: '22款思域',
        currentMileageKm: 10000,
        roadDate: const LocalDate(2023, 8, 12),
        sync: sync,
      ),
    );

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
    final firstCarId = await createCar(repository, 
      Car(
        brand: '本田',
        model: '22款思域',
        currentMileageKm: 10000,
        roadDate: const LocalDate(2023, 8, 12),
        sync: sync,
      ),
    );
    final secondCarId = await createCar(repository, 
      Car(
        brand: '日产',
        model: '22款轩逸',
        currentMileageKm: 8000,
        roadDate: const LocalDate(2024, 1, 1),
        sync: sync,
      ),
    );
    await repository.setAppliedCarId(firstCarId);

    await repository.deleteCar(firstCarId);

    expect(await repository.getAppliedCarId(), '$secondCarId');
  });

  test('same car and date is unique', () async {
    final (carId, itemId) = await seedCarAndItem();
    final first = MaintenanceRecord(
      carId: carId,
      date: const LocalDate(2026, 5, 19),
      itemIds: [itemId],
      costCents: 10000,
      mileageKm: 12000,
      sync: sync,
    );
    final duplicateDay = MaintenanceRecord(
      carId: carId,
      date: const LocalDate(2026, 5, 19),
      itemIds: [itemId],
      costCents: 10000,
      mileageKm: 13000,
      sync: sync,
    );

    await repository.saveMaintenanceRecord(first);

    expect(
      () => repository.saveMaintenanceRecord(duplicateDay),
      throwsA(isA<StateError>()),
    );
  });

  test('same car and date rejects a record with different items too', () async {
    // R4 收紧：同车同日只允许一条记录，即使项目不同也拦截
    // （此前业务层放行、插入时撞表级唯一约束抛 SqliteException）。
    final (carId, firstItemId) = await seedCarAndItem();
    final secondItemId = await repository.saveMaintenanceItem(
      MaintenanceItem(
        carsId: carId,
        name: '机滤',
        enabled: true,
        remindByMileage: true,
        remindByTime: true,
        mileageIntervalKm: 5000,
        timeIntervalMonths: 6,
        notOverdueUpperLimit: 100,
        overdueUpperLimit: 125,
        sortOrder: 2,
        sync: sync,
      ),
    );
    final first = MaintenanceRecord(
      carId: carId,
      date: const LocalDate(2026, 5, 19),
      itemIds: [firstItemId],
      costCents: 10000,
      mileageKm: 12000,
      sync: sync,
    );
    final differentItemsSameDay = MaintenanceRecord(
      carId: carId,
      date: const LocalDate(2026, 5, 19),
      itemIds: [secondItemId],
      costCents: 20000,
      mileageKm: 12500,
      sync: sync,
    );

    await repository.saveMaintenanceRecord(first);

    await expectLater(
      repository.saveMaintenanceRecord(differentItemsSameDay),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          '这辆车当天已有保养记录，请编辑原记录',
        ),
      ),
    );
    expect(
      await repository.listMaintenanceRecordsForCar(carId),
      hasLength(1),
    );
  });

  test('lists updates and deletes maintenance records', () async {
    final (carId, itemId) = await seedCarAndItem();
    final recordId = await repository.saveMaintenanceRecord(
      MaintenanceRecord(
        carId: carId,
        date: const LocalDate(2026, 5, 19),
        itemIds: [itemId],
        costCents: 10000,
        mileageKm: 12000,
        sync: sync,
      ),
    );

    expect(await repository.listMaintenanceRecordsForCar(carId), hasLength(1));

    await repository.updateMaintenanceRecord(
      MaintenanceRecord(
        id: recordId,
        carId: carId,
        date: const LocalDate(2026, 5, 20),
        itemIds: [itemId],
        costCents: 12000,
        mileageKm: 13000,
        note: '更新',
        sync: sync,
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

  test(
    'saves maintenance record and item intervals in one transaction',
    () async {
      final (carId, itemId) = await seedCarAndItem();

      await repository.saveMaintenanceRecordWithItemUpdates(
        record: MaintenanceRecord(
          carId: carId,
          date: const LocalDate(2026, 5, 19),
          itemIds: [itemId],
          costCents: 10000,
          mileageKm: 12000,
          sync: sync,
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
    final (carId, oilId) = await seedCarAndItem();
    final filterId = await saveItem(carId, '机滤', 2);
    final recordId = await repository.saveMaintenanceRecord(
      MaintenanceRecord(
        carId: carId,
        date: const LocalDate(2026, 5, 19),
        itemIds: [oilId, filterId],
        costCents: 10000,
        mileageKm: 12000,
        sync: sync,
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
    final (carId, itemId) = await seedCarAndItem();
    final recordId = await repository.saveMaintenanceRecord(
      MaintenanceRecord(
        carId: carId,
        date: const LocalDate(2026, 5, 19),
        itemIds: [itemId],
        costCents: 10000,
        mileageKm: 12000,
        sync: sync,
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
    final (carId, itemId) = await seedCarAndItem();
    final initialUpdatedAt =
        (await database.select(database.cars).get()).single.updatedAt;
    await repository.saveMaintenanceRecord(
      MaintenanceRecord(
        carId: carId,
        date: const LocalDate(2026, 5, 19),
        itemIds: [itemId],
        costCents: 10000,
        mileageKm: 9000,
        sync: sync,
      ),
    );
    expect((await repository.listCars()).single.currentMileageKm, 10000);
    expect(
      (await database.select(database.cars).get()).single.updatedAt,
      initialUpdatedAt,
    );

    await repository.saveMaintenanceRecord(
      MaintenanceRecord(
        carId: carId,
        date: const LocalDate(2026, 6, 19),
        itemIds: [itemId],
        costCents: 10000,
        mileageKm: 13000,
        sync: sync,
      ),
    );
    expect((await repository.listCars()).single.currentMileageKm, 13000);
    expect(
      (await database.select(database.cars).get()).single.updatedAt,
      isNot(initialUpdatedAt),
    );
  });

  test('delete car removes related local records and items', () async {
    final (carId, itemId) = await seedCarAndItem();
    await repository.setAppliedCarId(carId);
    await repository.saveMaintenanceRecord(
      MaintenanceRecord(
        carId: carId,
        date: const LocalDate(2026, 5, 19),
        itemIds: [itemId],
        costCents: 10000,
        mileageKm: 12000,
        sync: sync,
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
    final (carId, _) = await seedCarAndItem();

    expect(
      () => repository.saveMaintenanceRecord(
        MaintenanceRecord(
          carId: carId,
          date: const LocalDate(2026, 5, 19),
          itemIds: const [999],
          costCents: 10000,
          mileageKm: 12000,
          sync: sync,
        ),
      ),
      throwsArgumentError,
    );
  });

  test('record rejects items from another car', () async {
    final (carId, _) = await seedCarAndItem();
    final otherCarId = await createCar(repository, 
      Car(
        brand: '日产',
        model: '22款轩逸',
        currentMileageKm: 10000,
        roadDate: const LocalDate(2024, 1, 1),
        sync: sync,
      ),
    );
    final otherItemId = await repository.saveMaintenanceItem(
      MaintenanceItem(
        carsId: otherCarId,
        name: '空调滤芯',
        enabled: true,
        remindByMileage: true,
        remindByTime: true,
        mileageIntervalKm: 20000,
        timeIntervalMonths: 12,
        sortOrder: 1,
        sync: sync,
      ),
    );

    expect(
      () => repository.saveMaintenanceRecord(
        MaintenanceRecord(
          carId: carId,
          date: const LocalDate(2026, 5, 19),
          itemIds: [otherItemId],
          costCents: 10000,
          mileageKm: 12000,
          sync: sync,
        ),
      ),
      throwsArgumentError,
    );
  });

  test('updates maintenance item settings', () async {
    final (carId, itemId) = await seedCarAndItem();

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
    final (_, itemId) = await seedCarAndItem();

    expect(
      () => repository.setMaintenanceItemEnabled(
        itemId: itemId,
        enabled: false,
        sync: sync,
      ),
      throwsArgumentError,
    );
  });

  test('deletes custom item without history', () async {
    final (carId, _) = await seedCarAndItem();
    final customItemId = await repository.saveMaintenanceItem(
      MaintenanceItem(
        carsId: carId,
        name: '玻璃水',
        enabled: true,
        remindByMileage: true,
        remindByTime: false,
        mileageIntervalKm: 3000,
        sortOrder: 2,
        sync: sync,
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
    final (carId, itemId) = await seedCarAndItem();
    await repository.saveMaintenanceItem(
      MaintenanceItem(
        carsId: carId,
        name: '机滤',
        enabled: true,
        remindByMileage: true,
        remindByTime: false,
        mileageIntervalKm: 5000,
        sortOrder: 2,
        sync: sync,
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
    final (carId, itemId) = await seedCarAndItem();
    final customItemId = await repository.saveMaintenanceItem(
      MaintenanceItem(
        carsId: carId,
        name: '玻璃水',
        enabled: true,
        remindByMileage: true,
        remindByTime: false,
        mileageIntervalKm: 3000,
        sortOrder: 2,
        sync: sync,
      ),
    );
    await repository.saveMaintenanceRecord(
      MaintenanceRecord(
        carId: carId,
        date: const LocalDate(2026, 5, 19),
        itemIds: [itemId],
        costCents: 1000,
        mileageKm: 12000,
        sync: sync,
      ),
    );

    expect(() => repository.deleteMaintenanceItem(itemId), throwsArgumentError);
    await repository.deleteMaintenanceItem(customItemId);
  });

  test('backup export and restore round-trips database content', () async {
    final (carId, itemId) = await seedCarAndItem();
    await repository.setAppliedCarId(carId);
    await repository.setPreferenceValue('manualDateEnabled', 'true');
    await repository.setPreferenceValue('manualDate', '2026-05-23');
    await repository.saveVehicleDefaultMaintenanceItem(
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
      MaintenanceRecord(
        carId: carId,
        date: const LocalDate(2026, 5, 19),
        itemIds: [itemId],
        costCents: 10000,
        mileageKm: 12000,
        sync: sync,
      ),
    );

    final backup = await repository.exportBackupPayload();
    expect(const BackupCodec().encode(backup), isNot(contains('preferences')));
    expect(
      const BackupCodec().encode(backup),
      isNot(contains('defaultMaintenanceItems')),
    );
    expect(const BackupCodec().encode(backup), isNot(contains('isDefault')));
    await database.close();
    database = AppDatabase.inMemory();
    repository = LunioRepository(
      database,
      loadBuiltInVehicleCatalog: () async => builtInCatalog,
    );
    // 恢复前在本地写入偏好：主题/手动日期/停车倒计时应跨恢复保留（R2 口径），
    // 提醒抑制键（snooze）应被恢复清除。
    await repository.setPreferenceValue('themeMode', 'dark');
    await repository.setPreferenceValue('manualDate', '2026-05-23');
    await repository.saveParkingCountdown(
      ParkingCountdown(
        startedAt: DateTime(2026, 6, 10, 10, 20, 15),
        durationSeconds: 1800,
      ),
    );
    await repository.setPreferenceValue(
      '${LunioRepository.maintenanceReminderSnoozedUntilPrefix}42',
      '2026-06-01',
    );
    await repository.setPreferenceValue(
      '${LunioRepository.mileageUpdateInAppAcknowledgedOnPrefix}42',
      '2026-05-23',
    );

    await repository.restoreBackupPayload(backup);

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
    expect(await repository.getAppliedCarId(), '${restoredCar.id}');
    // 偏好保留：恢复只替换三类业务数据。
    expect(await repository.getPreferenceValue('themeMode'), 'dark');
    expect(await repository.getPreferenceValue('manualDate'), '2026-05-23');
    expect(
      await repository.getParkingCountdown(),
      ParkingCountdown(
        startedAt: DateTime(2026, 6, 10, 10, 20, 15),
        durationSeconds: 1800,
      ),
    );
    // 提醒抑制键按前缀清除：恢复出的车/项目是全新 id，旧抑制不再生效。
    expect(
      await repository.getPreferenceValue(
        '${LunioRepository.maintenanceReminderSnoozedUntilPrefix}42',
      ),
      isNull,
    );
    expect(
      await repository.getPreferenceValue(
        '${LunioRepository.mileageUpdateInAppAcknowledgedOnPrefix}42',
      ),
      isNull,
    );
  });

  test('backup restore rejects tampered business data before writing', () async {
    final (carId, itemId) = await seedCarAndItem();
    final backup = await repository.exportBackupPayload();
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

    expect(
      () => repository.restoreBackupPayload(negativeCost),
      throwsArgumentError,
    );
    expect(
      () => repository.restoreBackupPayload(negativeMileage),
      throwsArgumentError,
    );
    expect(
      () => repository.restoreBackupPayload(emptyItemIds),
      throwsArgumentError,
    );
    expect(
      () => repository.restoreBackupPayload(invalidItemInterval),
      throwsArgumentError,
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

  test('parking countdown is temporary preference outside backup', () async {
    final countdown = ParkingCountdown(
      startedAt: DateTime(2026, 6, 10, 10, 20, 15),
      durationSeconds: 1800,
    );

    await repository.saveParkingCountdown(countdown);

    expect(await repository.getParkingCountdown(), countdown);
    expect(
      await repository.getPreferenceValue('parkingCountdown'),
      contains('"durationSeconds":1800'),
    );
    final backup = await repository.exportBackupPayload();
    expect(const BackupCodec().encode(backup), isNot(contains('parking')));

    await repository.clearParkingCountdown();

    expect(await repository.getParkingCountdown(), isNull);
  });

  test(
    'backup restore tolerates bootstrapped default items after clearing data',
    () async {
      final (carId, _) = await seedCarAndItem();
      await repository.setAppliedCarId(carId);
      await repository.ensureDefaultMaintenanceItems();
      final backup = await repository.exportBackupPayload();

      await repository.clearAllData();
      await repository.ensureDefaultMaintenanceItems();

      await repository.restoreBackupPayload(backup);

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
    final (existingCarId, _) = await seedCarAndItem();
    await repository.setAppliedCarId(existingCarId);
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

    await repository.restoreBackupPayload(backup);

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
    expect(await repository.getAppliedCarId(), '${cars.single.id}');
  });

  test(
    'backup restore rejects invalid references before replacing data',
    () async {
      await seedCarAndItem();
      final backup = await repository.exportBackupPayload();
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
        () => repository.restoreBackupPayload(invalid),
        throwsArgumentError,
      );
      expect(await database.select(database.cars).get(), hasLength(1));
    },
  );

  test('backup restore rejects record items from another car', () async {
    final (carId, _) = await seedCarAndItem();
    final otherCarId = await createCar(repository, 
      Car(
        brand: '日产',
        model: '22款轩逸',
        currentMileageKm: 10000,
        roadDate: const LocalDate(2024, 1, 1),
        sync: sync,
      ),
    );
    final otherItemId = await repository.saveMaintenanceItem(
      MaintenanceItem(
        carsId: otherCarId,
        name: '空调滤芯',
        enabled: true,
        remindByMileage: true,
        remindByTime: true,
        mileageIntervalKm: 20000,
        timeIntervalMonths: 12,
        sortOrder: 1,
        sync: sync,
      ),
    );
    final backup = await repository.exportBackupPayload();
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

    expect(() => repository.restoreBackupPayload(invalid), throwsArgumentError);
  });

  test('clear all data removes local rows', () async {
    final (carId, itemId) = await seedCarAndItem();
    await repository.setAppliedCarId(carId);
    await repository.setPreferenceValue('manualDateEnabled', 'true');
    await repository.ensureBootstrapData();
    final defaultItemsBeforeClear = await database
        .select(database.vehicleDefaultMaintenanceItems)
        .get();
    final vehicleModelsBeforeClear = await database
        .select(database.vehicleModels)
        .get();
    expect(defaultItemsBeforeClear, isNotEmpty);
    expect(vehicleModelsBeforeClear, isNotEmpty);
    await repository.saveMaintenanceRecord(
      MaintenanceRecord(
        carId: carId,
        date: const LocalDate(2026, 5, 19),
        itemIds: [itemId],
        costCents: 10000,
        mileageKm: 12000,
        sync: sync,
      ),
    );

    await repository.clearAllData();

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
    final (carId, _) = await seedCarAndItem();
    await repository.setAppliedCarId(carId);
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

    expect(() => repository.restoreBackupPayload(invalid), throwsA(anything));
    expect(await database.select(database.cars).get(), hasLength(1));
    expect(await repository.getAppliedCarId(), '$carId');
  });
}

List<String> _defaultItemRules(List<VehicleDefaultMaintenanceItem> items) {
  return [
    for (final item in items)
      '${item.itemName}|${item.remindByMileage}|${item.remindByTime}|'
          '${item.mileageIntervalKm}|${item.timeIntervalMonths}',
  ];
}

const _genericFuelRules = [
  '机油|true|true|5000|6',
  '机滤|true|true|5000|6',
  '空气滤芯|true|true|20000|12',
  '空调滤芯|true|true|20000|12',
  '汽油滤芯|true|false|40000|null',
  '刹车油|true|true|40000|24',
  '变速箱油|true|true|60000|36',
  '火花塞|true|false|100000|null',
  '轮胎换位|true|false|10000|null',
  '防冻液|true|true|40000|24',
];

const _genericHybridRules = [..._genericFuelRules, '混动系统检查|true|true|20000|12'];

const _genericPlugInRules = [
  '机油|true|true|10000|12',
  '机滤|true|true|10000|12',
  '空气滤芯|true|true|20000|12',
  '空调滤芯|true|true|20000|12',
  '刹车油|true|true|40000|24',
  '防冻液|true|true|40000|24',
  '火花塞|true|false|100000|null',
  '轮胎换位|true|false|10000|null',
  '动力电池/电驱系统检查|true|true|20000|12',
];

const _genericEvRules = [
  '空调滤芯|true|true|20000|12',
  '刹车油|true|true|40000|24',
  '减速器油|true|true|60000|36',
  '电驱冷却液|true|true|40000|24',
  '动力电池/高压系统检查|true|true|20000|12',
  '制动系统检查|true|true|10000|12',
  '轮胎换位|true|false|10000|null',
];
