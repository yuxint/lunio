// 内置"默认保养项目模板"实体：按 品牌+车型 维度预置的保养项配置。
//
// 数据来源是 asset（assets/data/built_in_vehicle_catalog.json），
// 首启时由 Repository bootstrap 灌入 vehicle_default_maintenance_items 表
// （幂等：按 catalogId 对账，新增则插入、移除则删除）。
// 用户添加车辆时，把所选车型的这批模板复制成车辆自己的保养项目。
//
// 与 MaintenanceItem 的区别：这是"目录数据"（不挂车），
// MaintenanceItem 是"车辆实例数据"（挂某辆车，用户可改可删）。
import 'sync_metadata.dart';

class VehicleDefaultMaintenanceItem {
  const VehicleDefaultMaintenanceItem({
    this.id,
    this.catalogId,
    required this.vehicleBrand,
    required this.vehicleModel,
    required this.itemName,
    required this.remindByMileage,
    required this.remindByTime,
    required this.sortOrder,
    required this.sync,
    this.mileageIntervalKm,
    this.timeIntervalMonths,
    this.notOverdueUpperLimit = 100,
    this.overdueUpperLimit = 125,
  });

  /// 数据库主键。
  final int? id;

  /// asset 目录里的稳定标识（如 "toyota-corolla-fuel:engine-oil"），
  /// bootstrap 按它做 upsert/删除对账。可为 null（兼容旧数据）。
  final String? catalogId;

  /// 适配品牌（与 VehicleModel.brand 对应）。
  final String vehicleBrand;

  /// 适配车型（与 VehicleModel.model 对应）。
  final String vehicleModel;

  /// 项目名，如"机油""空气滤芯"。
  final String itemName;

  /// 是否按里程提醒（复制给车辆项目时继承）。
  final bool remindByMileage;

  /// 是否按时间提醒。
  final bool remindByTime;

  /// 里程间隔（公里）。
  final int? mileageIntervalKm;

  /// 时间间隔（月）。
  final int? timeIntervalMonths;

  /// 到期（warning）阈值百分比。
  final double notOverdueUpperLimit;

  /// 超期（danger）阈值百分比。
  final double overdueUpperLimit;

  /// 排序权重。
  final int sortOrder;

  /// 云同步元数据。
  final SyncMetadata sync;
}
