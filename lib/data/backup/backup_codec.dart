// 备份 JSON 的编解码器（≈ Java 里的 Jackson 手写 Serializer/Deserializer）。
//
// 备份契约（schemaVersion = 5，与数据库 schemaVersion 是两套独立版本号）：
// {
//   "schemaVersion": 5,
//   "cars": [ { id, brand, model, powertrainType, currentMileageKm, roadDate,
//               tankCapacityLiters, totalTankCapacityLiters, sync } ],
//   "maintenanceItems": [ { id, carsId, name, ..., sync } ],
//   "records": [ { id, carId, date, itemIds[], itemCosts[], costCents,
//                  mileageKm, note, sync } ],
//   "fuelPrediction": { "province": "湖北", "gradeCode": "92" },
//   "fuelPredictions": [ { carId, fuelPercent, sync } ],
//   "fuelRecords": [ { carId, date, grade, unitPriceCents, payableCents,
//                      actualCents, volumeLiters, sync } ],
//   "diagnosticsProbes": [ { carId, name, command, parseType, enabled,
//                            refreshIntervalSeconds, header, sync } ]
// }
// itemCosts 条目：{ itemId, materialCents, laborCents, costCents }，
// 三个金额都可空（null = 未填），只写有内容的项目（ADR 0010）。
// fuelRecords 条目不带 id：行 id 恢复时重新生成雪花，备份里没有引用
// 它的地方（与 fuelPredictions 同先例；ADR 0014）。volumeLiters 导出
// 仅为镜像库内预留列，恢复时由实体按 应付÷单价 重算（ADR 0015）。
// diagnosticsProbes 条目不带自身 id / catalogKey：行 id 恢复时重新生成
// 雪花（沿 fuelRecords 先例）；catalogKey 是内置标识，段只导自定义项
// ——内置五条不进备份、恢复后由每车 bootstrap 幂等重建（ADR 0021
// 修订节）。carId 是备份里的车辆 id，恢复时经 carIdMap 重映射；
// refreshIntervalSeconds 是用户刷新规则，header 是私有 DID 预留。
// enabled 是用户数据，随段导出往返保留。
//
// 版本兼容（ADR 0010 确立先例：纯增量缺失按空读入）：解码接受 v1–v5
// ——v2 只比 v1 多 itemCosts 字段，v1 条目没有它就等于"全部项目费用未
// 填"；v3 只比 v2 多 fuelRecords 字段，v1/v2 没有它就等于"没有加油记录"；
// v4 只比 v3 多 diagnosticsProbes 字段，v1–v3 没有它就等于"没有自定义
// 检测点"；v5 只比 v4 多 cars.totalTankCapacityLiters 与检测点的
// carId/refreshIntervalSeconds/header。v1–v4 的检测点段没有 carId，
// 恢复到第一辆车；缺省间隔 60（2026-11-21 起；此前 30）、header/总容积 null。这不是 ADR 0005
// 禁止的"旧字段语义变化回退"。除此之外的版本直接拒绝，不做字段回退。
// 油价缓存与手填油价是临时数据，不进备份。
//
// ⚠ v3 例外（ADR 0015，2026-09-22）：fuelRecords 的条目结构在版本号
// 不变的前提下就地重定义过一次（旧五字段 日期/里程/金额/升数/加满 →
// 新五字段 日期/油品/单价/应付/实付）。含旧结构加油条目的 v3 备份文件
// 解码会失败、整单被拒——拍板依据：记录卡在旧结构存续期间一直被屏蔽，
// 不存在含加油条目的真实备份（ADR 0015"你的操作顺序"一节）。
//
// ⚠ 契约边界（改字段前必读）：
//  - 不包含偏好（主题/应用车辆/通知设置/snooze 等）；
//  - 不包含停车倒计时（临时状态）；
//  - 不包含油价缓存/手填油价（临时状态）；
//  - 不包含车型目录/默认项目模板/内置检测点（恢复后由 bootstrap 幂等
//    重建）。
// 导出在 Repository.exportBackupPayload，导入在 restoreBackupPayload。
import 'dart:convert';

import '../../core/date/local_date.dart';
import '../../domain/entities/car.dart';
import '../../domain/entities/diagnostics_parse_type.dart';
import '../../domain/entities/diagnostics_probe.dart';
import '../../domain/entities/fuel_prediction.dart';
import '../../domain/entities/fuel_price.dart';
import '../../domain/entities/fuel_record.dart';
import '../../domain/entities/maintenance_item.dart';
import '../../domain/entities/maintenance_record.dart';
import '../../domain/entities/powertrain_type.dart';
import '../../domain/entities/sync_metadata.dart';
/// 备份载荷对象：待编码/已解码的全量业务数据。
class BackupPayload {
  const BackupPayload({
    required this.schemaVersion,
    this.cars = const [],
    this.maintenanceItems = const [],
    this.records = const [],
    this.fuelPrediction,
    this.fuelPredictions = const [],
    this.fuelRecords = const [],
    this.diagnosticsProbes = const [],
  });

  /// 备份契约版本（v1 = 无项目费用；v2 = 增项目费用，ADR 0010；
  /// v3 = 增加油记录，ADR 0014；v4 = 增自定义检测点，ADR 0021；
  /// v5 = 增车辆总容积与检测点 carId/刷新间隔/header，ADR 0021 修订节/
  /// 0022）。
  final int schemaVersion;
  final List<Car> cars;
  final List<MaintenanceItem> maintenanceItems;
  final List<MaintenanceRecord> records;

  /// 全局加油设置（省份 + 油品），用户没改过为 null。
  final BackupFuelPreference? fuelPrediction;

  /// 每辆车的加油预测设置（剩余油量；容积在 cars 条目里）。
  final List<FuelPrediction> fuelPredictions;

  /// 加油流水（ADR 0014）。v1/v2 备份没有该字段，解码按空读入。
  final List<FuelRecord> fuelRecords;

  /// 自定义检测点（ADR 0021 修订节）：段只导自定义项，内置不进备份
  /// （恢复后每车 bootstrap 重建）。条目不带自身 id / catalogKey，解码
  /// 产物永远 catalogKey = null；带 carId（v5 起）与刷新间隔/header。
  /// v1–v3 备份没有该字段，解码按空读入；v4 无 carId，归第一辆车。
  final List<DiagnosticsProbe> diagnosticsProbes;
}

/// 备份里的全局加油设置（省份 + 油品编号）。
class BackupFuelPreference {
  const BackupFuelPreference({required this.province, required this.gradeCode});

  final String province;
  final String gradeCode;
}

/// 编解码器。无状态，UI 层（settings_data.dart）直接实例化使用。
final class BackupCodec {
  const BackupCodec();

  /// 当前写入的备份契约版本。
  static const int currentSchemaVersion = 5;

  /// 解码接受的版本：当前版本 + 纯增量兼容的 v1–v4（缺 itemCosts =
  /// 费用全空；缺 fuelRecords = 无加油记录；缺 diagnosticsProbes = 无
  /// 自定义检测点；v4 检测点无 carId = 归第一辆车，ADR 0010/0014/
  /// 0021/0022）。
  static const List<int> supportedSchemaVersions = [1, 2, 3, 4, 5];

  /// 编码为 JSON 字符串（导出文件内容）。
  String encode(BackupPayload payload) {
    return jsonEncode({
      'schemaVersion': payload.schemaVersion,
      'cars': payload.cars.map(_carToJson).toList(),
      'maintenanceItems': payload.maintenanceItems.map(_itemToJson).toList(),
      'records': payload.records.map(_recordToJson).toList(),
      'fuelPrediction': payload.fuelPrediction == null
          ? null
          : {
              'province': payload.fuelPrediction!.province,
              'gradeCode': payload.fuelPrediction!.gradeCode,
            },
      'fuelPredictions': payload.fuelPredictions
          .map(_fuelPredictionToJson)
          .toList(),
      'fuelRecords': payload.fuelRecords.map(_fuelRecordToJson).toList(),
      // v4 新增段（ADR 0021）：条目为自定义检测点，字段清单见
      // _diagnosticsProbeToJson。追加在契约末尾，保持前面各段字节不变。
      'diagnosticsProbes': payload.diagnosticsProbes
          .map(_diagnosticsProbeToJson)
          .toList(),
    });
  }

  /// 从 JSON 字符串解码（导入文件内容）。
  ///
  /// 接受 v1–v5（见 supportedSchemaVersions），其他版本抛 UnsupportedError，
  /// UI 提示"不支持的备份文件"（ADR 0005：不做版本分支兼容；ADR 0010/0014/0021：
  /// 纯增量缺失按空读入——v1/v2 项目费用全空、加油记录为空，v1–v3 无自定义
  /// 检测点，v4 检测点无 carId 归第一辆车）。引用完整性与业务规则（金额/里程
  /// 非负等）由 Repository 的两层预校验在事务外负责（审查报告 R35），codec
  /// 只做结构解码。
  BackupPayload decode(String json) {
    final map = jsonDecode(json) as Map<String, Object?>;
    final version = map['schemaVersion'] as int;
    if (!supportedSchemaVersions.contains(version)) {
      throw UnsupportedError('Unsupported backup schemaVersion: $version');
    }
    final cars = ((map['cars'] as List?) ?? const [])
        .cast<Map<String, Object?>>()
        .map(_carFromJson)
        .toList();
    final firstCarId = cars.isEmpty ? null : cars.first.id;
    final fuelPreferenceMap = map['fuelPrediction'] as Map<String, Object?>?;
    return BackupPayload(
      schemaVersion: version,
      cars: cars,
      maintenanceItems: ((map['maintenanceItems'] as List?) ?? const [])
          .cast<Map<String, Object?>>()
          .map(_itemFromJson)
          .toList(),
      records: ((map['records'] as List?) ?? const [])
          .cast<Map<String, Object?>>()
          .map(_recordFromJson)
          .toList(),
      fuelPrediction: fuelPreferenceMap == null
          ? null
          : BackupFuelPreference(
              province: fuelPreferenceMap['province'] as String,
              gradeCode: fuelPreferenceMap['gradeCode'] as String,
            ),
      fuelPredictions: ((map['fuelPredictions'] as List?) ?? const [])
          .cast<Map<String, Object?>>()
          .map(_fuelPredictionFromJson)
          .toList(),
      // v1/v2 备份没有 fuelRecords 字段 = 没有加油记录，按空列表读入
      // （ADR 0014 的纯增量兼容，沿用 itemCosts 先例）。
      fuelRecords: ((map['fuelRecords'] as List?) ?? const [])
          .cast<Map<String, Object?>>()
          .map(_fuelRecordFromJson)
          .toList(),
      // v1–v3 备份没有 diagnosticsProbes 字段 = 没有自定义检测点，按空
      // 列表读入（ADR 0021 的纯增量兼容，沿 fuelRecords 先例）。条目
      // 不读自身 id / catalogKey——解码产物永远是无 id 的自定义检测点；
      // v5 起读 carId，v4 及更早无 carId 归第一辆车（没有车则丢弃）。
      diagnosticsProbes: ((map['diagnosticsProbes'] as List?) ?? const [])
          .cast<Map<String, Object?>>()
          .map(
            (probe) => _diagnosticsProbeFromJson(
              probe,
              fallbackCarId: firstCarId,
            ),
          )
          .whereType<DiagnosticsProbe>()
          .toList(),
    );
  }

  Map<String, Object?> _carToJson(Car car) {
    return {
      'id': car.id,
      'brand': car.brand,
      'model': car.model,
      'powertrainType': car.powertrainType.wire,
      'currentMileageKm': car.currentMileageKm,
      'roadDate': car.roadDate.toString(),
      'tankCapacityLiters': car.tankCapacityLiters,
      'totalTankCapacityLiters': car.totalTankCapacityLiters,
      'sync': car.sync.toJson(),
    };
  }

  Map<String, Object?> _itemToJson(MaintenanceItem item) {
    return {
      'id': item.id,
      'carsId': item.carsId,
      'name': item.name,
      'enabled': item.enabled,
      'remindByMileage': item.remindByMileage,
      'remindByTime': item.remindByTime,
      'mileageIntervalKm': item.mileageIntervalKm,
      'timeIntervalMonths': item.timeIntervalMonths,
      'notOverdueUpperLimit': item.notOverdueUpperLimit,
      'overdueUpperLimit': item.overdueUpperLimit,
      'sortOrder': item.sortOrder,
      'sync': item.sync.toJson(),
    };
  }

  MaintenanceItem _itemFromJson(Map<String, Object?> json) {
    return MaintenanceItem(
      id: json['id'] as int?,
      carsId: json['carsId'] as int,
      name: json['name'] as String,
      enabled: json['enabled'] as bool,
      remindByMileage: json['remindByMileage'] as bool,
      remindByTime: json['remindByTime'] as bool,
      mileageIntervalKm: json['mileageIntervalKm'] as int?,
      timeIntervalMonths: json['timeIntervalMonths'] as int?,
      notOverdueUpperLimit: (json['notOverdueUpperLimit'] as num).toDouble(),
      overdueUpperLimit: (json['overdueUpperLimit'] as num).toDouble(),
      sortOrder: json['sortOrder'] as int,
      sync: SyncMetadata.fromJson(
        (json['sync'] as Map).cast<String, Object?>(),
      ),
    );
  }

  Car _carFromJson(Map<String, Object?> json) {
    return Car(
      id: json['id'] as int?,
      brand: json['brand'] as String,
      model: json['model'] as String,
      powertrainType: PowertrainType.byWire(json['powertrainType'] as String),
      currentMileageKm: json['currentMileageKm'] as int,
      roadDate: LocalDate.parse(json['roadDate'] as String),
      tankCapacityLiters: (json['tankCapacityLiters'] as num?)?.toDouble(),
      totalTankCapacityLiters:
          (json['totalTankCapacityLiters'] as num?)?.toDouble(),
      sync: SyncMetadata.fromJson(
        (json['sync'] as Map).cast<String, Object?>(),
      ),
    );
  }

  Map<String, Object?> _recordToJson(MaintenanceRecord record) {
    return {
      'id': record.id,
      'carId': record.carId,
      'date': record.date.toString(),
      'itemIds': record.itemIds,
      'itemCosts': record.itemCosts.map(_itemCostToJson).toList(),
      'costCents': record.costCents,
      'mileageKm': record.mileageKm,
      'note': record.note,
      'sync': record.sync.toJson(),
    };
  }

  Map<String, Object?> _itemCostToJson(RecordItemCost cost) {
    return {
      'itemId': cost.itemId,
      'materialCents': cost.materialCents,
      'laborCents': cost.laborCents,
      'costCents': cost.costCents,
    };
  }

  MaintenanceRecord _recordFromJson(Map<String, Object?> json) {
    return MaintenanceRecord(
      id: json['id'] as int?,
      carId: json['carId'] as int,
      date: LocalDate.parse(json['date'] as String),
      itemIds: (json['itemIds'] as List).cast<int>(),
      // v1 备份没有 itemCosts 字段 = 全部项目费用未填，按空列表读入
      // （ADR 0010 的纯增量兼容）。
      itemCosts: ((json['itemCosts'] as List?) ?? const [])
          .cast<Map<String, Object?>>()
          .map(_itemCostFromJson)
          .toList(),
      costCents: json['costCents'] as int,
      mileageKm: json['mileageKm'] as int,
      note: json['note'] as String?,
      sync: SyncMetadata.fromJson(
        (json['sync'] as Map).cast<String, Object?>(),
      ),
    );
  }

  RecordItemCost _itemCostFromJson(Map<String, Object?> json) {
    return RecordItemCost(
      itemId: json['itemId'] as int,
      materialCents: json['materialCents'] as int?,
      laborCents: json['laborCents'] as int?,
      costCents: json['costCents'] as int?,
    );
  }

  Map<String, Object?> _fuelPredictionToJson(FuelPrediction prediction) {
    return {
      'carId': prediction.carId,
      'fuelPercent': prediction.fuelPercent,
      'sync': prediction.sync.toJson(),
    };
  }

  FuelPrediction _fuelPredictionFromJson(Map<String, Object?> json) {
    return FuelPrediction(
      carId: json['carId'] as int,
      fuelPercent: json['fuelPercent'] as int,
      sync: SyncMetadata.fromJson(
        (json['sync'] as Map).cast<String, Object?>(),
      ),
    );
  }

  Map<String, Object?> _fuelRecordToJson(FuelRecord record) {
    return {
      'carId': record.carId,
      'date': record.date.toString(),
      'grade': record.grade.code,
      'unitPriceCents': record.unitPriceCents,
      'payableCents': record.payableCents,
      'actualCents': record.actualCents,
      'volumeLiters': record.volumeLiters,
      'sync': record.sync.toJson(),
    };
  }

  /// 容积不读备份里的存值——实体构造时按 应付÷单价 重算（派生值
  /// 唯一算法在实体，恢复后的行与重存的行字节一致）。
  FuelRecord _fuelRecordFromJson(Map<String, Object?> json) {
    return FuelRecord(
      carId: json['carId'] as int,
      date: LocalDate.parse(json['date'] as String),
      grade: FuelGrade.tryParse(json['grade'] as String) ??
          FuelGrade.gasoline92,
      unitPriceCents: json['unitPriceCents'] as int,
      payableCents: json['payableCents'] as int,
      actualCents: json['actualCents'] as int?,
      sync: SyncMetadata.fromJson(
        (json['sync'] as Map).cast<String, Object?>(),
      ),
    );
  }

  Map<String, Object?> _diagnosticsProbeToJson(DiagnosticsProbe probe) {
    return {
      'carId': probe.carId,
      'name': probe.name,
      'command': probe.command,
      'parseType': probe.parseType.wire,
      'enabled': probe.enabled,
      'refreshIntervalSeconds': probe.refreshIntervalSeconds,
      'header': probe.header,
      'sync': probe.sync.toJson(),
    };
  }

  /// 条目不读自身 id / catalogKey（备份里没有这两个字段，ADR 0021）——
  /// 解码产物永远是待重插的自定义检测点（id 由恢复循环重新生成雪花，
  /// catalogKey 恒 null）。v5 起读 carId；v1–v4 无 carId 用
  /// [fallbackCarId]（第一辆车）；没有宿主车的条目丢弃。
  DiagnosticsProbe? _diagnosticsProbeFromJson(
    Map<String, Object?> json, {
    required int? fallbackCarId,
  }) {
    final carId = (json['carId'] as int?) ?? fallbackCarId;
    if (carId == null) {
      return null;
    }
    return DiagnosticsProbe(
      carId: carId,
      name: json['name'] as String,
      command: json['command'] as String,
      parseType: DiagnosticsParseType.byWire(json['parseType'] as String),
      enabled: json['enabled'] as bool,
      refreshIntervalSeconds:
          (json['refreshIntervalSeconds'] as int?) ?? 60,
      header: json['header'] as String?,
      sync: SyncMetadata.fromJson(
        (json['sync'] as Map).cast<String, Object?>(),
      ),
    );
  }
}
