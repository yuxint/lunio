// 车型目录与默认模板数据层测试：目录 JSON 校验、按动力类型/车型专属
// 模板解析、bootstrap 对账（幂等灌库/旧行认领/目录删除不碰车辆项目）。
// 2026-09-26 测试夹具收编② 自 database_test.dart 按域拆出（先例：widget
// 测试按域拆分）；仓库装配统一走 widget_app 的 TestRepositories。
import 'package:flutter_test/flutter_test.dart';
import 'package:lunio/core/date/local_date.dart';
import 'package:lunio/data/bootstrap/built_in_vehicle_catalog.dart';
import 'package:lunio/data/database/app_database.dart';
import 'package:lunio/data/preferences/app_preferences.dart';
import 'package:lunio/data/repositories/built_in_catalog_repository.dart';
import 'package:lunio/data/repositories/lunio_repository.dart';
import 'package:lunio/domain/entities/powertrain_type.dart';
import 'package:lunio/domain/entities/sync_metadata.dart';
import 'package:lunio/domain/entities/vehicle_default_maintenance_item.dart';
import 'package:lunio/domain/entities/vehicle_model.dart';

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
    sync = repos.sync;
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
  test(
    'create car copies default maintenance items and applies first car',
    () async {
      await catalogRepository.ensureDefaultMaintenanceItems();

      final carId = await createCarWithDefaultItems(database, defaultCar(model: '思域（燃油版）'),
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
      expect(await preferences.getAppliedCarId(), carId);
    },
  );

  test(
    'bootstraps default maintenance items per powertrain type',
    () async {
      await catalogRepository.ensureDefaultMaintenanceItems();

      final fuelItems = await catalogRepository.listDefaultItemsForPowertrain(
        powertrainType: PowertrainType.fuel,
      );
      final hybridItems = await catalogRepository.listDefaultItemsForPowertrain(
        powertrainType: PowertrainType.hybrid,
      );
      final plugInItems = await catalogRepository.listDefaultItemsForPowertrain(
        powertrainType: PowertrainType.plugIn,
      );
      final extendedItems = await catalogRepository.listDefaultItemsForPowertrain(
        powertrainType: PowertrainType.extendedRange,
      );
      final evItems = await catalogRepository.listDefaultItemsForPowertrain(
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
    await catalogRepository.ensureDefaultMaintenanceItems();

    // 目录解析：思域条目带 itemTemplate，civicFuel 组 14 项、首项燃油宝。
    final civic = builtInCatalog.findVehicle('本田', '思域');
    expect(civic, isNotNull);
    expect(civic!.itemTemplate, 'civicFuel');
    final civicTemplate = builtInCatalog.vehicleTemplateItems('civicFuel');
    expect(civicTemplate, hasLength(14));
    expect(civicTemplate!.first.name, '燃油宝');

    // 仓库按（品牌+车型+推荐动力类型一致）返回专属模板。
    final items = await catalogRepository.listDefaultItemsForVehicleModel(
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
    final fuelItems = await catalogRepository.listDefaultItemsForPowertrain(
      powertrainType: PowertrainType.fuel,
    );
    expect(fuelItems, hasLength(10));
    expect(fuelItems.any((item) => item.itemName == '燃油宝'), isFalse);
  });

  test('vehicle-specific template falls back when rules not met', () async {
    // 改选其他动力类型：专属模板不适用，返回 null（向导回退通用模板）。
    expect(
      await catalogRepository.listDefaultItemsForVehicleModel(
        brand: '本田',
        model: '思域',
        selectedPowertrain: PowertrainType.electric,
      ),
      isNull,
    );
    // 目录里没有专属模板的车型（本田 型格）→ null。
    expect(
      await catalogRepository.listDefaultItemsForVehicleModel(
        brand: '本田',
        model: '型格',
        selectedPowertrain: PowertrainType.fuel,
      ),
      isNull,
    );
    // 非目录自定义车型 → null。
    expect(
      await catalogRepository.listDefaultItemsForVehicleModel(
        brand: '自定义',
        model: '手工车',
        selectedPowertrain: PowertrainType.fuel,
      ),
      isNull,
    );
  });

  test('resolveDefaultItems composes bootstrap, specific-first, fallback', () async {
    // 解析唯一入口自带 bootstrap 对账（上面两个用例先手动 ensure，
    // 这个用例不 ensure，验证 resolveDefaultItems 自己完成灌库）。
    // 专属命中：思域 + 燃油（与目录推荐一致）→ civicFuel 14 项。
    final civic = await catalogRepository.resolveDefaultItems(
      brand: '本田',
      model: '思域',
      selectedPowertrain: PowertrainType.fuel,
    );
    expect(civic, hasLength(14));
    expect(civic.first.itemName, '燃油宝');

    // 专属未命中（改选纯电，与推荐不一致）→ 回退纯电通用组（7 项）。
    final evFallback = await catalogRepository.resolveDefaultItems(
      brand: '本田',
      model: '思域',
      selectedPowertrain: PowertrainType.electric,
    );
    expect(evFallback, hasLength(7));
    expect(evFallback.any((item) => item.itemName == '燃油宝'), isFalse);

    // 非目录车型 → 回退燃油通用组（10 项）。
    final fuelFallback = await catalogRepository.resolveDefaultItems(
      brand: '自定义',
      model: '手工车',
      selectedPowertrain: PowertrainType.fuel,
    );
    expect(fuelFallback, hasLength(10));
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
    await catalogRepository.saveVehicleDefaultMaintenanceItem(
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

    await catalogRepository.ensureDefaultMaintenanceItems();

    final items = await catalogRepository.listDefaultItemsForPowertrain(
      powertrainType: PowertrainType.fuel,
    );
    final oilItems = items.where((item) => item.itemName == '机油');
    expect(oilItems, hasLength(1));
    expect(_defaultItemRules(oilItems.toList()), ['机油|true|true|5000|6']);
  });

  test(
    'bootstrap adopts legacy built-in rows and updates them by catalog id',
    () async {
      await catalogRepository.saveVehicleModel(
        VehicleModel(
          brand: '日产',
          model: '轩逸',
          template: PowertrainType.fuel,
          sortOrder: 99,
          sync: sync,
        ),
      );
      await catalogRepository.saveVehicleDefaultMaintenanceItem(
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
      await BuiltInCatalogRepository(
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
      await BuiltInCatalogRepository(
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
      final seedCatalogRepository = BuiltInCatalogRepository(
        database,
        loadBuiltInVehicleCatalog: () async => initialCatalog,
      );
      await seedCatalogRepository.ensureBootstrapData();
      await catalogRepository.saveVehicleModel(
        VehicleModel(
          brand: '自定义品牌',
          model: '自定义车型',
          template: PowertrainType.fuel,
          sortOrder: 1,
          sync: sync,
        ),
      );
      await catalogRepository.saveVehicleDefaultMaintenanceItem(
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
      final carId = await createCarWithDefaultItems(database, defaultCar(
          brand: '日产',
          model: '轩逸（燃油版）',
          roadDate: const LocalDate(2024, 1, 1),
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
      await BuiltInCatalogRepository(
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
    await catalogRepository.ensureDefaultMaintenanceItems();

    final items = await catalogRepository.listDefaultItemsForPowertrain(
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
    await catalogRepository.ensureVehicleModels();

    final models = await catalogRepository.listVehicleModels();

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
    await catalogRepository.saveVehicleModel(
      VehicleModel(
        brand: '东风日产',
        model: '轩逸',
        template: PowertrainType.fuel,
        sortOrder: 1,
        sync: sync,
      ),
    );

    await catalogRepository.ensureBootstrapData();

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
    final oldCarId = await repos.insertCarForTest(defaultCar(
        brand: '东风日产',
        model: '轩逸（燃油版）',
        currentMileageKm: 15000,
        roadDate: const LocalDate(2024, 1, 1),
      ),
    );
    await repos.insertCarForTest(defaultCar(
        brand: '日产',
        model: '轩逸（燃油版）',
        currentMileageKm: 20000,
        roadDate: const LocalDate(2024, 1, 1),
      ),
    );
    await preferences.setAppliedCarId(oldCarId);

    await catalogRepository.ensureBootstrapData();

    final cars = await repository.listCars();
    expect(cars, hasLength(2));
    expect(cars.map((car) => car.brand), containsAll(['东风日产', '日产']));
    expect(await preferences.getAppliedCarId(), oldCarId);
  });
  test('bootstraps selectable vehicle models', () async {
    await catalogRepository.ensureVehicleModels();

    final models = await catalogRepository.listVehicleModels();

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
