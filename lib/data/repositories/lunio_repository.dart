import 'package:drift/drift.dart';

import '../../core/date/local_date.dart';
import '../../domain/entities/car.dart' as domain;
import '../../domain/entities/maintenance_item.dart' as domain;
import '../../domain/entities/maintenance_record.dart' as domain;
import '../../domain/entities/sync_metadata.dart';
import '../../domain/entities/vehicle_default_maintenance_item.dart' as domain;
import '../../domain/rules/record_rules.dart';
import '../backup/backup_codec.dart';
import '../database/app_database.dart';

class LunioRepository {
  const LunioRepository(this.database);

  final AppDatabase database;

  Future<int> createCar(domain.Car car) {
    return database
        .into(database.cars)
        .insert(
          CarsCompanion.insert(
            brand: car.brand,
            model: car.model,
            currentMileageKm: car.currentMileageKm,
            roadDate: car.roadDate.toString(),
            syncStatus: Value(car.sync.status.name),
            updatedAt: car.sync.updatedAt.toIso8601String(),
            version: Value(car.sync.version),
          ),
        );
  }

  Future<List<domain.Car>> listCars() async {
    final rows = await database.select(database.cars).get();
    return rows.map(_carFromRow).toList();
  }

  Future<void> deleteCar(int carId) {
    return database.transaction(() async {
      await (database.delete(
        database.maintenanceRecordItems,
      )..where((row) => row.carId.equals(carId))).go();
      await (database.delete(
        database.maintenanceRecords,
      )..where((row) => row.carId.equals(carId))).go();
      await (database.delete(
        database.maintenanceItems,
      )..where((row) => row.carsId.equals(carId))).go();
      await (database.delete(database.appPreferences)..where(
            (row) =>
                row.key.equals('appliedCarId') & row.value.equals('$carId'),
          ))
          .go();
      await (database.delete(
        database.cars,
      )..where((row) => row.id.equals(carId))).go();
    });
  }

  Future<int> saveVehicleDefaultMaintenanceItem(
    domain.VehicleDefaultMaintenanceItem item,
  ) {
    return database
        .into(database.vehicleDefaultMaintenanceItems)
        .insert(
          VehicleDefaultMaintenanceItemsCompanion.insert(
            vehicleBrand: item.vehicleBrand,
            vehicleModel: item.vehicleModel,
            itemName: item.itemName,
            remindByMileage: item.remindByMileage,
            remindByTime: item.remindByTime,
            mileageIntervalKm: Value(item.mileageIntervalKm),
            timeIntervalMonths: Value(item.timeIntervalMonths),
            notOverdueUpperLimit: Value(item.notOverdueUpperLimit),
            overdueUpperLimit: Value(item.overdueUpperLimit),
            sortOrder: item.sortOrder,
            syncStatus: Value(item.sync.status.name),
            updatedAt: item.sync.updatedAt.toIso8601String(),
            version: Value(item.sync.version),
          ),
        );
  }

  Future<List<domain.VehicleDefaultMaintenanceItem>> listDefaultItemsForModel({
    required String brand,
    required String model,
  }) async {
    final rows =
        await (database.select(database.vehicleDefaultMaintenanceItems)
              ..where(
                (row) =>
                    row.vehicleBrand.equals(brand) &
                    row.vehicleModel.equals(model),
              )
              ..orderBy([(row) => OrderingTerm.asc(row.sortOrder)]))
            .get();
    return rows.map(_defaultItemFromRow).toList();
  }

  Future<int> saveMaintenanceItem(domain.MaintenanceItem item) {
    item.validate();
    return database
        .into(database.maintenanceItems)
        .insert(
          MaintenanceItemsCompanion.insert(
            carsId: item.carsId,
            name: item.name,
            isDefault: item.isDefault,
            enabled: Value(item.enabled),
            remindByMileage: item.remindByMileage,
            remindByTime: item.remindByTime,
            mileageIntervalKm: Value(item.mileageIntervalKm),
            timeIntervalMonths: Value(item.timeIntervalMonths),
            notOverdueUpperLimit: Value(item.notOverdueUpperLimit),
            overdueUpperLimit: Value(item.overdueUpperLimit),
            sortOrder: item.sortOrder,
            syncStatus: Value(item.sync.status.name),
            updatedAt: item.sync.updatedAt.toIso8601String(),
            version: Value(item.sync.version),
          ),
        );
  }

  Future<int> saveMaintenanceRecord(domain.MaintenanceRecord record) {
    RecordRules.validateRecord(record);
    final uniqueItemIds = RecordRules.uniqueItemIds(record.itemIds);

    return database.transaction(() async {
      await _validateRecordItems(carId: record.carId, itemIds: uniqueItemIds);

      final recordId = await database
          .into(database.maintenanceRecords)
          .insert(
            MaintenanceRecordsCompanion.insert(
              carId: record.carId,
              date: record.date.toString(),
              mileageKm: record.mileageKm,
              costCents: record.costCents,
              note: Value(record.note),
              syncStatus: Value(record.sync.status.name),
              updatedAt: record.sync.updatedAt.toIso8601String(),
              version: Value(record.sync.version),
            ),
          );

      for (final itemId in uniqueItemIds) {
        await database
            .into(database.maintenanceRecordItems)
            .insert(
              MaintenanceRecordItemsCompanion.insert(
                maintenanceRecordId: recordId,
                carId: record.carId,
                itemId: itemId,
                date: record.date.toString(),
              ),
            );
      }

      final car = await (database.select(
        database.cars,
      )..where((row) => row.id.equals(record.carId))).getSingle();
      final nextMileage = RecordRules.mileageAfterRecord(
        currentMileageKm: car.currentMileageKm,
        recordMileageKm: record.mileageKm,
      );
      if (nextMileage != car.currentMileageKm) {
        await (database.update(database.cars)
              ..where((row) => row.id.equals(record.carId)))
            .write(CarsCompanion(currentMileageKm: Value(nextMileage)));
      }
      return recordId;
    });
  }

  Future<BackupPayload> exportBackupPayload() async {
    final cars = (await database.select(database.cars).get())
        .map(_carFromRow)
        .toList();
    final defaultItems =
        (await database.select(database.vehicleDefaultMaintenanceItems).get())
            .map(_defaultItemFromRow)
            .toList();
    final items = (await database.select(database.maintenanceItems).get())
        .map(_maintenanceItemFromRow)
        .toList();
    final recordRows = await database.select(database.maintenanceRecords).get();
    final recordItemRows = await database
        .select(database.maintenanceRecordItems)
        .get();
    final itemIdsByRecordId = <int, List<int>>{};
    for (final row in recordItemRows) {
      itemIdsByRecordId
          .putIfAbsent(row.maintenanceRecordId, () => [])
          .add(row.itemId);
    }
    final records = recordRows.map((row) {
      return _recordFromRow(row, itemIdsByRecordId[row.id] ?? const []);
    }).toList();
    final preferences = (await database.select(database.appPreferences).get())
        .map(_preferenceFromRow)
        .toList();

    return BackupPayload(
      schemaVersion: 1,
      cars: cars,
      defaultMaintenanceItems: defaultItems,
      maintenanceItems: items,
      records: records,
      preferences: preferences,
    );
  }

  Future<void> restoreBackupPayload(BackupPayload payload) {
    if (payload.schemaVersion != 1) {
      throw UnsupportedError(
        'Unsupported backup schemaVersion: ${payload.schemaVersion}',
      );
    }
    _validateBackupReferences(payload);

    return database.transaction(() async {
      await database.delete(database.appPreferences).go();
      await database.delete(database.maintenanceRecordItems).go();
      await database.delete(database.maintenanceRecords).go();
      await database.delete(database.maintenanceItems).go();
      await database.delete(database.vehicleDefaultMaintenanceItems).go();
      await database.delete(database.cars).go();

      for (final car in payload.cars) {
        final id = car.id;
        if (id == null) {
          throw ArgumentError('Backup car id is required');
        }
        await database
            .into(database.cars)
            .insert(
              CarsCompanion.insert(
                id: Value(id),
                brand: car.brand,
                model: car.model,
                currentMileageKm: car.currentMileageKm,
                roadDate: car.roadDate.toString(),
                syncStatus: Value(car.sync.status.name),
                updatedAt: car.sync.updatedAt.toIso8601String(),
                version: Value(car.sync.version),
              ),
            );
      }

      for (final item in payload.defaultMaintenanceItems) {
        final id = item.id;
        if (id == null) {
          throw ArgumentError('Backup default maintenance item id is required');
        }
        await database
            .into(database.vehicleDefaultMaintenanceItems)
            .insert(
              VehicleDefaultMaintenanceItemsCompanion.insert(
                id: Value(id),
                vehicleBrand: item.vehicleBrand,
                vehicleModel: item.vehicleModel,
                itemName: item.itemName,
                remindByMileage: item.remindByMileage,
                remindByTime: item.remindByTime,
                mileageIntervalKm: Value(item.mileageIntervalKm),
                timeIntervalMonths: Value(item.timeIntervalMonths),
                notOverdueUpperLimit: Value(item.notOverdueUpperLimit),
                overdueUpperLimit: Value(item.overdueUpperLimit),
                sortOrder: item.sortOrder,
                syncStatus: Value(item.sync.status.name),
                updatedAt: item.sync.updatedAt.toIso8601String(),
                version: Value(item.sync.version),
              ),
            );
      }

      for (final item in payload.maintenanceItems) {
        final id = item.id;
        if (id == null) {
          throw ArgumentError('Backup maintenance item id is required');
        }
        await database
            .into(database.maintenanceItems)
            .insert(
              MaintenanceItemsCompanion.insert(
                id: Value(id),
                carsId: item.carsId,
                name: item.name,
                isDefault: item.isDefault,
                enabled: Value(item.enabled),
                remindByMileage: item.remindByMileage,
                remindByTime: item.remindByTime,
                mileageIntervalKm: Value(item.mileageIntervalKm),
                timeIntervalMonths: Value(item.timeIntervalMonths),
                notOverdueUpperLimit: Value(item.notOverdueUpperLimit),
                overdueUpperLimit: Value(item.overdueUpperLimit),
                sortOrder: item.sortOrder,
                syncStatus: Value(item.sync.status.name),
                updatedAt: item.sync.updatedAt.toIso8601String(),
                version: Value(item.sync.version),
              ),
            );
      }

      for (final record in payload.records) {
        final id = record.id;
        if (id == null) {
          throw ArgumentError('Backup maintenance record id is required');
        }
        await database
            .into(database.maintenanceRecords)
            .insert(
              MaintenanceRecordsCompanion.insert(
                id: Value(id),
                carId: record.carId,
                date: record.date.toString(),
                mileageKm: record.mileageKm,
                costCents: record.costCents,
                note: Value(record.note),
                syncStatus: Value(record.sync.status.name),
                updatedAt: record.sync.updatedAt.toIso8601String(),
                version: Value(record.sync.version),
              ),
            );
        for (final itemId in RecordRules.uniqueItemIds(record.itemIds)) {
          await database
              .into(database.maintenanceRecordItems)
              .insert(
                MaintenanceRecordItemsCompanion.insert(
                  maintenanceRecordId: id,
                  carId: record.carId,
                  itemId: itemId,
                  date: record.date.toString(),
                ),
              );
        }
      }

      for (final preference in payload.preferences) {
        final id = preference.id;
        if (id == null) {
          throw ArgumentError('Backup preference id is required');
        }
        await database
            .into(database.appPreferences)
            .insert(
              AppPreferencesCompanion.insert(
                id: Value(id),
                key: preference.key,
                value: Value(preference.value),
                syncStatus: Value(preference.sync.status.name),
                updatedAt: preference.sync.updatedAt.toIso8601String(),
                version: Value(preference.sync.version),
              ),
            );
      }
    });
  }

  Future<String?> getAppliedCarId() async {
    final row = await (database.select(
      database.appPreferences,
    )..where((pref) => pref.key.equals('appliedCarId'))).getSingleOrNull();
    return row?.value;
  }

  Future<void> setAppliedCarId(int? carId) async {
    final existing = await (database.select(
      database.appPreferences,
    )..where((pref) => pref.key.equals('appliedCarId'))).getSingleOrNull();
    final value = carId?.toString();
    final now = DateTime.now().toIso8601String();
    if (existing == null) {
      await database
          .into(database.appPreferences)
          .insert(
            AppPreferencesCompanion.insert(
              key: 'appliedCarId',
              value: Value(value),
              updatedAt: now,
            ),
          );
      return;
    }
    await (database.update(
      database.appPreferences,
    )..where((pref) => pref.key.equals('appliedCarId'))).write(
      AppPreferencesCompanion(value: Value(value), updatedAt: Value(now)),
    );
  }

  domain.Car _carFromRow(CarRow row) {
    return domain.Car(
      id: row.id,
      brand: row.brand,
      model: row.model,
      currentMileageKm: row.currentMileageKm,
      roadDate: LocalDate.parse(row.roadDate),
      sync: SyncMetadata(
        status: SyncStatus.values.byName(row.syncStatus),
        updatedAt: DateTime.parse(row.updatedAt),
        version: row.version,
      ),
    );
  }

  domain.VehicleDefaultMaintenanceItem _defaultItemFromRow(
    VehicleDefaultMaintenanceItemRow row,
  ) {
    return domain.VehicleDefaultMaintenanceItem(
      id: row.id,
      vehicleBrand: row.vehicleBrand,
      vehicleModel: row.vehicleModel,
      itemName: row.itemName,
      remindByMileage: row.remindByMileage,
      remindByTime: row.remindByTime,
      mileageIntervalKm: row.mileageIntervalKm,
      timeIntervalMonths: row.timeIntervalMonths,
      notOverdueUpperLimit: row.notOverdueUpperLimit,
      overdueUpperLimit: row.overdueUpperLimit,
      sortOrder: row.sortOrder,
      sync: SyncMetadata(
        status: SyncStatus.values.byName(row.syncStatus),
        updatedAt: DateTime.parse(row.updatedAt),
        version: row.version,
      ),
    );
  }

  Future<void> _validateRecordItems({
    required int carId,
    required List<int> itemIds,
  }) async {
    final rows = await (database.select(
      database.maintenanceItems,
    )..where((row) => row.id.isIn(itemIds))).get();
    if (rows.length != itemIds.length) {
      throw ArgumentError('Maintenance record contains missing items');
    }
    final hasOtherCarItem = rows.any((row) => row.carsId != carId);
    if (hasOtherCarItem) {
      throw ArgumentError('Maintenance record contains items from another car');
    }
  }

  void _validateBackupReferences(BackupPayload payload) {
    final carIds = payload.cars.map((car) => car.id).whereType<int>().toSet();
    final itemCarIds = <int, int>{};
    for (final item in payload.maintenanceItems) {
      final itemId = item.id;
      if (itemId != null) {
        itemCarIds[itemId] = item.carsId;
      }
    }
    final itemIds = itemCarIds.keys.toSet();
    if (carIds.length != payload.cars.length) {
      throw ArgumentError('Backup contains cars without ids');
    }
    if (itemIds.length != payload.maintenanceItems.length) {
      throw ArgumentError('Backup contains maintenance items without ids');
    }
    for (final item in payload.maintenanceItems) {
      if (!carIds.contains(item.carsId)) {
        throw ArgumentError('Backup maintenance item references missing car');
      }
    }
    for (final record in payload.records) {
      if (record.id == null) {
        throw ArgumentError('Backup maintenance record id is required');
      }
      if (!carIds.contains(record.carId)) {
        throw ArgumentError('Backup maintenance record references missing car');
      }
      for (final itemId in RecordRules.uniqueItemIds(record.itemIds)) {
        if (!itemIds.contains(itemId)) {
          throw ArgumentError(
            'Backup maintenance record references missing item',
          );
        }
        if (itemCarIds[itemId] != record.carId) {
          throw ArgumentError(
            'Backup maintenance record references item from another car',
          );
        }
      }
    }
    for (final preference in payload.preferences) {
      if (preference.id == null) {
        throw ArgumentError('Backup preference id is required');
      }
      if (preference.key == 'appliedCarId' && preference.value != null) {
        final appliedCarId = int.tryParse(preference.value!);
        if (appliedCarId == null || !carIds.contains(appliedCarId)) {
          throw ArgumentError('Backup appliedCarId references missing car');
        }
      }
    }
  }

  domain.MaintenanceItem _maintenanceItemFromRow(MaintenanceItemRow row) {
    return domain.MaintenanceItem(
      id: row.id,
      carsId: row.carsId,
      name: row.name,
      isDefault: row.isDefault,
      enabled: row.enabled,
      remindByMileage: row.remindByMileage,
      remindByTime: row.remindByTime,
      mileageIntervalKm: row.mileageIntervalKm,
      timeIntervalMonths: row.timeIntervalMonths,
      notOverdueUpperLimit: row.notOverdueUpperLimit,
      overdueUpperLimit: row.overdueUpperLimit,
      sortOrder: row.sortOrder,
      sync: SyncMetadata(
        status: SyncStatus.values.byName(row.syncStatus),
        updatedAt: DateTime.parse(row.updatedAt),
        version: row.version,
      ),
    );
  }

  domain.MaintenanceRecord _recordFromRow(
    MaintenanceRecordRow row,
    List<int> itemIds,
  ) {
    return domain.MaintenanceRecord(
      id: row.id,
      carId: row.carId,
      date: LocalDate.parse(row.date),
      itemIds: itemIds,
      costCents: row.costCents,
      mileageKm: row.mileageKm,
      note: row.note,
      sync: SyncMetadata(
        status: SyncStatus.values.byName(row.syncStatus),
        updatedAt: DateTime.parse(row.updatedAt),
        version: row.version,
      ),
    );
  }

  BackupPreference _preferenceFromRow(AppPreferenceRow row) {
    return BackupPreference(
      id: row.id,
      key: row.key,
      value: row.value,
      sync: SyncMetadata(
        status: SyncStatus.values.byName(row.syncStatus),
        updatedAt: DateTime.parse(row.updatedAt),
        version: row.version,
      ),
    );
  }
}
