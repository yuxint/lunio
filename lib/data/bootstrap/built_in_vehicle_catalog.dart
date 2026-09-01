// 内置车型目录：解析 asset JSON，供首启 bootstrap 把车型库和默认保养
// 项目模板灌入数据库。
//
// 目录 asset 按字母分片存储（车型库大，单文件不便维护）：
//   assets/data/catalog/templates.json        —— schemaVersion + 按动力类型的保养模板；
//   assets/data/catalog/vehicles_a.json ... vehicles_z.json
//                                             —— 每个字母一个分片
//                                                {schemaVersion, letter, vehicles}。
// 车型条目名用懂车帝原始车系名（ADR 0003），每条带"推荐动力类型"（template
// 字段，仅作添加向导预选）；默认保养模板按动力类型分组（fuel/hybrid/plugIn/
// extended/ev 五组，增程组内容同插混组），不再按品牌+车型逐条展开。
// 例外：个别车型有厂商专属保养项（如思域的燃油宝等），通过条目上可选的
// itemTemplate 字段引用 templates.json 顶层 vehicleTemplates 里的
// 车型专属模板（ADR 0004）；专属模板不进数据库，只在添加向导取默认
// 项目时按（品牌+车型+推荐动力类型一致）命中。
//
// typedef ≈ Java 的函数式接口：这里把"目录加载器"抽象成可注入的函数类型，
// 测试可以传入内存版本而不用真 asset（虽然当前加载器在 Repository 内
// 固定为 asset 版本）。
import 'dart:convert';

import 'package:flutter/services.dart';

import '../../domain/entities/powertrain_type.dart';
import '../../domain/entities/sync_metadata.dart';
import '../../domain/entities/vehicle_default_maintenance_item.dart';
import '../../domain/entities/vehicle_model.dart';

/// 目录加载器类型：无参、异步返回目录。
typedef BuiltInVehicleCatalogLoader = Future<BuiltInVehicleCatalog> Function();

/// 车型分片的字母清单（a–z 全量生成，无品牌的字母是空分片，加载不用判存在）。
const _catalogShardLetters = [
  'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm',
  'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z',
];

/// 从 Flutter asset 读取分片目录：templates.json + 26 个字母分片拼装成
/// 完整目录结构后，走 [BuiltInVehicleCatalog.fromJson] 统一校验。
/// 注意：本文件因此 import 了 Flutter services（rootBundle）——
/// data 层对 Flutter 的反向依赖点（审查报告 §3）。
Future<BuiltInVehicleCatalog> loadBuiltInVehicleCatalogAsset() async {
  final templatesJson = await rootBundle.loadString(
    'assets/data/catalog/templates.json',
  );
  final templatesMap = (jsonDecode(templatesJson) as Map)
      .cast<String, Object?>();
  if (templatesMap['schemaVersion'] != 2) {
    throw ArgumentError('Unsupported vehicle catalog schemaVersion');
  }
  final vehicles = <Object?>[];
  for (final letter in _catalogShardLetters) {
    final shardJson = await rootBundle.loadString(
      'assets/data/catalog/vehicles_$letter.json',
    );
    final shard = (jsonDecode(shardJson) as Map).cast<String, Object?>();
    if (shard['schemaVersion'] != 2) {
      throw ArgumentError(
        'Unsupported vehicle catalog shard schemaVersion: vehicles_$letter',
      );
    }
    vehicles.addAll((shard['vehicles'] as List?) ?? const []);
  }
  return BuiltInVehicleCatalog.fromJson({
    'schemaVersion': 2,
    'templates': templatesMap['templates'],
    'vehicleTemplates': templatesMap['vehicleTemplates'],
    'vehicles': vehicles,
  });
}

/// 解析后的目录：模板集合 + 车型列表，可展开成两张表的实体。
class BuiltInVehicleCatalog {
  const BuiltInVehicleCatalog({
    required this.templates,
    required this.vehicles,
    this.vehicleTemplates = const {},
  });

  /// 模板键（= 动力类型 wire 值）→ 该模板的保养项目规格列表。
  final Map<String, List<BuiltInMaintenanceItemSpec>> templates;

  /// 车型专属模板键（如 "civicFuel"）→ 保养项目规格列表。
  /// 与 [templates] 的区别：键不是动力类型，整组不进
  /// vehicle_default_maintenance_items 表，只在添加向导按车型命中。
  final Map<String, List<BuiltInMaintenanceItemSpec>> vehicleTemplates;

  /// 车型种子列表（约 1675 个：懂车帝在售 1645 + 停售 30，ADR 0003）。
  final List<BuiltInVehicleSeed> vehicles;

  /// 解析 + 完整性校验（fail-fast，坏目录直接抛 ArgumentError）：
  ///  - schemaVersion 必须是 2；
  ///  - 每个模板至少一个项目、模板内项目 id 不重复；
  ///  - 车型 id 不重复、引用的 template（推荐动力类型）必须存在；
  ///  - 车型引用的 itemTemplate（车型专属模板）必须在 vehicleTemplates 里。
  factory BuiltInVehicleCatalog.fromJson(Map<String, Object?> json) {
    final schemaVersion = json['schemaVersion'];
    if (schemaVersion != 2) {
      throw ArgumentError('Unsupported vehicle catalog schemaVersion');
    }
    final templatesJson = (json['templates'] as Map).cast<String, Object?>();
    final templates = templatesJson.map(_parseTemplateEntry);
    final vehicleTemplatesJson =
        (json['vehicleTemplates'] as Map?)?.cast<String, Object?>();
    final vehicleTemplates = vehicleTemplatesJson?.map(_parseTemplateEntry) ??
        const <String, List<BuiltInMaintenanceItemSpec>>{};
    final vehicles = ((json['vehicles'] as List?) ?? const [])
        .cast<Map<String, Object?>>()
        .map(BuiltInVehicleSeed.fromJson)
        .toList();
    _validateUniqueIds(vehicles.map((vehicle) => vehicle.id), 'vehicle');
    for (final vehicle in vehicles) {
      if (!templates.containsKey(vehicle.template)) {
        throw ArgumentError('Unknown vehicle template: ${vehicle.template}');
      }
      final itemTemplate = vehicle.itemTemplate;
      if (itemTemplate != null &&
          !vehicleTemplates.containsKey(itemTemplate)) {
        throw ArgumentError(
          'Unknown vehicle itemTemplate: $itemTemplate '
          '(${vehicle.brand} ${vehicle.model})',
        );
      }
    }
    return BuiltInVehicleCatalog(
      templates: templates,
      vehicles: vehicles,
      vehicleTemplates: vehicleTemplates,
    );
  }

  /// 解析单个模板条目（键 + 项目规格列表，组内 id 查重、空组报错），
  /// templates 与 vehicleTemplates 共用。
  static MapEntry<String, List<BuiltInMaintenanceItemSpec>>
      _parseTemplateEntry(String key, Object? value) {
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
    if (items.isEmpty) {
      throw ArgumentError('Template has no maintenance items: $templateKey');
    }
    return MapEntry(templateKey, items);
  }

  /// 按品牌+车型找目录条目（自定义车型不在目录里，返回 null）。
  /// 同名第一条生效，与添加向导推荐动力类型的查找约定一致。
  BuiltInVehicleSeed? findVehicle(String brand, String model) {
    for (final vehicle in vehicles) {
      if (vehicle.brand == brand && vehicle.model == model) {
        return vehicle;
      }
    }
    return null;
  }

  /// 车型专属模板的项目规格；键不存在返回 null。
  List<BuiltInMaintenanceItemSpec>? vehicleTemplateItems(String key) {
    return vehicleTemplates[key];
  }

  /// 展开为 vehicle_models 表实体。sortOrder 按目录顺序 1..n；
  /// template 是推荐动力类型（添加向导预选用）。
  List<VehicleModel> vehicleModels(SyncMetadata sync) {
    return [
      for (final entry in vehicles.indexed)
        VehicleModel(
          catalogId: entry.$2.id,
          brand: entry.$2.brand,
          model: entry.$2.model,
          template: PowertrainType.byWire(entry.$2.template),
          sortOrder: entry.$1 + 1,
          sync: sync,
        ),
    ];
  }

  /// 展开为 vehicle_default_maintenance_items 表实体：
  /// 每个动力类型模板 × 其每个项目（约 5 组 × 10 项 ≈ 50 行），
  /// catalogId = "tpl:{动力类型}:{项目id}"（bootstrap 幂等对账的稳定标识）。
  List<VehicleDefaultMaintenanceItem> defaultMaintenanceItems(
    SyncMetadata sync,
  ) {
    return [
      for (final entry in templates.entries)
        for (final item in entry.value.indexed)
          VehicleDefaultMaintenanceItem(
            catalogId: 'tpl:${entry.key}:${item.$2.id}',
            powertrainType: PowertrainType.byWire(entry.key),
            itemName: item.$2.name,
            remindByMileage: item.$2.remindByMileage,
            remindByTime: item.$2.remindByTime,
            mileageIntervalKm: item.$2.mileageIntervalKm,
            timeIntervalMonths: item.$2.timeIntervalMonths,
            sortOrder: item.$1 + 1,
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
    this.itemTemplate,
  });

  /// 稳定标识（"vehicle-dcd-" + 懂车帝 品牌|车系名 的哈希）。
  final String id;

  /// 品牌名。
  final String brand;

  /// 车型名（懂车帝原始车系名）。
  final String model;

  /// 推荐动力类型的 wire 值（如 "fuel"/"extended"）。
  final String template;

  /// 车型专属保养模板键（可选，如 "civicFuel"），引用 templates.json 顶层
  /// vehicleTemplates；null 表示没有专属模板，走动力类型通用模板（ADR 0004）。
  final String? itemTemplate;

  factory BuiltInVehicleSeed.fromJson(Map<String, Object?> json) {
    return BuiltInVehicleSeed(
      id: _nonEmptyString(json['id'], 'vehicle id'),
      brand: _nonEmptyString(json['brand'], 'vehicle brand'),
      model: _nonEmptyString(json['model'], 'vehicle model'),
      template: _nonEmptyString(json['template'], 'vehicle template'),
      itemTemplate: json['itemTemplate'] == null
          ? null
          : _nonEmptyString(json['itemTemplate'], 'vehicle itemTemplate'),
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
