import 'package:drift/drift.dart';

import '../../core/date/local_date.dart';
import '../../domain/entities/car.dart' as domain;
import '../../domain/entities/maintenance_item.dart' as domain;
import '../../domain/entities/maintenance_record.dart' as domain;
import '../../domain/entities/sync_metadata.dart';
import '../../domain/rules/record_rules.dart';
import '../database/app_database.dart';

class LunioRepository {
  const LunioRepository(this.database);

  final AppDatabase database;

  Future<void> createCar(domain.Car car) {
    return database
        .into(database.cars)
        .insert(
          CarsCompanion.insert(
            id: car.id,
            brand: car.brand,
            model: car.model,
            brandModelKey: car.brandModelKey,
            currentMileageKm: car.currentMileageKm,
            roadDate: car.roadDate.toString(),
            syncStatus: Value(car.sync.status.name),
            updatedAt: car.sync.updatedAt,
            deletedAt: Value(car.sync.deletedAt),
            version: Value(car.sync.version),
          ),
        );
  }

  Future<List<domain.Car>> listCars() async {
    final rows = await database.select(database.cars).get();
    return rows.map(_carFromRow).toList();
  }

  Future<void> deleteCar(String carId) {
    return database.transaction(() async {
      await (database.delete(
        database.maintenanceRecordItems,
      )..where((row) => row.carId.equals(carId))).go();
      await (database.delete(
        database.maintenanceRecords,
      )..where((row) => row.carId.equals(carId))).go();
      await (database.delete(
        database.maintenanceItems,
      )..where((row) => row.ownerCarId.equals(carId))).go();
      await (database.delete(
        database.cars,
      )..where((row) => row.id.equals(carId))).go();
    });
  }

  Future<void> saveMaintenanceItem(domain.MaintenanceItem item) {
    item.validate();
    return database
        .into(database.maintenanceItems)
        .insert(
          MaintenanceItemsCompanion.insert(
            id: item.id,
            ownerCarId: item.ownerCarId,
            name: item.name,
            isDefault: item.isDefault,
            enabled: Value(item.enabled),
            catalogKey: Value(item.catalogKey),
            remindByMileage: item.remindByMileage,
            remindByTime: item.remindByTime,
            mileageIntervalKm: Value(item.mileageIntervalKm),
            timeIntervalMonths: Value(item.timeIntervalMonths),
            warningThresholdPercent: Value(item.warningThresholdPercent),
            dangerThresholdPercent: Value(item.dangerThresholdPercent),
            sortOrder: item.sortOrder,
            syncStatus: Value(item.sync.status.name),
            updatedAt: item.sync.updatedAt,
            deletedAt: Value(item.sync.deletedAt),
            version: Value(item.sync.version),
          ),
        );
  }

  Future<void> saveMaintenanceRecord(domain.MaintenanceRecord record) {
    RecordRules.validateRecord(record);
    final uniqueItemIds = RecordRules.uniqueItemIds(record.itemIds);

    return database.transaction(() async {
      await database
          .into(database.maintenanceRecords)
          .insert(
            MaintenanceRecordsCompanion.insert(
              id: record.id,
              carId: record.carId,
              date: record.date.toString(),
              cycleKey: record.cycleKey,
              mileageKm: record.mileageKm,
              costCents: record.costCents,
              note: Value(record.note),
              syncStatus: Value(record.sync.status.name),
              updatedAt: record.sync.updatedAt,
              deletedAt: Value(record.sync.deletedAt),
              version: Value(record.sync.version),
            ),
          );

      for (final itemId in uniqueItemIds) {
        final key = RecordRules.cycleItemKey(
          carId: record.carId,
          date: record.date.toString(),
          itemId: itemId,
        );
        await database
            .into(database.maintenanceRecordItems)
            .insert(
              MaintenanceRecordItemsCompanion.insert(
                id: '${record.id}::$itemId',
                recordId: record.id,
                carId: record.carId,
                itemId: itemId,
                date: record.date.toString(),
                cycleItemKey: key,
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
    });
  }

  Future<String?> getAppliedCarId() async {
    final row = await (database.select(
      database.appPreferences,
    )..where((pref) => pref.key.equals('appliedCarId'))).getSingleOrNull();
    return row?.value;
  }

  Future<void> setAppliedCarId(String? carId) {
    return database
        .into(database.appPreferences)
        .insertOnConflictUpdate(
          AppPreferencesCompanion.insert(
            key: 'appliedCarId',
            value: Value(carId),
          ),
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
        updatedAt: row.updatedAt,
        deletedAt: row.deletedAt,
        version: row.version,
      ),
    );
  }
}
