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

  test(
    'create car copies default maintenance items and applies first car',
    () async {
      await repository.ensureDefaultMaintenanceItems();

      final carId = await repository.createCarWithDefaultItems(
        Car(
          brand: '本田',
          model: '22款思域',
          currentMileageKm: 10000,
          roadDate: const LocalDate(2023, 8, 12),
          sync: sync,
        ),
      );

      final items = await repository.listMaintenanceItemsForCar(carId);
      expect(items.map((item) => item.name), containsAll(['机油', '机滤', '空调滤芯']));
      expect(await repository.getAppliedCarId(), '$carId');
    },
  );

  test('applied car falls back to first available car', () async {
    final firstCarId = await repository.createCar(
      Car(
        brand: '本田',
        model: '22款思域',
        currentMileageKm: 10000,
        roadDate: const LocalDate(2023, 8, 12),
        sync: sync,
      ),
    );
    await repository.createCar(
      Car(
        brand: '日产',
        model: '22款轩逸',
        currentMileageKm: 8000,
        roadDate: const LocalDate(2024, 1, 1),
        sync: sync,
      ),
    );
    await repository.setAppliedCarId(999);

    final appliedCar = await repository.getAppliedCar();

    expect(appliedCar?.id, firstCarId);
    expect(await repository.getAppliedCarId(), '$firstCarId');
  });

  test('updates car mileage and road date', () async {
    final carId = await repository.createCar(
      Car(
        brand: '本田',
        model: '22款思域',
        currentMileageKm: 10000,
        roadDate: const LocalDate(2023, 8, 12),
        sync: sync,
      ),
    );

    await repository.updateCar(
      Car(
        id: carId,
        brand: '本田',
        model: '22款思域',
        currentMileageKm: 18000,
        roadDate: const LocalDate(2023, 9, 1),
        sync: sync,
      ),
    );

    final car = (await repository.listCars()).single;
    expect(car.currentMileageKm, 18000);
    expect(car.roadDate, const LocalDate(2023, 9, 1));
  });

  test('delete applied car switches preference to remaining car', () async {
    final firstCarId = await repository.createCar(
      Car(
        brand: '本田',
        model: '22款思域',
        currentMileageKm: 10000,
        roadDate: const LocalDate(2023, 8, 12),
        sync: sync,
      ),
    );
    final secondCarId = await repository.createCar(
      Car(
        brand: '日产',
        model: '22款轩逸',
        currentMileageKm: 8000,
        roadDate: const LocalDate(2024, 1, 1),
        sync: sync,
      ),
    );
    await repository.setAppliedCarId(firstCarId);

    await repository.deleteCar(firstCarId);

    expect(await repository.getAppliedCarId(), '$secondCarId');
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

  test('lists updates and deletes maintenance records', () async {
    final (carId, itemId) = await seedCarAndItem();
    final recordId = await repository.saveMaintenanceRecord(
      MaintenanceRecord(
        carId: carId,
        date: const LocalDate(2026, 5, 19),
        itemIds: [itemId],
        costCents: 10000,
        mileageKm: 12000,
        sync: sync,
      ),
    );

    expect(await repository.listMaintenanceRecordsForCar(carId), hasLength(1));

    await repository.updateMaintenanceRecord(
      MaintenanceRecord(
        id: recordId,
        carId: carId,
        date: const LocalDate(2026, 5, 20),
        itemIds: [itemId],
        costCents: 12000,
        mileageKm: 13000,
        note: '更新',
        sync: sync,
      ),
    );
    final updated = (await repository.listMaintenanceRecordsForCar(
      carId,
    )).single;
    expect(updated.date, const LocalDate(2026, 5, 20));
    expect(updated.costCents, 12000);
    expect(updated.note, '更新');

    await repository.deleteMaintenanceRecord(recordId);

    expect(await repository.listMaintenanceRecordsForCar(carId), isEmpty);
    expect(
      await database.select(database.maintenanceRecordItems).get(),
      isEmpty,
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

  test('updates maintenance item settings', () async {
    final (carId, itemId) = await seedCarAndItem();

    await repository.updateMaintenanceItem(
      MaintenanceItem(
        id: itemId,
        carsId: carId,
        name: '机油',
        isDefault: true,
        enabled: true,
        remindByMileage: true,
        remindByTime: false,
        mileageIntervalKm: 8000,
        sortOrder: 1,
        sync: sync,
      ),
    );

    final item = (await repository.listMaintenanceItemsForCar(carId)).single;
    expect(item.remindByTime, isFalse);
    expect(item.mileageIntervalKm, 8000);
  });

  test('cannot disable the last enabled maintenance item', () async {
    final (_, itemId) = await seedCarAndItem();

    expect(
      () => repository.setMaintenanceItemEnabled(
        itemId: itemId,
        enabled: false,
        sync: sync,
      ),
      throwsArgumentError,
    );
  });

  test('deletes custom item without history', () async {
    final (carId, _) = await seedCarAndItem();
    final customItemId = await repository.saveMaintenanceItem(
      MaintenanceItem(
        carsId: carId,
        name: '玻璃水',
        isDefault: false,
        enabled: true,
        remindByMileage: true,
        remindByTime: false,
        mileageIntervalKm: 3000,
        sortOrder: 2,
        sync: sync,
      ),
    );

    await repository.deleteMaintenanceItem(customItemId);

    expect(
      (await repository.listMaintenanceItemsForCar(
        carId,
      )).map((item) => item.name),
      isNot(contains('玻璃水')),
    );
  });

  test('does not delete default item or item with history', () async {
    final (carId, itemId) = await seedCarAndItem();
    final customItemId = await repository.saveMaintenanceItem(
      MaintenanceItem(
        carsId: carId,
        name: '玻璃水',
        isDefault: false,
        enabled: true,
        remindByMileage: true,
        remindByTime: false,
        mileageIntervalKm: 3000,
        sortOrder: 2,
        sync: sync,
      ),
    );
    await repository.saveMaintenanceRecord(
      MaintenanceRecord(
        carId: carId,
        date: const LocalDate(2026, 5, 19),
        itemIds: [customItemId],
        costCents: 1000,
        mileageKm: 12000,
        sync: sync,
      ),
    );

    expect(() => repository.deleteMaintenanceItem(itemId), throwsArgumentError);
    expect(
      () => repository.deleteMaintenanceItem(customItemId),
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

  test('preference values are saved and exported', () async {
    await repository.setPreferenceValue('manualDateEnabled', 'true');
    await repository.setPreferenceValue('manualDate', '2026-05-23');

    expect(await repository.getPreferenceValue('manualDateEnabled'), 'true');
    expect(await repository.getPreferenceValue('manualDate'), '2026-05-23');

    final backup = await repository.exportBackupPayload();

    expect(
      backup.preferences.map((preference) => preference.key),
      containsAll(['manualDateEnabled', 'manualDate']),
    );
  });

  test('backup restore rejects invalid manual date preference', () async {
    await seedCarAndItem();
    final backup = await repository.exportBackupPayload();
    final invalid = BackupPayload(
      schemaVersion: 1,
      cars: backup.cars,
      maintenanceItems: backup.maintenanceItems,
      preferences: [
        BackupPreference(
          id: 1,
          key: 'manualDate',
          value: '2026-02-30',
          sync: sync,
        ),
      ],
    );

    expect(() => repository.restoreBackupPayload(invalid), throwsArgumentError);
  });

  test('clear all data removes local rows', () async {
    final (carId, itemId) = await seedCarAndItem();
    await repository.setAppliedCarId(carId);
    await repository.setPreferenceValue('manualDateEnabled', 'true');
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

    await repository.clearAllData();

    expect(await database.select(database.cars).get(), isEmpty);
    expect(await database.select(database.maintenanceItems).get(), isEmpty);
    expect(await database.select(database.maintenanceRecords).get(), isEmpty);
    expect(
      await database.select(database.maintenanceRecordItems).get(),
      isEmpty,
    );
    expect(await database.select(database.appPreferences).get(), isEmpty);
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
