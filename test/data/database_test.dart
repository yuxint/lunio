import 'package:flutter_test/flutter_test.dart';
import 'package:lunio/core/date/local_date.dart';
import 'package:lunio/data/database/app_database.dart';
import 'package:lunio/data/repositories/lunio_repository.dart';
import 'package:lunio/domain/entities/car.dart';
import 'package:lunio/domain/entities/maintenance_item.dart';
import 'package:lunio/domain/entities/maintenance_record.dart';
import 'package:lunio/domain/entities/sync_metadata.dart';

void main() {
  late AppDatabase database;
  late LunioRepository repository;
  late SyncMetadata sync;

  setUp(() {
    database = AppDatabase.inMemory();
    repository = LunioRepository(database);
    sync = SyncMetadata(status: SyncStatus.synced, updatedAt: DateTime(2026));
  });

  tearDown(() async {
    await database.close();
  });

  Future<void> seedCarAndItem() async {
    await repository.createCar(
      Car(
        id: 'car-1',
        brand: '本田',
        model: '22款思域',
        currentMileageKm: 10000,
        roadDate: const LocalDate(2023, 8, 12),
        sync: sync,
      ),
    );
    await repository.saveMaintenanceItem(
      MaintenanceItem(
        id: 'item-1',
        ownerCarId: 'car-1',
        name: '机油',
        isDefault: true,
        enabled: true,
        remindByMileage: true,
        remindByTime: true,
        mileageIntervalKm: 5000,
        timeIntervalMonths: 6,
        warningThresholdPercent: 100,
        dangerThresholdPercent: 125,
        sortOrder: 1,
        sync: sync,
      ),
    );
  }

  test('creates schema and persists car data', () async {
    await seedCarAndItem();

    final cars = await repository.listCars();

    expect(cars, hasLength(1));
    expect(cars.single.brandModelKey, '本田::22款思域');
  });

  test('same car and date is unique', () async {
    await seedCarAndItem();
    final first = MaintenanceRecord(
      id: 'record-1',
      carId: 'car-1',
      date: const LocalDate(2026, 5, 19),
      itemIds: const ['item-1'],
      costCents: 10000,
      mileageKm: 12000,
      sync: sync,
    );
    final duplicateDay = MaintenanceRecord(
      id: 'record-2',
      carId: 'car-1',
      date: const LocalDate(2026, 5, 19),
      itemIds: const ['item-1'],
      costCents: 10000,
      mileageKm: 13000,
      sync: sync,
    );

    await repository.saveMaintenanceRecord(first);

    expect(
      () => repository.saveMaintenanceRecord(duplicateDay),
      throwsA(isA<Exception>()),
    );
  });

  test('record can only increase car mileage', () async {
    await seedCarAndItem();
    await repository.saveMaintenanceRecord(
      MaintenanceRecord(
        id: 'record-1',
        carId: 'car-1',
        date: const LocalDate(2026, 5, 19),
        itemIds: const ['item-1'],
        costCents: 10000,
        mileageKm: 9000,
        sync: sync,
      ),
    );
    expect((await repository.listCars()).single.currentMileageKm, 10000);

    await repository.saveMaintenanceRecord(
      MaintenanceRecord(
        id: 'record-2',
        carId: 'car-1',
        date: const LocalDate(2026, 6, 19),
        itemIds: const ['item-1'],
        costCents: 10000,
        mileageKm: 13000,
        sync: sync,
      ),
    );
    expect((await repository.listCars()).single.currentMileageKm, 13000);
  });

  test('delete car removes related local records and items', () async {
    await seedCarAndItem();
    await repository.saveMaintenanceRecord(
      MaintenanceRecord(
        id: 'record-1',
        carId: 'car-1',
        date: const LocalDate(2026, 5, 19),
        itemIds: const ['item-1'],
        costCents: 10000,
        mileageKm: 12000,
        sync: sync,
      ),
    );

    await repository.deleteCar('car-1');

    expect(await database.select(database.cars).get(), isEmpty);
    expect(await database.select(database.maintenanceItems).get(), isEmpty);
    expect(await database.select(database.maintenanceRecords).get(), isEmpty);
    expect(
      await database.select(database.maintenanceRecordItems).get(),
      isEmpty,
    );
  });
}
