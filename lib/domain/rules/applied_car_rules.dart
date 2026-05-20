import '../entities/car.dart';

class AppliedCarRules {
  const AppliedCarRules._();

  static String? resolveAppliedCarId({
    required List<Car> cars,
    required String? storedCarId,
  }) {
    if (cars.isEmpty) {
      return null;
    }
    if (storedCarId != null && cars.any((car) => car.id == storedCarId)) {
      return storedCarId;
    }
    return cars.first.id;
  }
}
