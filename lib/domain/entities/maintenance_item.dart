import 'sync_metadata.dart';

class MaintenanceItem {
  const MaintenanceItem({
    required this.id,
    required this.ownerCarId,
    required this.name,
    required this.isDefault,
    required this.enabled,
    required this.remindByMileage,
    required this.remindByTime,
    required this.warningThresholdPercent,
    required this.dangerThresholdPercent,
    required this.sortOrder,
    required this.sync,
    this.catalogKey,
    this.mileageIntervalKm,
    this.timeIntervalMonths,
  });

  final String id;
  final String ownerCarId;
  final String name;
  final bool isDefault;
  final bool enabled;
  final bool remindByMileage;
  final bool remindByTime;
  final int? mileageIntervalKm;
  final int? timeIntervalMonths;
  final int warningThresholdPercent;
  final int dangerThresholdPercent;
  final int sortOrder;
  final String? catalogKey;
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
