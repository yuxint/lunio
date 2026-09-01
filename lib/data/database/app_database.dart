// 数据库定义：Drift 表结构 + 迁移策略 + 连接方式。
//
// Drift ≈ Java 世界的 MyBatis-Generator/JPA：用 Dart 类声明表，
// build_runner 生成 app_database.g.dart 里的类型安全查询代码
// （那个文件是生成物，不要手改；表结构变更后跑 dart run build_runner build）。
//
// 通用约定（8 张表一致）：
//  - 主键 id 手工填 Snowflake 雪花 id（见 core/id/），不用自增；
//  - 每张业务表都带 syncStatus/updatedAt/version 三列（云同步预留）；
//  - 没有声明 FOREIGN KEY 外键——表间关联靠应用层维护
//    （删除车辆时由 Repository 在事务里手工级联删除）。
//
// ⚠ 唯一约束是重要的业务边界（改字段前先看 docs/migration/）：
//  - cars:                {brand, model, roadDate}
//  - vehicleModels:       {catalogId}, {brand, model}
//  - defaultItems:        {catalogId}, {powertrainType, itemName}
//  - maintenanceItems:    {carsId, name}
//  - maintenanceRecords:  {carId, date}          ← 一辆车一天只能一条记录
//  - recordItems:         {carId, date, itemId}
//  - appPreferences:      {key}
//  - fuelPredictions:     {carId}                ← 一辆车一份加油预测设置
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

// part：把生成的 app_database.g.dart 并入本库（≈ Java 一个类拆多文件）。
part 'app_database.g.dart';

// ---------------------------- 表定义 ----------------------------

/// 车辆表。roadDate/syncStatus/updatedAt 以文本存储（yyyy-MM-dd / ISO 时间）。
/// tankCapacityLiters：油箱容积（升），车的属性，添加/编辑车辆时填写，
/// 可空（非必填）；加油预估用它算加满金额（v8 起从 fuel_predictions 迁来）。
/// powertrainType：动力类型（v9 起，ADR 0003），添加车辆时用户选择、
/// 添加后不可改；老库迁移与 v3 备份导入一律默认 'fuel'。
@DataClassName('CarRow')
class Cars extends Table {
  IntColumn get id => integer()();
  TextColumn get brand => text()();
  TextColumn get model => text()();
  TextColumn get powertrainType =>
      text().withDefault(const Constant('fuel'))();
  IntColumn get currentMileageKm => integer()();
  TextColumn get roadDate => text()();
  RealColumn get tankCapacityLiters => real().nullable()();
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
/// v9 起按动力类型分组（每动力一组，共五组约 50 行），不再按品牌+车型
/// 逐条展开（ADR 0003）。
@DataClassName('VehicleDefaultMaintenanceItemRow')
class VehicleDefaultMaintenanceItems extends Table {
  IntColumn get id => integer()();
  TextColumn get catalogId => text().nullable()();
  TextColumn get powertrainType =>
      text().withDefault(const Constant('fuel'))();
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
    {powertrainType, itemName},
  ];
}

/// 内置车型目录表（2026-09-01 起精简为每品牌最多 10 款热门车型，共约 1220 条，
/// 添加车辆向导的选择器数据源）。
/// template：推荐动力类型 wire 值（添加向导预选动力 chip 用，v9 起）。
@DataClassName('VehicleModelRow')
class VehicleModels extends Table {
  IntColumn get id => integer()();
  TextColumn get catalogId => text().nullable()();
  TextColumn get brand => text()();
  TextColumn get model => text()();
  TextColumn get template => text().withDefault(const Constant('fuel'))();
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
/// 油价缓存、手填油价、snooze/ack 记录等都存这里
/// （key 文案见 AGENTS.md 的"重要偏好 key"）。
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

/// 加油预测设置表（按车辆一条）：剩余油量（= 加满预估的基准档）。
/// 唯一约束 {carId}：一辆车只有一份加油预测设置；
/// 删除车辆时由 Repository 在事务里级联删除。
/// v8 起容积挪到 cars 表（车的属性），本表只剩剩余油量；
/// 没有行的车按默认 50% 展示（首次滚动定档时才落库）。油价不在本表
/// （油价缓存/手填价是全局临时状态，存偏好表，不进备份）。
@DataClassName('FuelPredictionRow')
class FuelPredictions extends Table {
  IntColumn get id => integer()();
  IntColumn get carId => integer()();
  IntColumn get fuelPercent => integer()();
  TextColumn get syncStatus => text().withDefault(const Constant('synced'))();
  TextColumn get updatedAt => text()();
  IntColumn get version => integer().withDefault(const Constant(1))();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {carId},
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
    FuelPredictions,
  ],
)
class AppDatabase extends _$AppDatabase {
  /// 生产构造：连接本地 SQLite 文件（惰性打开，见 [_openConnection]）。
  AppDatabase() : super(_openConnection());

  /// 测试构造：内存库（每个测试用例独立、不落盘）。
  AppDatabase.inMemory() : super(NativeDatabase.memory());

  /// 测试构造：自定义执行器。迁移测试用它打开临时文件库——先建库再
  /// 退化成老版本形状、拨回老版本号，重开后验证 onUpgrade 路径
  /// （内存库每次都是全新 schema，走不到迁移分支）。
  AppDatabase.withExecutor(super.executor);

  /// ⚠ 数据库结构版本（≠ 备份 JSON 的 schemaVersion=4，两者独立演进）。
  /// 改表结构必须 +1 并补 onUpgrade 分支，再跑 build_runner。
  @override
  int get schemaVersion => 9;

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
  /// v6→v7：新增加油预测设置表 fuel_predictions（纯建表，老数据不动）。
  /// v7→v8：油箱容积从 fuel_predictions 挪到 cars（车的属性）。
  ///       cars 加列 tank_capacity_liters，fuel_predictions 删旧列；
  ///       容积数据不搬迁（App 未上线、库里只有开发数据，产品已确认
  ///        放弃）。删列用 DROP COLUMN（SQLite ≥3.35）。
  /// v8→v9：动力类型改版（ADR 0003）。cars/vehicle_models 各加一列
  ///       （powertrainType / template，默认 'fuel'）；默认项目模板表从
  ///       "按品牌+车型"重建为"按动力类型"——形状变了，直接删表重建，
  ///       旧模板行（约 1.8 万行）不搬迁，首启 bootstrap 按新目录灌入。
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
          if (from < 7) {
            // v6→v7：加油预测设置表。全新安装走 createAll 时建表约束
            // 已含 {carId} 唯一约束，这里 createTable 与其语义等价。
            await migrator.createTable(fuelPredictions);
          }
          if (from < 8) {
            // v7→v8：容积挪去 cars 表（车的属性）。
            // 先给 cars 加列（老库没有这列，不加会在写车时报 no such column），
            // 再删 fuel_predictions 的旧列。容积数据不搬迁（App 未上线，
            // 产品已确认放弃旧开发数据）。列没进任何索引/唯一约束，
            // DROP COLUMN 安全（SQLite ≥3.35）。
            await migrator.addColumn(cars, cars.tankCapacityLiters);
            await customStatement(
              'ALTER TABLE fuel_predictions DROP COLUMN tank_capacity_liters',
            );
          }
          if (from < 9) {
            // v8→v9：动力类型改版（ADR 0003）。
            // cars/vehicle_models 加列（都有默认值，老行自动补 'fuel'）；
            // 默认项目模板表形状从"品牌+车型"变成"动力类型"，删表重建，
            // 旧数据不搬迁——首启 bootstrap 会按新目录重新灌入。
            await migrator.addColumn(cars, cars.powertrainType);
            await migrator.addColumn(vehicleModels, vehicleModels.template);
            // deleteTable 收表名字符串；删表连带旧的部分唯一索引一起消失。
            await migrator.deleteTable(
              vehicleDefaultMaintenanceItems.actualTableName,
            );
            await migrator.createTable(vehicleDefaultMaintenanceItems);
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
