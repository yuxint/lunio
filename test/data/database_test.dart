import 'package:flutter_test/flutter_test.dart';
import 'package:lunio/core/date/local_date.dart';
import 'package:lunio/data/backup/backup_codec.dart';
import 'package:lunio/data/database/app_database.dart';
import 'package:lunio/data/repositories/lunio_repository.dart';
import 'package:lunio/domain/entities/car.dart';
import 'package:lunio/domain/entities/maintenance_item.dart';
import 'package:lunio/domain/entities/maintenance_record.dart';
import 'package:lunio/domain/entities/sync_metadata.dart';
import 'package:lunio/domain/entities/vehicle_default_maintenance_item.dart';

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

  Future<(int, int)> seedCarAndItem() async {
    final carId = await repository.createCar(
      Car(
        brand: '本田',
        model: '22款思域',
        currentMileageKm: 10000,
        roadDate: const LocalDate(2023, 8, 12),
        sync: sync,
      ),
    );
    final itemId = await repository.saveMaintenanceItem(
      MaintenanceItem(
        carsId: carId,
        name: '机油',
        isDefault: true,
        enabled: true,
        remindByMileage: true,
        remindByTime: true,
        mileageIntervalKm: 5000,
        timeIntervalMonths: 6,
        notOverdueUpperLimit: 100,
        overdueUpperLimit: 125,
        sortOrder: 1,
        sync: sync,
      ),
    );
    return (carId, itemId);
  }

  test('creates schema and persists car data', () async {
    await seedCarAndItem();

    final cars = await repository.listCars();

    expect(cars, hasLength(1));
    expect(cars.single.id, isNotNull);
    expect(cars.single.brand, '本田');
    expect(cars.single.model, '22款思域');
  });

  test('same car and date is unique', () async {
    final (carId, itemId) = await seedCarAndItem();
    final first = MaintenanceRecord(
      carId: carId,
      date: const LocalDate(2026, 5, 19),
      itemIds: [itemId],
      costCents: 10000,
      mileageKm: 12000,
      sync: sync,
    );
    final duplicateDay = MaintenanceRecord(
      carId: carId,
      date: const LocalDate(2026, 5, 19),
      itemIds: [itemId],
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
    final (carId, itemId) = await seedCarAndItem();
    await repository.saveMaintenanceRecord(
      MaintenanceRecord(
        carId: carId,
        date: const LocalDate(2026, 5, 19),
        itemIds: [itemId],
        costCents: 10000,
        mileageKm: 9000,
        sync: sync,
      ),
    );
    expect((await repository.listCars()).single.currentMileageKm, 10000);

    await repository.saveMaintenanceRecord(
      MaintenanceRecord(
        carId: carId,
        date: const LocalDate(2026, 6, 19),
        itemIds: [itemId],
        costCents: 10000,
        mileageKm: 13000,
        sync: sync,
      ),
    );
    expect((await repository.listCars()).single.currentMileageKm, 13000);
  });

  test('delete car removes related local records and items', () async {
    final (carId, itemId) = await seedCarAndItem();
    await repository.setAppliedCarId(carId);
    await repository.saveMaintenanceRecord(
      MaintenanceRecord(
        carId: carId,
        date: const LocalDate(2026, 5, 19),
        itemIds: [itemId],
        costCents: 10000,
        mileageKm: 12000,
        sync: sync,
      ),
    );

    await repository.deleteCar(carId);

    expect(await database.select(database.cars).get(), isEmpty);
    expect(await database.select(database.maintenanceItems).get(), isEmpty);
    expect(await database.select(database.maintenanceRecords).get(), isEmpty);
    expect(
      await database.select(database.maintenanceRecordItems).get(),
      isEmpty,
    );
    expect(await database.select(database.appPreferences).get(), isEmpty);
  });

  test('record rejects missing item ids', () async {
    final (carId, _) = await seedCarAndItem();

    expect(
      () => repository.saveMaintenanceRecord(
        MaintenanceRecord(
          carId: carId,
          date: const LocalDate(2026, 5, 19),
          itemIds: const [999],
          costCents: 10000,
          mileageKm: 12000,
          sync: sync,
        ),
      ),
      throwsArgumentError,
    );
  });

  test('record rejects items from another car', () async {
    final (carId, _) = await seedCarAndItem();
    final otherCarId = await repository.createCar(
      Car(
        brand: '日产',
        model: '22款轩逸',
        currentMileageKm: 10000,
        roadDate: const LocalDate(2024, 1, 1),
        sync: sync,
      ),
    );
    final otherItemId = await repository.saveMaintenanceItem(
      MaintenanceItem(
        carsId: otherCarId,
        name: '空调滤芯',
        isDefault: true,
        enabled: true,
        remindByMileage: true,
        remindByTime: true,
        mileageIntervalKm: 20000,
        timeIntervalMonths: 12,
        sortOrder: 1,
        sync: sync,
      ),
    );

    expect(
      () => repository.saveMaintenanceRecord(
        MaintenanceRecord(
          carId: carId,
          date: const LocalDate(2026, 5, 19),
          itemIds: [otherItemId],
          costCents: 10000,
          mileageKm: 12000,
          sync: sync,
        ),
      ),
      throwsArgumentError,
    );
  });

  test('backup export and restore round-trips database content', () async {
    final (carId, itemId) = await seedCarAndItem();
    await repository.setAppliedCarId(carId);
    await repository.saveVehicleDefaultMaintenanceItem(
      VehicleDefaultMaintenanceItem(
        vehicleBrand: '本田',
        vehicleModel: '22款思域',
        itemName: '机油',
        remindByMileage: true,
        remindByTime: true,
        mileageIntervalKm: 5000,
        timeIntervalMonths: 6,
        sortOrder: 1,
        sync: sync,
      ),
    );
    await repository.saveMaintenanceRecord(
      MaintenanceRecord(
        carId: carId,
        date: const LocalDate(2026, 5, 19),
        itemIds: [itemId],
        costCents: 10000,
        mileageKm: 12000,
        sync: sync,
      ),
    );

    final backup = await repository.exportBackupPayload();
    await database.close();
    database = AppDatabase.inMemory();
    repository = LunioRepository(database);

    await repository.restoreBackupPayload(backup);

    expect(await database.select(database.cars).get(), hasLength(1));
    expect(
      await database.select(database.vehicleDefaultMaintenanceItems).get(),
      hasLength(1),
    );
    expect(
      await database.select(database.maintenanceItems).get(),
      hasLength(1),
    );
    expect(
      await database.select(database.maintenanceRecords).get(),
      hasLength(1),
    );
    expect(
      await database.select(database.maintenanceRecordItems).get(),
      hasLength(1),
    );
    expect(await repository.getAppliedCarId(), '$carId');
  });

  test(
    'backup restore rejects invalid references before replacing data',
    () async {
      await seedCarAndItem();
      final backup = await repository.exportBackupPayload();
      final invalid = BackupPayload(
        schemaVersion: 1,
        cars: backup.cars,
        maintenanceItems: backup.maintenanceItems,
        records: [
          MaintenanceRecord(
            id: 1,
            carId: 999,
            date: const LocalDate(2026, 5, 19),
            itemIds: const [1],
            costCents: 10000,
            mileageKm: 12000,
            sync: sync,
          ),
        ],
      );

      expect(
        () => repository.restoreBackupPayload(invalid),
        throwsArgumentError,
      );
      expect(await database.select(database.cars).get(), hasLength(1));
    },
  );

  test('backup restore rejects record items from another car', () async {
    final (carId, _) = await seedCarAndItem();
    final otherCarId = await repository.createCar(
      Car(
        brand: '日产',
        model: '22款轩逸',
        currentMileageKm: 10000,
        roadDate: const LocalDate(2024, 1, 1),
        sync: sync,
      ),
    );
    final otherItemId = await repository.saveMaintenanceItem(
      MaintenanceItem(
        carsId: otherCarId,
        name: '空调滤芯',
        isDefault: true,
        enabled: true,
        remindByMileage: true,
        remindByTime: true,
        mileageIntervalKm: 20000,
        timeIntervalMonths: 12,
        sortOrder: 1,
        sync: sync,
      ),
    );
    final backup = await repository.exportBackupPayload();
    final invalid = BackupPayload(
      schemaVersion: 1,
      cars: backup.cars,
      maintenanceItems: backup.maintenanceItems,
      records: [
        MaintenanceRecord(
          id: 1,
          carId: carId,
          date: const LocalDate(2026, 5, 19),
          itemIds: [otherItemId],
          costCents: 10000,
          mileageKm: 12000,
          sync: sync,
        ),
      ],
    );

    expect(() => repository.restoreBackupPayload(invalid), throwsArgumentError);
  });

  test('backup restore rejects invalid applied car preference', () async {
    await seedCarAndItem();
    final backup = await repository.exportBackupPayload();
    final invalid = BackupPayload(
      schemaVersion: 1,
      cars: backup.cars,
      maintenanceItems: backup.maintenanceItems,
      preferences: [
        BackupPreference(id: 1, key: 'appliedCarId', value: '999', sync: sync),
      ],
    );

    expect(() => repository.restoreBackupPayload(invalid), throwsArgumentError);
  });

  test('backup restore rolls back when inserts fail', () async {
    await seedCarAndItem();
    final backup = await repository.exportBackupPayload();
    final car = backup.cars.single;
    final invalid = BackupPayload(
      schemaVersion: 1,
      cars: [
        car,
        Car(
          id: car.id! + 1,
          brand: car.brand,
          model: car.model,
          currentMileageKm: car.currentMileageKm,
          roadDate: car.roadDate,
          sync: car.sync,
        ),
      ],
    );

    expect(() => repository.restoreBackupPayload(invalid), throwsA(anything));
    expect(await database.select(database.cars).get(), hasLength(1));
  });
}
