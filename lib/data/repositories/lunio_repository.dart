// 唯一 Repository（≈ Java 的 Service + DAO 合体）：全部数据库读写的出口。
//
// 职责：
//  - 行(Row) ↔ 领域实体(Entity) 映射（Row 是 Drift 生成类，Entity 是 domain/entities）；
//  - 事务编排（database.transaction ≈ Spring 的 @Transactional，闭包抛异常自动回滚）；
//  - 写前业务校验（调 RecordRules / 实体 validate / 内部 _ensureXxx）；
//  - bootstrap：把 asset 目录灌入两张内置表（幂等对账）；
//  - 偏好 KV 读写（app_preferences 表）、停车倒计时的存取；
//  - 备份导出/导入恢复（配合 backup_codec.dart）。
//
// 重要约定：
//  1. fail-fast：校验失败抛 ArgumentError / StateError，不吞异常；
//     部分面向用户的中文文案直接从这里抛出（见 _ensureRecordIsUnique）。
//  2. 本类**不做缓存失效**——写库后刷新 UI 缓存（invalidateXxxProviders）
//     是调用方（UI 层）的责任。
//  3. import as domain：给同名实体加命名空间，避免与 Drift 生成的 Row 类
//     同名冲突（≈ Java 里两个同名类用全限定名区分）。
import 'dart:convert';

import 'package:drift/drift.dart';

import '../../core/date/local_date.dart';
import '../../core/id/snowflake_id_generator.dart';
import '../../domain/entities/car.dart' as domain;
import '../../domain/entities/maintenance_item.dart' as domain;
import '../../domain/entities/maintenance_record.dart' as domain;
import '../../domain/entities/parking_countdown.dart' as domain;
import '../../domain/entities/sync_metadata.dart';
import '../../domain/entities/vehicle_default_maintenance_item.dart' as domain;
import '../../domain/entities/vehicle_model.dart' as domain;
import '../../domain/rules/applied_car_rules.dart';
import '../../domain/rules/record_rules.dart';
import '../backup/backup_codec.dart';
import '../bootstrap/built_in_vehicle_catalog.dart';
import '../database/app_database.dart';

class LunioRepository {
  /// 构造时注入数据库连接；目录加载器可选注入（测试可换成内存版本）。
  LunioRepository(
    this.database, {
    BuiltInVehicleCatalogLoader? loadBuiltInVehicleCatalog,
  }) : _loadBuiltInVehicleCatalog =
           loadBuiltInVehicleCatalog ?? loadBuiltInVehicleCatalogAsset;

  /// 停车倒计时在偏好表里的 key。
  static const _parkingCountdownPreferenceKey = 'parkingCountdown';

  /// 雪花 id 生成器（static：进程内唯一，保证所有表 id 不重复）。
  static final SnowflakeIdGenerator _idGenerator = SnowflakeIdGenerator();

  final AppDatabase database;
  final BuiltInVehicleCatalogLoader _loadBuiltInVehicleCatalog;

  /// 确保默认保养项目模板已入库（单独暴露给测试/特殊调用，一般走 ensureBootstrapData）。
  Future<void> ensureDefaultMaintenanceItems() async {
    final catalog = await _loadBuiltInVehicleCatalog();
    await _ensureDefaultMaintenanceItems(catalog);
  }

  /// 模板表幂等对账（事务内三步）：
  ///  1. 删除"目录里已不存在"的行（catalogId 不在目标集合）；
  ///  2. 逐条比对：没有则插入、字段有变化则更新（_defaultItemNeedsUpdate）；
  ///  3. 兼容老数据：catalogId 为 null 的旧行按"品牌+车型+项目名"匹配。
  /// 结果：库里的模板表与 asset 目录完全一致（升级 App 更新目录后自动同步）。
  Future<void> _ensureDefaultMaintenanceItems(
    BuiltInVehicleCatalog catalog,
  ) async {
    final sync = SyncMetadata(
      status: SyncStatus.synced,
      updatedAt: DateTime.now(),
    );
    final builtInItems = catalog.defaultMaintenanceItems(sync);
    final targetCatalogIds = builtInItems
        .map((item) => item.catalogId!)
        .toSet();
    await database.transaction(() async {
      await (database.delete(database.vehicleDefaultMaintenanceItems)..where(
            (row) =>
                row.catalogId.isNotNull() &
                row.catalogId.isNotIn(targetCatalogIds),
          ))
          .go();
      final existing = await database
          .select(database.vehicleDefaultMaintenanceItems)
          .get();
      final existingByCatalogId = {
        for (final row in existing)
          if (row.catalogId != null) row.catalogId!: row,
      };
      final existingByLegacyKey = {
        for (final row in existing)
          if (row.catalogId == null)
            _defaultItemKey(row.vehicleBrand, row.vehicleModel, row.itemName):
                row,
      };
      for (final item in builtInItems) {
        final existingRow =
            existingByCatalogId[item.catalogId] ??
            existingByLegacyKey[_defaultItemKey(
              item.vehicleBrand,
              item.vehicleModel,
              item.itemName,
            )];
        if (existingRow == null) {
          await saveVehicleDefaultMaintenanceItem(item);
        } else if (_defaultItemNeedsUpdate(existingRow, item)) {
          await _updateVehicleDefaultMaintenanceItem(existingRow.id, item);
        }
      }
    });
  }

  /// 确保车型目录已入库（同上，单独暴露）。
  Future<void> ensureVehicleModels() async {
    final catalog = await _loadBuiltInVehicleCatalog();
    await _ensureVehicleModels(catalog);
  }

  /// 车型表幂等对账，逻辑与 _ensureDefaultMaintenanceItems 同构。
  Future<void> _ensureVehicleModels(BuiltInVehicleCatalog catalog) async {
    final sync = SyncMetadata(
      status: SyncStatus.synced,
      updatedAt: DateTime.now(),
    );
    final builtInModels = catalog.vehicleModels(sync);
    final targetCatalogIds = builtInModels
        .map((model) => model.catalogId!)
        .toSet();
    await database.transaction(() async {
      await (database.delete(database.vehicleModels)..where(
            (row) =>
                row.catalogId.isNotNull() &
                row.catalogId.isNotIn(targetCatalogIds),
          ))
          .go();
      final existing = await database.select(database.vehicleModels).get();
      final existingByCatalogId = {
        for (final row in existing)
          if (row.catalogId != null) row.catalogId!: row,
      };
      final existingByLegacyKey = {
        for (final row in existing)
          if (row.catalogId == null)
            _vehicleModelKey(row.brand, row.model): row,
      };
      for (final model in builtInModels) {
        final existingRow =
            existingByCatalogId[model.catalogId] ??
            existingByLegacyKey[_vehicleModelKey(model.brand, model.model)];
        if (existingRow == null) {
          await saveVehicleModel(model);
        } else if (_vehicleModelNeedsUpdate(existingRow, model)) {
          await _updateVehicleModel(existingRow.id, model);
        }
      }
    });
  }

  /// 首启/升级引导总入口：车型目录 + 默认项目模板两张表各做一次幂等对账。
  /// 由 defaultMaintenanceBootstrapProvider（providers.dart）在 AppShell 首帧触发。
  /// 注意：目录 asset 会被加载 3 次（本方法 1 次 + 两个 ensure 各 1 次，无缓存）。
  Future<void> ensureBootstrapData() async {
    final catalog = await _loadBuiltInVehicleCatalog();
    await _ensureVehicleModels(catalog);
    await _ensureDefaultMaintenanceItems(catalog);
  }

  /// 单条插入车辆（无事务、无项目）。⚠ 近乎遗留 API：UI 实际都走
  /// createCarWithMaintenanceItems；测试在用。业务上不建议直接调用。
  Future<int> createCar(domain.Car car) async {
    final carId = _nextId();
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

  /// 用所选车型的默认模板创建车辆（模板 → 车辆级项目实例）。
  /// UI 不直接调用它（向导需要先让用户编辑草稿），主要供测试使用。
  Future<int> createCarWithDefaultItems(domain.Car car) async {
    final defaultItems = await listDefaultItemsForModel(
      brand: car.brand,
      model: car.model,
    );
    return createCarWithMaintenanceItems(
      car,
      defaultItems
          .map(
            (item) => domain.MaintenanceItem(
              carsId: 0,
              name: item.itemName,
              enabled: true,
              remindByMileage: item.remindByMileage,
              remindByTime: item.remindByTime,
              mileageIntervalKm: item.mileageIntervalKm,
              timeIntervalMonths: item.timeIntervalMonths,
              notOverdueUpperLimit: item.notOverdueUpperLimit,
              overdueUpperLimit: item.overdueUpperLimit,
              sortOrder: item.sortOrder,
              sync: car.sync,
            ),
          )
          .toList(),
    );
  }

  /// 创建车辆 + 一批保养项目（添加车辆向导"完成"按钮的落库入口）。
  ///
  /// 校验：至少一个启用项目；每个项目过实体 validate。
  /// 事务内：插车辆 → 逐条插项目 → 若当前无应用车辆（appliedCarId 为空）
  /// 则把新车设为应用车辆（首辆车自动成为当前车）。
  /// 任意一步失败整体回滚。返回新车辆 id。
  Future<int> createCarWithMaintenanceItems(
    domain.Car car,
    List<domain.MaintenanceItem> items,
  ) {
    if (!items.any((item) => item.enabled)) {
      throw ArgumentError('At least one maintenance item must stay enabled');
    }
    for (final item in items) {
      item.validate();
    }
    return database.transaction(() async {
      final carId = _nextId();
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

      for (final item in items) {
        final itemId = _nextId();
        await database
            .into(database.maintenanceItems)
            .insert(
              MaintenanceItemsCompanion.insert(
                id: Value(itemId),
                carsId: carId,
                name: item.name,
                enabled: Value(item.enabled),
                remindByMileage: item.remindByMileage,
                remindByTime: item.remindByTime,
                mileageIntervalKm: Value(item.mileageIntervalKm),
                timeIntervalMonths: Value(item.timeIntervalMonths),
                notOverdueUpperLimit: Value(item.notOverdueUpperLimit),
                overdueUpperLimit: Value(item.overdueUpperLimit),
                sortOrder: item.sortOrder,
                syncStatus: Value(item.sync.status.name),
                updatedAt: item.sync.updatedAt.toIso8601String(),
                version: Value(item.sync.version),
              ),
            );
      }

      final storedAppliedCarId = await _getAppliedCarIdInTransaction();
      if (storedAppliedCarId == null) {
        await _writeAppliedCarId(carId);
      }
      return carId;
    });
  }

  /// 全部车辆列表（无排序约束，全表扫描）。
  Future<List<domain.Car>> listCars() async {
    final rows = await database.select(database.cars).get();
    return rows.map(_carFromRow).toList();
  }

  /// 编辑车辆（只允许改里程/上路日期/sync；品牌型号是身份字段不可改，
  /// 因此 UI 的编辑表单不提供品牌车型输入）。id 为空抛错。
  Future<void> updateCar(domain.Car car) {
    final carId = car.id;
    if (carId == null) {
      throw ArgumentError('Car id is required');
    }
    return (database.update(
      database.cars,
    )..where((row) => row.id.equals(carId))).write(
      CarsCompanion(
        currentMileageKm: Value(car.currentMileageKm),
        roadDate: Value(car.roadDate.toString()),
        syncStatus: Value(car.sync.status.name),
        updatedAt: Value(car.sync.updatedAt.toIso8601String()),
        version: Value(car.sync.version),
      ),
    );
  }

  /// 读取当前应用车辆（提醒页/记录页展示的车）。
  ///
  /// 副作用方法（读路径里夹带写）：按 AppliedCarRules 解析后，如果结果与
  /// 偏好里存的不一致（如应用车辆被删除），会把修正值写回偏好。
  /// 无车时清空 appliedCarId 并返回 null。
  Future<domain.Car?> getAppliedCar() async {
    final cars = await listCars();
    final storedCarId = int.tryParse(await getAppliedCarId() ?? '');
    final appliedCarId = AppliedCarRules.resolveAppliedCarId(
      cars: cars,
      storedCarId: storedCarId,
    );
    if (appliedCarId == null) {
      await setAppliedCarId(null);
      return null;
    }
    if (appliedCarId != storedCarId) {
      await setAppliedCarId(appliedCarId);
    }
    return cars.firstWhere((car) => car.id == appliedCarId);
  }

  /// 删除车辆（事务级联删，无外键所以手工按序删）：
  /// 记录关联表 → 记录表 → 项目表 → appliedCarId 偏好（仅当指向本车）→ 车辆本身。
  /// 删完把应用车辆指向剩余第一辆；没有剩余则清空。
  Future<void> deleteCar(int carId) {
    return database.transaction(() async {
      await (database.delete(
        database.maintenanceRecordItems,
      )..where((row) => row.carId.equals(carId))).go();
      await (database.delete(
        database.maintenanceRecords,
      )..where((row) => row.carId.equals(carId))).go();
      await (database.delete(
        database.maintenanceItems,
      )..where((row) => row.carsId.equals(carId))).go();
      await (database.delete(database.appPreferences)..where(
            (row) =>
                row.key.equals('appliedCarId') & row.value.equals('$carId'),
          ))
          .go();
      await (database.delete(
        database.cars,
      )..where((row) => row.id.equals(carId))).go();
      final remainingCars = await database.select(database.cars).get();
      if (remainingCars.isEmpty) {
        await _writeAppliedCarId(null);
      } else {
        await _writeAppliedCarId(remainingCars.first.id);
      }
    });
  }

  /// 单条插入默认项目模板（bootstrap 对账用；生成的 id 自增雪花）。
  Future<int> saveVehicleDefaultMaintenanceItem(
    domain.VehicleDefaultMaintenanceItem item,
  ) async {
    final itemId = _nextId();
    await database
        .into(database.vehicleDefaultMaintenanceItems)
        .insert(
          VehicleDefaultMaintenanceItemsCompanion.insert(
            id: Value(itemId),
            catalogId: Value(item.catalogId),
            vehicleBrand: item.vehicleBrand,
            vehicleModel: item.vehicleModel,
            itemName: item.itemName,
            remindByMileage: item.remindByMileage,
            remindByTime: item.remindByTime,
            mileageIntervalKm: Value(item.mileageIntervalKm),
            timeIntervalMonths: Value(item.timeIntervalMonths),
            notOverdueUpperLimit: Value(item.notOverdueUpperLimit),
            overdueUpperLimit: Value(item.overdueUpperLimit),
            sortOrder: item.sortOrder,
            syncStatus: Value(item.sync.status.name),
            updatedAt: item.sync.updatedAt.toIso8601String(),
            version: Value(item.sync.version),
          ),
        );
    return itemId;
  }

  /// 单条插入车型（bootstrap 用）。
  Future<int> saveVehicleModel(domain.VehicleModel model) async {
    final modelId = _nextId();
    await database
        .into(database.vehicleModels)
        .insert(
          VehicleModelsCompanion.insert(
            id: Value(modelId),
            catalogId: Value(model.catalogId),
            brand: model.brand,
            model: model.model,
            sortOrder: model.sortOrder,
            syncStatus: Value(model.sync.status.name),
            updatedAt: model.sync.updatedAt.toIso8601String(),
            version: Value(model.sync.version),
          ),
        );
    return modelId;
  }

  /// 按新实体全量更新车型行（bootstrap 对账用）。
  Future<void> _updateVehicleModel(int id, domain.VehicleModel model) async {
    await (database.update(
      database.vehicleModels,
    )..where((row) => row.id.equals(id))).write(
      VehicleModelsCompanion(
        catalogId: Value(model.catalogId),
        brand: Value(model.brand),
        model: Value(model.model),
        sortOrder: Value(model.sortOrder),
        syncStatus: Value(model.sync.status.name),
        updatedAt: Value(model.sync.updatedAt.toIso8601String()),
        version: Value(model.sync.version),
      ),
    );
  }

  /// 按新实体全量更新模板行（bootstrap 对账用）。
  Future<void> _updateVehicleDefaultMaintenanceItem(
    int id,
    domain.VehicleDefaultMaintenanceItem item,
  ) async {
    await (database.update(
      database.vehicleDefaultMaintenanceItems,
    )..where((row) => row.id.equals(id))).write(
      VehicleDefaultMaintenanceItemsCompanion(
        catalogId: Value(item.catalogId),
        vehicleBrand: Value(item.vehicleBrand),
        vehicleModel: Value(item.vehicleModel),
        itemName: Value(item.itemName),
        remindByMileage: Value(item.remindByMileage),
        remindByTime: Value(item.remindByTime),
        mileageIntervalKm: Value(item.mileageIntervalKm),
        timeIntervalMonths: Value(item.timeIntervalMonths),
        notOverdueUpperLimit: Value(item.notOverdueUpperLimit),
        overdueUpperLimit: Value(item.overdueUpperLimit),
        sortOrder: Value(item.sortOrder),
        syncStatus: Value(item.sync.status.name),
        updatedAt: Value(item.sync.updatedAt.toIso8601String()),
        version: Value(item.sync.version),
      ),
    );
  }

  /// 行与目标实体逐字段比对，决定 bootstrap 是否需要 update
  /// （updatedAt 故意不比，避免每次启动都写库）。
  bool _vehicleModelNeedsUpdate(
    VehicleModelRow row,
    domain.VehicleModel model,
  ) {
    return row.catalogId != model.catalogId ||
        row.brand != model.brand ||
        row.model != model.model ||
        row.sortOrder != model.sortOrder ||
        row.syncStatus != model.sync.status.name ||
        row.version != model.sync.version;
  }

  /// 同上，模板表版本。
  bool _defaultItemNeedsUpdate(
    VehicleDefaultMaintenanceItemRow row,
    domain.VehicleDefaultMaintenanceItem item,
  ) {
    return row.catalogId != item.catalogId ||
        row.vehicleBrand != item.vehicleBrand ||
        row.vehicleModel != item.vehicleModel ||
        row.itemName != item.itemName ||
        row.remindByMileage != item.remindByMileage ||
        row.remindByTime != item.remindByTime ||
        row.mileageIntervalKm != item.mileageIntervalKm ||
        row.timeIntervalMonths != item.timeIntervalMonths ||
        row.notOverdueUpperLimit != item.notOverdueUpperLimit ||
        row.overdueUpperLimit != item.overdueUpperLimit ||
        row.sortOrder != item.sortOrder ||
        row.syncStatus != item.sync.status.name ||
        row.version != item.sync.version;
  }

  /// 车型目录列表（按 sortOrder 升序），添加车辆向导的选择器数据源。
  Future<List<domain.VehicleModel>> listVehicleModels() async {
    final rows = await (database.select(
      database.vehicleModels,
    )..orderBy([(row) => OrderingTerm.asc(row.sortOrder)])).get();
    return rows.map(_vehicleModelFromRow).toList();
  }

  /// 某品牌+车型的默认保养项目模板（添加车辆向导第二步的初始草稿）。
  Future<List<domain.VehicleDefaultMaintenanceItem>> listDefaultItemsForModel({
    required String brand,
    required String model,
  }) async {
    final rows =
        await (database.select(database.vehicleDefaultMaintenanceItems)
              ..where(
                (row) =>
                    row.vehicleBrand.equals(brand) &
                    row.vehicleModel.equals(model),
              )
              ..orderBy([(row) => OrderingTerm.asc(row.sortOrder)]))
            .get();
    return rows.map(_defaultItemFromRow).toList();
  }

  /// 新增保养项目（先过实体 validate；无事务——单条插入）。
  /// 记录表单里"行内新增项目"和项目 sheet 的新建都走这里。
  Future<int> saveMaintenanceItem(domain.MaintenanceItem item) async {
    item.validate();
    final itemId = _nextId();
    await database
        .into(database.maintenanceItems)
        .insert(
          MaintenanceItemsCompanion.insert(
            id: Value(itemId),
            carsId: item.carsId,
            name: item.name,
            enabled: Value(item.enabled),
            remindByMileage: item.remindByMileage,
            remindByTime: item.remindByTime,
            mileageIntervalKm: Value(item.mileageIntervalKm),
            timeIntervalMonths: Value(item.timeIntervalMonths),
            notOverdueUpperLimit: Value(item.notOverdueUpperLimit),
            overdueUpperLimit: Value(item.overdueUpperLimit),
            sortOrder: item.sortOrder,
            syncStatus: Value(item.sync.status.name),
            updatedAt: item.sync.updatedAt.toIso8601String(),
            version: Value(item.sync.version),
          ),
        );
    return itemId;
  }

  /// 某辆车的全部保养项目（按 sortOrder 升序）。
  Future<List<domain.MaintenanceItem>> listMaintenanceItemsForCar(
    int carId,
  ) async {
    final rows =
        await (database.select(database.maintenanceItems)
              ..where((row) => row.carsId.equals(carId))
              ..orderBy([(row) => OrderingTerm.asc(row.sortOrder)]))
            .get();
    return rows.map(_maintenanceItemFromRow).toList();
  }

  /// 编辑保养项目。若结果为停用，先校验"至少保留一个启用项"。
  /// ⚠ 校验和更新不在同一事务（check-then-act），单 isolate 下窗口极小。
  Future<void> updateMaintenanceItem(domain.MaintenanceItem item) async {
    item.validate();
    final itemId = item.id;
    if (itemId == null) {
      throw ArgumentError('Maintenance item id is required');
    }
    if (!item.enabled) {
      await _ensureCanDisableMaintenanceItem(
        carId: item.carsId,
        itemId: itemId,
      );
    }
    await (database.update(
      database.maintenanceItems,
    )..where((row) => row.id.equals(itemId))).write(
      MaintenanceItemsCompanion(
        name: Value(item.name),
        enabled: Value(item.enabled),
        remindByMileage: Value(item.remindByMileage),
        remindByTime: Value(item.remindByTime),
        mileageIntervalKm: Value(item.mileageIntervalKm),
        timeIntervalMonths: Value(item.timeIntervalMonths),
        notOverdueUpperLimit: Value(item.notOverdueUpperLimit),
        overdueUpperLimit: Value(item.overdueUpperLimit),
        sortOrder: Value(item.sortOrder),
        syncStatus: Value(item.sync.status.name),
        updatedAt: Value(item.sync.updatedAt.toIso8601String()),
        version: Value(item.sync.version),
      ),
    );
  }

  /// 只切换项目启用/停用（项目卡片上的开关）。
  /// 停用同样受"至少保留一个启用项"约束。
  Future<void> setMaintenanceItemEnabled({
    required int itemId,
    required bool enabled,
    required SyncMetadata sync,
  }) async {
    final item = await _getMaintenanceItemById(itemId);
    if (!enabled) {
      await _ensureCanDisableMaintenanceItem(
        carId: item.carsId,
        itemId: itemId,
      );
    }
    await (database.update(
      database.maintenanceItems,
    )..where((row) => row.id.equals(itemId))).write(
      MaintenanceItemsCompanion(
        enabled: Value(enabled),
        syncStatus: Value(sync.status.name),
        updatedAt: Value(sync.updatedAt.toIso8601String()),
        version: Value(sync.version),
      ),
    );
  }

  /// 项目是否有历史记录（出现在任何记录的关联表里）。
  /// ⚠ 实现为 select().get() 拉全行判空，数据量大时不如 count/limit(1)。
  Future<bool> maintenanceItemHasHistory(int itemId) async {
    final count = await (database.select(
      database.maintenanceRecordItems,
    )..where((row) => row.itemId.equals(itemId))).get();
    return count.isNotEmpty;
  }

  /// 删除保养项目。三道约束：项目必须存在；有历史记录则拒绝
  /// （防止破坏既有记录的引用）；删的是启用项时至少保留一个启用项。
  /// ⚠ 查历史与删除之间无事务包裹。
  Future<void> deleteMaintenanceItem(int itemId) async {
    final item = await _getMaintenanceItemById(itemId);
    if (await maintenanceItemHasHistory(itemId)) {
      throw ArgumentError('Maintenance item has history records');
    }
    if (item.enabled) {
      await _ensureCanDisableMaintenanceItem(
        carId: item.carsId,
        itemId: itemId,
      );
    }
    await (database.delete(
      database.maintenanceItems,
    )..where((row) => row.id.equals(itemId))).go();
  }

  /// 新增保养记录（基础版，不带项目间隔更新）。UI 走 WithItemUpdates 版。
  ///
  /// 事务内三步：校验项目归属 → 校验同日唯一 → 插记录+关联+同步车辆里程。
  Future<int> saveMaintenanceRecord(domain.MaintenanceRecord record) {
    RecordRules.validateRecord(record);
    final uniqueItemIds = RecordRules.uniqueItemIds(record.itemIds);

    return database.transaction(() async {
      await _validateRecordItems(carId: record.carId, itemIds: uniqueItemIds);
      await _ensureRecordIsUnique(
        carId: record.carId,
        date: record.date,
        itemIds: uniqueItemIds,
      );

      return _insertMaintenanceRecordInTransaction(
        record: record,
        uniqueItemIds: uniqueItemIds,
      );
    });
  }

  /// 新增保养记录 + 顺带更新所选项目的提醒间隔（记录表单两步提交的落库入口）。
  /// itemUpdates 只允许包含"本次记录选中的、属于本车的"项目
  /// （_updateMaintenanceItemIntervalsInTransaction 强校验）。
  Future<int> saveMaintenanceRecordWithItemUpdates({
    required domain.MaintenanceRecord record,
    required List<domain.MaintenanceItem> itemUpdates,
  }) {
    RecordRules.validateRecord(record);
    final uniqueItemIds = RecordRules.uniqueItemIds(record.itemIds);

    return database.transaction(() async {
      await _validateRecordItems(carId: record.carId, itemIds: uniqueItemIds);
      await _ensureRecordIsUnique(
        carId: record.carId,
        date: record.date,
        itemIds: uniqueItemIds,
      );

      final recordId = await _insertMaintenanceRecordInTransaction(
        record: record,
        uniqueItemIds: uniqueItemIds,
      );
      await _updateMaintenanceItemIntervalsInTransaction(
        carId: record.carId,
        selectedItemIds: uniqueItemIds,
        itemUpdates: itemUpdates,
      );
      return recordId;
    });
  }

  /// 编辑保养记录（基础版）。excludingRecordId 让唯一校验跳过自己。
  Future<void> updateMaintenanceRecord(domain.MaintenanceRecord record) {
    final recordId = record.id;
    if (recordId == null) {
      throw ArgumentError('Maintenance record id is required');
    }
    RecordRules.validateRecord(record);
    final uniqueItemIds = RecordRules.uniqueItemIds(record.itemIds);

    return database.transaction(() async {
      await _validateRecordItems(carId: record.carId, itemIds: uniqueItemIds);
      await _ensureRecordIsUnique(
        carId: record.carId,
        date: record.date,
        itemIds: uniqueItemIds,
        excludingRecordId: recordId,
      );

      await _updateMaintenanceRecordInTransaction(
        record: record,
        uniqueItemIds: uniqueItemIds,
      );
    });
  }

  /// 编辑保养记录 + 顺带更新项目间隔（UI 实际使用的编辑入口）。
  Future<void> updateMaintenanceRecordWithItemUpdates({
    required domain.MaintenanceRecord record,
    required List<domain.MaintenanceItem> itemUpdates,
  }) {
    final recordId = record.id;
    if (recordId == null) {
      throw ArgumentError('Maintenance record id is required');
    }
    RecordRules.validateRecord(record);
    final uniqueItemIds = RecordRules.uniqueItemIds(record.itemIds);

    return database.transaction(() async {
      await _validateRecordItems(carId: record.carId, itemIds: uniqueItemIds);
      await _ensureRecordIsUnique(
        carId: record.carId,
        date: record.date,
        itemIds: uniqueItemIds,
        excludingRecordId: recordId,
      );

      await _updateMaintenanceRecordInTransaction(
        record: record,
        uniqueItemIds: uniqueItemIds,
      );
      await _updateMaintenanceItemIntervalsInTransaction(
        carId: record.carId,
        selectedItemIds: uniqueItemIds,
        itemUpdates: itemUpdates,
      );
    });
  }

  /// 某车辆全部记录（日期倒序）。两次查询组装：主表 + 关联表按
  /// maintenanceRecordId 分组拼 itemIds，避免 N+1。
  /// 无分页——记录页全量载入内存过滤。
  Future<List<domain.MaintenanceRecord>> listMaintenanceRecordsForCar(
    int carId,
  ) async {
    final recordRows =
        await (database.select(database.maintenanceRecords)
              ..where((row) => row.carId.equals(carId))
              ..orderBy([(row) => OrderingTerm.desc(row.date)]))
            .get();
    final recordIds = recordRows.map((row) => row.id).toList();
    final itemRows = recordIds.isEmpty
        ? <MaintenanceRecordItemRow>[]
        : await (database.select(
            database.maintenanceRecordItems,
          )..where((row) => row.maintenanceRecordId.isIn(recordIds))).get();
    final itemIdsByRecordId = <int, List<int>>{};
    for (final row in itemRows) {
      itemIdsByRecordId
          .putIfAbsent(row.maintenanceRecordId, () => [])
          .add(row.itemId);
    }
    return recordRows
        .map(
          (row) => _recordFromRow(row, itemIdsByRecordId[row.id] ?? const []),
        )
        .toList();
  }

  /// 删除整条记录（事务：先删关联行再删主行）。
  Future<void> deleteMaintenanceRecord(int recordId) {
    return database.transaction(() async {
      await (database.delete(
        database.maintenanceRecordItems,
      )..where((row) => row.maintenanceRecordId.equals(recordId))).go();
      await (database.delete(
        database.maintenanceRecords,
      )..where((row) => row.id.equals(recordId))).go();
    });
  }

  /// 从记录里移除单个项目（按项目视图删除按钮）。
  ///
  /// 返回值表示"记录是否被整体删除了"：
  ///  - 记录只剩这一个项目 → 连记录一起删，返回 true（因为表约束
  ///    {carId,date} 一天一条，空记录没有存在意义）；
  ///  - 否则只删关联行，主记录标记 pendingUpdate，返回 false。
  /// 记录或关联不存在直接抛 ArgumentError。
  Future<bool> removeMaintenanceRecordItem({
    required int recordId,
    required int itemId,
  }) {
    return database.transaction(() async {
      final recordRow = await (database.select(
        database.maintenanceRecords,
      )..where((row) => row.id.equals(recordId))).getSingleOrNull();
      if (recordRow == null) {
        throw ArgumentError('Maintenance record not found');
      }
      final itemRows = await (database.select(
        database.maintenanceRecordItems,
      )..where((row) => row.maintenanceRecordId.equals(recordId))).get();
      final existingItemIds = RecordRules.uniqueItemIds(
        itemRows.map((row) => row.itemId).toList(),
      );
      if (!existingItemIds.contains(itemId)) {
        throw ArgumentError('Maintenance record does not contain item');
      }
      if (existingItemIds.length <= 1) {
        await (database.delete(
          database.maintenanceRecordItems,
        )..where((row) => row.maintenanceRecordId.equals(recordId))).go();
        await (database.delete(
          database.maintenanceRecords,
        )..where((row) => row.id.equals(recordId))).go();
        return true;
      }

      await (database.delete(database.maintenanceRecordItems)..where(
            (row) =>
                row.maintenanceRecordId.equals(recordId) &
                row.itemId.equals(itemId),
          ))
          .go();
      await (database.update(
        database.maintenanceRecords,
      )..where((row) => row.id.equals(recordId))).write(
        MaintenanceRecordsCompanion(
          syncStatus: Value(SyncStatus.pendingUpdate.name),
          updatedAt: Value(DateTime.now().toIso8601String()),
        ),
      );
      return false;
    });
  }

  /// 导出备份：4 张业务表全量读取（顺序两次查询拼 itemIds，无 N+1），
  /// 组装 BackupPayload（schemaVersion 固定 2）。不含偏好/停车倒计时/目录。
  Future<BackupPayload> exportBackupPayload() async {
    final cars = (await database.select(database.cars).get())
        .map(_carFromRow)
        .toList();
    final items = (await database.select(database.maintenanceItems).get())
        .map(_maintenanceItemFromRow)
        .toList();
    final recordRows = await database.select(database.maintenanceRecords).get();
    final recordItemRows = await database
        .select(database.maintenanceRecordItems)
        .get();
    final itemIdsByRecordId = <int, List<int>>{};
    for (final row in recordItemRows) {
      itemIdsByRecordId
          .putIfAbsent(row.maintenanceRecordId, () => [])
          .add(row.itemId);
    }
    final records = recordRows.map((row) {
      return _recordFromRow(row, itemIdsByRecordId[row.id] ?? const []);
    }).toList();
    return BackupPayload(
      schemaVersion: 2,
      cars: cars,
      maintenanceItems: items,
      records: records,
    );
  }

  /// 恢复备份（导入）。流程：
  ///  1. 版本校验（必须 2）；
  ///  2. 事务外先做引用完整性预校验（_validateBackupReferences），
  ///     失败直接抛，不碰库；
  ///  3. 单一大事务：清空全部数据（⚠ _clearAllDataInTransaction 连偏好
  ///     一起删，主题/通知设置等会丢，见审查报告 R2）→ 按 cars→items→
  ///     records 顺序逐行插入，id 全部换成新雪花 id（旧→新映射表），
  ///     任何一行违反约束抛错则整体回滚（UI 提示"未写入任何数据"）；
  ///  4. 应用车辆指向恢复出的第一辆车。
  /// 注意：恢复走裸 insert，不执行 RecordRules 业务校验（R35）。
  Future<void> restoreBackupPayload(BackupPayload payload) {
    if (payload.schemaVersion != 2) {
      throw UnsupportedError(
        'Unsupported backup schemaVersion: ${payload.schemaVersion}',
      );
    }
    _validateBackupReferences(payload);

    return database.transaction(() async {
      await _clearAllDataInTransaction();
      final carIdMap = <int, int>{};
      final itemIdMap = <int, int>{};
      int? firstRestoredCarId;

      for (final car in payload.cars) {
        final sourceId = car.id;
        if (sourceId == null) {
          throw ArgumentError('Backup car id is required');
        }
        final carId = _nextId();
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
        carIdMap[sourceId] = carId;
        firstRestoredCarId ??= carId;
      }

      for (final item in payload.maintenanceItems) {
        final sourceId = item.id;
        if (sourceId == null) {
          throw ArgumentError('Backup maintenance item id is required');
        }
        final carId = carIdMap[item.carsId];
        if (carId == null) {
          throw ArgumentError('Backup maintenance item references missing car');
        }
        final itemId = _nextId();
        await database
            .into(database.maintenanceItems)
            .insert(
              MaintenanceItemsCompanion.insert(
                id: Value(itemId),
                carsId: carId,
                name: item.name,
                enabled: Value(item.enabled),
                remindByMileage: item.remindByMileage,
                remindByTime: item.remindByTime,
                mileageIntervalKm: Value(item.mileageIntervalKm),
                timeIntervalMonths: Value(item.timeIntervalMonths),
                notOverdueUpperLimit: Value(item.notOverdueUpperLimit),
                overdueUpperLimit: Value(item.overdueUpperLimit),
                sortOrder: item.sortOrder,
                syncStatus: Value(item.sync.status.name),
                updatedAt: item.sync.updatedAt.toIso8601String(),
                version: Value(item.sync.version),
              ),
            );
        itemIdMap[sourceId] = itemId;
      }

      for (final record in payload.records) {
        final carId = carIdMap[record.carId];
        if (carId == null) {
          throw ArgumentError(
            'Backup maintenance record references missing car',
          );
        }
        final recordId = _nextId();
        await database
            .into(database.maintenanceRecords)
            .insert(
              MaintenanceRecordsCompanion.insert(
                id: Value(recordId),
                carId: carId,
                date: record.date.toString(),
                mileageKm: record.mileageKm,
                costCents: record.costCents,
                note: Value(record.note),
                syncStatus: Value(record.sync.status.name),
                updatedAt: record.sync.updatedAt.toIso8601String(),
                version: Value(record.sync.version),
              ),
            );
        for (final itemId in RecordRules.uniqueItemIds(record.itemIds)) {
          final mappedItemId = itemIdMap[itemId];
          if (mappedItemId == null) {
            throw ArgumentError(
              'Backup maintenance record references missing item',
            );
          }
          final recordItemId = _nextId();
          await database
              .into(database.maintenanceRecordItems)
              .insert(
                MaintenanceRecordItemsCompanion.insert(
                  id: Value(recordItemId),
                  maintenanceRecordId: recordId,
                  carId: carId,
                  itemId: mappedItemId,
                  date: record.date.toString(),
                ),
              );
        }
      }

      await _writeAppliedCarId(firstRestoredCarId);
      await _ensureAppliedCarInTransaction();
    });
  }

  /// 读偏好 key `appliedCarId` 的原始字符串值。
  Future<String?> getAppliedCarId() async {
    final row = await (database.select(
      database.appPreferences,
    )..where((pref) => pref.key.equals('appliedCarId'))).getSingleOrNull();
    return row?.value;
  }

  /// 写应用车辆 id（null = 清除）。切换车辆按钮走这里。
  Future<void> setAppliedCarId(int? carId) async {
    return _writeAppliedCarId(carId);
  }

  /// 通用偏好读：按 key 取 value（不存在返回 null）。
  /// 所有偏好 key 清单见 AGENTS.md。
  Future<String?> getPreferenceValue(String key) async {
    final row = await (database.select(
      database.appPreferences,
    )..where((pref) => pref.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  /// 通用偏好写（value 为 null 等价删除该 key）。
  Future<void> setPreferenceValue(String key, String? value) async {
    return _writePreferenceValue(key, value);
  }

  /// 读停车倒计时（偏好里的 JSON）。
  /// ⚠ JSON 损坏时 catch(_) 静默返回 null——坏数据留在库里无提示（R14）。
  Future<domain.ParkingCountdown?> getParkingCountdown() async {
    final value = await getPreferenceValue(_parkingCountdownPreferenceKey);
    if (value == null) {
      return null;
    }
    try {
      final json = jsonDecode(value) as Map<String, Object?>;
      return domain.ParkingCountdown.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  /// 保存停车倒计时（序列化为 JSON 存偏好）。只写库——
  /// 系统通知的调度/取消由 UI 层（parking_countdown.dart）负责。
  Future<void> saveParkingCountdown(domain.ParkingCountdown countdown) {
    return setPreferenceValue(
      _parkingCountdownPreferenceKey,
      jsonEncode(countdown.toJson()),
    );
  }

  /// 清除停车倒计时（写 null 删 key）。系统通知取消同样由 UI 层负责。
  Future<void> clearParkingCountdown() {
    return setPreferenceValue(_parkingCountdownPreferenceKey, null);
  }

  /// 清空数据（"我的"页入口）：事务内删 5 张表。
  /// ⚠ 连 app_preferences 一起删：主题、通知设置、手动日期、开发者模式、
  /// 全部 snooze/ack 记录都会丢（备份契约本就不含偏好，属刻意设计，
  /// 但用户预期需要靠 UI 文案对齐，见审查报告 R2）。
  /// 清空后 UI 会 invalidate 触发 bootstrap 重新灌车型目录。
  Future<void> clearAllData() {
    return database.transaction(() async {
      await _clearAllDataInTransaction();
    });
  }

  /// 清库实现（须在事务内调用；restoreBackupPayload 也复用它）。
  Future<void> _clearAllDataInTransaction() async {
    await database.delete(database.appPreferences).go();
    await database.delete(database.maintenanceRecordItems).go();
    await database.delete(database.maintenanceRecords).go();
    await database.delete(database.maintenanceItems).go();
    await database.delete(database.cars).go();
  }

  /// 事务内读应用车辆偏好（与 getAppliedCarId 相同但用于事务上下文）。
  Future<String?> _getAppliedCarIdInTransaction() async {
    final row = await (database.select(
      database.appPreferences,
    )..where((pref) => pref.key.equals('appliedCarId'))).getSingleOrNull();
    return row?.value;
  }

  /// 写应用车辆偏好。
  Future<void> _writeAppliedCarId(int? carId) async {
    return _writePreferenceValue('appliedCarId', carId?.toString());
  }

  /// 事务内保证应用车辆有效（AppliedCarRules 内联版）：
  /// 无车清空；偏好指向不存在的车则回退第一辆。恢复备份收尾时调用。
  Future<void> _ensureAppliedCarInTransaction() async {
    final cars = await database.select(database.cars).get();
    if (cars.isEmpty) {
      await _writeAppliedCarId(null);
      return;
    }
    final appliedCarId = int.tryParse(
      await _getAppliedCarIdInTransaction() ?? '',
    );
    if (appliedCarId != null && cars.any((car) => car.id == appliedCarId)) {
      return;
    }
    await _writeAppliedCarId(cars.first.id);
  }

  /// 偏好 upsert：null 删行；无则插入、有则更新（syncStatus 记 pendingUpdate，
  /// updatedAt 刷新）。⚠ select-then-insert 非原子（单 isolate 下窗口极小）。
  Future<void> _writePreferenceValue(String key, String? value) async {
    if (value == null) {
      await (database.delete(
        database.appPreferences,
      )..where((pref) => pref.key.equals(key))).go();
      return;
    }
    final existing = await (database.select(
      database.appPreferences,
    )..where((pref) => pref.key.equals(key))).getSingleOrNull();
    final now = DateTime.now().toIso8601String();
    if (existing == null) {
      final preferenceId = _nextId();
      await database
          .into(database.appPreferences)
          .insert(
            AppPreferencesCompanion.insert(
              id: Value(preferenceId),
              key: key,
              value: Value(value),
              syncStatus: const Value('pendingUpdate'),
              updatedAt: now,
            ),
          );
      return;
    }
    await (database.update(
      database.appPreferences,
    )..where((pref) => pref.key.equals(key))).write(
      AppPreferencesCompanion(
        value: Value(value),
        syncStatus: const Value('pendingUpdate'),
        updatedAt: Value(now),
      ),
    );
  }

  /// 生成下一个雪花 id（static 生成器，进程内唯一）。
  static int _nextId() => _idGenerator.next();

  // ---------------- 行(Row) → 实体(Entity) 映射器 ----------------
  // Row 是 Drift 生成的表行类（≈ MyBatis 的 ResultMap），
  // Entity 是 domain/entities 里的纯业务对象。字段一一对应。

  /// cars 表行 → Car 实体。
  domain.Car _carFromRow(CarRow row) {
    return domain.Car(
      id: row.id,
      brand: row.brand,
      model: row.model,
      currentMileageKm: row.currentMileageKm,
      roadDate: LocalDate.parse(row.roadDate),
      sync: SyncMetadata(
        status: SyncStatus.values.byName(row.syncStatus),
        updatedAt: DateTime.parse(row.updatedAt),
        version: row.version,
      ),
    );
  }

  /// 模板表行 → 实体。
  domain.VehicleDefaultMaintenanceItem _defaultItemFromRow(
    VehicleDefaultMaintenanceItemRow row,
  ) {
    return domain.VehicleDefaultMaintenanceItem(
      id: row.id,
      catalogId: row.catalogId,
      vehicleBrand: row.vehicleBrand,
      vehicleModel: row.vehicleModel,
      itemName: row.itemName,
      remindByMileage: row.remindByMileage,
      remindByTime: row.remindByTime,
      mileageIntervalKm: row.mileageIntervalKm,
      timeIntervalMonths: row.timeIntervalMonths,
      notOverdueUpperLimit: row.notOverdueUpperLimit,
      overdueUpperLimit: row.overdueUpperLimit,
      sortOrder: row.sortOrder,
      sync: SyncMetadata(
        status: SyncStatus.values.byName(row.syncStatus),
        updatedAt: DateTime.parse(row.updatedAt),
        version: row.version,
      ),
    );
  }

  /// 车型表行 → 实体。
  domain.VehicleModel _vehicleModelFromRow(VehicleModelRow row) {
    return domain.VehicleModel(
      id: row.id,
      catalogId: row.catalogId,
      brand: row.brand,
      model: row.model,
      sortOrder: row.sortOrder,
      sync: SyncMetadata(
        status: SyncStatus.values.byName(row.syncStatus),
        updatedAt: DateTime.parse(row.updatedAt),
        version: row.version,
      ),
    );
  }

  /// 同日唯一性校验（业务层规则，先于数据库约束给出友好文案）：
  ///  - 同车同日已有记录且包含本次任一项目 → "当天已保存过相同保养项目"；
  ///  - 同车同日已有记录但项目不重叠 → "当天已有保养记录，请编辑原记录"。
  /// ⚠ 第二条意味着业务层只允许"同日多条不重叠记录"，但表级唯一约束
  ///    {carId,date} 实际只允许一天一条——不重叠的第二条会插主表时撞
  ///    SqliteException（由 UI 层翻译成通用文案），两层口径不一致（R4）。
  /// excludingRecordId：编辑场景跳过自身。
  Future<void> _ensureRecordIsUnique({
    required int carId,
    required LocalDate date,
    required List<int> itemIds,
    int? excludingRecordId,
  }) async {
    final existingRecords =
        await (database.select(database.maintenanceRecords)..where(
              (row) =>
                  row.carId.equals(carId) &
                  row.date.equals(date.toString()) &
                  (excludingRecordId == null
                      ? const Constant(true)
                      : row.id.equals(excludingRecordId).not()),
            ))
            .get();
    if (existingRecords.isEmpty) {
      return;
    }
    final existingRecordIds = existingRecords.map((row) => row.id).toList();
    final duplicateItems =
        await (database.select(database.maintenanceRecordItems)..where(
              (row) =>
                  row.maintenanceRecordId.isIn(existingRecordIds) &
                  row.itemId.isIn(itemIds),
            ))
            .get();
    if (duplicateItems.isNotEmpty) {
      throw StateError('这辆车当天已经保存过相同保养项目');
    }
    throw StateError('这辆车当天已有保养记录，请编辑原记录');
  }

  /// 事务内更新记录：主表 write → 删掉全部关联行 → 按新 itemIds 重插
  /// （全量重建关联，不做 diff）→ 里程只增同步。
  Future<void> _updateMaintenanceRecordInTransaction({
    required domain.MaintenanceRecord record,
    required List<int> uniqueItemIds,
  }) async {
    final recordId = record.id;
    if (recordId == null) {
      throw ArgumentError('Maintenance record id is required');
    }
    await (database.update(
      database.maintenanceRecords,
    )..where((row) => row.id.equals(recordId))).write(
      MaintenanceRecordsCompanion(
        date: Value(record.date.toString()),
        mileageKm: Value(record.mileageKm),
        costCents: Value(record.costCents),
        note: Value(record.note),
        syncStatus: Value(record.sync.status.name),
        updatedAt: Value(record.sync.updatedAt.toIso8601String()),
        version: Value(record.sync.version),
      ),
    );
    await (database.delete(
      database.maintenanceRecordItems,
    )..where((row) => row.maintenanceRecordId.equals(recordId))).go();
    for (final itemId in uniqueItemIds) {
      await database
          .into(database.maintenanceRecordItems)
          .insert(
            MaintenanceRecordItemsCompanion.insert(
              id: Value(_nextId()),
              maintenanceRecordId: recordId,
              carId: record.carId,
              itemId: itemId,
              date: record.date.toString(),
            ),
          );
    }
    await _syncCarMileageInTransaction(
      carId: record.carId,
      recordMileageKm: record.mileageKm,
    );
  }

  /// 事务内插入新记录：主表 + 逐条关联行 + 里程只增同步。返回新记录 id。
  Future<int> _insertMaintenanceRecordInTransaction({
    required domain.MaintenanceRecord record,
    required List<int> uniqueItemIds,
  }) async {
    final recordId = _nextId();
    await database
        .into(database.maintenanceRecords)
        .insert(
          MaintenanceRecordsCompanion.insert(
            id: Value(recordId),
            carId: record.carId,
            date: record.date.toString(),
            mileageKm: record.mileageKm,
            costCents: record.costCents,
            note: Value(record.note),
            syncStatus: Value(record.sync.status.name),
            updatedAt: record.sync.updatedAt.toIso8601String(),
            version: Value(record.sync.version),
          ),
        );

    for (final itemId in uniqueItemIds) {
      await database
          .into(database.maintenanceRecordItems)
          .insert(
            MaintenanceRecordItemsCompanion.insert(
              id: Value(_nextId()),
              maintenanceRecordId: recordId,
              carId: record.carId,
              itemId: itemId,
              date: record.date.toString(),
            ),
          );
    }

    await _syncCarMileageInTransaction(
      carId: record.carId,
      recordMileageKm: record.mileageKm,
    );
    return recordId;
  }

  /// 事务内更新项目提醒间隔（记录表单第二步提交的间隔修改）。
  /// 强校验：每个 itemUpdate 必须属于本车且在本次选中项目集合内，
  /// 否则抛错回滚整个记录保存。
  Future<void> _updateMaintenanceItemIntervalsInTransaction({
    required int carId,
    required List<int> selectedItemIds,
    required List<domain.MaintenanceItem> itemUpdates,
  }) async {
    final selectedItemIdSet = selectedItemIds.toSet();
    for (final item in itemUpdates) {
      item.validate();
      final itemId = item.id;
      if (itemId == null) {
        throw ArgumentError('Maintenance item id is required');
      }
      if (item.carsId != carId || !selectedItemIdSet.contains(itemId)) {
        throw ArgumentError('Maintenance item update is outside record scope');
      }
      await (database.update(
        database.maintenanceItems,
      )..where((row) => row.id.equals(itemId))).write(
        MaintenanceItemsCompanion(
          remindByMileage: Value(item.remindByMileage),
          remindByTime: Value(item.remindByTime),
          mileageIntervalKm: Value(item.mileageIntervalKm),
          timeIntervalMonths: Value(item.timeIntervalMonths),
          syncStatus: Value(item.sync.status.name),
          updatedAt: Value(item.sync.updatedAt.toIso8601String()),
          version: Value(item.sync.version),
        ),
      );
    }
  }

  /// 事务内同步车辆里程：max(当前, 记录里程)，有变化才写
  /// （避免无谓写库；写时把车辆标记 pendingUpdate + 刷新 updatedAt）。
  Future<void> _syncCarMileageInTransaction({
    required int carId,
    required int recordMileageKm,
  }) async {
    final car = await (database.select(
      database.cars,
    )..where((row) => row.id.equals(carId))).getSingle();
    final nextMileage = RecordRules.mileageAfterRecord(
      currentMileageKm: car.currentMileageKm,
      recordMileageKm: recordMileageKm,
    );
    if (nextMileage != car.currentMileageKm) {
      final now = DateTime.now().toIso8601String();
      await (database.update(
        database.cars,
      )..where((row) => row.id.equals(carId))).write(
        CarsCompanion(
          currentMileageKm: Value(nextMileage),
          syncStatus: Value(SyncStatus.pendingUpdate.name),
          updatedAt: Value(now),
        ),
      );
    }
  }

  /// 校验记录引用的项目：全部存在（数量一致）且都属于本车。
  Future<void> _validateRecordItems({
    required int carId,
    required List<int> itemIds,
  }) async {
    final rows = await (database.select(
      database.maintenanceItems,
    )..where((row) => row.id.isIn(itemIds))).get();
    if (rows.length != itemIds.length) {
      throw ArgumentError('Maintenance record contains missing items');
    }
    final hasOtherCarItem = rows.any((row) => row.carsId != carId);
    if (hasOtherCarItem) {
      throw ArgumentError('Maintenance record contains items from another car');
    }
  }

  /// 按 id 取项目，不存在抛错。
  Future<domain.MaintenanceItem> _getMaintenanceItemById(int itemId) async {
    final row = await (database.select(
      database.maintenanceItems,
    )..where((row) => row.id.equals(itemId))).getSingleOrNull();
    if (row == null) {
      throw ArgumentError('Maintenance item not found');
    }
    return _maintenanceItemFromRow(row);
  }

  /// 校验"除本项目外该车至少还有一个启用项目"——停用/删除启用项目前调用。
  Future<void> _ensureCanDisableMaintenanceItem({
    required int carId,
    required int itemId,
  }) async {
    final enabledRows =
        await (database.select(database.maintenanceItems)..where(
              (row) =>
                  row.carsId.equals(carId) &
                  row.enabled.equals(true) &
                  row.id.equals(itemId).not(),
            ))
            .get();
    if (enabledRows.isEmpty) {
      throw ArgumentError('At least one maintenance item must stay enabled');
    }
  }

  /// 备份引用完整性校验（恢复前、事务外执行）：
  /// cars/items 的 id 齐全且不重复；每个 item 的 carsId 存在；
  /// 每条 record 的 carId 存在、每个 itemId 存在且与 record 同车
  /// （跨车引用的备份直接拒绝）。不校验业务规则（R35）。
  void _validateBackupReferences(BackupPayload payload) {
    final carIds = payload.cars.map((car) => car.id).whereType<int>().toSet();
    final itemCarIds = <int, int>{};
    for (final item in payload.maintenanceItems) {
      final itemId = item.id;
      if (itemId != null) {
        itemCarIds[itemId] = item.carsId;
      }
    }
    final itemIds = itemCarIds.keys.toSet();
    if (carIds.length != payload.cars.length) {
      throw ArgumentError('Backup contains cars without ids');
    }
    if (itemIds.length != payload.maintenanceItems.length) {
      throw ArgumentError('Backup contains maintenance items without ids');
    }
    for (final item in payload.maintenanceItems) {
      if (!carIds.contains(item.carsId)) {
        throw ArgumentError('Backup maintenance item references missing car');
      }
    }
    for (final record in payload.records) {
      if (!carIds.contains(record.carId)) {
        throw ArgumentError('Backup maintenance record references missing car');
      }
      for (final itemId in RecordRules.uniqueItemIds(record.itemIds)) {
        if (!itemIds.contains(itemId)) {
          throw ArgumentError(
            'Backup maintenance record references missing item',
          );
        }
        if (itemCarIds[itemId] != record.carId) {
          throw ArgumentError(
            'Backup maintenance record references item from another car',
          );
        }
      }
    }
  }

  /// 项目表行 → 实体。
  domain.MaintenanceItem _maintenanceItemFromRow(MaintenanceItemRow row) {
    return domain.MaintenanceItem(
      id: row.id,
      carsId: row.carsId,
      name: row.name,
      enabled: row.enabled,
      remindByMileage: row.remindByMileage,
      remindByTime: row.remindByTime,
      mileageIntervalKm: row.mileageIntervalKm,
      timeIntervalMonths: row.timeIntervalMonths,
      notOverdueUpperLimit: row.notOverdueUpperLimit,
      overdueUpperLimit: row.overdueUpperLimit,
      sortOrder: row.sortOrder,
      sync: SyncMetadata(
        status: SyncStatus.values.byName(row.syncStatus),
        updatedAt: DateTime.parse(row.updatedAt),
        version: row.version,
      ),
    );
  }

  /// 记录表行 + 关联 itemIds → 实体。
  domain.MaintenanceRecord _recordFromRow(
    MaintenanceRecordRow row,
    List<int> itemIds,
  ) {
    return domain.MaintenanceRecord(
      id: row.id,
      carId: row.carId,
      date: LocalDate.parse(row.date),
      itemIds: itemIds,
      costCents: row.costCents,
      mileageKm: row.mileageKm,
      note: row.note,
      sync: SyncMetadata(
        status: SyncStatus.values.byName(row.syncStatus),
        updatedAt: DateTime.parse(row.updatedAt),
        version: row.version,
      ),
    );
  }
}

// bootstrap 对账用的"旧数据兜底键"：\u0000 作分隔符保证组合不歧义。
String _vehicleModelKey(String brand, String model) => '$brand\u0000$model';

String _defaultItemKey(String brand, String model, String itemName) {
  return '$brand\u0000$model\u0000$itemName';
}
