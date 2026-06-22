import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

@DataClassName('CarRow')
class Cars extends Table {
  IntColumn get id => integer()();
  TextColumn get brand => text()();
  TextColumn get model => text()();
  IntColumn get currentMileageKm => integer()();
  TextColumn get roadDate => text()();
  TextColumn get syncStatus => text().withDefault(const Constant('synced'))();
  TextColumn get updatedAt => text()();
  IntColumn get version => integer().withDefault(const Constant(1))();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {brand, model, roadDate},
  ];
}

@DataClassName('VehicleDefaultMaintenanceItemRow')
class VehicleDefaultMaintenanceItems extends Table {
  IntColumn get id => integer()();
  TextColumn get catalogId => text().nullable()();
  TextColumn get vehicleBrand => text()();
  TextColumn get vehicleModel => text()();
  TextColumn get itemName => text()();
  BoolColumn get remindByMileage => boolean()();
  BoolColumn get remindByTime => boolean()();
  IntColumn get mileageIntervalKm => integer().nullable()();
  IntColumn get timeIntervalMonths => integer().nullable()();
  RealColumn get notOverdueUpperLimit =>
      real().withDefault(const Constant(100))();
  RealColumn get overdueUpperLimit => real().withDefault(const Constant(125))();
  IntColumn get sortOrder => integer()();
  TextColumn get syncStatus => text().withDefault(const Constant('synced'))();
  TextColumn get updatedAt => text()();
  IntColumn get version => integer().withDefault(const Constant(1))();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {catalogId},
    {vehicleBrand, vehicleModel, itemName},
  ];
}

@DataClassName('VehicleModelRow')
class VehicleModels extends Table {
  IntColumn get id => integer()();
  TextColumn get catalogId => text().nullable()();
  TextColumn get brand => text()();
  TextColumn get model => text()();
  IntColumn get sortOrder => integer()();
  TextColumn get syncStatus => text().withDefault(const Constant('synced'))();
  TextColumn get updatedAt => text()();
  IntColumn get version => integer().withDefault(const Constant(1))();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {catalogId},
    {brand, model},
  ];
}

@DataClassName('MaintenanceItemRow')
class MaintenanceItems extends Table {
  IntColumn get id => integer()();
  IntColumn get carsId => integer()();
  TextColumn get name => text()();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  BoolColumn get remindByMileage => boolean()();
  BoolColumn get remindByTime => boolean()();
  IntColumn get mileageIntervalKm => integer().nullable()();
  IntColumn get timeIntervalMonths => integer().nullable()();
  RealColumn get notOverdueUpperLimit =>
      real().withDefault(const Constant(100))();
  RealColumn get overdueUpperLimit => real().withDefault(const Constant(125))();
  IntColumn get sortOrder => integer()();
  TextColumn get syncStatus => text().withDefault(const Constant('synced'))();
  TextColumn get updatedAt => text()();
  IntColumn get version => integer().withDefault(const Constant(1))();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {carsId, name},
  ];
}

@DataClassName('MaintenanceRecordRow')
class MaintenanceRecords extends Table {
  IntColumn get id => integer()();
  IntColumn get carId => integer()();
  TextColumn get date => text()();
  IntColumn get mileageKm => integer()();
  IntColumn get costCents => integer()();
  TextColumn get note => text().nullable()();
  TextColumn get syncStatus => text().withDefault(const Constant('synced'))();
  TextColumn get updatedAt => text()();
  IntColumn get version => integer().withDefault(const Constant(1))();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {carId, date},
  ];
}

@DataClassName('MaintenanceRecordItemRow')
class MaintenanceRecordItems extends Table {
  IntColumn get id => integer()();
  IntColumn get maintenanceRecordId => integer()();
  IntColumn get carId => integer()();
  IntColumn get itemId => integer()();
  TextColumn get date => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {carId, date, itemId},
  ];
}

@DataClassName('AppPreferenceRow')
class AppPreferences extends Table {
  IntColumn get id => integer()();
  TextColumn get key => text()();
  TextColumn get value => text().nullable()();
  TextColumn get syncStatus => text().withDefault(const Constant('synced'))();
  TextColumn get updatedAt => text()();
  IntColumn get version => integer().withDefault(const Constant(1))();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {key},
  ];
}

@DriftDatabase(
  tables: [
    Cars,
    VehicleDefaultMaintenanceItems,
    VehicleModels,
    MaintenanceItems,
    MaintenanceRecords,
    MaintenanceRecordItems,
    AppPreferences,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.inMemory() : super(NativeDatabase.memory());

  @override
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onUpgrade: (migrator, from, to) async {
        if (from < 2) {
          for (final table in allTables) {
            await migrator.deleteTable(table.actualTableName);
          }
          await migrator.createAll();
        } else {
          if (from < 3) {
            await migrator.alterTable(TableMigration(maintenanceItems));
          }
          if (from < 4) {
            await migrator.alterTable(TableMigration(cars));
          }
          if (from < 5) {
            await migrator.addColumn(vehicleModels, vehicleModels.catalogId);
            await migrator.addColumn(
              vehicleDefaultMaintenanceItems,
              vehicleDefaultMaintenanceItems.catalogId,
            );
            await customStatement(
              'CREATE UNIQUE INDEX IF NOT EXISTS '
              'vehicle_models_catalog_id_unique '
              'ON vehicle_models (catalog_id) WHERE catalog_id IS NOT NULL',
            );
            await customStatement(
              'CREATE UNIQUE INDEX IF NOT EXISTS '
              'vehicle_default_maintenance_items_catalog_id_unique '
              'ON vehicle_default_maintenance_items (catalog_id) '
              'WHERE catalog_id IS NOT NULL',
            );
          }
        }
      },
    );
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File(p.join(directory.path, 'lunio.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
