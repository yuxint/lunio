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
    if (schemaVersion != 1) {
      throw ArgumentError('Unsupported vehicle catalog schemaVersion');
    }
    final templatesJson = (json['templates'] as Map).cast<String, Object?>();
    final templates = templatesJson.map((key, value) {
      final templateKey = _nonEmptyString(key, 'template key');
      return MapEntry(
        templateKey,
        (value as List)
            .cast<Map<String, Object?>>()
            .map(BuiltInMaintenanceItemSpec.fromJson)
            .toList(),
      );
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
    required this.brand,
    required this.model,
    required this.template,
  });

  final String brand;
  final String model;
  final String template;

  factory BuiltInVehicleSeed.fromJson(Map<String, Object?> json) {
    return BuiltInVehicleSeed(
      brand: _nonEmptyString(json['brand'], 'vehicle brand'),
      model: _nonEmptyString(json['model'], 'vehicle model'),
      template: _nonEmptyString(json['template'], 'vehicle template'),
    );
  }
}

class BuiltInMaintenanceItemSpec {
  const BuiltInMaintenanceItemSpec({
    required this.name,
    required this.remindByMileage,
    required this.remindByTime,
    this.mileageIntervalKm,
    this.timeIntervalMonths,
  });

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
