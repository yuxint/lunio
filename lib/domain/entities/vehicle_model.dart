import 'sync_metadata.dart';

class VehicleModel {
  const VehicleModel({
    this.id,
    required this.brand,
    required this.model,
    required this.sortOrder,
    required this.sync,
  });

  final int? id;
  final String brand;
  final String model;
  final int sortOrder;
  final SyncMetadata sync;
}
