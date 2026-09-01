// 内置车型实体：添加车辆向导里"选品牌 → 选车型"两级选择器的数据来源。
//
// 与按动力类型的保养模板一起构成 asset 目录（assets/data/catalog/ 按字母分片），
// 首启 bootstrap 灌库，幂等对账。用户不能增删车型——这是只读目录数据。
import 'powertrain_type.dart';
import 'sync_metadata.dart';

class VehicleModel {
  const VehicleModel({
    this.id,
    this.catalogId,
    required this.brand,
    required this.model,
    required this.template,
    required this.sortOrder,
    required this.sync,
  });

  /// 数据库主键。
  final int? id;

  /// asset 目录稳定标识，bootstrap 对账用。
  final String? catalogId;

  /// 品牌名，如"丰田"。
  final String brand;

  /// 车型名，如"卡罗拉 1.2T"（懂车帝原始车系名，ADR 0003）。
  final String model;

  /// 推荐动力类型：目录按车系名/品牌推断，只在添加向导里预选动力 chip，
  /// 用户可改；不参与默认项目的取数（默认项目只看用户选的动力类型）。
  final PowertrainType template;

  /// 品牌内排序权重。
  final int sortOrder;

  /// 云同步元数据。
  final SyncMetadata sync;
}
