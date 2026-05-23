import 'dart:convert';

import '../../core/date/local_date.dart';
import '../../domain/entities/car.dart';
import '../../domain/entities/maintenance_item.dart';
import '../../domain/entities/maintenance_record.dart';
import '../../domain/entities/sync_metadata.dart';
import '../../domain/entities/vehicle_default_maintenance_item.dart';

class BackupPayload {
  const BackupPayload({
    required this.schemaVersion,
    this.cars = const [],
    this.defaultMaintenanceItems = const [],
    this.maintenanceItems = const [],
    this.records = const [],
    this.preferences = const [],
  });

  final int schemaVersion;
  final List<Car> cars;
  final List<VehicleDefaultMaintenanceItem> defaultMaintenanceItems;
  final List<MaintenanceItem> maintenanceItems;
  final List<MaintenanceRecord> records;
  final List<BackupPreference> preferences;
}

class BackupPreference {
  const BackupPreference({
    this.id,
    required this.key,
    required this.value,
    required this.sync,
  });

  final int? id;
  final String key;
  final String? value;
  final SyncMetadata sync;
}

class BackupCodec {
  const BackupCodec();

  String encode(BackupPayload payload) {
    return jsonEncode({
      'schemaVersion': payload.schemaVersion,
      'cars': payload.cars.map(_carToJson).toList(),
      'defaultMaintenanceItems': payload.defaultMaintenanceItems
          .map(_defaultItemToJson)
          .toList(),
      'maintenanceItems': payload.maintenanceItems.map(_itemToJson).toList(),
      'records': payload.records.map(_recordToJson).toList(),
      'preferences': payload.preferences.map(_preferenceToJson).toList(),
    });
  }

  BackupPayload decode(String json) {
    final map = jsonDecode(json) as Map<String, Object?>;
    final version = map['schemaVersion'] as int;
    if (version != 1) {
      throw UnsupportedError('Unsupported backup schemaVersion: $version');
    }
    return BackupPayload(
      schemaVersion: version,
      cars: ((map['cars'] as List?) ?? const [])
          .cast<Map<String, Object?>>()
          .map(_carFromJson)
          .toList(),
      defaultMaintenanceItems:
          ((map['defaultMaintenanceItems'] as List?) ?? const [])
              .cast<Map<String, Object?>>()
              .map(_defaultItemFromJson)
              .toList(),
      maintenanceItems: ((map['maintenanceItems'] as List?) ?? const [])
          .cast<Map<String, Object?>>()
          .map(_itemFromJson)
          .toList(),
      records: ((map['records'] as List?) ?? const [])
          .cast<Map<String, Object?>>()
          .map(_recordFromJson)
          .toList(),
      preferences: ((map['preferences'] as List?) ?? const [])
          .cast<Map<String, Object?>>()
          .map(_preferenceFromJson)
          .toList(),
    );
  }

  Map<String, Object?> _carToJson(Car car) {
    return {
      'id': car.id,
      'brand': car.brand,
      'model': car.model,
      'currentMileageKm': car.currentMileageKm,
      'roadDate': car.roadDate.toString(),
      'sync': car.sync.toJson(),
    };
  }

  Map<String, Object?> _defaultItemToJson(VehicleDefaultMaintenanceItem item) {
    return {
      'id': item.id,
      'vehicleBrand': item.vehicleBrand,
      'vehicleModel': item.vehicleModel,
      'itemName': item.itemName,
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

  VehicleDefaultMaintenanceItem _defaultItemFromJson(
    Map<String, Object?> json,
  ) {
    return VehicleDefaultMaintenanceItem(
      id: json['id'] as int?,
      vehicleBrand: json['vehicleBrand'] as String,
      vehicleModel: json['vehicleModel'] as String,
      itemName: json['itemName'] as String,
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

  Map<String, Object?> _itemToJson(MaintenanceItem item) {
    return {
      'id': item.id,
      'carsId': item.carsId,
      'name': item.name,
      'isDefault': item.isDefault,
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
      isDefault: json['isDefault'] as bool,
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
      currentMileageKm: json['currentMileageKm'] as int,
      roadDate: LocalDate.parse(json['roadDate'] as String),
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

  Map<String, Object?> _preferenceToJson(BackupPreference preference) {
    return {
      'id': preference.id,
      'key': preference.key,
      'value': preference.value,
      'sync': preference.sync.toJson(),
    };
  }

  BackupPreference _preferenceFromJson(Map<String, Object?> json) {
    return BackupPreference(
      id: json['id'] as int?,
      key: json['key'] as String,
      value: json['value'] as String?,
      sync: SyncMetadata.fromJson(
        (json['sync'] as Map).cast<String, Object?>(),
      ),
    );
  }
}
