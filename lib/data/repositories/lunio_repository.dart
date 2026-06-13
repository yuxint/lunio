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
    final sync = SyncMetadata(
      status: SyncStatus.synced,
      updatedAt: DateTime.now(),
    );
    final builtInItems = _builtInDefaultItems(sync);
    for (final entry in _authoritativeDefaultModels.entries) {
      final items = builtInItems
          .where(
            (item) =>
                item.vehicleBrand == entry.key.$1 &&
                item.vehicleModel == entry.key.$2,
          )
          .toList();
      if (items.isEmpty) {
        continue;
      }
      final rows =
          await (database.select(database.vehicleDefaultMaintenanceItems)
                ..where(
                  (row) =>
                      row.vehicleBrand.equals(entry.key.$1) &
                      row.vehicleModel.equals(entry.key.$2),
                ))
              .get();
      if (!_defaultItemsMatch(rows, items)) {
        await (database.delete(database.vehicleDefaultMaintenanceItems)..where(
              (row) =>
                  row.vehicleBrand.equals(entry.key.$1) &
                  row.vehicleModel.equals(entry.key.$2),
            ))
            .go();
        for (final item in items) {
          await saveVehicleDefaultMaintenanceItem(item);
        }
      }
    }

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

  static int _nextId() => _idGenerator.next();

  static const _authoritativeDefaultModels = {
    ('东风本田', '思域'): true,
    ('东风日产', '轩逸'): true,
  };

  bool _defaultItemsMatch(
    List<VehicleDefaultMaintenanceItemRow> rows,
    List<domain.VehicleDefaultMaintenanceItem> items,
  ) {
    if (rows.length != items.length) {
      return false;
    }
    final rowsByName = {for (final row in rows) row.itemName: row};
    for (final item in items) {
      final row = rowsByName[item.itemName];
      if (row == null ||
          row.remindByMileage != item.remindByMileage ||
          row.remindByTime != item.remindByTime ||
          row.mileageIntervalKm != item.mileageIntervalKm ||
          row.timeIntervalMonths != item.timeIntervalMonths ||
          row.notOverdueUpperLimit != item.notOverdueUpperLimit ||
          row.overdueUpperLimit != item.overdueUpperLimit ||
          row.sortOrder != item.sortOrder) {
        return false;
      }
    }
    return true;
  }

  List<domain.VehicleDefaultMaintenanceItem> _builtInDefaultItems(
    SyncMetadata sync,
  ) {
    return [
      domain.VehicleDefaultMaintenanceItem(
        vehicleBrand: '东风本田',
        vehicleModel: '思域',
        itemName: '燃油宝',
        remindByMileage: true,
        remindByTime: false,
        mileageIntervalKm: 5000,
        sortOrder: 1,
        sync: sync,
      ),
      domain.VehicleDefaultMaintenanceItem(
        vehicleBrand: '东风本田',
        vehicleModel: '思域',
        itemName: '机油',
        remindByMileage: true,
        remindByTime: true,
        mileageIntervalKm: 5000,
        timeIntervalMonths: 6,
        sortOrder: 2,
        sync: sync,
      ),
      domain.VehicleDefaultMaintenanceItem(
        vehicleBrand: '东风本田',
        vehicleModel: '思域',
        itemName: '机滤',
        remindByMileage: true,
        remindByTime: true,
        mileageIntervalKm: 5000,
        timeIntervalMonths: 6,
        sortOrder: 3,
        sync: sync,
      ),
      domain.VehicleDefaultMaintenanceItem(
        vehicleBrand: '东风本田',
        vehicleModel: '思域',
        itemName: '空调滤芯',
        remindByMileage: true,
        remindByTime: true,
        mileageIntervalKm: 20000,
        timeIntervalMonths: 12,
        sortOrder: 4,
        sync: sync,
      ),
      domain.VehicleDefaultMaintenanceItem(
        vehicleBrand: '东风本田',
        vehicleModel: '思域',
        itemName: '空气滤芯',
        remindByMileage: true,
        remindByTime: false,
        mileageIntervalKm: 20000,
        sortOrder: 5,
        sync: sync,
      ),
      domain.VehicleDefaultMaintenanceItem(
        vehicleBrand: '东风本田',
        vehicleModel: '思域',
        itemName: '变速箱油',
        remindByMileage: true,
        remindByTime: true,
        mileageIntervalKm: 40000,
        timeIntervalMonths: 24,
        sortOrder: 6,
        sync: sync,
      ),
      domain.VehicleDefaultMaintenanceItem(
        vehicleBrand: '东风本田',
        vehicleModel: '思域',
        itemName: '刹车油',
        remindByMileage: false,
        remindByTime: true,
        timeIntervalMonths: 36,
        sortOrder: 7,
        sync: sync,
      ),
      domain.VehicleDefaultMaintenanceItem(
        vehicleBrand: '东风本田',
        vehicleModel: '思域',
        itemName: '火花塞',
        remindByMileage: true,
        remindByTime: false,
        mileageIntervalKm: 100000,
        sortOrder: 8,
        sync: sync,
      ),
      domain.VehicleDefaultMaintenanceItem(
        vehicleBrand: '东风本田',
        vehicleModel: '思域',
        itemName: '检查传动皮带',
        remindByMileage: true,
        remindByTime: true,
        mileageIntervalKm: 40000,
        timeIntervalMonths: 24,
        sortOrder: 9,
        sync: sync,
      ),
      domain.VehicleDefaultMaintenanceItem(
        vehicleBrand: '东风本田',
        vehicleModel: '思域',
        itemName: '检查气门间隙',
        remindByMileage: true,
        remindByTime: false,
        mileageIntervalKm: 120000,
        sortOrder: 10,
        sync: sync,
      ),
      domain.VehicleDefaultMaintenanceItem(
        vehicleBrand: '东风本田',
        vehicleModel: '思域',
        itemName: '检查刹车',
        remindByMileage: true,
        remindByTime: false,
        mileageIntervalKm: 120000,
        sortOrder: 11,
        sync: sync,
      ),
      domain.VehicleDefaultMaintenanceItem(
        vehicleBrand: '东风本田',
        vehicleModel: '思域',
        itemName: '防冻液',
        remindByMileage: true,
        remindByTime: true,
        mileageIntervalKm: 200000,
        timeIntervalMonths: 120,
        sortOrder: 12,
        sync: sync,
      ),
      domain.VehicleDefaultMaintenanceItem(
        vehicleBrand: '东风本田',
        vehicleModel: '思域',
        itemName: '汽油滤芯',
        remindByMileage: true,
        remindByTime: false,
        mileageIntervalKm: 140000,
        sortOrder: 13,
        sync: sync,
      ),
      domain.VehicleDefaultMaintenanceItem(
        vehicleBrand: '东风本田',
        vehicleModel: '思域',
        itemName: '轮胎换位',
        remindByMileage: true,
        remindByTime: false,
        mileageIntervalKm: 10000,
        sortOrder: 14,
        sync: sync,
      ),
      domain.VehicleDefaultMaintenanceItem(
        vehicleBrand: '东风日产',
        vehicleModel: '轩逸',
        itemName: '机油',
        remindByMileage: true,
        remindByTime: true,
        mileageIntervalKm: 10000,
        timeIntervalMonths: 6,
        sortOrder: 1,
        sync: sync,
      ),
      domain.VehicleDefaultMaintenanceItem(
        vehicleBrand: '东风日产',
        vehicleModel: '轩逸',
        itemName: '空调滤芯',
        remindByMileage: true,
        remindByTime: true,
        mileageIntervalKm: 20000,
        timeIntervalMonths: 12,
        sortOrder: 2,
        sync: sync,
      ),
      domain.VehicleDefaultMaintenanceItem(
        vehicleBrand: '东风日产',
        vehicleModel: '轩逸',
        itemName: '空气滤芯',
        remindByMileage: true,
        remindByTime: false,
        mileageIntervalKm: 20000,
        sortOrder: 3,
        sync: sync,
      ),
      domain.VehicleDefaultMaintenanceItem(
        vehicleBrand: '东风日产',
        vehicleModel: '轩逸',
        itemName: '变速箱油',
        remindByMileage: false,
        remindByTime: true,
        timeIntervalMonths: 24,
        sortOrder: 4,
        sync: sync,
      ),
      domain.VehicleDefaultMaintenanceItem(
        vehicleBrand: '东风日产',
        vehicleModel: '轩逸',
        itemName: '刹车油',
        remindByMileage: false,
        remindByTime: true,
        timeIntervalMonths: 36,
        sortOrder: 5,
        sync: sync,
      ),
      domain.VehicleDefaultMaintenanceItem(
        vehicleBrand: '一汽丰田',
        vehicleModel: '卡罗拉',
        itemName: '机油',
        remindByMileage: true,
        remindByTime: true,
        mileageIntervalKm: 10000,
        timeIntervalMonths: 6,
        sortOrder: 1,
        sync: sync,
      ),
      domain.VehicleDefaultMaintenanceItem(
        vehicleBrand: '一汽丰田',
        vehicleModel: '卡罗拉',
        itemName: '机滤',
        remindByMileage: true,
        remindByTime: true,
        mileageIntervalKm: 10000,
        timeIntervalMonths: 6,
        sortOrder: 2,
        sync: sync,
      ),
    ];
  }

  List<domain.VehicleModel> _builtInVehicleModels(SyncMetadata sync) {
    return [
      domain.VehicleModel(brand: '东风本田', model: '思域', sortOrder: 1, sync: sync),
      domain.VehicleModel(brand: '东风日产', model: '轩逸', sortOrder: 2, sync: sync),
      domain.VehicleModel(
        brand: '一汽丰田',
        model: '卡罗拉',
        sortOrder: 3,
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
