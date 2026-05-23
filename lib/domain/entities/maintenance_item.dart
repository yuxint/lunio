import 'sync_metadata.dart';

class MaintenanceItem {
  const MaintenanceItem({
    this.id,
    required this.carsId,
    required this.name,
    required this.isDefault,
    required this.enabled,
    required this.remindByMileage,
    required this.remindByTime,
    this.notOverdueUpperLimit = 100,
    this.overdueUpperLimit = 125,
    required this.sortOrder,
    required this.sync,
    this.mileageIntervalKm,
    this.timeIntervalMonths,
  });

  final int? id;
  final int carsId;
  final String name;
  final bool isDefault;
  final bool enabled;
  final bool remindByMileage;
  final bool remindByTime;
  final int? mileageIntervalKm;
  final int? timeIntervalMonths;
  final double notOverdueUpperLimit;
  final double overdueUpperLimit;
  final int sortOrder;
  final SyncMetadata sync;

  void validate() {
    if (name.trim().isEmpty) {
      throw ArgumentError.value(name, 'name', 'Maintenance item name is empty');
    }
    if (!remindByMileage && !remindByTime) {
      throw ArgumentError('At least one reminder type must be enabled');
    }
    if (remindByMileage &&
        (mileageIntervalKm == null || mileageIntervalKm! <= 0)) {
      throw ArgumentError('Mileage reminder interval must be positive');
    }
    if (remindByTime &&
        (timeIntervalMonths == null || timeIntervalMonths! <= 0)) {
      throw ArgumentError('Time reminder interval must be positive');
    }
  }
}
