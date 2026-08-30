// 内置车型实体：添加车辆向导里"选品牌 → 选车型"两级选择器的数据来源。
//
// 与 VehicleDefaultMaintenanceItem 一起构成 asset 目录
// （built_in_vehicle_catalog.json），首启 bootstrap 灌库，幂等对账。
// 用户不能增删车型——这是只读目录数据。
import 'sync_metadata.dart';

class VehicleModel {
  const VehicleModel({
    this.id,
    this.catalogId,
    required this.brand,
    required this.model,
    required this.sortOrder,
    required this.sync,
  });

  /// 数据库主键。
  final int? id;

  /// asset 目录稳定标识，bootstrap 对账用。
  final String? catalogId;

  /// 品牌名，如"丰田"。
  final String brand;

  /// 车型名，如"卡罗拉 1.2T"。
  final String model;

  /// 品牌内排序权重。
  final int sortOrder;

  /// 云同步元数据。
  final SyncMetadata sync;
}
