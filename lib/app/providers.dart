import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/date/app_date_context.dart';
import '../core/date/local_date.dart';
import '../data/database/app_database.dart';
import '../data/repositories/lunio_repository.dart';
import '../domain/entities/car.dart';
import '../domain/entities/maintenance_item.dart';
import '../domain/entities/maintenance_record.dart';

final appDateContextProvider = Provider<AppDateContext>(
  (ref) => AppDateContext.system(),
);

final manualDatePreferenceProvider = FutureProvider<LocalDate?>((ref) async {
  final repository = ref.watch(lunioRepositoryProvider);
  final enabled = await repository.getPreferenceValue('manualDateEnabled');
  if (enabled != 'true') {
    return null;
  }
  final value = await repository.getPreferenceValue('manualDate');
  if (value == null) {
    return null;
  }
  return LocalDate.tryParse(value);
});

final effectiveTodayProvider = FutureProvider<LocalDate>((ref) async {
  final baseDateContext = ref.watch(appDateContextProvider);
  final manualDate = await ref.watch(manualDatePreferenceProvider.future);
  return manualDate ?? baseDateContext.today();
});

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final database = AppDatabase();
  ref.onDispose(database.close);
  return database;
});

final lunioRepositoryProvider = Provider<LunioRepository>((ref) {
  return LunioRepository(ref.watch(appDatabaseProvider));
});

final defaultMaintenanceBootstrapProvider = FutureProvider<void>((ref) {
  return ref.watch(lunioRepositoryProvider).ensureDefaultMaintenanceItems();
});

final carsProvider = FutureProvider<List<Car>>((ref) {
  ref.watch(defaultMaintenanceBootstrapProvider);
  return ref.watch(lunioRepositoryProvider).listCars();
});

final appliedCarProvider = FutureProvider<Car?>((ref) {
  ref.watch(carsProvider);
  return ref.watch(lunioRepositoryProvider).getAppliedCar();
});

final appliedCarMaintenanceItemsProvider =
    FutureProvider<List<MaintenanceItem>>((ref) async {
      final car = await ref.watch(appliedCarProvider.future);
      if (car?.id == null) {
        return const [];
      }
      return ref
          .watch(lunioRepositoryProvider)
          .listMaintenanceItemsForCar(car!.id!);
    });

final appliedCarRecordsProvider = FutureProvider<List<MaintenanceRecord>>((
  ref,
) async {
  final car = await ref.watch(appliedCarProvider.future);
  if (car?.id == null) {
    return const [];
  }
  return ref
      .watch(lunioRepositoryProvider)
      .listMaintenanceRecordsForCar(car!.id!);
});

void invalidateVehicleProviders(WidgetRef ref) {
  ref.invalidate(carsProvider);
  ref.invalidate(appliedCarProvider);
  ref.invalidate(appliedCarMaintenanceItemsProvider);
  ref.invalidate(appliedCarRecordsProvider);
}

void invalidatePreferenceProviders(WidgetRef ref) {
  ref.invalidate(manualDatePreferenceProvider);
  ref.invalidate(effectiveTodayProvider);
}

void invalidateAllAppDataProviders(WidgetRef ref) {
  ref.invalidate(defaultMaintenanceBootstrapProvider);
  invalidateVehicleProviders(ref);
  invalidatePreferenceProviders(ref);
}
