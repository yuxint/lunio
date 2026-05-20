import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

@DataClassName('CarRow')
class Cars extends Table {
  TextColumn get id => text()();
  TextColumn get brand => text()();
  TextColumn get model => text()();
  TextColumn get brandModelKey => text().unique()();
  IntColumn get currentMileageKm => integer()();
  TextColumn get roadDate => text()();
  TextColumn get syncStatus => text().withDefault(const Constant('synced'))();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  IntColumn get version => integer().withDefault(const Constant(1))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('MaintenanceItemRow')
class MaintenanceItems extends Table {
  TextColumn get id => text()();
  TextColumn get ownerCarId => text()();
  TextColumn get name => text()();
  BoolColumn get isDefault => boolean()();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  TextColumn get catalogKey => text().nullable()();
  BoolColumn get remindByMileage => boolean()();
  BoolColumn get remindByTime => boolean()();
  IntColumn get mileageIntervalKm => integer().nullable()();
  IntColumn get timeIntervalMonths => integer().nullable()();
  IntColumn get warningThresholdPercent =>
      integer().withDefault(const Constant(100))();
  IntColumn get dangerThresholdPercent =>
      integer().withDefault(const Constant(125))();
  IntColumn get sortOrder => integer()();
  TextColumn get syncStatus => text().withDefault(const Constant('synced'))();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  IntColumn get version => integer().withDefault(const Constant(1))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('MaintenanceRecordRow')
class MaintenanceRecords extends Table {
  TextColumn get id => text()();
  TextColumn get carId => text()();
  TextColumn get date => text()();
  TextColumn get cycleKey => text().unique()();
  IntColumn get mileageKm => integer()();
  IntColumn get costCents => integer()();
  TextColumn get note => text().nullable()();
  TextColumn get syncStatus => text().withDefault(const Constant('synced'))();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  IntColumn get version => integer().withDefault(const Constant(1))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('MaintenanceRecordItemRow')
class MaintenanceRecordItems extends Table {
  TextColumn get id => text()();
  TextColumn get recordId => text()();
  TextColumn get carId => text()();
  TextColumn get itemId => text()();
  TextColumn get date => text()();
  TextColumn get cycleItemKey => text().unique()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('AppPreferenceRow')
class AppPreferences extends Table {
  TextColumn get key => text()();
  TextColumn get value => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

@DriftDatabase(
  tables: [
    Cars,
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
  int get schemaVersion => 1;
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File(p.join(directory.path, 'lunio.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
