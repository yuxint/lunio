// 内置车型目录：解析 asset JSON（assets/data/built_in_vehicle_catalog.json），
// 供首启 bootstrap 把车型库和默认保养项目模板灌入数据库。
//
// 目录 JSON 的结构（schemaVersion = 2，与备份契约的 2 无关）：
//   templates: { "fuel": [ {id,name,remindByMileage,...}, ... ], "ev": [...] }
//   vehicles:  [ {id,brand,model,template:"fuel"}, ... ]
// 一个 template 是一组保养项目，多个车型可共用同一 template
// （如所有燃油车共用 fuel 模板）。
//
// typedef ≈ Java 的函数式接口：这里把"目录加载器"抽象成可注入的函数类型，
// 测试可以传入内存版本而不用真 asset（虽然当前加载器在 Repository 内
// 固定为 asset 版本）。
import 'dart:convert';

import 'package:flutter/services.dart';

import '../../domain/entities/sync_metadata.dart';
import '../../domain/entities/vehicle_default_maintenance_item.dart';
import '../../domain/entities/vehicle_model.dart';

/// 目录加载器类型：无参、异步返回目录。
typedef BuiltInVehicleCatalogLoader = Future<BuiltInVehicleCatalog> Function();

/// 从 Flutter asset 根读取目录 JSON 并解析。
/// 注意：本文件因此 import 了 Flutter services（rootBundle）——
/// data 层对 Flutter 的反向依赖点（审查报告 §3）。
Future<BuiltInVehicleCatalog> loadBuiltInVehicleCatalogAsset() async {
  final json = await rootBundle.loadString(
    'assets/data/built_in_vehicle_catalog.json',
  );
  return BuiltInVehicleCatalog.fromJson(
    (jsonDecode(json) as Map).cast<String, Object?>(),
  );
}

/// 解析后的目录：模板集合 + 车型列表，可展开成两张表的实体。
class BuiltInVehicleCatalog {
  const BuiltInVehicleCatalog({
    required this.templates,
    required this.vehicles,
  });

  /// templateKey → 该模板的保养项目规格列表。
  final Map<String, List<BuiltInMaintenanceItemSpec>> templates;

  /// 车型种子列表（约 190 个）。
  final List<BuiltInVehicleSeed> vehicles;

  /// 解析 + 完整性校验（fail-fast，坏目录直接抛 ArgumentError）：
  ///  - schemaVersion 必须是 2；
  ///  - 每个模板至少一个项目、模板内项目 id 不重复；
  ///  - 车型 id 不重复、引用的 template 必须存在。
  factory BuiltInVehicleCatalog.fromJson(Map<String, Object?> json) {
    final schemaVersion = json['schemaVersion'];
    if (schemaVersion != 2) {
      throw ArgumentError('Unsupported vehicle catalog schemaVersion');
    }
    final templatesJson = (json['templates'] as Map).cast<String, Object?>();
    final templates = templatesJson.map((key, value) {
      final templateKey = _nonEmptyString(key, 'template key');
      final items = (value as List)
          .cast<Map<String, Object?>>()
          .map(BuiltInMaintenanceItemSpec.fromJson)
          .toList();
      _validateUniqueIds(
        items.map((item) => item.id),
        'maintenance item',
        templateKey,
      );
      return MapEntry(templateKey, items);
    });
    for (final entry in templates.entries) {
      if (entry.value.isEmpty) {
        throw ArgumentError('Template has no maintenance items: ${entry.key}');
      }
    }
    final vehicles = ((json['vehicles'] as List?) ?? const [])
        .cast<Map<String, Object?>>()
        .map(BuiltInVehicleSeed.fromJson)
        .toList();
    _validateUniqueIds(vehicles.map((vehicle) => vehicle.id), 'vehicle');
    for (final vehicle in vehicles) {
      if (!templates.containsKey(vehicle.template)) {
        throw ArgumentError('Unknown vehicle template: ${vehicle.template}');
      }
    }
    return BuiltInVehicleCatalog(templates: templates, vehicles: vehicles);
  }

  /// 展开为 vehicle_models 表实体。sortOrder 按目录顺序 1..n。
  List<VehicleModel> vehicleModels(SyncMetadata sync) {
    return [
      for (final entry in vehicles.indexed)
        VehicleModel(
          catalogId: entry.$2.id,
          brand: entry.$2.brand,
          model: entry.$2.model,
          sortOrder: entry.$1 + 1,
          sync: sync,
        ),
    ];
  }

  /// 展开为 vehicle_default_maintenance_items 表实体：
  /// 每个车型 × 其模板的每个项目，catalogId = "{车型id}:{项目id}"
  /// （bootstrap 幂等对账的稳定标识）。
  List<VehicleDefaultMaintenanceItem> defaultMaintenanceItems(
    SyncMetadata sync,
  ) {
    return [
      for (final vehicle in vehicles)
        for (final entry in templates[vehicle.template]!.indexed)
          VehicleDefaultMaintenanceItem(
            catalogId: '${vehicle.id}:${entry.$2.id}',
            vehicleBrand: vehicle.brand,
            vehicleModel: vehicle.model,
            itemName: entry.$2.name,
            remindByMileage: entry.$2.remindByMileage,
            remindByTime: entry.$2.remindByTime,
            mileageIntervalKm: entry.$2.mileageIntervalKm,
            timeIntervalMonths: entry.$2.timeIntervalMonths,
            sortOrder: entry.$1 + 1,
            sync: sync,
          ),
    ];
  }
}

/// 车型种子（目录 JSON 里的一条 vehicle 记录）。
class BuiltInVehicleSeed {
  const BuiltInVehicleSeed({
    required this.id,
    required this.brand,
    required this.model,
    required this.template,
  });

  /// 稳定标识，如 "toyota-corolla-fuel"。
  final String id;

  /// 品牌名。
  final String brand;

  /// 车型名。
  final String model;

  /// 使用的模板 key（如 "fuel"/"ev"）。
  final String template;

  factory BuiltInVehicleSeed.fromJson(Map<String, Object?> json) {
    return BuiltInVehicleSeed(
      id: _nonEmptyString(json['id'], 'vehicle id'),
      brand: _nonEmptyString(json['brand'], 'vehicle brand'),
      model: _nonEmptyString(json['model'], 'vehicle model'),
      template: _nonEmptyString(json['template'], 'vehicle template'),
    );
  }
}

/// 保养项目规格（模板里的一条 item 记录）。校验规则与
/// MaintenanceItem.validate 一致：至少一种提醒方式、间隔为正。
class BuiltInMaintenanceItemSpec {
  const BuiltInMaintenanceItemSpec({
    required this.id,
    required this.name,
    required this.remindByMileage,
    required this.remindByTime,
    this.mileageIntervalKm,
    this.timeIntervalMonths,
  });

  final String id;
  final String name;
  final bool remindByMileage;
  final bool remindByTime;
  final int? mileageIntervalKm;
  final int? timeIntervalMonths;

  factory BuiltInMaintenanceItemSpec.fromJson(Map<String, Object?> json) {
    final remindByMileage = json['remindByMileage'] as bool;
    final remindByTime = json['remindByTime'] as bool;
    final mileageIntervalKm = json['mileageIntervalKm'] as int?;
    final timeIntervalMonths = json['timeIntervalMonths'] as int?;
    if (!remindByMileage && !remindByTime) {
      throw ArgumentError('Maintenance item must remind by mileage or time');
    }
    if (remindByMileage &&
        (mileageIntervalKm == null || mileageIntervalKm <= 0)) {
      throw ArgumentError('Mileage reminder requires a positive interval');
    }
    if (remindByTime &&
        (timeIntervalMonths == null || timeIntervalMonths <= 0)) {
      throw ArgumentError('Time reminder requires a positive interval');
    }
    return BuiltInMaintenanceItemSpec(
      id: _nonEmptyString(json['id'], 'maintenance item id'),
      name: _nonEmptyString(json['name'], 'maintenance item name'),
      remindByMileage: remindByMileage,
      remindByTime: remindByTime,
      mileageIntervalKm: mileageIntervalKm,
      timeIntervalMonths: timeIntervalMonths,
    );
  }
}

/// 字段必须是非空字符串，否则抛错（目录数据 fail-fast 校验）。
String _nonEmptyString(Object? value, String fieldName) {
  if (value is! String || value.trim().isEmpty) {
    throw ArgumentError('Invalid $fieldName');
  }
  return value;
}

/// id 去重校验（Set.add 返回 false 即重复）。
void _validateUniqueIds(Iterable<String> ids, String label, [String? scope]) {
  final seen = <String>{};
  for (final id in ids) {
    if (!seen.add(id)) {
      final suffix = scope == null ? '' : ' in $scope';
      throw ArgumentError('Duplicate $label id$suffix: $id');
    }
  }
}
