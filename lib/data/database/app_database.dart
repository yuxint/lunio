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
// ⚠ 唯一约束是重要的业务边界（改字段前先看 docs/migration/current-database-schema.md
// 与 docs/adr/0005：版本不符删库重建，改表必须把 schemaVersion +1）：
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
/// 可空（非必填）；加油预估用它算加满金额。
/// powertrainType：动力类型（ADR 0003），添加车辆时用户选择、添加后不可改。
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
/// 按动力类型分组（每动力一组，共五组约 50 行，ADR 0003）。
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

/// 内置车型目录表（每品牌最多 10 款热门车型，共约 1220 条，
/// 添加车辆向导的选择器数据源）。
/// template：推荐动力类型 wire 值（添加向导预选动力 chip 用）。
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
/// 容积在 cars 表（车的属性），本表只剩剩余油量；
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

  /// ⚠ 数据库结构版本（≠ 备份 JSON 的 schemaVersion=1，两者独立演进）。
  /// 改表结构必须 +1：版本与库文件不一致时按 ADR 0005 删库重建，
  /// 不写升级分支。改完跑 build_runner。
  @override
  int get schemaVersion => 1;

  /// 迁移策略（ADR 0005）：库文件版本与代码不一致（升或降）时，
  /// 删光全部表再重建，不保留任何升级路径。
  /// 全新安装走 onCreate 的 createAll，不经过这里。
  /// 开发期改表结构：schemaVersion +1 即可，旧开发库下次启动自动清空重建。
  @override
  MigrationStrategy get migration => destructiveFallback;
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
