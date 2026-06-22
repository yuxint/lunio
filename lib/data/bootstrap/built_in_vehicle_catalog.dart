import 'dart:convert';

import 'package:flutter/services.dart';

import '../../domain/entities/sync_metadata.dart';
import '../../domain/entities/vehicle_default_maintenance_item.dart';
import '../../domain/entities/vehicle_model.dart';

typedef BuiltInVehicleCatalogLoader = Future<BuiltInVehicleCatalog> Function();

Future<BuiltInVehicleCatalog> loadBuiltInVehicleCatalogAsset() async {
  final json = await rootBundle.loadString(
    'assets/data/built_in_vehicle_catalog.json',
  );
  return BuiltInVehicleCatalog.fromJson(
    (jsonDecode(json) as Map).cast<String, Object?>(),
  );
}

class BuiltInVehicleCatalog {
  const BuiltInVehicleCatalog({
    required this.templates,
    required this.vehicles,
  });

  final Map<String, List<BuiltInMaintenanceItemSpec>> templates;
  final List<BuiltInVehicleSeed> vehicles;

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

class BuiltInVehicleSeed {
  const BuiltInVehicleSeed({
    required this.id,
    required this.brand,
    required this.model,
    required this.template,
  });

  final String id;
  final String brand;
  final String model;
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

String _nonEmptyString(Object? value, String fieldName) {
  if (value is! String || value.trim().isEmpty) {
    throw ArgumentError('Invalid $fieldName');
  }
  return value;
}

void _validateUniqueIds(Iterable<String> ids, String label, [String? scope]) {
  final seen = <String>{};
  for (final id in ids) {
    if (!seen.add(id)) {
      final suffix = scope == null ? '' : ' in $scope';
      throw ArgumentError('Duplicate $label id$suffix: $id');
    }
  }
}
