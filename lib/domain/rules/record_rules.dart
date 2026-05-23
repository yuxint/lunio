import '../entities/maintenance_record.dart';

class RecordRules {
  const RecordRules._();

  static List<int> uniqueItemIds(List<int> itemIds) {
    final result = <int>[];
    final seen = <int>{};
    for (final id in itemIds) {
      if (seen.add(id)) {
        result.add(id);
      }
    }
    return result;
  }

  static void validateRecord(MaintenanceRecord record) {
    if (record.costCents < 0) {
      throw ArgumentError.value(
        record.costCents,
        'costCents',
        'Cost must be non-negative',
      );
    }
    if (record.mileageKm < 0) {
      throw ArgumentError.value(
        record.mileageKm,
        'mileageKm',
        'Mileage must be non-negative',
      );
    }
    if (uniqueItemIds(record.itemIds).isEmpty) {
      throw ArgumentError.value(
        record.itemIds,
        'itemIds',
        'Record must contain items',
      );
    }
  }

  static int mileageAfterRecord({
    required int currentMileageKm,
    required int recordMileageKm,
  }) {
    return recordMileageKm > currentMileageKm
        ? recordMileageKm
        : currentMileageKm;
  }
}
