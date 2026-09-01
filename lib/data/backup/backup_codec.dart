// 备份 JSON 的编解码器（≈ Java 里的 Jackson 手写 Serializer/Deserializer）。
//
// 备份契约（schemaVersion = 1，与数据库 schemaVersion=1 是两套独立版本号）：
// {
//   "schemaVersion": 1,
//   "cars": [ { id, brand, model, powertrainType, currentMileageKm, roadDate,
//               tankCapacityLiters, sync } ],
//   "maintenanceItems": [ { id, carsId, name, ..., sync } ],
//   "records": [ { id, carId, date, itemIds[], costCents, mileageKm, note, sync } ],
//   "fuelPrediction": { "province": "湖北", "gradeCode": "92" },
//   "fuelPredictions": [ { carId, fuelPercent, sync } ]
// }
//
// 解码只认 schemaVersion=1，其他版本直接拒绝，不做旧版本字段回退
// （ADR 0005）。油价缓存与手填油价是临时数据，不进备份。
//
// ⚠ 契约边界（改字段前必读）：
//  - 不包含偏好（主题/应用车辆/通知设置/snooze 等）；
//  - 不包含停车倒计时（临时状态）；
//  - 不包含油价缓存/手填油价（临时状态）；
//  - 不包含车型目录/默认项目模板（恢复后由 bootstrap 幂等重建）。
// 导出在 Repository.exportBackupPayload，导入在 restoreBackupPayload。
import 'dart:convert';

import '../../core/date/local_date.dart';
import '../../domain/entities/car.dart';
import '../../domain/entities/fuel_prediction.dart';
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
  });

  /// 备份契约版本（ADR 0005：只认 1，不做旧版本兼容）。
  final int schemaVersion;
  final List<Car> cars;
  final List<MaintenanceItem> maintenanceItems;
  final List<MaintenanceRecord> records;

  /// 全局加油设置（省份 + 油品），用户没改过为 null。
  final BackupFuelPreference? fuelPrediction;

  /// 每辆车的加油预测设置（剩余油量；容积在 cars 条目里）。
  final List<FuelPrediction> fuelPredictions;
}

/// 备份里的全局加油设置（省份 + 油品编号）。
class BackupFuelPreference {
  const BackupFuelPreference({required this.province, required this.gradeCode});

  final String province;
  final String gradeCode;
}

/// 编解码器。无状态，UI 层（settings_data.dart）直接实例化使用。
class BackupCodec {
  const BackupCodec();

  /// 当前写入的备份契约版本（ADR 0005）。
  static const int currentSchemaVersion = 1;

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
    });
  }

  /// 从 JSON 字符串解码（导入文件内容）。
  ///
  /// 只接受当前版本，其他版本抛 UnsupportedError，UI 提示"不支持的备份
  /// 文件"（ADR 0005：不做旧版本兼容）。引用完整性由
  /// Repository._validateBackupReferences 负责，业务规则（金额/里程非负
  /// 等）恢复时不校验（审查报告 R35）。
  BackupPayload decode(String json) {
    final map = jsonDecode(json) as Map<String, Object?>;
    final version = map['schemaVersion'] as int;
    if (version != currentSchemaVersion) {
      throw UnsupportedError('Unsupported backup schemaVersion: $version');
    }
    final fuelPreferenceMap = map['fuelPrediction'] as Map<String, Object?>?;
    return BackupPayload(
      schemaVersion: version,
      cars: ((map['cars'] as List?) ?? const [])
          .cast<Map<String, Object?>>()
          .map(_carFromJson)
          .toList(),
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
      'costCents': record.costCents,
      'mileageKm': record.mileageKm,
      'note': record.note,
      'sync': record.sync.toJson(),
    };
  }

  MaintenanceRecord _recordFromJson(Map<String, Object?> json) {
    return MaintenanceRecord(
      id: json['id'] as int?,
      carId: json['carId'] as int,
      date: LocalDate.parse(json['date'] as String),
      itemIds: (json['itemIds'] as List).cast<int>(),
      costCents: json['costCents'] as int,
      mileageKm: json['mileageKm'] as int,
      note: json['note'] as String?,
      sync: SyncMetadata.fromJson(
        (json['sync'] as Map).cast<String, Object?>(),
      ),
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
}
