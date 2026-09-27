// 测试数据 builder 层（≈ Java 测试的 TestDataFactory / ObjectMother）：
// 「一条最小合法数据」的唯一出口——四个核心实体的默认构造收编在这里，
// 测试只写与断言相关的增量，不再手抄 11 字段构造块。
//
// 纪律（2026-09-26 架构审查第三轮拍板）：
//  - 默认值只收编既有测试的高频事实（本田/22款思域/10000km/2023-08-12、
//    机油/5000km/6 个月、加油 92# 8.15 元/应付 300 元），不发明新数据；
//  - 保养记录的日期/里程/费用是断言值，保持必填，不虚构默认；
//  - 备份载荷里"重建已入库行"的构造（固定 id 逐字段钉死）继续用实体
//    构造器——契约测试要的就是逐字段钉死，不走 builder；
//  - 本文件保持纯 Dart：只 import 领域实体，不碰数据库与仓库。
//    需要仓库的播种动作（裸插车辆、按模板建车）归 widget_app.dart。
import 'package:lunio/core/date/local_date.dart';
import 'package:lunio/domain/entities/car.dart';
import 'package:lunio/domain/entities/fuel_price.dart';
import 'package:lunio/domain/entities/fuel_record.dart';
import 'package:lunio/domain/entities/maintenance_item.dart';
import 'package:lunio/domain/entities/maintenance_record.dart';
import 'package:lunio/domain/entities/powertrain_type.dart';
import 'package:lunio/domain/entities/sync_metadata.dart';

/// 测试标准同步元数据：synced / 2026-01-01（固定时刻，断言确定性）。
/// 与各测试文件原来的 `SyncMetadata(SyncStatus.synced, DateTime(2026))` 同值。
final SyncMetadata testSync =
    SyncMetadata(status: SyncStatus.synced, updatedAt: DateTime(2026));

/// 默认车辆：本田 / 22款思域 / 10000km / 2023-08-12 上路 / 燃油。
/// 品牌/型号/上路日期是身份字段（cars 表 {brand, model, roadDate} 唯一
/// 约束；Car.copyWith 不开放替换），所以走 builder 直参——一个用例建
/// 多辆车时用 [model] 区分（21款雅阁 等）。
Car defaultCar({
  String brand = '本田',
  String model = '22款思域',
  int currentMileageKm = 10000,
  LocalDate roadDate = const LocalDate(2023, 8, 12),
  PowertrainType powertrainType = PowertrainType.fuel,
  double? tankCapacityLiters,
  SyncMetadata? sync,
}) {
  return Car(
    brand: brand,
    model: model,
    powertrainType: powertrainType,
    currentMileageKm: currentMileageKm,
    roadDate: roadDate,
    tankCapacityLiters: tankCapacityLiters,
    sync: sync ?? testSync,
  );
}

/// 默认保养项目：机油 / 按里程 5000km + 按时间 6 个月双提醒 / 排序 1 /
/// 启用。阈值两字段（100/125）等于实体默认值，不再单列。
/// [mileageIntervalKm]/[timeIntervalMonths] 可显式传 null 关掉对应间隔
/// ——实体 copyWith 传 null 是"保留原值"，置空只能走这里。
MaintenanceItem defaultOilItem({
  int carsId = 0,
  String name = '机油',
  bool enabled = true,
  bool remindByMileage = true,
  bool remindByTime = true,
  int? mileageIntervalKm = 5000,
  int? timeIntervalMonths = 6,
  int sortOrder = 1,
  SyncMetadata? sync,
}) {
  return MaintenanceItem(
    carsId: carsId,
    name: name,
    enabled: enabled,
    remindByMileage: remindByMileage,
    remindByTime: remindByTime,
    mileageIntervalKm: mileageIntervalKm,
    timeIntervalMonths: timeIntervalMonths,
    sortOrder: sortOrder,
    sync: sync ?? testSync,
  );
}

/// 默认保养记录：日期/里程/费用/项目是断言值，保持必填不虚构默认；
/// 收编的只有 [sync] 与 [itemCosts] 空表两样样板。带 id 的更新构造
/// 也从这里走（[id] 直参），备份载荷契约块除外。
MaintenanceRecord defaultRecord({
  int? id,
  required int carId,
  required LocalDate date,
  required List<int> itemIds,
  required int costCents,
  required int mileageKm,
  String? note,
  List<RecordItemCost> itemCosts = const [],
  SyncMetadata? sync,
}) {
  return MaintenanceRecord(
    id: id,
    carId: carId,
    date: date,
    itemIds: itemIds,
    itemCosts: itemCosts,
    costCents: costCents,
    mileageKm: mileageKm,
    note: note,
    sync: sync ?? testSync,
  );
}

/// 默认加油记录：92# / 单价 8.15 元 / 应付 300 元 / 实付未填（fuel_test
/// fuelSeed 的口径归一为全仓默认）；备份往返等特殊金额由调用方显式传。
/// 容积由实体按 应付÷单价 自算（ADR 0015），不接受外部传入。
FuelRecord defaultFuelRecord(
  int carId, {
  required LocalDate date,
  FuelGrade grade = FuelGrade.gasoline92,
  int unitPriceCents = 815,
  int payableCents = 30000,
  int? actualCents,
  SyncMetadata? sync,
}) {
  return FuelRecord(
    carId: carId,
    date: date,
    grade: grade,
    unitPriceCents: unitPriceCents,
    payableCents: payableCents,
    actualCents: actualCents,
    sync: sync ?? testSync,
  );
}
