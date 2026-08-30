// 数据库定义：Drift 表结构 + 迁移策略 + 连接方式。
//
// Drift ≈ Java 世界的 MyBatis-Generator/JPA：用 Dart 类声明表，
// build_runner 生成 app_database.g.dart 里的类型安全查询代码
// （那个文件是生成物，不要手改；表结构变更后跑 dart run build_runner build）。
//
// 通用约定（7 张表一致）：
//  - 主键 id 手工填 Snowflake 雪花 id（见 core/id/），不用自增；
//  - 每张业务表都带 syncStatus/updatedAt/version 三列（云同步预留）；
//  - 没有声明 FOREIGN KEY 外键——表间关联靠应用层维护
//    （删除车辆时由 Repository 在事务里手工级联删除）。
//
// ⚠ 唯一约束是重要的业务边界（改字段前先看 docs/migration/）：
//  - cars:                {brand, model, roadDate}
//  - vehicleModels:       {catalogId}, {brand, model}
//  - defaultItems:        {catalogId}, {brand, model, itemName}
//  - maintenanceItems:    {carsId, name}
//  - maintenanceRecords:  {carId, date}          ← 一辆车一天只能一条记录
//  - recordItems:         {carId, date, itemId}
//  - appPreferences:      {key}
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

// part：把生成的 app_database.g.dart 并入本库（≈ Java 一个类拆多文件）。
part 'app_database.g.dart';

// ---------------------------- 表定义 ----------------------------

/// 车辆表。roadDate/syncStatus/updatedAt 以文本存储（yyyy-MM-dd / ISO 时间）。
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

/// 内置默认保养项目模板表（目录数据，首启从 asset 灌入，按 catalogId 对账）。
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

/// 内置车型目录表（约 190 个车型，添加车辆向导的选择器数据源）。
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

/// 车辆保养项目表（每辆车一套，从模板复制而来，用户可编辑）。
/// carsId 普通索引：提醒页/记录页按车查项目是高频路径（原全表扫描，R16）。
@TableIndex(name: 'idx_maintenance_items_cars_id', columns: {#carsId})
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

/// 保养记录主表。
/// carId 普通索引：记录页按车全量拉取记录走它（原全表扫描，R16）。
@TableIndex(name: 'idx_maintenance_records_car_id', columns: {#carId})
/// 唯一约束 {carId, date}：一辆车一天只有一条记录（R4 收紧后与业务层
/// "同日一条"校验口径一致，见审查报告 R4）。
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

/// 记录-项目关联表（一条记录可挂多个项目）。
/// 冗余存了 carId/date（与主表同值），方便按车按天查询。
/// maintenanceRecordId 普通索引：组装记录 itemIds 时按记录 id 批量查
/// （原全表扫描，R16）。
@TableIndex(
  name: 'idx_maintenance_record_items_record_id',
  columns: {#maintenanceRecordId},
)
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

/// 偏好 KV 表：主题、应用车辆、通知设置、手动日期、停车倒计时、
/// snooze/ack 记录等都存这里（key 文案见 AGENTS.md 的"重要偏好 key"）。
/// value 可为 null（等价"删除该 key"）。
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

// ---------------------------- 数据库与迁移 ----------------------------

/// App 数据库。列出全部表后由 Drift 生成类型安全的 API
/// （database.cars / database.select(...) 等）。
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
  /// 生产构造：连接本地 SQLite 文件（惰性打开，见 [_openConnection]）。
  AppDatabase() : super(_openConnection());

  /// 测试构造：内存库（每个测试用例独立、不落盘）。
  AppDatabase.inMemory() : super(NativeDatabase.memory());

  /// ⚠ 数据库结构版本（≠ 备份 JSON 的 schemaVersion=2，两者独立演进）。
  /// 改表结构必须 +1 并补 onUpgrade 分支，再跑 build_runner。
  @override
  int get schemaVersion => 6;

  /// 迁移策略：老库升级到当前版本的路径（全新安装走 createAll，不经过这里）。
  ///
  /// ⚠ from < 2 是破坏性迁移：删光全部表重建，v1 用户的旧数据会丢失。
  /// v2→v3：maintenanceItems 表结构重建（TableMigration 会按新定义
  ///        建临时表-拷贝-换名，≈"在线改表"）。
  /// v3→v4：cars 表同样重建。
  /// v4→v5：两张目录表加 catalogId 列，并补建"部分唯一索引"
  ///        （WHERE catalog_id IS NOT NULL——SQLite 里可空列的 UNIQUE
  ///        约束允许多个 NULL，部分索引与建表约束语义等价）。
  /// v5→v6：三张业务表（items/records/recordItems）补普通索引，
  ///        升级库用 createIndex 建独立索引对象，与全新安装时
  ///        建表附带的表内索引两种形态语义等价（R19）。
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
          if (from < 6) {
            // v5→v6：三张业务表补普通索引（R16）。drift 会为 @TableIndex
            // 生成同名 getter，建表约束与迁移索引两种形态等价（R19）。
            await migrator.createIndex(idxMaintenanceItemsCarsId);
            await migrator.createIndex(idxMaintenanceRecordsCarId);
            await migrator.createIndex(idxMaintenanceRecordItemsRecordId);
          }
        }
      },
    );
  }
}

/// 惰性连接：只有第一条 SQL 真正执行时才打开数据库文件。
/// createInBackground 把 SQLite 运行在后台 isolate（≈ 后台线程），
/// 避免大查询阻塞 UI 线程。库文件位于应用文档目录 lunio.sqlite。
LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File(p.join(directory.path, 'lunio.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
