// 主仓库（LunioRepository）：车辆 / 保养项目 / 保养记录核心域的数据库
// 读写出口（≈ Java 的 Service + DAO 合体，拆分后只保留这三个高内聚域）。
//
// 域拆分后的兄弟模块（互不嵌套，经 providers.dart 装配组合）：
//  - LunioPreferences（lib/data/preferences/）：偏好 KV 的 typed 门面；
//  - BuiltInCatalogRepository：车型目录与默认模板两张内置表 + bootstrap；
//  - FuelRepository：加油预测设置与油价缓存/手填价；
//  - BackupRepository：备份导出/恢复/清空数据。
//
// 本类仍拥有的职责：
//  - 核心域的行(Row) ↔ 实体(Entity) 映射（共享编解码见 entity_row_codec.dart）；
//  - 事务编排（database.transaction ≈ Spring 的 @Transactional，闭包抛异常自动回滚）；
//  - 写前业务校验（调 RecordRules / AppliedCarRules / 实体 validate / 内部 _ensureXxx）。
//
// 重要约定：
//  1. fail-fast：校验失败抛 ArgumentError / LunioErrorException，不吞
//     异常；表单提交路径的业务规则失败抛 LunioErrorException（错误类型
//     与中文文案见 lib/domain/errors/lunio_error.dart）。
//  2. 本类**不做缓存失效**——写库后刷新 UI 缓存（invalidateXxxProviders）
//     是调用方（保存动作层）的责任。
//  3. import as domain：给同名实体加命名空间，避免与 Drift 生成的 Row 类
//     同名冲突（≈ Java 里两个同名类用全限定名区分）。
import 'package:drift/drift.dart';

import '../../core/date/local_date.dart';
import '../../core/id/snowflake_id_generator.dart';
import '../../domain/entities/car.dart' as domain;
import '../../domain/errors/lunio_error.dart';
import '../../domain/entities/maintenance_item.dart' as domain;
import '../../domain/entities/maintenance_record.dart' as domain;
import '../../domain/entities/sync_metadata.dart';
import '../../domain/rules/applied_car_rules.dart';
import '../../domain/rules/fuel_rules.dart';
import '../../domain/rules/record_rules.dart';
import '../database/app_database.dart';
import '../preferences/app_preferences.dart';
import 'entity_row_codec.dart';
import 'fuel_repository.dart';

class LunioRepository {
  /// 构造时注入数据库连接；偏好门面与加油仓库可选注入（测试可不传，
  /// 默认按同一数据库连接自行装配——三者无状态，多实例等价）。
  LunioRepository(
    this.database, {
    LunioPreferences? preferences,
    FuelRepository? fuel,
  }) : preferences = preferences ?? LunioPreferences(database),
       fuel = fuel ?? FuelRepository(database, preferences ?? LunioPreferences(database));

  final AppDatabase database;

  /// 偏好门面：应用车辆 id 等偏好的存取通道（key 与编解码在门面里）。
  final LunioPreferences preferences;

  /// 加油仓库：删除车辆的级联清理要借道它删预测行（表知识不外泄）。
  final FuelRepository fuel;

  /// 创建车辆 + 一批保养项目（添加车辆向导"完成"按钮的落库入口）。
  ///
  /// 校验：至少一个启用项目；每个项目过实体 validate。
  /// 事务内：插车辆 → 逐条插项目 → 若当前无应用车辆（appliedCarId 为空）
  /// 则把新车设为应用车辆（首辆车自动成为当前车）。
  /// 任意一步失败整体回滚。返回新车辆 id。
  ///
  /// （原 createCar / createCarWithDefaultItems 两个遗留入口已删，R26：
  /// 前者等价 createCarWithMaintenanceItems(car, const [])，后者等价
  /// ensureBootstrapData + listDefaultItemsForPowertrain + 模板转实体的组合。）
  Future<int> createCarWithMaintenanceItems(
    domain.Car car,
    List<domain.MaintenanceItem> items,
  ) {
    if (!items.any((item) => item.enabled)) {
      throw const LunioErrorException(
        LunioErrorKind.lastEnabledMaintenanceItem,
        '至少保留一个可用保养项目',
      );
    }
    for (final item in items) {
      item.validate();
    }
    FuelRules.validateTankCapacity(car.tankCapacityLiters);
    return database.transaction(() async {
      final carId = SnowflakeIdGenerator.instance.next();
      await database.into(database.cars).insert(carCompanion(car, carId));

      for (final item in items) {
        await database
            .into(database.maintenanceItems)
            .insert(
              maintenanceItemCompanion(
                // 草稿实体的 carsId 是占位 0，落库前重映射为真实车辆 id。
                item.copyWith(carsId: carId),
                SnowflakeIdGenerator.instance.next(),
              ),
            );
      }

      final storedAppliedCarId = await preferences.getAppliedCarId();
      if (storedAppliedCarId == null) {
        await preferences.setAppliedCarId(carId);
      }
      return carId;
    });
  }

  /// 全部车辆列表（无排序约束，全表扫描）。
  Future<List<domain.Car>> listCars() async {
    final rows = await database.select(database.cars).get();
    return rows.map(carFromRow).toList();
  }

  /// 编辑车辆（只允许改里程/上路日期/油箱容积/sync；品牌型号是身份字段
  /// 不可改，因此 UI 的编辑表单不提供品牌车型输入）。id 为空抛错。
  Future<void> updateCar(domain.Car car) {
    final carId = car.id;
    if (carId == null) {
      throw ArgumentError('Car id is required');
    }
    FuelRules.validateTankCapacity(car.tankCapacityLiters);
    return (database.update(
      database.cars,
    )..where((row) => row.id.equals(carId))).write(
      CarsCompanion(
        currentMileageKm: Value(car.currentMileageKm),
        roadDate: Value(car.roadDate.toString()),
        tankCapacityLiters: Value(car.tankCapacityLiters),
        syncStatus: Value(car.sync.status.name),
        updatedAt: Value(car.sync.updatedAt.toIso8601String()),
        version: Value(car.sync.version),
      ),
    );
  }

  /// 读取当前应用车辆（提醒页/记录页展示的车）。
  ///
  /// 实现为点查（R31）：先按偏好 id 点查该车，命中直接用；未命中才
  /// 全表按 id 升序加载，交给 [AppliedCarRules.resolveAppliedCarId]
  /// 裁决回退值（规则唯一事实来源，读/写路径共用同一份）。
  /// 副作用方法（读路径里夹带写）：解析结果与偏好不一致时把修正值写回
  /// 偏好（无车清空、失效回退第一辆）。
  Future<domain.Car?> getAppliedCar() async {
    final storedCarId = await preferences.getAppliedCarId();
    if (storedCarId != null) {
      final storedRow = await (database.select(
        database.cars,
      )..where((row) => row.id.equals(storedCarId)))
          .getSingleOrNull();
      if (storedRow != null) {
        return carFromRow(storedRow);
      }
    }
    final rows = await (database.select(
      database.cars,
    )..orderBy([(row) => OrderingTerm.asc(row.id)]))
        .get();
    final cars = rows.map(carFromRow).toList();
    final resolvedCarId = AppliedCarRules.resolveAppliedCarId(
      cars: cars,
      storedCarId: storedCarId,
    );
    await preferences.setAppliedCarId(resolvedCarId);
    if (resolvedCarId == null) {
      return null;
    }
    return cars.firstWhere((car) => car.id == resolvedCarId);
  }

  /// 删除车辆（事务级联删，无外键所以手工按序删）：
  /// 记录关联表 → 记录表 → 项目表 → appliedCarId 偏好（仅当指向本车）→
  /// 加油预测行（经 FuelRepository，表知识不越过它的 seam）→ 车辆本身。
  /// 删完按 AppliedCarRules 把应用车辆指向剩余 id 最小的车；没有剩余则清空。
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
      await preferences.clearAppliedCarIdIfValue(carId);
      await fuel.deleteForCar(carId);
      await (database.delete(
        database.cars,
      )..where((row) => row.id.equals(carId))).go();
      final remainingRows = await (database.select(
        database.cars,
      )..orderBy([(row) => OrderingTerm.asc(row.id)]))
          .get();
      final remainingCars = remainingRows.map(carFromRow).toList();
      await preferences.setAppliedCarId(
        AppliedCarRules.resolveAppliedCarId(
          cars: remainingCars,
          storedCarId: null,
        ),
      );
    });
  }

  /// 新增保养项目（先过实体 validate；无事务——单条插入）。
  /// 记录表单里"行内新增项目"和项目 sheet 的新建都走这里。
  Future<int> saveMaintenanceItem(domain.MaintenanceItem item) async {
    item.validate();
    final itemId = SnowflakeIdGenerator.instance.next();
    await database
        .into(database.maintenanceItems)
        .insert(maintenanceItemCompanion(item, itemId));
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
    return rows.map(maintenanceItemFromRow).toList();
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
  /// limit(1) 点查：只判存在性，不拉全行（R31）。
  Future<bool> maintenanceItemHasHistory(int itemId) async {
    final rows = await (database.select(
      database.maintenanceRecordItems,
    )
          ..where((row) => row.itemId.equals(itemId))
          ..limit(1))
        .get();
    return rows.isNotEmpty;
  }

  /// 删除保养项目。三道约束：项目必须存在；有历史记录则拒绝
  /// （防止破坏既有记录的引用）；删的是启用项时至少保留一个启用项。
  /// ⚠ 查历史与删除之间无事务包裹。
  Future<void> deleteMaintenanceItem(int itemId) async {
    final item = await _getMaintenanceItemById(itemId);
    if (await maintenanceItemHasHistory(itemId)) {
      throw const LunioErrorException(
        LunioErrorKind.maintenanceItemHasHistory,
        '已有保养记录的项目不能删除',
      );
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
          (row) =>
              maintenanceRecordFromRow(row, itemIdsByRecordId[row.id] ?? const []),
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

  // ---------------- 事务内私有实现 ----------------

  /// 同日唯一性校验（业务层规则，先于数据库约束给出友好文案）：
  /// 同车同日只允许一条保养记录（R4 收紧，与表级唯一约束 {carId,date}
  /// 对齐），已有记录时提示用户编辑原记录。
  /// excludingRecordId：编辑场景跳过自身。
  Future<void> _ensureRecordIsUnique({
    required int carId,
    required LocalDate date,
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
    if (existingRecords.isNotEmpty) {
      throw const LunioErrorException(
        LunioErrorKind.duplicateMaintenanceRecord,
        '这辆车当天已有保养记录，请编辑原记录',
      );
    }
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
            maintenanceRecordItemCompanion(
              id: SnowflakeIdGenerator.instance.next(),
              recordId: recordId,
              carId: record.carId,
              itemId: itemId,
              date: record.date,
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
    final recordId = SnowflakeIdGenerator.instance.next();
    await database
        .into(database.maintenanceRecords)
        .insert(maintenanceRecordCompanion(record, recordId));

    for (final itemId in uniqueItemIds) {
      await database
          .into(database.maintenanceRecordItems)
          .insert(
            maintenanceRecordItemCompanion(
              id: SnowflakeIdGenerator.instance.next(),
              recordId: recordId,
              carId: record.carId,
              itemId: itemId,
              date: record.date,
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
      throw const LunioErrorException(
        LunioErrorKind.missingRecordItems,
        '选择的保养项目不存在，请重新选择',
      );
    }
    final hasOtherCarItem = rows.any((row) => row.carsId != carId);
    if (hasOtherCarItem) {
      throw const LunioErrorException(
        LunioErrorKind.itemFromAnotherCar,
        '保养项目不属于当前车辆，请重新选择',
      );
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
    return maintenanceItemFromRow(row);
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
      throw const LunioErrorException(
        LunioErrorKind.lastEnabledMaintenanceItem,
        '至少保留一个可用保养项目',
      );
    }
  }
}
