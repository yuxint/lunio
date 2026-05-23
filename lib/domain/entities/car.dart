import '../../core/date/local_date.dart';
import 'sync_metadata.dart';

class Car {
  const Car({
    this.id,
    required this.brand,
    required this.model,
    required this.currentMileageKm,
    required this.roadDate,
    required this.sync,
  });

  final int? id;
  final String brand;
  final String model;
  final int currentMileageKm;
  final LocalDate roadDate;
  final SyncMetadata sync;

  Car copyWith({int? currentMileageKm, SyncMetadata? sync}) {
    return Car(
      id: id,
      brand: brand,
      model: model,
      currentMileageKm: currentMileageKm ?? this.currentMileageKm,
      roadDate: roadDate,
      sync: sync ?? this.sync,
    );
  }
}
