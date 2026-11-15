// 数据库定义：Drift 表结构 + 迁移策略 + 连接方式。
//
// Drift ≈ Java 世界的 MyBatis-Generator/JPA：用 Dart 类声明表，
// build_runner 生成 app_database.g.dart 里的类型安全查询代码
// （那个文件是生成物，不要手改；表结构变更后跑 dart run build_runner build）。
//
// 通用约定（9 张表一致）：
//  - 主键 id 手工填 Snowflake 雪花 id（见 core/id/），不用自增；
//  - 每张业务表都带 syncStatus/updatedAt/version 三列（云同步预留）；
//  - 没有声明 FOREIGN KEY 外键——表间关联靠应用层维护
//    （删除车辆时由 Repository 在事务里手工级联删除）。
//
// ⚠ 唯一约束是重要的业务边界（改字段前先看 docs/migration/current-database-schema.md
// 与 docs/adr/0005：改表必须把 schemaVersion +1 并在 onUpgrade 补增量迁移，
// 破坏性变更才删库重建）：
//  - cars:                {brand, model, roadDate}
//  - vehicleModels:       {catalogId}, {brand, model}
//  - defaultItems:        {catalogId}, {powertrainType, itemName}
//  - maintenanceItems:    {carsId, name}
//  - maintenanceRecords:  {carId, date}          ← 一辆车一天只能一条记录
//  - recordItems:         {carId, date, itemId}
//  - appPreferences:      {key}
//  - fuelPredictions:     {carId}                ← 一辆车一份加油预测设置
//  - fuelRecords:         （故意不设唯一约束——同车同日多箱合法，ADR 0014）
//  - diagnosticsProbes:   {catalogKey}           ← 内置 key 唯一（自定义行该列 NULL，
//                                                  SQLite UNIQUE 多 NULL 合法，ADR 0021）
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

// part：把生成的 app_database.g.dart 并入本库（≈ Java 一个类拆多文件）。
part 'app_database.g.dart';

// ---------------------------- 表定义 ----------------------------

/// 车辆表。roadDate/syncStatus/updatedAt 以文本存储（yyyy-MM-dd / ISO 时间）。
/// tankCapacityLiters：加满可加油量（可用容积，升），车的属性，添加/
/// 编辑车辆时填写，可空（非必填）；加油预估用它算加满金额（ADR 0022）。
/// totalTankCapacityLiters：官方总容积（升），可空；储备油量 =
/// 总容积 − 可用容积（ADR 0022）。
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
  RealColumn get totalTankCapacityLiters => real().nullable()();
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
/// 项目费用三列（ADR 0010）：材料费/工时费/项目费用，单位分，可空 =
/// 未填。一行 = 一条记录 × 一个项目（≈ 订单明细行），同一个项目每次
/// 价格不同由行天然区分。三列允许合法的不一致（如优惠改价后项目费用
/// ≠ 材料+工时），读取方原样展示并按规则标提示，不做读时修正。
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
  IntColumn get materialCostCents => integer().nullable()();
  IntColumn get laborCostCents => integer().nullable()();
  IntColumn get costCents => integer().nullable()();

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

/// 加油记录表（ADR 0015，2026-09-22 就地重定义 v3 结构）：一次加油的
/// 流水——日期/油品/单价/应付金额/实付金额五项输入，容积（应付÷单价）
/// 由实体算好落列**预留**（页面暂不展示，与 cars.tankCapacityLiters
/// 油箱容积不是一回事）。
/// 与保养记录（maintenance_records）的两个关键差异（沿 ADR 0014）：
///  - **故意不设** {carId, date} 唯一约束：同一天加两次油（长途两箱）
///    合法，一天多条是常态而非脏数据；
///  - 不联动车辆当前里程——保养记录是车辆里程的唯一写源。
/// carId 普通索引：加油卡按车拉流水是高频路径（与保养记录同先例）。
@TableIndex(name: 'idx_fuel_records_car_id', columns: {#carId})
@DataClassName('FuelRecordRow')
class FuelRecords extends Table {
  IntColumn get id => integer()();
  IntColumn get carId => integer()();

  /// 加油日期（yyyy-MM-dd）。
  TextColumn get date => text()();

  /// 油品（FuelGrade 的稳定 code：'92'/'95'/'98'/'0'）。
  TextColumn get grade => text()();

  /// 每升单价，单位"分"（8.15 元/升存 815）。用户输入的权威值。
  IntColumn get unitPriceCents => integer()();

  /// 应付金额（加油机口径 = 单价 × 容积），单位分，与保养记录
  /// costCents 同口径避免浮点误差。
  IntColumn get payableCents => integer()();

  /// 实付金额（优惠后实际支付），单位分。可空：null = 未填（无优惠，
  /// 统计与展示取应付金额）。
  IntColumn get actualCents => integer().nullable()();

  /// 加油容积（升，两位小数）＝应付金额 ÷ 单价，由实体在构造时算好
  /// 落列。**预留字段**：页面暂不展示，供将来油耗等功能使用。
  RealColumn get volumeLiters => real()();

  TextColumn get syncStatus => text().withDefault(const Constant('synced'))();
  TextColumn get updatedAt => text()();
  IntColumn get version => integer().withDefault(const Constant(1))();

  @override
  Set<Column<Object>> get primaryKey => {id};

  // 故意不声明 uniqueKeys：同车同日多条加油合法（ADR 0014）。
}

/// 车辆诊断检测点表（ADR 0021 修订节，2026-11-15）：每车一套，挂
/// carId；删车在仓库事务里手工级联删除。与车辆数据纪元无关（写点不
/// bump 车辆纪元，读写走 provider 点失效）。
///  - 名称/指令原文/解析类型/刷新间隔/启停：检测点五要素（GLOSSARY
///    「检测点」）；内置三行可编辑、不可删除，自定义行可增改删；
///  - catalogKey：内置标识——非 null = 内置行（bootstrap 按 key 幂等
///    补缺失，不纠偏用户编辑），null = 自定义行。唯一约束
///    {carId, catalogKey}：同一辆车的内置 key 唯一；自定义行该列为
///    NULL（SQLite UNIQUE 允许多个 NULL）。
///  - refreshIntervalSeconds：每条检测点自己的自动轮询间隔（ADR 0023）
///  - header：29-bit 物理头（私有 DID 预留，本轮无 UI）
@TableIndex(name: 'idx_diagnostics_probes_car_id', columns: {#carId})
@DataClassName('DiagnosticsProbeRow')
class DiagnosticsProbes extends Table {
  IntColumn get id => integer()();

  /// 所属车辆 id（每车一套）。存储列可空只为迁移期存量回填；代码层
  /// 必填——种子/表单/恢复备份都必须带车。
  IntColumn get carId => integer().nullable()();

  /// 展示名（如"油量"）。
  TextColumn get name => text()();

  /// 指令原文（如 `012F`、`ATRV`），发送前由会话决策体规整。
  TextColumn get command => text()();

  /// 解析类型（DiagnosticsParseType 的稳定 wire 值）。
  TextColumn get parseType => text()();

  /// 启停。轮询只发启用项。
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();

  /// 内置标识（稳定 catalogKey）：非 null = 内置行（可编辑、不可删），
  /// null = 自定义行（可增改删）。
  TextColumn get catalogKey => text().nullable()();

  /// 自动轮询间隔（秒，ADR 0023）：默认 30，范围 5–3600。
  IntColumn get refreshIntervalSeconds =>
      integer().withDefault(const Constant(30))();

  /// 29-bit 物理头（如 `DA 60 F1`，私有 DID 预留，ADR 0023）；null =
  /// 默认功能寻址。本轮无 UI。
  TextColumn get header => text().nullable()();

  /// 最后读数三列（2026-11-15，ADR 0021 修订节）：检测点最后一次**有效**
  /// 轮询的展示值与时刻，离页重进可见。只写有效值——「无数据」不写库、
  /// 不覆盖旧值；页内实时显示不受影响（无数据照显灰字）。读数是设备
  /// 派生的临时数据：不进备份（导出/恢复白名单不携带）、高频写不盖同
  /// 步章（syncStatus/updatedAt/version 不动）。
  TextColumn get lastValue => text().nullable()();

  /// 最后读数的油量百分比（仅 fuelLevel 类有效值写，可空）：重进页面
  /// 油量卡升数估算（百分比 × 油箱容积）不缺数据。
  RealColumn get lastPercent => real().nullable()();

  /// 最后读数的时刻（ISO 8601 文本）。
  TextColumn get lastReadingAt => text().nullable()();

  TextColumn get syncStatus => text().withDefault(const Constant('synced'))();
  TextColumn get updatedAt => text()();
  IntColumn get version => integer().withDefault(const Constant(1))();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {carId, catalogKey},
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
    FuelRecords,
    DiagnosticsProbes,
  ],
)
class AppDatabase extends _$AppDatabase {
  /// 生产构造：连接本地 SQLite 文件（惰性打开，见 [_openConnection]）。
  AppDatabase() : super(_openConnection());

  /// 测试构造：内存库（每个测试用例独立、不落盘）。
  AppDatabase.inMemory() : super(NativeDatabase.memory());

  /// 测试构造：指定文件库（迁移测试用——内存库无法模拟"关掉再打开"，
  /// 也就触发不了 onUpgrade）。生产代码不要用。
  AppDatabase.forFile(File file) : super(NativeDatabase(file));

  /// 测试构造：注入任意执行器（后台 isolate 连接等"生产执行器形态"的
  /// 机制测试用——异常经 drift 远程协议回传会包 DriftRemoteException，
  /// 与进程内连接不同型，见 data/repositories/unique_constraint.dart）。
  /// 生产代码不要用。
  AppDatabase.forExecutor(super.executor);

  /// ⚠ 数据库结构版本（≠ 备份 JSON 的 schemaVersion，两者独立演进）。
  /// 改表结构必须 +1，并在 onUpgrade 补增量分支（ADR 0005 及其
  /// 2026-09-20 修订）。改完跑 build_runner。
  @override
  int get schemaVersion => 6;

  /// 迁移策略（ADR 0005，2026-09-20 修订）：纯增量变更（新增表/列）写
  /// onUpgrade 增量迁移，老库原地升级、存量数据保留——用户拍板"升级
  /// 不得删库重建"；删库重建（destructiveFallback）只保留给破坏性变更
  /// （改列类型/删表/改字段语义）。
  /// 全新安装走 onCreate 的 createAll，不经过 onUpgrade。
  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          // v2 → v3：新增加油记录表，纯增量——只建新表，不碰任何旧表，
          // 车辆/项目/记录等存量数据原样保留。表结构以 ADR 0015
          // （2026-09-22 就地重定义）为准：老 v3 库（旧五字段结构）不跑
          // 本分支、也不兼容新代码，本分支只服务"v2 真老库"。
          if (from < 3) {
            await m.createTable(fuelRecords);
          }
          // v3 → v4：新增车辆诊断检测点表（ADR 0021）。createTable 永远
          // 建**当前形态**（含 v5 读数三列与 v6 每车/间隔/header 列），
          // 所以建表分支必须与后面的加列分支互斥。
          if (from < 4) {
            await m.createTable(diagnosticsProbes);
          } else if (from < 5) {
            // v4 → v5：最后读数三列，纯增量 ADD COLUMN（ADR 0021 修订节）。
            await m.addColumn(diagnosticsProbes, diagnosticsProbes.lastValue);
            await m.addColumn(diagnosticsProbes, diagnosticsProbes.lastPercent);
            await m.addColumn(
              diagnosticsProbes,
              diagnosticsProbes.lastReadingAt,
            );
          }
          // v5 → v6：双油量总容积（ADR 0022）+ 检测点每车/刷新间隔/
          // header（ADR 0021 修订节、ADR 0023）。检测点唯一键从
          // {catalogKey} 改为 {carId, catalogKey}；SQLite 不能 ALTER
          // 约束，重建表。存量行归第一辆车（当前只有一辆时等价于当前
          // 应用车辆）；没有车时回填为 NULL，重建后立即清掉这些孤儿行
          // ——它们没有宿主（仓库按 carId 过滤读不到、bootstrap 种子
          // 对账也不会认领），且备份导出是全表读取、实体 carId 必填，
          // 留着会让导出永久失败（审查问题 1）。v6 之前的检测点没有
          // 归属概念，无车时无从归属，清理即升级语义。
          if (from < 6) {
            await m.addColumn(cars, cars.totalTankCapacityLiters);
            if (from >= 4) {
              await m.alterTable(
                TableMigration(
                  diagnosticsProbes,
                  columnTransformer: {
                    diagnosticsProbes.carId: const CustomExpression<int>(
                      '(SELECT id FROM cars ORDER BY id LIMIT 1)',
                    ),
                    diagnosticsProbes.refreshIntervalSeconds:
                        const Constant(30),
                  },
                  newColumns: [
                    diagnosticsProbes.carId,
                    diagnosticsProbes.refreshIntervalSeconds,
                    diagnosticsProbes.header,
                  ],
                ),
              );
              await m.database.customStatement(
                'DELETE FROM diagnostics_probes WHERE car_id IS NULL',
              );
            }
          }
        },
      );
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
