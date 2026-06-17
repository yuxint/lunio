import 'dart:convert';

import 'package:drift/drift.dart';

import '../../core/date/local_date.dart';
import '../../core/id/snowflake_id_generator.dart';
import '../../domain/entities/car.dart' as domain;
import '../../domain/entities/maintenance_item.dart' as domain;
import '../../domain/entities/maintenance_record.dart' as domain;
import '../../domain/entities/parking_countdown.dart' as domain;
import '../../domain/entities/sync_metadata.dart';
import '../../domain/entities/vehicle_default_maintenance_item.dart' as domain;
import '../../domain/entities/vehicle_model.dart' as domain;
import '../../domain/rules/applied_car_rules.dart';
import '../../domain/rules/record_rules.dart';
import '../backup/backup_codec.dart';
import '../database/app_database.dart';

class LunioRepository {
  const LunioRepository(this.database);

  static const _parkingCountdownPreferenceKey = 'parkingCountdown';
  static final SnowflakeIdGenerator _idGenerator = SnowflakeIdGenerator();

  final AppDatabase database;

  Future<void> ensureDefaultMaintenanceItems() async {
    await _canonicalizeDefaultMaintenanceItems();
    final sync = SyncMetadata(
      status: SyncStatus.synced,
      updatedAt: DateTime.now(),
    );
    final builtInItems = _builtInDefaultItems(sync);
    final existing = await database
        .select(database.vehicleDefaultMaintenanceItems)
        .get();
    final existingKeys = existing
        .map(
          (row) =>
              '${row.vehicleBrand}\u0000${row.vehicleModel}\u0000${row.itemName}',
        )
        .toSet();
    for (final item in builtInItems) {
      final key =
          '${item.vehicleBrand}\u0000${item.vehicleModel}\u0000${item.itemName}';
      if (!existingKeys.contains(key)) {
        await saveVehicleDefaultMaintenanceItem(item);
      }
    }
  }

  Future<void> ensureVehicleModels() async {
    await _canonicalizeVehicleModels();
    final existing = await database.select(database.vehicleModels).get();
    final existingKeys = existing
        .map((row) => '${row.brand}\u0000${row.model}')
        .toSet();
    final sync = SyncMetadata(
      status: SyncStatus.synced,
      updatedAt: DateTime.now(),
    );
    for (final model in _builtInVehicleModels(sync)) {
      final key = '${model.brand}\u0000${model.model}';
      if (!existingKeys.contains(key)) {
        await saveVehicleModel(model);
      }
    }
  }

  Future<void> ensureBootstrapData() async {
    await _canonicalizeVehicleData();
    await ensureVehicleModels();
    await ensureDefaultMaintenanceItems();
  }

  Future<int> createCar(domain.Car car) async {
    final carId = _nextId();
    await database
        .into(database.cars)
        .insert(
          CarsCompanion.insert(
            id: Value(carId),
            brand: car.brand,
            model: car.model,
            currentMileageKm: car.currentMileageKm,
            roadDate: car.roadDate.toString(),
            syncStatus: Value(car.sync.status.name),
            updatedAt: car.sync.updatedAt.toIso8601String(),
            version: Value(car.sync.version),
          ),
        );
    return carId;
  }

  Future<int> createCarWithDefaultItems(domain.Car car) async {
    final defaultItems = await listDefaultItemsForModel(
      brand: car.brand,
      model: car.model,
    );
    return createCarWithMaintenanceItems(
      car,
      defaultItems
          .map(
            (item) => domain.MaintenanceItem(
              carsId: 0,
              name: item.itemName,
              enabled: true,
              remindByMileage: item.remindByMileage,
              remindByTime: item.remindByTime,
              mileageIntervalKm: item.mileageIntervalKm,
              timeIntervalMonths: item.timeIntervalMonths,
              notOverdueUpperLimit: item.notOverdueUpperLimit,
              overdueUpperLimit: item.overdueUpperLimit,
              sortOrder: item.sortOrder,
              sync: car.sync,
            ),
          )
          .toList(),
    );
  }

  Future<int> createCarWithMaintenanceItems(
    domain.Car car,
    List<domain.MaintenanceItem> items,
  ) {
    if (!items.any((item) => item.enabled)) {
      throw ArgumentError('At least one maintenance item must stay enabled');
    }
    for (final item in items) {
      item.validate();
    }
    return database.transaction(() async {
      final carId = _nextId();
      await database
          .into(database.cars)
          .insert(
            CarsCompanion.insert(
              id: Value(carId),
              brand: car.brand,
              model: car.model,
              currentMileageKm: car.currentMileageKm,
              roadDate: car.roadDate.toString(),
              syncStatus: Value(car.sync.status.name),
              updatedAt: car.sync.updatedAt.toIso8601String(),
              version: Value(car.sync.version),
            ),
          );

      for (final item in items) {
        final itemId = _nextId();
        await database
            .into(database.maintenanceItems)
            .insert(
              MaintenanceItemsCompanion.insert(
                id: Value(itemId),
                carsId: carId,
                name: item.name,
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

      final storedAppliedCarId = await _getAppliedCarIdInTransaction();
      if (storedAppliedCarId == null) {
        await _writeAppliedCarId(carId);
      }
      return carId;
    });
  }

  Future<List<domain.Car>> listCars() async {
    final rows = await database.select(database.cars).get();
    return rows.map(_carFromRow).toList();
  }

  Future<void> updateCar(domain.Car car) {
    final carId = car.id;
    if (carId == null) {
      throw ArgumentError('Car id is required');
    }
    return (database.update(
      database.cars,
    )..where((row) => row.id.equals(carId))).write(
      CarsCompanion(
        currentMileageKm: Value(car.currentMileageKm),
        roadDate: Value(car.roadDate.toString()),
        syncStatus: Value(car.sync.status.name),
        updatedAt: Value(car.sync.updatedAt.toIso8601String()),
        version: Value(car.sync.version),
      ),
    );
  }

  Future<domain.Car?> getAppliedCar() async {
    final cars = await listCars();
    final storedCarId = int.tryParse(await getAppliedCarId() ?? '');
    final appliedCarId = AppliedCarRules.resolveAppliedCarId(
      cars: cars,
      storedCarId: storedCarId,
    );
    if (appliedCarId == null) {
      await setAppliedCarId(null);
      return null;
    }
    if (appliedCarId != storedCarId) {
      await setAppliedCarId(appliedCarId);
    }
    return cars.firstWhere((car) => car.id == appliedCarId);
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
      final remainingCars = await database.select(database.cars).get();
      if (remainingCars.isEmpty) {
        await _writeAppliedCarId(null);
      } else {
        await _writeAppliedCarId(remainingCars.first.id);
      }
    });
  }

  Future<int> saveVehicleDefaultMaintenanceItem(
    domain.VehicleDefaultMaintenanceItem item,
  ) async {
    final itemId = _nextId();
    await database
        .into(database.vehicleDefaultMaintenanceItems)
        .insert(
          VehicleDefaultMaintenanceItemsCompanion.insert(
            id: Value(itemId),
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
    return itemId;
  }

  Future<int> saveVehicleModel(domain.VehicleModel model) async {
    final modelId = _nextId();
    await database
        .into(database.vehicleModels)
        .insert(
          VehicleModelsCompanion.insert(
            id: Value(modelId),
            brand: model.brand,
            model: model.model,
            sortOrder: model.sortOrder,
            syncStatus: Value(model.sync.status.name),
            updatedAt: model.sync.updatedAt.toIso8601String(),
            version: Value(model.sync.version),
          ),
        );
    return modelId;
  }

  Future<List<domain.VehicleModel>> listVehicleModels() async {
    final rows = await (database.select(
      database.vehicleModels,
    )..orderBy([(row) => OrderingTerm.asc(row.sortOrder)])).get();
    return rows.map(_vehicleModelFromRow).toList();
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

  Future<int> saveMaintenanceItem(domain.MaintenanceItem item) async {
    item.validate();
    final itemId = _nextId();
    await database
        .into(database.maintenanceItems)
        .insert(
          MaintenanceItemsCompanion.insert(
            id: Value(itemId),
            carsId: item.carsId,
            name: item.name,
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
    return itemId;
  }

  Future<List<domain.MaintenanceItem>> listMaintenanceItemsForCar(
    int carId,
  ) async {
    final rows =
        await (database.select(database.maintenanceItems)
              ..where((row) => row.carsId.equals(carId))
              ..orderBy([(row) => OrderingTerm.asc(row.sortOrder)]))
            .get();
    return rows.map(_maintenanceItemFromRow).toList();
  }

  Future<void> updateMaintenanceItem(domain.MaintenanceItem item) async {
    item.validate();
    final itemId = item.id;
    if (itemId == null) {
      throw ArgumentError('Maintenance item id is required');
    }
    if (!item.enabled) {
      await _ensureCanDisableMaintenanceItem(
        carId: item.carsId,
        itemId: itemId,
      );
    }
    await (database.update(
      database.maintenanceItems,
    )..where((row) => row.id.equals(itemId))).write(
      MaintenanceItemsCompanion(
        name: Value(item.name),
        enabled: Value(item.enabled),
        remindByMileage: Value(item.remindByMileage),
        remindByTime: Value(item.remindByTime),
        mileageIntervalKm: Value(item.mileageIntervalKm),
        timeIntervalMonths: Value(item.timeIntervalMonths),
        notOverdueUpperLimit: Value(item.notOverdueUpperLimit),
        overdueUpperLimit: Value(item.overdueUpperLimit),
        sortOrder: Value(item.sortOrder),
        syncStatus: Value(item.sync.status.name),
        updatedAt: Value(item.sync.updatedAt.toIso8601String()),
        version: Value(item.sync.version),
      ),
    );
  }

  Future<void> setMaintenanceItemEnabled({
    required int itemId,
    required bool enabled,
    required SyncMetadata sync,
  }) async {
    final item = await _getMaintenanceItemById(itemId);
    if (!enabled) {
      await _ensureCanDisableMaintenanceItem(
        carId: item.carsId,
        itemId: itemId,
      );
    }
    await (database.update(
      database.maintenanceItems,
    )..where((row) => row.id.equals(itemId))).write(
      MaintenanceItemsCompanion(
        enabled: Value(enabled),
        syncStatus: Value(sync.status.name),
        updatedAt: Value(sync.updatedAt.toIso8601String()),
        version: Value(sync.version),
      ),
    );
  }

  Future<bool> maintenanceItemHasHistory(int itemId) async {
    final count = await (database.select(
      database.maintenanceRecordItems,
    )..where((row) => row.itemId.equals(itemId))).get();
    return count.isNotEmpty;
  }

  Future<void> deleteMaintenanceItem(int itemId) async {
    final item = await _getMaintenanceItemById(itemId);
    if (await maintenanceItemHasHistory(itemId)) {
      throw ArgumentError('Maintenance item has history records');
    }
    if (item.enabled) {
      await _ensureCanDisableMaintenanceItem(
        carId: item.carsId,
        itemId: itemId,
      );
    }
    await (database.delete(
      database.maintenanceItems,
    )..where((row) => row.id.equals(itemId))).go();
  }

  Future<int> saveMaintenanceRecord(domain.MaintenanceRecord record) {
    RecordRules.validateRecord(record);
    final uniqueItemIds = RecordRules.uniqueItemIds(record.itemIds);

    return database.transaction(() async {
      await _validateRecordItems(carId: record.carId, itemIds: uniqueItemIds);
      await _ensureRecordIsUnique(
        carId: record.carId,
        date: record.date,
        itemIds: uniqueItemIds,
      );

      return _insertMaintenanceRecordInTransaction(
        record: record,
        uniqueItemIds: uniqueItemIds,
      );
    });
  }

  Future<int> saveMaintenanceRecordWithItemUpdates({
    required domain.MaintenanceRecord record,
    required List<domain.MaintenanceItem> itemUpdates,
  }) {
    RecordRules.validateRecord(record);
    final uniqueItemIds = RecordRules.uniqueItemIds(record.itemIds);

    return database.transaction(() async {
      await _validateRecordItems(carId: record.carId, itemIds: uniqueItemIds);
      await _ensureRecordIsUnique(
        carId: record.carId,
        date: record.date,
        itemIds: uniqueItemIds,
      );

      final recordId = await _insertMaintenanceRecordInTransaction(
        record: record,
        uniqueItemIds: uniqueItemIds,
      );
      await _updateMaintenanceItemIntervalsInTransaction(
        carId: record.carId,
        selectedItemIds: uniqueItemIds,
        itemUpdates: itemUpdates,
      );
      return recordId;
    });
  }

  Future<void> updateMaintenanceRecord(domain.MaintenanceRecord record) {
    final recordId = record.id;
    if (recordId == null) {
      throw ArgumentError('Maintenance record id is required');
    }
    RecordRules.validateRecord(record);
    final uniqueItemIds = RecordRules.uniqueItemIds(record.itemIds);

    return database.transaction(() async {
      await _validateRecordItems(carId: record.carId, itemIds: uniqueItemIds);
      await _ensureRecordIsUnique(
        carId: record.carId,
        date: record.date,
        itemIds: uniqueItemIds,
        excludingRecordId: recordId,
      );

      await _updateMaintenanceRecordInTransaction(
        record: record,
        uniqueItemIds: uniqueItemIds,
      );
    });
  }

  Future<void> updateMaintenanceRecordWithItemUpdates({
    required domain.MaintenanceRecord record,
    required List<domain.MaintenanceItem> itemUpdates,
  }) {
    final recordId = record.id;
    if (recordId == null) {
      throw ArgumentError('Maintenance record id is required');
    }
    RecordRules.validateRecord(record);
    final uniqueItemIds = RecordRules.uniqueItemIds(record.itemIds);

    return database.transaction(() async {
      await _validateRecordItems(carId: record.carId, itemIds: uniqueItemIds);
      await _ensureRecordIsUnique(
        carId: record.carId,
        date: record.date,
        itemIds: uniqueItemIds,
        excludingRecordId: recordId,
      );

      await _updateMaintenanceRecordInTransaction(
        record: record,
        uniqueItemIds: uniqueItemIds,
      );
      await _updateMaintenanceItemIntervalsInTransaction(
        carId: record.carId,
        selectedItemIds: uniqueItemIds,
        itemUpdates: itemUpdates,
      );
    });
  }

  Future<List<domain.MaintenanceRecord>> listMaintenanceRecordsForCar(
    int carId,
  ) async {
    final recordRows =
        await (database.select(database.maintenanceRecords)
              ..where((row) => row.carId.equals(carId))
              ..orderBy([(row) => OrderingTerm.desc(row.date)]))
            .get();
    final recordIds = recordRows.map((row) => row.id).toList();
    final itemRows = recordIds.isEmpty
        ? <MaintenanceRecordItemRow>[]
        : await (database.select(
            database.maintenanceRecordItems,
          )..where((row) => row.maintenanceRecordId.isIn(recordIds))).get();
    final itemIdsByRecordId = <int, List<int>>{};
    for (final row in itemRows) {
      itemIdsByRecordId
          .putIfAbsent(row.maintenanceRecordId, () => [])
          .add(row.itemId);
    }
    return recordRows
        .map(
          (row) => _recordFromRow(row, itemIdsByRecordId[row.id] ?? const []),
        )
        .toList();
  }

  Future<void> deleteMaintenanceRecord(int recordId) {
    return database.transaction(() async {
      await (database.delete(
        database.maintenanceRecordItems,
      )..where((row) => row.maintenanceRecordId.equals(recordId))).go();
      await (database.delete(
        database.maintenanceRecords,
      )..where((row) => row.id.equals(recordId))).go();
    });
  }

  Future<bool> removeMaintenanceRecordItem({
    required int recordId,
    required int itemId,
  }) {
    return database.transaction(() async {
      final recordRow = await (database.select(
        database.maintenanceRecords,
      )..where((row) => row.id.equals(recordId))).getSingleOrNull();
      if (recordRow == null) {
        throw ArgumentError('Maintenance record not found');
      }
      final itemRows = await (database.select(
        database.maintenanceRecordItems,
      )..where((row) => row.maintenanceRecordId.equals(recordId))).get();
      final existingItemIds = RecordRules.uniqueItemIds(
        itemRows.map((row) => row.itemId).toList(),
      );
      if (!existingItemIds.contains(itemId)) {
        throw ArgumentError('Maintenance record does not contain item');
      }
      if (existingItemIds.length <= 1) {
        await (database.delete(
          database.maintenanceRecordItems,
        )..where((row) => row.maintenanceRecordId.equals(recordId))).go();
        await (database.delete(
          database.maintenanceRecords,
        )..where((row) => row.id.equals(recordId))).go();
        return true;
      }

      await (database.delete(database.maintenanceRecordItems)..where(
            (row) =>
                row.maintenanceRecordId.equals(recordId) &
                row.itemId.equals(itemId),
          ))
          .go();
      await (database.update(
        database.maintenanceRecords,
      )..where((row) => row.id.equals(recordId))).write(
        MaintenanceRecordsCompanion(
          syncStatus: Value(SyncStatus.pendingUpdate.name),
          updatedAt: Value(DateTime.now().toIso8601String()),
        ),
      );
      return false;
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
    return BackupPayload(
      schemaVersion: 2,
      cars: cars,
      defaultMaintenanceItems: defaultItems,
      maintenanceItems: items,
      records: records,
    );
  }

  Future<void> restoreBackupPayload(BackupPayload payload) {
    if (payload.schemaVersion != 2) {
      throw UnsupportedError(
        'Unsupported backup schemaVersion: ${payload.schemaVersion}',
      );
    }
    _validateBackupReferences(payload);

    return database.transaction(() async {
      await _clearAllDataInTransaction();
      final carIdMap = <int, int>{};
      final itemIdMap = <int, int>{};
      int? firstRestoredCarId;

      for (final car in payload.cars) {
        final sourceId = car.id;
        if (sourceId == null) {
          throw ArgumentError('Backup car id is required');
        }
        final carId = _nextId();
        await database
            .into(database.cars)
            .insert(
              CarsCompanion.insert(
                id: Value(carId),
                brand: car.brand,
                model: car.model,
                currentMileageKm: car.currentMileageKm,
                roadDate: car.roadDate.toString(),
                syncStatus: Value(car.sync.status.name),
                updatedAt: car.sync.updatedAt.toIso8601String(),
                version: Value(car.sync.version),
              ),
            );
        carIdMap[sourceId] = carId;
        firstRestoredCarId ??= carId;
      }

      for (final item in payload.defaultMaintenanceItems) {
        await _restoreDefaultMaintenanceItemInTransaction(item);
      }

      for (final item in payload.maintenanceItems) {
        final sourceId = item.id;
        if (sourceId == null) {
          throw ArgumentError('Backup maintenance item id is required');
        }
        final carId = carIdMap[item.carsId];
        if (carId == null) {
          throw ArgumentError('Backup maintenance item references missing car');
        }
        final itemId = _nextId();
        await database
            .into(database.maintenanceItems)
            .insert(
              MaintenanceItemsCompanion.insert(
                id: Value(itemId),
                carsId: carId,
                name: item.name,
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
        itemIdMap[sourceId] = itemId;
      }

      for (final record in payload.records) {
        final carId = carIdMap[record.carId];
        if (carId == null) {
          throw ArgumentError(
            'Backup maintenance record references missing car',
          );
        }
        final recordId = _nextId();
        await database
            .into(database.maintenanceRecords)
            .insert(
              MaintenanceRecordsCompanion.insert(
                id: Value(recordId),
                carId: carId,
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
          final mappedItemId = itemIdMap[itemId];
          if (mappedItemId == null) {
            throw ArgumentError(
              'Backup maintenance record references missing item',
            );
          }
          final recordItemId = _nextId();
          await database
              .into(database.maintenanceRecordItems)
              .insert(
                MaintenanceRecordItemsCompanion.insert(
                  id: Value(recordItemId),
                  maintenanceRecordId: recordId,
                  carId: carId,
                  itemId: mappedItemId,
                  date: record.date.toString(),
                ),
              );
        }
      }

      await _writeAppliedCarId(firstRestoredCarId);
      await _canonicalizeVehicleDataInTransaction();
      await _ensureAppliedCarInTransaction();
    });
  }

  Future<String?> getAppliedCarId() async {
    final row = await (database.select(
      database.appPreferences,
    )..where((pref) => pref.key.equals('appliedCarId'))).getSingleOrNull();
    return row?.value;
  }

  Future<void> setAppliedCarId(int? carId) async {
    return _writeAppliedCarId(carId);
  }

  Future<String?> getPreferenceValue(String key) async {
    final row = await (database.select(
      database.appPreferences,
    )..where((pref) => pref.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Future<void> setPreferenceValue(String key, String? value) async {
    return _writePreferenceValue(key, value);
  }

  Future<domain.ParkingCountdown?> getParkingCountdown() async {
    final value = await getPreferenceValue(_parkingCountdownPreferenceKey);
    if (value == null) {
      return null;
    }
    try {
      final json = jsonDecode(value) as Map<String, Object?>;
      return domain.ParkingCountdown.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveParkingCountdown(domain.ParkingCountdown countdown) {
    return setPreferenceValue(
      _parkingCountdownPreferenceKey,
      jsonEncode(countdown.toJson()),
    );
  }

  Future<void> clearParkingCountdown() {
    return setPreferenceValue(_parkingCountdownPreferenceKey, null);
  }

  Future<void> clearAllData() {
    return database.transaction(() async {
      await _clearAllDataInTransaction();
    });
  }

  Future<void> _clearAllDataInTransaction() async {
    await database.delete(database.appPreferences).go();
    await database.delete(database.maintenanceRecordItems).go();
    await database.delete(database.maintenanceRecords).go();
    await database.delete(database.maintenanceItems).go();
    await database.delete(database.cars).go();
    await database.delete(database.vehicleModels).go();
  }

  Future<String?> _getAppliedCarIdInTransaction() async {
    final row = await (database.select(
      database.appPreferences,
    )..where((pref) => pref.key.equals('appliedCarId'))).getSingleOrNull();
    return row?.value;
  }

  Future<void> _writeAppliedCarId(int? carId) async {
    return _writePreferenceValue('appliedCarId', carId?.toString());
  }

  Future<void> _ensureAppliedCarInTransaction() async {
    final cars = await database.select(database.cars).get();
    if (cars.isEmpty) {
      await _writeAppliedCarId(null);
      return;
    }
    final appliedCarId = int.tryParse(
      await _getAppliedCarIdInTransaction() ?? '',
    );
    if (appliedCarId != null && cars.any((car) => car.id == appliedCarId)) {
      return;
    }
    await _writeAppliedCarId(cars.first.id);
  }

  Future<void> _writePreferenceValue(String key, String? value) async {
    if (value == null) {
      await (database.delete(
        database.appPreferences,
      )..where((pref) => pref.key.equals(key))).go();
      return;
    }
    final existing = await (database.select(
      database.appPreferences,
    )..where((pref) => pref.key.equals(key))).getSingleOrNull();
    final now = DateTime.now().toIso8601String();
    if (existing == null) {
      final preferenceId = _nextId();
      await database
          .into(database.appPreferences)
          .insert(
            AppPreferencesCompanion.insert(
              id: Value(preferenceId),
              key: key,
              value: Value(value),
              syncStatus: const Value('pendingUpdate'),
              updatedAt: now,
            ),
          );
      return;
    }
    await (database.update(
      database.appPreferences,
    )..where((pref) => pref.key.equals(key))).write(
      AppPreferencesCompanion(
        value: Value(value),
        syncStatus: const Value('pendingUpdate'),
        updatedAt: Value(now),
      ),
    );
  }

  Future<void> _canonicalizeVehicleModels() {
    return database.transaction(_canonicalizeVehicleModelsInTransaction);
  }

  Future<void> _canonicalizeDefaultMaintenanceItems() {
    return database.transaction(
      _canonicalizeDefaultMaintenanceItemsInTransaction,
    );
  }

  Future<void> _canonicalizeVehicleData() {
    return database.transaction(_canonicalizeVehicleDataInTransaction);
  }

  Future<void> _canonicalizeVehicleDataInTransaction() async {
    await _canonicalizeVehicleModelsInTransaction();
    await _canonicalizeDefaultMaintenanceItemsInTransaction();
    await _canonicalizeCarsInTransaction();
  }

  Future<void> _canonicalizeVehicleModelsInTransaction() async {
    final rows = await database.select(database.vehicleModels).get();
    for (final row in rows) {
      final brand = _canonicalVehicleBrand(row.brand);
      if (brand == row.brand) {
        continue;
      }
      final existing =
          await (database.select(database.vehicleModels)..where(
                (candidate) =>
                    candidate.id.equals(row.id).not() &
                    candidate.brand.equals(brand) &
                    candidate.model.equals(row.model),
              ))
              .getSingleOrNull();
      if (existing != null) {
        await (database.delete(
          database.vehicleModels,
        )..where((candidate) => candidate.id.equals(row.id))).go();
        continue;
      }
      await (database.update(database.vehicleModels)
            ..where((candidate) => candidate.id.equals(row.id)))
          .write(VehicleModelsCompanion(brand: Value(brand)));
    }
  }

  Future<void> _canonicalizeDefaultMaintenanceItemsInTransaction() async {
    final rows = await database
        .select(database.vehicleDefaultMaintenanceItems)
        .get();
    for (final row in rows) {
      final brand = _canonicalVehicleBrand(row.vehicleBrand);
      if (brand == row.vehicleBrand) {
        continue;
      }
      final existing =
          await (database.select(database.vehicleDefaultMaintenanceItems)
                ..where(
                  (candidate) =>
                      candidate.id.equals(row.id).not() &
                      candidate.vehicleBrand.equals(brand) &
                      candidate.vehicleModel.equals(row.vehicleModel) &
                      candidate.itemName.equals(row.itemName),
                ))
              .getSingleOrNull();
      if (existing != null) {
        await (database.delete(
          database.vehicleDefaultMaintenanceItems,
        )..where((candidate) => candidate.id.equals(row.id))).go();
        continue;
      }
      await (database.update(
        database.vehicleDefaultMaintenanceItems,
      )..where((candidate) => candidate.id.equals(row.id))).write(
        VehicleDefaultMaintenanceItemsCompanion(vehicleBrand: Value(brand)),
      );
    }
  }

  Future<void> _canonicalizeCarsInTransaction() async {
    final rows = await database.select(database.cars).get();
    final rowsByKey = <String, List<CarRow>>{};
    for (final row in rows) {
      final key = _canonicalCarKey(row);
      rowsByKey.putIfAbsent(key, () => []).add(row);
    }

    final appliedCarId = int.tryParse(
      await _getAppliedCarIdInTransaction() ?? '',
    );
    for (final entry in rowsByKey.entries) {
      final group = entry.value;
      final first = group.first;
      final brand = _canonicalVehicleBrand(first.brand);
      if (group.length == 1) {
        if (brand != first.brand) {
          await _updateCarIdentityInTransaction(
            carId: first.id,
            brand: brand,
            model: first.model,
            currentMileageKm: first.currentMileageKm,
          );
        }
        continue;
      }
      await _mergeCanonicalCarGroupInTransaction(
        group,
        canonicalBrand: brand,
        appliedCarId: appliedCarId,
      );
    }
  }

  Future<void> _mergeCanonicalCarGroupInTransaction(
    List<CarRow> group, {
    required String canonicalBrand,
    required int? appliedCarId,
  }) async {
    final retained = group.firstWhere(
      (row) => row.id == appliedCarId,
      orElse: () => group.reduce((a, b) => a.id < b.id ? a : b),
    );
    final retainedCarId = retained.id;
    final carIds = group.map((row) => row.id).toList();
    final duplicateCarIds = carIds.where((id) => id != retainedCarId).toList();
    final itemIdMap = await _mergeMaintenanceItemsForCarsInTransaction(
      carIds: carIds,
      retainedCarId: retainedCarId,
    );
    await _mergeMaintenanceRecordsForCarsInTransaction(
      carIds: carIds,
      retainedCarId: retainedCarId,
      itemIdMap: itemIdMap,
    );
    await (database.delete(
      database.maintenanceItems,
    )..where((row) => row.carsId.isIn(duplicateCarIds))).go();
    await (database.delete(
      database.cars,
    )..where((row) => row.id.isIn(duplicateCarIds))).go();
    final mileage = group
        .map((row) => row.currentMileageKm)
        .reduce((a, b) => a > b ? a : b);
    await _updateCarIdentityInTransaction(
      carId: retainedCarId,
      brand: canonicalBrand,
      model: retained.model,
      currentMileageKm: mileage,
    );
    await _writeAppliedCarId(retainedCarId);
  }

  Future<Map<int, int>> _mergeMaintenanceItemsForCarsInTransaction({
    required List<int> carIds,
    required int retainedCarId,
  }) async {
    final rows = await (database.select(
      database.maintenanceItems,
    )..where((row) => row.carsId.isIn(carIds))).get();
    final rowsByName = <String, List<MaintenanceItemRow>>{};
    for (final row in rows) {
      rowsByName.putIfAbsent(row.name, () => []).add(row);
    }

    final itemIdMap = <int, int>{};
    for (final itemRows in rowsByName.values) {
      final target = itemRows.firstWhere(
        (row) => row.carsId == retainedCarId,
        orElse: () => itemRows.reduce((a, b) => a.id < b.id ? a : b),
      );
      final enabled = itemRows.any((row) => row.enabled);
      final sortOrder = itemRows
          .map((row) => row.sortOrder)
          .reduce((a, b) => a < b ? a : b);
      for (final row in itemRows) {
        itemIdMap[row.id] = target.id;
      }
      await (database.update(
        database.maintenanceItems,
      )..where((row) => row.id.equals(target.id))).write(
        MaintenanceItemsCompanion(
          carsId: Value(retainedCarId),
          enabled: Value(enabled),
          sortOrder: Value(sortOrder),
          syncStatus: Value(SyncStatus.pendingUpdate.name),
          updatedAt: Value(DateTime.now().toIso8601String()),
        ),
      );
    }
    return itemIdMap;
  }

  Future<void> _mergeMaintenanceRecordsForCarsInTransaction({
    required List<int> carIds,
    required int retainedCarId,
    required Map<int, int> itemIdMap,
  }) async {
    final rows = await (database.select(
      database.maintenanceRecords,
    )..where((row) => row.carId.isIn(carIds))).get();
    final rowsByDate = <String, List<MaintenanceRecordRow>>{};
    for (final row in rows) {
      rowsByDate.putIfAbsent(row.date, () => []).add(row);
    }

    for (final recordRows in rowsByDate.values) {
      final retainedRecord = recordRows.firstWhere(
        (row) => row.carId == retainedCarId,
        orElse: () => recordRows.reduce((a, b) => a.id < b.id ? a : b),
      );
      final recordIds = recordRows.map((row) => row.id).toList();
      final recordItems = await (database.select(
        database.maintenanceRecordItems,
      )..where((row) => row.maintenanceRecordId.isIn(recordIds))).get();
      final itemIds = <int>{};
      for (final item in recordItems) {
        itemIds.add(itemIdMap[item.itemId] ?? item.itemId);
      }
      final costCents = recordRows.fold<int>(
        0,
        (total, row) => total + row.costCents,
      );
      final mileageKm = recordRows
          .map((row) => row.mileageKm)
          .reduce((a, b) => a > b ? a : b);
      final note = _mergedRecordNote(recordRows);

      await (database.delete(
        database.maintenanceRecordItems,
      )..where((row) => row.maintenanceRecordId.isIn(recordIds))).go();
      await (database.update(
        database.maintenanceRecords,
      )..where((row) => row.id.equals(retainedRecord.id))).write(
        MaintenanceRecordsCompanion(
          carId: Value(retainedCarId),
          costCents: Value(costCents),
          mileageKm: Value(mileageKm),
          note: Value(note),
          syncStatus: Value(SyncStatus.pendingUpdate.name),
          updatedAt: Value(DateTime.now().toIso8601String()),
        ),
      );
      await (database.delete(database.maintenanceRecords)..where(
            (row) =>
                row.id.isIn(recordIds) & row.id.equals(retainedRecord.id).not(),
          ))
          .go();
      for (final itemId in itemIds) {
        await database
            .into(database.maintenanceRecordItems)
            .insert(
              MaintenanceRecordItemsCompanion.insert(
                id: Value(_nextId()),
                maintenanceRecordId: retainedRecord.id,
                carId: retainedCarId,
                itemId: itemId,
                date: retainedRecord.date,
              ),
            );
      }
    }
  }

  Future<void> _updateCarIdentityInTransaction({
    required int carId,
    required String brand,
    required String model,
    required int currentMileageKm,
  }) async {
    await (database.update(
      database.cars,
    )..where((row) => row.id.equals(carId))).write(
      CarsCompanion(
        brand: Value(brand),
        model: Value(model),
        currentMileageKm: Value(currentMileageKm),
        syncStatus: Value(SyncStatus.pendingUpdate.name),
        updatedAt: Value(DateTime.now().toIso8601String()),
      ),
    );
  }

  String _mergedRecordNote(List<MaintenanceRecordRow> rows) {
    final notes = <String>[];
    for (final row in rows) {
      final note = row.note?.trim();
      if (note != null && note.isNotEmpty && !notes.contains(note)) {
        notes.add(note);
      }
    }
    if (notes.isEmpty) {
      return '';
    }
    return notes.join('\n');
  }

  String _canonicalCarKey(CarRow row) {
    return [
      _canonicalVehicleBrand(row.brand),
      row.model,
      row.roadDate,
    ].join('\u0000');
  }

  static int _nextId() => _idGenerator.next();

  List<domain.VehicleDefaultMaintenanceItem> _builtInDefaultItems(
    SyncMetadata sync,
  ) {
    return [
      for (final seed in _builtInVehicleCatalog)
        ..._defaultItemsForSeed(seed, sync),
    ];
  }

  List<domain.VehicleModel> _builtInVehicleModels(SyncMetadata sync) {
    return [
      for (final entry in _indexedBuiltInVehicleCatalog())
        domain.VehicleModel(
          brand: entry.seed.brand,
          model: entry.seed.model,
          sortOrder: entry.sortOrder,
          sync: sync,
        ),
    ];
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

  domain.VehicleModel _vehicleModelFromRow(VehicleModelRow row) {
    return domain.VehicleModel(
      id: row.id,
      brand: row.brand,
      model: row.model,
      sortOrder: row.sortOrder,
      sync: SyncMetadata(
        status: SyncStatus.values.byName(row.syncStatus),
        updatedAt: DateTime.parse(row.updatedAt),
        version: row.version,
      ),
    );
  }

  Future<void> _ensureRecordIsUnique({
    required int carId,
    required LocalDate date,
    required List<int> itemIds,
    int? excludingRecordId,
  }) async {
    final existingRecords =
        await (database.select(database.maintenanceRecords)..where(
              (row) =>
                  row.carId.equals(carId) &
                  row.date.equals(date.toString()) &
                  (excludingRecordId == null
                      ? const Constant(true)
                      : row.id.equals(excludingRecordId).not()),
            ))
            .get();
    if (existingRecords.isEmpty) {
      return;
    }
    final existingRecordIds = existingRecords.map((row) => row.id).toList();
    final duplicateItems =
        await (database.select(database.maintenanceRecordItems)..where(
              (row) =>
                  row.maintenanceRecordId.isIn(existingRecordIds) &
                  row.itemId.isIn(itemIds),
            ))
            .get();
    if (duplicateItems.isNotEmpty) {
      throw StateError('这辆车当天已经保存过相同保养项目');
    }
    throw StateError('这辆车当天已有保养记录，请编辑原记录');
  }

  Future<void> _updateMaintenanceRecordInTransaction({
    required domain.MaintenanceRecord record,
    required List<int> uniqueItemIds,
  }) async {
    final recordId = record.id;
    if (recordId == null) {
      throw ArgumentError('Maintenance record id is required');
    }
    await (database.update(
      database.maintenanceRecords,
    )..where((row) => row.id.equals(recordId))).write(
      MaintenanceRecordsCompanion(
        date: Value(record.date.toString()),
        mileageKm: Value(record.mileageKm),
        costCents: Value(record.costCents),
        note: Value(record.note),
        syncStatus: Value(record.sync.status.name),
        updatedAt: Value(record.sync.updatedAt.toIso8601String()),
        version: Value(record.sync.version),
      ),
    );
    await (database.delete(
      database.maintenanceRecordItems,
    )..where((row) => row.maintenanceRecordId.equals(recordId))).go();
    for (final itemId in uniqueItemIds) {
      await database
          .into(database.maintenanceRecordItems)
          .insert(
            MaintenanceRecordItemsCompanion.insert(
              id: Value(_nextId()),
              maintenanceRecordId: recordId,
              carId: record.carId,
              itemId: itemId,
              date: record.date.toString(),
            ),
          );
    }
    await _syncCarMileageInTransaction(
      carId: record.carId,
      recordMileageKm: record.mileageKm,
    );
  }

  Future<int> _insertMaintenanceRecordInTransaction({
    required domain.MaintenanceRecord record,
    required List<int> uniqueItemIds,
  }) async {
    final recordId = _nextId();
    await database
        .into(database.maintenanceRecords)
        .insert(
          MaintenanceRecordsCompanion.insert(
            id: Value(recordId),
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
              id: Value(_nextId()),
              maintenanceRecordId: recordId,
              carId: record.carId,
              itemId: itemId,
              date: record.date.toString(),
            ),
          );
    }

    await _syncCarMileageInTransaction(
      carId: record.carId,
      recordMileageKm: record.mileageKm,
    );
    return recordId;
  }

  Future<void> _restoreDefaultMaintenanceItemInTransaction(
    domain.VehicleDefaultMaintenanceItem item,
  ) async {
    final existing =
        await (database.select(database.vehicleDefaultMaintenanceItems)..where(
              (row) =>
                  row.vehicleBrand.equals(item.vehicleBrand) &
                  row.vehicleModel.equals(item.vehicleModel) &
                  row.itemName.equals(item.itemName),
            ))
            .getSingleOrNull();
    if (existing == null) {
      await database
          .into(database.vehicleDefaultMaintenanceItems)
          .insert(
            VehicleDefaultMaintenanceItemsCompanion.insert(
              id: Value(_nextId()),
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
      return;
    }

    await (database.update(
      database.vehicleDefaultMaintenanceItems,
    )..where((row) => row.id.equals(existing.id))).write(
      VehicleDefaultMaintenanceItemsCompanion(
        remindByMileage: Value(item.remindByMileage),
        remindByTime: Value(item.remindByTime),
        mileageIntervalKm: Value(item.mileageIntervalKm),
        timeIntervalMonths: Value(item.timeIntervalMonths),
        notOverdueUpperLimit: Value(item.notOverdueUpperLimit),
        overdueUpperLimit: Value(item.overdueUpperLimit),
        sortOrder: Value(item.sortOrder),
        syncStatus: Value(item.sync.status.name),
        updatedAt: Value(item.sync.updatedAt.toIso8601String()),
        version: Value(item.sync.version),
      ),
    );
  }

  Future<void> _updateMaintenanceItemIntervalsInTransaction({
    required int carId,
    required List<int> selectedItemIds,
    required List<domain.MaintenanceItem> itemUpdates,
  }) async {
    final selectedItemIdSet = selectedItemIds.toSet();
    for (final item in itemUpdates) {
      item.validate();
      final itemId = item.id;
      if (itemId == null) {
        throw ArgumentError('Maintenance item id is required');
      }
      if (item.carsId != carId || !selectedItemIdSet.contains(itemId)) {
        throw ArgumentError('Maintenance item update is outside record scope');
      }
      await (database.update(
        database.maintenanceItems,
      )..where((row) => row.id.equals(itemId))).write(
        MaintenanceItemsCompanion(
          remindByMileage: Value(item.remindByMileage),
          remindByTime: Value(item.remindByTime),
          mileageIntervalKm: Value(item.mileageIntervalKm),
          timeIntervalMonths: Value(item.timeIntervalMonths),
          syncStatus: Value(item.sync.status.name),
          updatedAt: Value(item.sync.updatedAt.toIso8601String()),
          version: Value(item.sync.version),
        ),
      );
    }
  }

  Future<void> _syncCarMileageInTransaction({
    required int carId,
    required int recordMileageKm,
  }) async {
    final car = await (database.select(
      database.cars,
    )..where((row) => row.id.equals(carId))).getSingle();
    final nextMileage = RecordRules.mileageAfterRecord(
      currentMileageKm: car.currentMileageKm,
      recordMileageKm: recordMileageKm,
    );
    if (nextMileage != car.currentMileageKm) {
      final now = DateTime.now().toIso8601String();
      await (database.update(
        database.cars,
      )..where((row) => row.id.equals(carId))).write(
        CarsCompanion(
          currentMileageKm: Value(nextMileage),
          syncStatus: Value(SyncStatus.pendingUpdate.name),
          updatedAt: Value(now),
        ),
      );
    }
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

  Future<domain.MaintenanceItem> _getMaintenanceItemById(int itemId) async {
    final row = await (database.select(
      database.maintenanceItems,
    )..where((row) => row.id.equals(itemId))).getSingleOrNull();
    if (row == null) {
      throw ArgumentError('Maintenance item not found');
    }
    return _maintenanceItemFromRow(row);
  }

  Future<void> _ensureCanDisableMaintenanceItem({
    required int carId,
    required int itemId,
  }) async {
    final enabledRows =
        await (database.select(database.maintenanceItems)..where(
              (row) =>
                  row.carsId.equals(carId) &
                  row.enabled.equals(true) &
                  row.id.equals(itemId).not(),
            ))
            .get();
    if (enabledRows.isEmpty) {
      throw ArgumentError('At least one maintenance item must stay enabled');
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
  }

  domain.MaintenanceItem _maintenanceItemFromRow(MaintenanceItemRow row) {
    return domain.MaintenanceItem(
      id: row.id,
      carsId: row.carsId,
      name: row.name,
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
}

enum _MaintenanceTemplateType { civicFuel, fuel, hybrid, plugIn, ev }

String _canonicalVehicleBrand(String brand) {
  return _canonicalVehicleBrands[brand] ?? brand;
}

const _canonicalVehicleBrands = {
  '东风本田': '本田',
  '广汽本田': '本田',
  '东风日产': '日产',
  '郑州日产': '日产',
  '一汽丰田': '丰田',
  '广汽丰田': '丰田',
  '一汽-大众': '大众',
  '上汽大众': '大众',
  '上汽通用别克': '别克',
  '长安福特': '福特',
  '北京现代': '现代',
  '华晨宝马': '宝马',
  '北京奔驰': '奔驰',
  '一汽奥迪': '奥迪',
  '沃尔沃亚太': '沃尔沃',
  '广汽传祺': '传祺',
  '广汽埃安': '埃安',
  '东风风神': '风神',
  '东风奕派': '奕派',
};

class _VehicleTemplateSeed {
  const _VehicleTemplateSeed(this.brand, this.model, this.templateType);

  final String brand;
  final String model;
  final _MaintenanceTemplateType templateType;
}

Iterable<({int sortOrder, _VehicleTemplateSeed seed})>
_indexedBuiltInVehicleCatalog() sync* {
  var sortOrder = 1;
  for (final seed in _builtInVehicleCatalog) {
    yield (sortOrder: sortOrder, seed: seed);
    sortOrder += 1;
  }
}

List<domain.VehicleDefaultMaintenanceItem> _defaultItemsForSeed(
  _VehicleTemplateSeed seed,
  SyncMetadata sync,
) {
  final specs = switch (seed.templateType) {
    _MaintenanceTemplateType.civicFuel => _civicFuelTemplate,
    _MaintenanceTemplateType.fuel => _fuelTemplate,
    _MaintenanceTemplateType.hybrid => _hybridTemplate,
    _MaintenanceTemplateType.plugIn => _plugInTemplate,
    _MaintenanceTemplateType.ev => _evTemplate,
  };
  return [
    for (final entry in specs.indexed)
      domain.VehicleDefaultMaintenanceItem(
        vehicleBrand: seed.brand,
        vehicleModel: seed.model,
        itemName: entry.$2.name,
        remindByMileage: entry.$2.remindByMileage,
        remindByTime: entry.$2.remindByTime,
        mileageIntervalKm: entry.$2.mileageIntervalKm,
        timeIntervalMonths: entry.$2.timeIntervalMonths,
        sortOrder: entry.$1 + 1,
        sync: sync,
      ),
  ];
}

class _TemplateItemSpec {
  const _TemplateItemSpec(
    this.name, {
    required this.remindByMileage,
    required this.remindByTime,
    this.mileageIntervalKm,
    this.timeIntervalMonths,
  });

  final String name;
  final bool remindByMileage;
  final bool remindByTime;
  final int? mileageIntervalKm;
  final int? timeIntervalMonths;
}

const _civicFuelTemplate = [
  _TemplateItemSpec(
    '燃油宝',
    remindByMileage: true,
    remindByTime: false,
    mileageIntervalKm: 5000,
  ),
  _TemplateItemSpec(
    '机油',
    remindByMileage: true,
    remindByTime: true,
    mileageIntervalKm: 5000,
    timeIntervalMonths: 6,
  ),
  _TemplateItemSpec(
    '机滤',
    remindByMileage: true,
    remindByTime: true,
    mileageIntervalKm: 5000,
    timeIntervalMonths: 6,
  ),
  _TemplateItemSpec(
    '空调滤芯',
    remindByMileage: true,
    remindByTime: true,
    mileageIntervalKm: 20000,
    timeIntervalMonths: 12,
  ),
  _TemplateItemSpec(
    '空气滤芯',
    remindByMileage: true,
    remindByTime: false,
    mileageIntervalKm: 20000,
  ),
  _TemplateItemSpec(
    '变速箱油',
    remindByMileage: true,
    remindByTime: true,
    mileageIntervalKm: 40000,
    timeIntervalMonths: 24,
  ),
  _TemplateItemSpec(
    '刹车油',
    remindByMileage: false,
    remindByTime: true,
    timeIntervalMonths: 36,
  ),
  _TemplateItemSpec(
    '火花塞',
    remindByMileage: true,
    remindByTime: false,
    mileageIntervalKm: 100000,
  ),
  _TemplateItemSpec(
    '检查传动皮带',
    remindByMileage: true,
    remindByTime: true,
    mileageIntervalKm: 40000,
    timeIntervalMonths: 24,
  ),
  _TemplateItemSpec(
    '检查气门间隙',
    remindByMileage: true,
    remindByTime: false,
    mileageIntervalKm: 120000,
  ),
  _TemplateItemSpec(
    '检查刹车',
    remindByMileage: true,
    remindByTime: false,
    mileageIntervalKm: 120000,
  ),
  _TemplateItemSpec(
    '防冻液',
    remindByMileage: true,
    remindByTime: true,
    mileageIntervalKm: 200000,
    timeIntervalMonths: 120,
  ),
  _TemplateItemSpec(
    '汽油滤芯',
    remindByMileage: true,
    remindByTime: false,
    mileageIntervalKm: 140000,
  ),
  _TemplateItemSpec(
    '轮胎换位',
    remindByMileage: true,
    remindByTime: false,
    mileageIntervalKm: 10000,
  ),
];

const _fuelTemplate = [
  _TemplateItemSpec(
    '机油',
    remindByMileage: true,
    remindByTime: true,
    mileageIntervalKm: 5000,
    timeIntervalMonths: 6,
  ),
  _TemplateItemSpec(
    '机滤',
    remindByMileage: true,
    remindByTime: true,
    mileageIntervalKm: 5000,
    timeIntervalMonths: 6,
  ),
  _TemplateItemSpec(
    '空气滤芯',
    remindByMileage: true,
    remindByTime: true,
    mileageIntervalKm: 20000,
    timeIntervalMonths: 12,
  ),
  _TemplateItemSpec(
    '空调滤芯',
    remindByMileage: true,
    remindByTime: true,
    mileageIntervalKm: 20000,
    timeIntervalMonths: 12,
  ),
  _TemplateItemSpec(
    '汽油滤芯',
    remindByMileage: true,
    remindByTime: false,
    mileageIntervalKm: 40000,
  ),
  _TemplateItemSpec(
    '刹车油',
    remindByMileage: true,
    remindByTime: true,
    mileageIntervalKm: 40000,
    timeIntervalMonths: 24,
  ),
  _TemplateItemSpec(
    '变速箱油',
    remindByMileage: true,
    remindByTime: true,
    mileageIntervalKm: 60000,
    timeIntervalMonths: 36,
  ),
  _TemplateItemSpec(
    '火花塞',
    remindByMileage: true,
    remindByTime: false,
    mileageIntervalKm: 100000,
  ),
  _TemplateItemSpec(
    '轮胎换位',
    remindByMileage: true,
    remindByTime: false,
    mileageIntervalKm: 10000,
  ),
  _TemplateItemSpec(
    '防冻液',
    remindByMileage: true,
    remindByTime: true,
    mileageIntervalKm: 40000,
    timeIntervalMonths: 24,
  ),
];

const _hybridTemplate = [
  ..._fuelTemplate,
  _TemplateItemSpec(
    '混动系统检查',
    remindByMileage: true,
    remindByTime: true,
    mileageIntervalKm: 20000,
    timeIntervalMonths: 12,
  ),
];

const _plugInTemplate = [
  _TemplateItemSpec(
    '机油',
    remindByMileage: true,
    remindByTime: true,
    mileageIntervalKm: 10000,
    timeIntervalMonths: 12,
  ),
  _TemplateItemSpec(
    '机滤',
    remindByMileage: true,
    remindByTime: true,
    mileageIntervalKm: 10000,
    timeIntervalMonths: 12,
  ),
  _TemplateItemSpec(
    '空气滤芯',
    remindByMileage: true,
    remindByTime: true,
    mileageIntervalKm: 20000,
    timeIntervalMonths: 12,
  ),
  _TemplateItemSpec(
    '空调滤芯',
    remindByMileage: true,
    remindByTime: true,
    mileageIntervalKm: 20000,
    timeIntervalMonths: 12,
  ),
  _TemplateItemSpec(
    '刹车油',
    remindByMileage: true,
    remindByTime: true,
    mileageIntervalKm: 40000,
    timeIntervalMonths: 24,
  ),
  _TemplateItemSpec(
    '防冻液',
    remindByMileage: true,
    remindByTime: true,
    mileageIntervalKm: 40000,
    timeIntervalMonths: 24,
  ),
  _TemplateItemSpec(
    '火花塞',
    remindByMileage: true,
    remindByTime: false,
    mileageIntervalKm: 100000,
  ),
  _TemplateItemSpec(
    '轮胎换位',
    remindByMileage: true,
    remindByTime: false,
    mileageIntervalKm: 10000,
  ),
  _TemplateItemSpec(
    '动力电池/电驱系统检查',
    remindByMileage: true,
    remindByTime: true,
    mileageIntervalKm: 20000,
    timeIntervalMonths: 12,
  ),
];

const _evTemplate = [
  _TemplateItemSpec(
    '空调滤芯',
    remindByMileage: true,
    remindByTime: true,
    mileageIntervalKm: 20000,
    timeIntervalMonths: 12,
  ),
  _TemplateItemSpec(
    '刹车油',
    remindByMileage: true,
    remindByTime: true,
    mileageIntervalKm: 40000,
    timeIntervalMonths: 24,
  ),
  _TemplateItemSpec(
    '减速器油',
    remindByMileage: true,
    remindByTime: true,
    mileageIntervalKm: 60000,
    timeIntervalMonths: 36,
  ),
  _TemplateItemSpec(
    '电驱冷却液',
    remindByMileage: true,
    remindByTime: true,
    mileageIntervalKm: 40000,
    timeIntervalMonths: 24,
  ),
  _TemplateItemSpec(
    '动力电池/高压系统检查',
    remindByMileage: true,
    remindByTime: true,
    mileageIntervalKm: 20000,
    timeIntervalMonths: 12,
  ),
  _TemplateItemSpec(
    '制动系统检查',
    remindByMileage: true,
    remindByTime: true,
    mileageIntervalKm: 10000,
    timeIntervalMonths: 12,
  ),
  _TemplateItemSpec(
    '轮胎换位',
    remindByMileage: true,
    remindByTime: false,
    mileageIntervalKm: 10000,
  ),
];

const _builtInVehicleCatalog = [
  _VehicleTemplateSeed('本田', '思域（燃油版）', _MaintenanceTemplateType.civicFuel),
  _VehicleTemplateSeed('本田', '思域（混动版）', _MaintenanceTemplateType.hybrid),
  _VehicleTemplateSeed('日产', '轩逸（燃油版）', _MaintenanceTemplateType.fuel),
  _VehicleTemplateSeed('日产', '轩逸（混动版）', _MaintenanceTemplateType.hybrid),
  _VehicleTemplateSeed('丰田', '卡罗拉（燃油版）', _MaintenanceTemplateType.fuel),
  _VehicleTemplateSeed('丰田', '卡罗拉（混动版）', _MaintenanceTemplateType.hybrid),
  _VehicleTemplateSeed('丰田', '凯美瑞（燃油版）', _MaintenanceTemplateType.fuel),
  _VehicleTemplateSeed('丰田', '凯美瑞（混动版）', _MaintenanceTemplateType.hybrid),
  _VehicleTemplateSeed('丰田', '汉兰达（混动版）', _MaintenanceTemplateType.hybrid),
  _VehicleTemplateSeed('丰田', '赛那（混动版）', _MaintenanceTemplateType.hybrid),
  _VehicleTemplateSeed('丰田', '威兰达（燃油版）', _MaintenanceTemplateType.fuel),
  _VehicleTemplateSeed('丰田', '威兰达（混动版）', _MaintenanceTemplateType.hybrid),
  _VehicleTemplateSeed('丰田', 'RAV4 荣放（燃油版）', _MaintenanceTemplateType.fuel),
  _VehicleTemplateSeed('丰田', 'RAV4 荣放（混动版）', _MaintenanceTemplateType.hybrid),
  _VehicleTemplateSeed('丰田', '格瑞维亚（混动版）', _MaintenanceTemplateType.hybrid),
  _VehicleTemplateSeed('本田', '雅阁（燃油版）', _MaintenanceTemplateType.fuel),
  _VehicleTemplateSeed('本田', '雅阁（混动版）', _MaintenanceTemplateType.hybrid),
  _VehicleTemplateSeed('本田', 'CR-V（燃油版）', _MaintenanceTemplateType.fuel),
  _VehicleTemplateSeed('本田', 'CR-V（混动版）', _MaintenanceTemplateType.hybrid),
  _VehicleTemplateSeed('本田', '皓影（燃油版）', _MaintenanceTemplateType.fuel),
  _VehicleTemplateSeed('本田', '皓影（混动版）', _MaintenanceTemplateType.hybrid),
  _VehicleTemplateSeed('本田', '型格（燃油版）', _MaintenanceTemplateType.fuel),
  _VehicleTemplateSeed('本田', '型格（混动版）', _MaintenanceTemplateType.hybrid),
  _VehicleTemplateSeed('本田', '奥德赛（混动版）', _MaintenanceTemplateType.hybrid),
  _VehicleTemplateSeed('日产', '天籁（燃油版）', _MaintenanceTemplateType.fuel),
  _VehicleTemplateSeed('日产', '逍客（燃油版）', _MaintenanceTemplateType.fuel),
  _VehicleTemplateSeed('日产', '奇骏（燃油版）', _MaintenanceTemplateType.fuel),
  _VehicleTemplateSeed('大众', '速腾（燃油版）', _MaintenanceTemplateType.fuel),
  _VehicleTemplateSeed('大众', '迈腾（燃油版）', _MaintenanceTemplateType.fuel),
  _VehicleTemplateSeed('大众', '探岳（燃油版）', _MaintenanceTemplateType.fuel),
  _VehicleTemplateSeed('大众', '朗逸（燃油版）', _MaintenanceTemplateType.fuel),
  _VehicleTemplateSeed('大众', '帕萨特（燃油版）', _MaintenanceTemplateType.fuel),
  _VehicleTemplateSeed('大众', '帕萨特（插混版）', _MaintenanceTemplateType.plugIn),
  _VehicleTemplateSeed('大众', '途观 L（燃油版）', _MaintenanceTemplateType.fuel),
  _VehicleTemplateSeed('大众', '途观 L（插混版）', _MaintenanceTemplateType.plugIn),
  _VehicleTemplateSeed('大众', '途昂（燃油版）', _MaintenanceTemplateType.fuel),
  _VehicleTemplateSeed('大众', 'ID.3（纯电版）', _MaintenanceTemplateType.ev),
  _VehicleTemplateSeed('大众', 'ID.4（纯电版）', _MaintenanceTemplateType.ev),
  _VehicleTemplateSeed('别克', 'GL8（燃油版）', _MaintenanceTemplateType.fuel),
  _VehicleTemplateSeed('别克', 'GL8（插混版）', _MaintenanceTemplateType.plugIn),
  _VehicleTemplateSeed('别克', 'GL8 新能源（插混版）', _MaintenanceTemplateType.plugIn),
  _VehicleTemplateSeed('别克', '昂科威（燃油版）', _MaintenanceTemplateType.fuel),
  _VehicleTemplateSeed('福特', '蒙迪欧（燃油版）', _MaintenanceTemplateType.fuel),
  _VehicleTemplateSeed('福特', '锐界 L（混动版）', _MaintenanceTemplateType.hybrid),
  _VehicleTemplateSeed('现代', '伊兰特（燃油版）', _MaintenanceTemplateType.fuel),
  _VehicleTemplateSeed('起亚', 'K3（燃油版）', _MaintenanceTemplateType.fuel),
  _VehicleTemplateSeed('起亚', '狮铂拓界（燃油版）', _MaintenanceTemplateType.fuel),
  _VehicleTemplateSeed('马自达', '昂克赛拉（燃油版）', _MaintenanceTemplateType.fuel),
  _VehicleTemplateSeed('马自达', 'CX-5（燃油版）', _MaintenanceTemplateType.fuel),
  _VehicleTemplateSeed('雪佛兰', '科鲁泽（燃油版）', _MaintenanceTemplateType.fuel),
  _VehicleTemplateSeed('比亚迪', '海鸥（纯电版）', _MaintenanceTemplateType.ev),
  _VehicleTemplateSeed('比亚迪', '海豚（纯电版）', _MaintenanceTemplateType.ev),
  _VehicleTemplateSeed('比亚迪', '秦 PLUS（插混版）', _MaintenanceTemplateType.plugIn),
  _VehicleTemplateSeed('比亚迪', '秦 PLUS（纯电版）', _MaintenanceTemplateType.ev),
  _VehicleTemplateSeed('比亚迪', '秦 L（插混版）', _MaintenanceTemplateType.plugIn),
  _VehicleTemplateSeed('比亚迪', '海豹 06（插混版）', _MaintenanceTemplateType.plugIn),
  _VehicleTemplateSeed('比亚迪', '汉（插混版）', _MaintenanceTemplateType.plugIn),
  _VehicleTemplateSeed('比亚迪', '汉（纯电版）', _MaintenanceTemplateType.ev),
  _VehicleTemplateSeed('比亚迪', '宋 PLUS（插混版）', _MaintenanceTemplateType.plugIn),
  _VehicleTemplateSeed('比亚迪', '宋 PLUS（纯电版）', _MaintenanceTemplateType.ev),
  _VehicleTemplateSeed('比亚迪', '宋 Pro（插混版）', _MaintenanceTemplateType.plugIn),
  _VehicleTemplateSeed('比亚迪', '元 UP（纯电版）', _MaintenanceTemplateType.ev),
  _VehicleTemplateSeed('比亚迪', '元 PLUS（纯电版）', _MaintenanceTemplateType.ev),
  _VehicleTemplateSeed('比亚迪', '唐（插混版）', _MaintenanceTemplateType.plugIn),
  _VehicleTemplateSeed('比亚迪', '海狮 06（插混版）', _MaintenanceTemplateType.plugIn),
  _VehicleTemplateSeed('比亚迪', '海狮 06（纯电版）', _MaintenanceTemplateType.ev),
  _VehicleTemplateSeed('比亚迪', '宋 L（插混版）', _MaintenanceTemplateType.plugIn),
  _VehicleTemplateSeed('比亚迪', '海豹 07（纯电版）', _MaintenanceTemplateType.ev),
  _VehicleTemplateSeed('腾势', 'D9（插混版）', _MaintenanceTemplateType.plugIn),
  _VehicleTemplateSeed('腾势', 'D9（纯电版）', _MaintenanceTemplateType.ev),
  _VehicleTemplateSeed('方程豹', '豹 5（插混版）', _MaintenanceTemplateType.plugIn),
  _VehicleTemplateSeed('吉利银河', '星愿（纯电版）', _MaintenanceTemplateType.ev),
  _VehicleTemplateSeed('吉利银河', 'L6（插混版）', _MaintenanceTemplateType.plugIn),
  _VehicleTemplateSeed('吉利银河', 'L7（插混版）', _MaintenanceTemplateType.plugIn),
  _VehicleTemplateSeed('吉利银河', 'E5（纯电版）', _MaintenanceTemplateType.ev),
  _VehicleTemplateSeed('吉利', '帝豪（燃油版）', _MaintenanceTemplateType.fuel),
  _VehicleTemplateSeed('吉利', '星瑞（燃油版）', _MaintenanceTemplateType.fuel),
  _VehicleTemplateSeed('吉利', '缤越（燃油版）', _MaintenanceTemplateType.fuel),
  _VehicleTemplateSeed('吉利', '博越 L（燃油版）', _MaintenanceTemplateType.fuel),
  _VehicleTemplateSeed('吉利', '星越 L（燃油版）', _MaintenanceTemplateType.fuel),
  _VehicleTemplateSeed('吉利', '星越 L（混动版）', _MaintenanceTemplateType.hybrid),
  _VehicleTemplateSeed('领克', '03（燃油版）', _MaintenanceTemplateType.fuel),
  _VehicleTemplateSeed('领克', '08（插混版）', _MaintenanceTemplateType.plugIn),
  _VehicleTemplateSeed('极氪', '001（纯电版）', _MaintenanceTemplateType.ev),
  _VehicleTemplateSeed('极氪', '007（纯电版）', _MaintenanceTemplateType.ev),
  _VehicleTemplateSeed('极氪', '7X（纯电版）', _MaintenanceTemplateType.ev),
  _VehicleTemplateSeed('奇瑞', '艾瑞泽 8（燃油版）', _MaintenanceTemplateType.fuel),
  _VehicleTemplateSeed('奇瑞', '瑞虎 7（燃油版）', _MaintenanceTemplateType.fuel),
  _VehicleTemplateSeed('奇瑞', '瑞虎 8（燃油版）', _MaintenanceTemplateType.fuel),
  _VehicleTemplateSeed('奇瑞', '瑞虎 9（燃油版）', _MaintenanceTemplateType.fuel),
  _VehicleTemplateSeed('奇瑞风云', 'A8（插混版）', _MaintenanceTemplateType.plugIn),
  _VehicleTemplateSeed('奇瑞风云', 'T9（插混版）', _MaintenanceTemplateType.plugIn),
  _VehicleTemplateSeed('捷途', 'X70（燃油版）', _MaintenanceTemplateType.fuel),
  _VehicleTemplateSeed('捷途', '旅行者（燃油版）', _MaintenanceTemplateType.fuel),
  _VehicleTemplateSeed('捷途山海', 'L7（插混版）', _MaintenanceTemplateType.plugIn),
  _VehicleTemplateSeed('星途', '瑶光（燃油版）', _MaintenanceTemplateType.fuel),
  _VehicleTemplateSeed('长安', '逸动（燃油版）', _MaintenanceTemplateType.fuel),
  _VehicleTemplateSeed('长安', 'CS75 PLUS（燃油版）', _MaintenanceTemplateType.fuel),
  _VehicleTemplateSeed('长安', 'UNI-V（燃油版）', _MaintenanceTemplateType.fuel),
  _VehicleTemplateSeed('长安', 'UNI-Z（插混版）', _MaintenanceTemplateType.plugIn),
  _VehicleTemplateSeed('长安启源', 'A05（插混版）', _MaintenanceTemplateType.plugIn),
  _VehicleTemplateSeed('长安启源', 'A07（插混版）', _MaintenanceTemplateType.plugIn),
  _VehicleTemplateSeed('长安启源', 'Q05（插混版）', _MaintenanceTemplateType.plugIn),
  _VehicleTemplateSeed('深蓝', 'S05（纯电版）', _MaintenanceTemplateType.ev),
  _VehicleTemplateSeed('深蓝', 'S07（增程版）', _MaintenanceTemplateType.plugIn),
  _VehicleTemplateSeed('深蓝', 'L07（增程版）', _MaintenanceTemplateType.plugIn),
  _VehicleTemplateSeed('深蓝', 'G318（增程版）', _MaintenanceTemplateType.plugIn),
  _VehicleTemplateSeed('阿维塔', '07（增程版）', _MaintenanceTemplateType.plugIn),
  _VehicleTemplateSeed('阿维塔', '11（纯电版）', _MaintenanceTemplateType.ev),
  _VehicleTemplateSeed('阿维塔', '12（纯电版）', _MaintenanceTemplateType.ev),
  _VehicleTemplateSeed('哈弗', 'H6（燃油版）', _MaintenanceTemplateType.fuel),
  _VehicleTemplateSeed('哈弗', 'H6（插混版）', _MaintenanceTemplateType.plugIn),
  _VehicleTemplateSeed('哈弗', '大狗（燃油版）', _MaintenanceTemplateType.fuel),
  _VehicleTemplateSeed('坦克', '300（燃油版）', _MaintenanceTemplateType.fuel),
  _VehicleTemplateSeed('坦克', '500（插混版）', _MaintenanceTemplateType.plugIn),
  _VehicleTemplateSeed('魏牌', '高山（插混版）', _MaintenanceTemplateType.plugIn),
  _VehicleTemplateSeed('五菱', '宏光 MINIEV（纯电版）', _MaintenanceTemplateType.ev),
  _VehicleTemplateSeed('五菱', '缤果（纯电版）', _MaintenanceTemplateType.ev),
  _VehicleTemplateSeed('五菱', '星光（插混版）', _MaintenanceTemplateType.plugIn),
  _VehicleTemplateSeed('五菱', '星光 730（插混版）', _MaintenanceTemplateType.plugIn),
  _VehicleTemplateSeed('宝骏', '云朵（纯电版）', _MaintenanceTemplateType.ev),
  _VehicleTemplateSeed('欧拉', '好猫（纯电版）', _MaintenanceTemplateType.ev),
  _VehicleTemplateSeed('红旗', 'H5（燃油版）', _MaintenanceTemplateType.fuel),
  _VehicleTemplateSeed('红旗', 'HS5（燃油版）', _MaintenanceTemplateType.fuel),
  _VehicleTemplateSeed('奔腾', 'B70（燃油版）', _MaintenanceTemplateType.fuel),
  _VehicleTemplateSeed('奔腾', 'T90（燃油版）', _MaintenanceTemplateType.fuel),
  _VehicleTemplateSeed('荣威', 'D7（插混版）', _MaintenanceTemplateType.plugIn),
  _VehicleTemplateSeed('荣威', 'RX5（燃油版）', _MaintenanceTemplateType.fuel),
  _VehicleTemplateSeed('MG', 'MG4（纯电版）', _MaintenanceTemplateType.ev),
  _VehicleTemplateSeed('MG', 'ZS（燃油版）', _MaintenanceTemplateType.fuel),
  _VehicleTemplateSeed('传祺', 'M8（燃油版）', _MaintenanceTemplateType.fuel),
  _VehicleTemplateSeed('传祺', 'E8（插混版）', _MaintenanceTemplateType.plugIn),
  _VehicleTemplateSeed('传祺', 'GS4（燃油版）', _MaintenanceTemplateType.fuel),
  _VehicleTemplateSeed('埃安', 'AION Y（纯电版）', _MaintenanceTemplateType.ev),
  _VehicleTemplateSeed('埃安', 'AION S（纯电版）', _MaintenanceTemplateType.ev),
  _VehicleTemplateSeed('埃安', 'AION V（纯电版）', _MaintenanceTemplateType.ev),
  _VehicleTemplateSeed('风神', '皓瀚（燃油版）', _MaintenanceTemplateType.fuel),
  _VehicleTemplateSeed('奕派', 'eπ007（增程版）', _MaintenanceTemplateType.plugIn),
  _VehicleTemplateSeed('岚图', '梦想家（插混版）', _MaintenanceTemplateType.plugIn),
  _VehicleTemplateSeed('岚图', '梦想家（纯电版）', _MaintenanceTemplateType.ev),
  _VehicleTemplateSeed('岚图', 'FREE（增程版）', _MaintenanceTemplateType.plugIn),
  _VehicleTemplateSeed('零跑', 'A10（纯电版）', _MaintenanceTemplateType.ev),
  _VehicleTemplateSeed('零跑', 'C10（纯电版）', _MaintenanceTemplateType.ev),
  _VehicleTemplateSeed('零跑', 'C10（增程版）', _MaintenanceTemplateType.plugIn),
  _VehicleTemplateSeed('零跑', 'C11（增程版）', _MaintenanceTemplateType.plugIn),
  _VehicleTemplateSeed('零跑', 'C16（增程版）', _MaintenanceTemplateType.plugIn),
  _VehicleTemplateSeed('理想', 'L6（增程版）', _MaintenanceTemplateType.plugIn),
  _VehicleTemplateSeed('理想', 'L7（增程版）', _MaintenanceTemplateType.plugIn),
  _VehicleTemplateSeed('理想', 'L8（增程版）', _MaintenanceTemplateType.plugIn),
  _VehicleTemplateSeed('理想', 'i6（纯电版）', _MaintenanceTemplateType.ev),
  _VehicleTemplateSeed('蔚来', 'ES6（纯电版）', _MaintenanceTemplateType.ev),
  _VehicleTemplateSeed('蔚来', 'ES8（纯电版）', _MaintenanceTemplateType.ev),
  _VehicleTemplateSeed('蔚来', 'ET5（纯电版）', _MaintenanceTemplateType.ev),
  _VehicleTemplateSeed('乐道', 'L60（纯电版）', _MaintenanceTemplateType.ev),
  _VehicleTemplateSeed('小鹏', 'MONA M03（纯电版）', _MaintenanceTemplateType.ev),
  _VehicleTemplateSeed('小鹏', 'P7（纯电版）', _MaintenanceTemplateType.ev),
  _VehicleTemplateSeed('小鹏', 'G6（纯电版）', _MaintenanceTemplateType.ev),
  _VehicleTemplateSeed('小鹏', 'X9（纯电版）', _MaintenanceTemplateType.ev),
  _VehicleTemplateSeed('小米', 'SU7（纯电版）', _MaintenanceTemplateType.ev),
  _VehicleTemplateSeed('小米', 'YU7（纯电版）', _MaintenanceTemplateType.ev),
  _VehicleTemplateSeed('智己', 'L6（纯电版）', _MaintenanceTemplateType.ev),
  _VehicleTemplateSeed('智己', 'LS6（纯电版）', _MaintenanceTemplateType.ev),
  _VehicleTemplateSeed('问界', 'M8（增程版）', _MaintenanceTemplateType.plugIn),
  _VehicleTemplateSeed('问界', 'M8（纯电版）', _MaintenanceTemplateType.ev),
  _VehicleTemplateSeed('问界', 'M9（增程版）', _MaintenanceTemplateType.plugIn),
  _VehicleTemplateSeed('智界', 'R7（纯电版）', _MaintenanceTemplateType.ev),
  _VehicleTemplateSeed('享界', 'S9（纯电版）', _MaintenanceTemplateType.ev),
  _VehicleTemplateSeed('极狐', '阿尔法 T5（纯电版）', _MaintenanceTemplateType.ev),
  _VehicleTemplateSeed('昊铂', 'HT（纯电版）', _MaintenanceTemplateType.ev),
  _VehicleTemplateSeed('昊铂', 'GT（纯电版）', _MaintenanceTemplateType.ev),
  _VehicleTemplateSeed('iCAR', '03（纯电版）', _MaintenanceTemplateType.ev),
  _VehicleTemplateSeed('特斯拉', 'Model 3（纯电版）', _MaintenanceTemplateType.ev),
  _VehicleTemplateSeed('特斯拉', 'Model Y（纯电版）', _MaintenanceTemplateType.ev),
  _VehicleTemplateSeed('宝马', '3 系（燃油版）', _MaintenanceTemplateType.fuel),
  _VehicleTemplateSeed('宝马', '5 系（燃油版）', _MaintenanceTemplateType.fuel),
  _VehicleTemplateSeed('宝马', 'X3（燃油版）', _MaintenanceTemplateType.fuel),
  _VehicleTemplateSeed('宝马', 'i3（纯电版）', _MaintenanceTemplateType.ev),
  _VehicleTemplateSeed('奔驰', 'C 级（燃油版）', _MaintenanceTemplateType.fuel),
  _VehicleTemplateSeed('奔驰', 'E 级（燃油版）', _MaintenanceTemplateType.fuel),
  _VehicleTemplateSeed('奔驰', 'GLC（燃油版）', _MaintenanceTemplateType.fuel),
  _VehicleTemplateSeed('奥迪', 'A4L（燃油版）', _MaintenanceTemplateType.fuel),
  _VehicleTemplateSeed('奥迪', 'A6L（燃油版）', _MaintenanceTemplateType.fuel),
  _VehicleTemplateSeed('奥迪', 'Q5L（燃油版）', _MaintenanceTemplateType.fuel),
  _VehicleTemplateSeed('凯迪拉克', 'CT5（燃油版）', _MaintenanceTemplateType.fuel),
  _VehicleTemplateSeed('沃尔沃', 'XC60（燃油版）', _MaintenanceTemplateType.fuel),
  _VehicleTemplateSeed('雷克萨斯', 'ES（混动版）', _MaintenanceTemplateType.hybrid),
  _VehicleTemplateSeed('林肯', '航海家（燃油版）', _MaintenanceTemplateType.fuel),
  _VehicleTemplateSeed('MINI', 'Cooper（纯电版）', _MaintenanceTemplateType.ev),
  _VehicleTemplateSeed('保时捷', 'Macan（纯电版）', _MaintenanceTemplateType.ev),
  _VehicleTemplateSeed('保时捷', 'Cayenne（燃油版）', _MaintenanceTemplateType.fuel),
  _VehicleTemplateSeed('路虎', '发现运动版（燃油版）', _MaintenanceTemplateType.fuel),
];
