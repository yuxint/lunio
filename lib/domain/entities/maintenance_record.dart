import '../../core/date/local_date.dart';
import 'sync_metadata.dart';

class MaintenanceRecord {
  const MaintenanceRecord({
    required this.id,
    required this.carId,
    required this.date,
    required this.itemIds,
    required this.costCents,
    required this.mileageKm,
    required this.sync,
    this.note,
  });

  final String id;
  final String carId;
  final LocalDate date;
  final List<String> itemIds;
  final int costCents;
  final int mileageKm;
  final String? note;
  final SyncMetadata sync;

  String get cycleKey => '$carId::$date';
}
