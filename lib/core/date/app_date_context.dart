import 'local_date.dart';

typedef DateTimeReader = DateTime Function();

class AppDateContext {
  const AppDateContext({required this.readSystemNow, this.manualDate});

  factory AppDateContext.system() {
    return AppDateContext(readSystemNow: DateTime.now);
  }

  final DateTimeReader readSystemNow;
  final LocalDate? manualDate;

  LocalDate today() {
    return manualDate ?? LocalDate.fromDateTime(readSystemNow());
  }

  AppDateContext withManualDate(LocalDate date) {
    return AppDateContext(readSystemNow: readSystemNow, manualDate: date);
  }

  AppDateContext withoutManualDate() {
    return AppDateContext(readSystemNow: readSystemNow);
  }
}
