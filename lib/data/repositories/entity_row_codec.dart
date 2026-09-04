// 行(Row) ↔ 实体(Entity) ↔ Companion 的共享编解码（顶层函数集）。
//
// ≈ Java 里抽出来的公共 RowMapper + InsertParamFactory：一张表的字段
// 清单只在这里出现一次，插入（新增路径/恢复备份路径）与读取共用。
// 改表结构时只需要改这里 + backup_codec.dart 的 JSON 契约两处。
//
// 为什么是顶层函数而不是类：这些函数无状态、不持有数据库连接，
// 主仓库 / 目录 / 加油 / 备份几个模块都要用，挂在任何一个类上都会
// 造成"借道"引用（≈ Java 静态工具方法）。
import 'package:drift/drift.dart';

import '../../core/date/local_date.dart';
import '../../domain/entities/car.dart' as domain;
import '../../domain/entities/fuel_prediction.dart' as domain;
import '../../domain/entities/maintenance_item.dart' as domain;
import '../../domain/entities/maintenance_record.dart' as domain;
import '../../domain/entities/powertrain_type.dart' as domain;
import '../../domain/entities/sync_metadata.dart';
import '../../domain/entities/vehicle_default_maintenance_item.dart' as domain;
import '../../domain/entities/vehicle_model.dart' as domain;
import '../database/app_database.dart';

// ---------------- cars ----------------

/// cars 表行 → Car 实体。
domain.Car carFromRow(CarRow row) {
  return domain.Car(
    id: row.id,
    brand: row.brand,
    model: row.model,
    powertrainType: domain.PowertrainType.byWire(row.powertrainType),
    currentMileageKm: row.currentMileageKm,
    roadDate: LocalDate.parse(row.roadDate),
    tankCapacityLiters: row.tankCapacityLiters,
    sync: SyncMetadata(
      status: SyncStatus.values.byName(row.syncStatus),
      updatedAt: DateTime.parse(row.updatedAt),
      version: row.version,
    ),
  );
}

/// Car 实体 + 指定 id → 插入用 Companion（新增车辆与恢复备份共用，
/// 字段清单全库只有这一份）。
CarsCompanion carCompanion(domain.Car car, int id) {
  return CarsCompanion.insert(
    id: Value(id),
    brand: car.brand,
    model: car.model,
    powertrainType: Value(car.powertrainType.wire),
    currentMileageKm: car.currentMileageKm,
    roadDate: car.roadDate.toString(),
    tankCapacityLiters: Value(car.tankCapacityLiters),
    syncStatus: Value(car.sync.status.name),
    updatedAt: car.sync.updatedAt.toIso8601String(),
    version: Value(car.sync.version),
  );
}

// ---------------- maintenance_items ----------------

/// 项目表行 → 实体。
domain.MaintenanceItem maintenanceItemFromRow(MaintenanceItemRow row) {
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

/// 项目实体 + 指定 id → 插入用 Companion。
MaintenanceItemsCompanion maintenanceItemCompanion(
  domain.MaintenanceItem item,
  int id,
) {
  return MaintenanceItemsCompanion.insert(
    id: Value(id),
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
  );
}

// ---------------- maintenance_records + 关联表 ----------------

/// 记录表行 + 关联 itemIds → 实体。
domain.MaintenanceRecord maintenanceRecordFromRow(
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

/// 记录实体 + 指定 id → 插入用 Companion。
/// [carId] 可选覆盖：恢复备份时实体的 carId 是备份里的旧库车辆 id，
/// 须传重映射后的新雪花 id（手工录入路径不传，直接用实体原值）。
MaintenanceRecordsCompanion maintenanceRecordCompanion(
  domain.MaintenanceRecord record,
  int id, {
  int? carId,
}) {
  return MaintenanceRecordsCompanion.insert(
    id: Value(id),
    carId: carId ?? record.carId,
    date: record.date.toString(),
    mileageKm: record.mileageKm,
    costCents: record.costCents,
    note: Value(record.note),
    syncStatus: Value(record.sync.status.name),
    updatedAt: record.sync.updatedAt.toIso8601String(),
    version: Value(record.sync.version),
  );
}

/// 记录关联行 → 插入用 Companion（手工录入、编辑重建关联、恢复备份
/// 三条路径共用）。
MaintenanceRecordItemsCompanion maintenanceRecordItemCompanion({
  required int id,
  required int recordId,
  required int carId,
  required int itemId,
  required LocalDate date,
}) {
  return MaintenanceRecordItemsCompanion.insert(
    id: Value(id),
    maintenanceRecordId: recordId,
    carId: carId,
    itemId: itemId,
    date: date.toString(),
  );
}

// ---------------- fuel_predictions ----------------

/// 加油预测表行 → 实体。
domain.FuelPrediction fuelPredictionFromRow(FuelPredictionRow row) {
  return domain.FuelPrediction(
    id: row.id,
    carId: row.carId,
    fuelPercent: row.fuelPercent,
    sync: SyncMetadata(
      status: SyncStatus.values.byName(row.syncStatus),
      updatedAt: DateTime.parse(row.updatedAt),
      version: row.version,
    ),
  );
}

/// 加油预测实体 + 指定 id → 插入用 Companion。
FuelPredictionsCompanion fuelPredictionCompanion(
  domain.FuelPrediction prediction,
  int id,
) {
  return FuelPredictionsCompanion.insert(
    id: Value(id),
    carId: prediction.carId,
    fuelPercent: prediction.fuelPercent,
    syncStatus: Value(prediction.sync.status.name),
    updatedAt: prediction.sync.updatedAt.toIso8601String(),
    version: Value(prediction.sync.version),
  );
}

// ---------------- 车型目录两张内置表 ----------------

/// 车型表行 → 实体。template 是推荐动力类型（添加向导预选用）。
domain.VehicleModel vehicleModelFromRow(VehicleModelRow row) {
  return domain.VehicleModel(
    id: row.id,
    catalogId: row.catalogId,
    brand: row.brand,
    model: row.model,
    template: domain.PowertrainType.byWire(row.template),
    sortOrder: row.sortOrder,
    sync: SyncMetadata(
      status: SyncStatus.values.byName(row.syncStatus),
      updatedAt: DateTime.parse(row.updatedAt),
      version: row.version,
    ),
  );
}

/// 车型实体 + 指定 id → 插入用 Companion。
VehicleModelsCompanion vehicleModelCompanion(domain.VehicleModel model, int id) {
  return VehicleModelsCompanion.insert(
    id: Value(id),
    catalogId: Value(model.catalogId),
    brand: model.brand,
    model: model.model,
    template: Value(model.template.wire),
    sortOrder: model.sortOrder,
    syncStatus: Value(model.sync.status.name),
    updatedAt: model.sync.updatedAt.toIso8601String(),
    version: Value(model.sync.version),
  );
}

/// 模板表行 → 实体。
domain.VehicleDefaultMaintenanceItem defaultItemFromRow(
  VehicleDefaultMaintenanceItemRow row,
) {
  return domain.VehicleDefaultMaintenanceItem(
    id: row.id,
    catalogId: row.catalogId,
    powertrainType: domain.PowertrainType.byWire(row.powertrainType),
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

/// 模板实体 + 指定 id → 插入用 Companion。
VehicleDefaultMaintenanceItemsCompanion defaultItemCompanion(
  domain.VehicleDefaultMaintenanceItem item,
  int id,
) {
  return VehicleDefaultMaintenanceItemsCompanion.insert(
    id: Value(id),
    catalogId: Value(item.catalogId),
    powertrainType: Value(item.powertrainType.wire),
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
  );
}
