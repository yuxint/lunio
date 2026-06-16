import 'package:flutter_test/flutter_test.dart';
import 'package:lunio/core/date/local_date.dart';
import 'package:lunio/data/backup/backup_codec.dart';
import 'package:lunio/data/database/app_database.dart';
import 'package:lunio/data/repositories/lunio_repository.dart';
import 'package:lunio/domain/entities/car.dart';
import 'package:lunio/domain/entities/maintenance_item.dart';
import 'package:lunio/domain/entities/maintenance_record.dart';
import 'package:lunio/domain/entities/parking_countdown.dart';
import 'package:lunio/domain/entities/sync_metadata.dart';
import 'package:lunio/domain/entities/vehicle_default_maintenance_item.dart';

void main() {
  late AppDatabase database;
  late LunioRepository repository;
  late SyncMetadata sync;

  setUp(() {
    database = AppDatabase.inMemory();
    repository = LunioRepository(database);
    sync = SyncMetadata(status: SyncStatus.synced, updatedAt: DateTime(2026));
  });

  tearDown(() async {
    await database.close();
  });

  Future<(int, int)> seedCarAndItem() async {
    final carId = await repository.createCar(
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

  test('allows same brand and model with different road dates', () async {
    await repository.createCar(
      Car(
        brand: '本田',
        model: '思域（燃油版）',
        currentMileageKm: 10000,
        roadDate: const LocalDate(2021, 10, 31),
        sync: sync,
      ),
    );
    await repository.createCar(
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

    await repository.createCar(car);

    expect(repository.createCar(car), throwsA(isA<Object>()));
  });

  test(
    'create car copies default maintenance items and applies first car',
    () async {
      await repository.ensureDefaultMaintenanceItems();

      final carId = await repository.createCarWithDefaultItems(
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
        containsAll(['燃油宝', '机油', '机滤', '空调滤芯']),
      );
      expect(items, hasLength(14));
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
    'bootstraps default maintenance items for common model templates',
    () async {
      await repository.ensureDefaultMaintenanceItems();

      final civicItems = await repository.listDefaultItemsForModel(
        brand: '本田',
        model: '思域（燃油版）',
      );
      final sylphyItems = await repository.listDefaultItemsForModel(
        brand: '东风日产',
        model: '轩逸（燃油版）',
      );
      final corollaItems = await repository.listDefaultItemsForModel(
        brand: '一汽丰田',
        model: '卡罗拉（燃油版）',
      );
      final modelYItems = await repository.listDefaultItemsForModel(
        brand: '特斯拉',
        model: 'Model Y（纯电版）',
      );
      final qinLItems = await repository.listDefaultItemsForModel(
        brand: '比亚迪',
        model: '秦 L（插混版）',
      );
      final camryHybridItems = await repository.listDefaultItemsForModel(
        brand: '广汽丰田',
        model: '凯美瑞（混动版）',
      );

      expect(_defaultItemRules(civicItems), [
        '燃油宝|true|false|5000|null',
        '机油|true|true|5000|6',
        '机滤|true|true|5000|6',
        '空调滤芯|true|true|20000|12',
        '空气滤芯|true|false|20000|null',
        '变速箱油|true|true|40000|24',
        '刹车油|false|true|null|36',
        '火花塞|true|false|100000|null',
        '检查传动皮带|true|true|40000|24',
        '检查气门间隙|true|false|120000|null',
        '检查刹车|true|false|120000|null',
        '防冻液|true|true|200000|120',
        '汽油滤芯|true|false|140000|null',
        '轮胎换位|true|false|10000|null',
      ]);
      expect(_defaultItemRules(sylphyItems), _genericFuelRules);
      expect(_defaultItemRules(corollaItems), _genericFuelRules);
      expect(_defaultItemRules(modelYItems), _genericEvRules);
      expect(_defaultItemRules(qinLItems), _genericPlugInRules);
      expect(_defaultItemRules(camryHybridItems), _genericHybridRules);
    },
  );

  test('bootstrap does not rebuild existing default template rows', () async {
    await repository.saveVehicleDefaultMaintenanceItem(
      VehicleDefaultMaintenanceItem(
        vehicleBrand: '东风日产',
        vehicleModel: '轩逸（燃油版）',
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

    final items = await repository.listDefaultItemsForModel(
      brand: '东风日产',
      model: '轩逸（燃油版）',
    );
    final oilItems = items.where((item) => item.itemName == '机油');
    expect(oilItems, hasLength(1));
    expect(_defaultItemRules(oilItems.toList()), ['机油|true|true|3000|3']);
  });

  test('pure electric templates do not include fuel service items', () async {
    await repository.ensureDefaultMaintenanceItems();

    final items = await repository.listDefaultItemsForModel(
      brand: '小米',
      model: 'SU7（纯电版）',
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

    expect(
      models.map((model) => '${model.brand} ${model.model}'),
      containsAll([
        '本田 思域（燃油版）',
        '东风日产 轩逸（燃油版）',
        '一汽丰田 卡罗拉（燃油版）',
        '比亚迪 秦 PLUS（插混版）',
        '吉利银河 星愿（纯电版）',
        '奇瑞 瑞虎 8（燃油版）',
        '长安 CS75 PLUS（燃油版）',
        '哈弗 H6（燃油版）',
        '特斯拉 Model 3（纯电版）',
        '理想 L6（增程版）',
        '问界 M8（增程版）',
        '一汽-大众 速腾（燃油版）',
        '广汽丰田 凯美瑞（混动版）',
        '上汽通用别克 GL8（燃油版）',
        '华晨宝马 3 系（燃油版）',
      ]),
    );
    expect(models.length, greaterThan(120));
  });

  test('writes snowflake ids for all local tables', () async {
    await repository.ensureBootstrapData();
    final carId = await repository.createCarWithDefaultItems(
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

    expect(models.map((model) => '${model.brand} ${model.model}'), [
      '本田 思域（燃油版）',
      '本田 思域（混动版）',
      '东风日产 轩逸（燃油版）',
      '东风日产 轩逸（混动版）',
      '一汽丰田 卡罗拉（燃油版）',
      '一汽丰田 卡罗拉（混动版）',
      '广汽丰田 凯美瑞（燃油版）',
      '广汽丰田 凯美瑞（混动版）',
      '广汽丰田 汉兰达（混动版）',
      '广汽丰田 赛那（混动版）',
      '广汽丰田 威兰达（燃油版）',
      '广汽丰田 威兰达（混动版）',
      '一汽丰田 RAV4 荣放（燃油版）',
      '一汽丰田 RAV4 荣放（混动版）',
      '一汽丰田 格瑞维亚（混动版）',
      '本田 雅阁（燃油版）',
      '本田 雅阁（混动版）',
      '本田 CR-V（燃油版）',
      '本田 CR-V（混动版）',
      '本田 皓影（燃油版）',
      '本田 皓影（混动版）',
      '东风日产 天籁（燃油版）',
      '东风日产 逍客（燃油版）',
      '一汽-大众 速腾（燃油版）',
      '一汽-大众 迈腾（燃油版）',
      '一汽-大众 探岳（燃油版）',
      '上汽大众 朗逸（燃油版）',
      '上汽大众 帕萨特（燃油版）',
      '上汽大众 帕萨特（插混版）',
      '上汽大众 途观 L（燃油版）',
      '上汽大众 途观 L（插混版）',
      '上汽通用别克 GL8（燃油版）',
      '上汽通用别克 GL8（插混版）',
      '上汽通用别克 昂科威（燃油版）',
      '长安福特 蒙迪欧（燃油版）',
      '长安福特 锐界 L（混动版）',
      '北京现代 伊兰特（燃油版）',
      '比亚迪 海鸥（纯电版）',
      '比亚迪 海豚（纯电版）',
      '比亚迪 秦 PLUS（插混版）',
      '比亚迪 秦 PLUS（纯电版）',
      '比亚迪 秦 L（插混版）',
      '比亚迪 海豹 06（插混版）',
      '比亚迪 汉（插混版）',
      '比亚迪 汉（纯电版）',
      '比亚迪 宋 PLUS（插混版）',
      '比亚迪 宋 PLUS（纯电版）',
      '比亚迪 宋 Pro（插混版）',
      '比亚迪 元 UP（纯电版）',
      '比亚迪 元 PLUS（纯电版）',
      '比亚迪 唐（插混版）',
      '腾势 D9（插混版）',
      '腾势 D9（纯电版）',
      '方程豹 豹 5（插混版）',
      '吉利银河 星愿（纯电版）',
      '吉利银河 L6（插混版）',
      '吉利银河 L7（插混版）',
      '吉利银河 E5（纯电版）',
      '吉利 帝豪（燃油版）',
      '吉利 星瑞（燃油版）',
      '吉利 缤越（燃油版）',
      '吉利 博越 L（燃油版）',
      '吉利 星越 L（燃油版）',
      '吉利 星越 L（混动版）',
      '领克 03（燃油版）',
      '领克 08（插混版）',
      '极氪 001（纯电版）',
      '极氪 007（纯电版）',
      '极氪 7X（纯电版）',
      '奇瑞 艾瑞泽 8（燃油版）',
      '奇瑞 瑞虎 7（燃油版）',
      '奇瑞 瑞虎 8（燃油版）',
      '奇瑞 瑞虎 9（燃油版）',
      '奇瑞风云 A8（插混版）',
      '奇瑞风云 T9（插混版）',
      '捷途 X70（燃油版）',
      '捷途 旅行者（燃油版）',
      '捷途山海 L7（插混版）',
      '星途 瑶光（燃油版）',
      '长安 逸动（燃油版）',
      '长安 CS75 PLUS（燃油版）',
      '长安 UNI-V（燃油版）',
      '长安 UNI-Z（插混版）',
      '长安启源 A05（插混版）',
      '长安启源 A07（插混版）',
      '深蓝 S05（纯电版）',
      '深蓝 S07（增程版）',
      '深蓝 L07（增程版）',
      '阿维塔 07（增程版）',
      '阿维塔 11（纯电版）',
      '阿维塔 12（纯电版）',
      '哈弗 H6（燃油版）',
      '哈弗 H6（插混版）',
      '哈弗 大狗（燃油版）',
      '坦克 300（燃油版）',
      '坦克 500（插混版）',
      '魏牌 高山（插混版）',
      '五菱 宏光 MINIEV（纯电版）',
      '五菱 缤果（纯电版）',
      '五菱 星光（插混版）',
      '宝骏 云朵（纯电版）',
      '红旗 H5（燃油版）',
      '红旗 HS5（燃油版）',
      '荣威 D7（插混版）',
      '荣威 RX5（燃油版）',
      'MG MG4（纯电版）',
      'MG ZS（燃油版）',
      '广汽传祺 M8（燃油版）',
      '广汽传祺 E8（插混版）',
      '广汽传祺 GS4（燃油版）',
      '广汽埃安 AION Y（纯电版）',
      '广汽埃安 AION S（纯电版）',
      '广汽埃安 AION V（纯电版）',
      '东风风神 皓瀚（燃油版）',
      '东风奕派 eπ007（增程版）',
      '岚图 梦想家（插混版）',
      '岚图 梦想家（纯电版）',
      '岚图 FREE（增程版）',
      '零跑 A10（纯电版）',
      '零跑 C10（纯电版）',
      '零跑 C10（增程版）',
      '零跑 C11（增程版）',
      '零跑 C16（增程版）',
      '理想 L6（增程版）',
      '理想 L7（增程版）',
      '理想 L8（增程版）',
      '蔚来 ES6（纯电版）',
      '蔚来 ET5（纯电版）',
      '乐道 L60（纯电版）',
      '小鹏 MONA M03（纯电版）',
      '小鹏 P7（纯电版）',
      '小鹏 G6（纯电版）',
      '小鹏 X9（纯电版）',
      '小米 SU7（纯电版）',
      '小米 YU7（纯电版）',
      '问界 M8（增程版）',
      '问界 M8（纯电版）',
      '问界 M9（增程版）',
      '智界 R7（纯电版）',
      '享界 S9（纯电版）',
      '极狐 阿尔法 T5（纯电版）',
      '特斯拉 Model 3（纯电版）',
      '特斯拉 Model Y（纯电版）',
      '华晨宝马 3 系（燃油版）',
      '华晨宝马 5 系（燃油版）',
      '华晨宝马 X3（燃油版）',
      '华晨宝马 i3（纯电版）',
      '北京奔驰 C 级（燃油版）',
      '北京奔驰 E 级（燃油版）',
      '北京奔驰 GLC（燃油版）',
      '一汽奥迪 A4L（燃油版）',
      '一汽奥迪 A6L（燃油版）',
      '一汽奥迪 Q5L（燃油版）',
      '凯迪拉克 CT5（燃油版）',
      '沃尔沃 XC60（燃油版）',
      '雷克萨斯 ES（混动版）',
      '路虎 发现运动版（燃油版）',
    ]);
  });

  test('applied car falls back to first available car', () async {
    final firstCarId = await repository.createCar(
      Car(
        brand: '本田',
        model: '22款思域',
        currentMileageKm: 10000,
        roadDate: const LocalDate(2023, 8, 12),
        sync: sync,
      ),
    );
    await repository.createCar(
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
    final firstCarId = await repository.createCar(
      Car(
        brand: '本田',
        model: '22款思域',
        currentMileageKm: 10000,
        roadDate: const LocalDate(2023, 8, 12),
        sync: sync,
      ),
    );
    await repository.createCar(
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
    final carId = await repository.createCar(
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
    final firstCarId = await repository.createCar(
      Car(
        brand: '本田',
        model: '22款思域',
        currentMileageKm: 10000,
        roadDate: const LocalDate(2023, 8, 12),
        sync: sync,
      ),
    );
    final secondCarId = await repository.createCar(
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
    final otherCarId = await repository.createCar(
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
        vehicleBrand: '本田',
        vehicleModel: '22款思域',
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
    expect(const BackupCodec().encode(backup), isNot(contains('isDefault')));
    await database.close();
    database = AppDatabase.inMemory();
    repository = LunioRepository(database);

    await repository.restoreBackupPayload(backup);

    expect(await database.select(database.cars).get(), hasLength(1));
    expect(
      await database.select(database.vehicleDefaultMaintenanceItems).get(),
      hasLength(1),
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
    expect(await repository.getPreferenceValue('manualDate'), isNull);
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
        hasLength(backup.defaultMaintenanceItems.length),
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
      schemaVersion: 2,
      cars: [
        Car(
          id: 99,
          brand: '日产',
          model: '22款轩逸',
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
    expect(cars.single.brand, '日产');
    expect(cars.single.model, '22款轩逸');
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
        schemaVersion: 2,
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
    final otherCarId = await repository.createCar(
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
      schemaVersion: 2,
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
    await repository.ensureDefaultMaintenanceItems();
    final defaultItemsBeforeClear = await database
        .select(database.vehicleDefaultMaintenanceItems)
        .get();
    expect(defaultItemsBeforeClear, isNotEmpty);
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
    expect(await database.select(database.vehicleModels).get(), isEmpty);
  });

  test('backup restore rolls back when unique constraints fail', () async {
    final (carId, _) = await seedCarAndItem();
    await repository.setAppliedCarId(carId);
    final invalid = BackupPayload(
      schemaVersion: 2,
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
