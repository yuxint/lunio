import 'sync_metadata.dart';

class VehicleDefaultMaintenanceItem {
  const VehicleDefaultMaintenanceItem({
    this.id,
    required this.vehicleBrand,
    required this.vehicleModel,
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

  final int? id;
  final String vehicleBrand;
  final String vehicleModel;
  final String itemName;
  final bool remindByMileage;
  final bool remindByTime;
  final int? mileageIntervalKm;
  final int? timeIntervalMonths;
  final double notOverdueUpperLimit;
  final double overdueUpperLimit;
  final int sortOrder;
  final SyncMetadata sync;
}
