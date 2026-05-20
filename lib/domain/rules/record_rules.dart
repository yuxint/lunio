import '../entities/maintenance_record.dart';

class RecordRules {
  const RecordRules._();

  static List<String> uniqueItemIds(List<String> itemIds) {
    final result = <String>[];
    final seen = <String>{};
    for (final id in itemIds) {
      if (id.trim().isEmpty) {
        continue;
      }
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

  static String cycleItemKey({
    required String carId,
    required String date,
    required String itemId,
  }) {
    return '$carId::$date::$itemId';
  }
}
