// 内置"默认保养项目模板"实体：按 动力类型 维度预置的保养项配置。
//
// 数据来源是 asset（assets/data/catalog/templates.json），首启时由
// Repository bootstrap 灌入 vehicle_default_maintenance_items 表
// （幂等：按 catalogId 对账，新增则插入、移除则删除）。
// 用户添加车辆时，按所选动力类型把这组模板复制成车辆自己的保养项目；
// "恢复默认项目"也按动力类型取。
//
// 与 MaintenanceItem 的区别：这是"目录数据"（不挂车；库里按动力类型
// 五组各一组，另有个别车型专属模板——如 civicFuel——只作内存草稿不落库，
// 见 docs/adr/0004），MaintenanceItem 是"车辆实例数据"（挂某辆车，
// 用户可改可删）。
import 'powertrain_type.dart';
import 'sync_metadata.dart';

class VehicleDefaultMaintenanceItem {
  const VehicleDefaultMaintenanceItem({
    this.id,
    this.catalogId,
    required this.powertrainType,
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

  /// asset 目录里的稳定标识（如 "tpl:fuel:engine-oil"），
  /// bootstrap 按它做 upsert/删除对账。可为 null（兼容旧数据）。
  final String? catalogId;

  /// 适配的动力类型（模板按动力类型分组，共五组；增程组内容同插混组）。
  final PowertrainType powertrainType;

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
