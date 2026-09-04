// 内置目录仓库（BuiltInCatalogRepository）：车型目录与默认保养项目模板
// 两张内置表的唯一读写出口，外加首启 bootstrap 幂等对账。
//
// ≈ Java 里把"启动时同步基础数据"的逻辑从大 Service 里拆成的独立
// Bean：只服务两张只读业务表（对用户是只读——UI 只查不改），与
// 车辆/项目/记录核心域几乎无耦合。
//
// 对账语义（幂等，升级 App 更新目录后自动同步）：
//  1. 删除"目录里已不存在"的行（catalogId 不在目标集合）；
//  2. 逐条比对：没有则插入、字段有变化则更新（updatedAt 故意不比，
//     避免每次启动都写库）。
// 目录 asset 解析结果按实例 memoize（R28），多个 ensure 入口共用一次。
import 'package:drift/drift.dart';

import '../../core/id/snowflake_id_generator.dart';
import '../../domain/entities/sync_metadata.dart';
import '../../domain/entities/powertrain_type.dart' as domain;
import '../../domain/entities/vehicle_default_maintenance_item.dart' as domain;
import '../../domain/entities/vehicle_model.dart' as domain;
import '../bootstrap/built_in_vehicle_catalog.dart';
import '../database/app_database.dart';
import 'entity_row_codec.dart';

class BuiltInCatalogRepository {
  /// 构造时注入数据库连接；目录加载器可选注入（测试可换成内存版本）。
  BuiltInCatalogRepository(
    this.database, {
    BuiltInVehicleCatalogLoader? loadBuiltInVehicleCatalog,
  }) : _loadBuiltInVehicleCatalog =
           loadBuiltInVehicleCatalog ?? loadBuiltInVehicleCatalogAsset;

  final AppDatabase database;
  final BuiltInVehicleCatalogLoader _loadBuiltInVehicleCatalog;

  /// 目录解析 Future 的 memoize（R28）：实例内 asset 只解析一次，
  /// ensureBootstrapData / ensureVehicleModels / ensureDefaultMaintenanceItems
  /// 三个入口共用（≈ Spring 的 @Cacheable）。
  Future<BuiltInVehicleCatalog>? _catalogFuture;

  /// 取（并缓存）内置目录。
  Future<BuiltInVehicleCatalog> _loadCatalog() {
    return _catalogFuture ??= _loadBuiltInVehicleCatalog();
  }

  /// 确保默认保养项目模板已入库（单独暴露给测试/特殊调用，一般走 ensureBootstrapData）。
  Future<void> ensureDefaultMaintenanceItems() async {
    final catalog = await _loadCatalog();
    await _ensureDefaultMaintenanceItems(catalog);
  }

  /// 模板表幂等对账（事务内三步）：删多余 → 缺失补插 → 变化更新。
  /// 模板行全部带 catalogId（首启 bootstrap 从 asset 灌入）。
  Future<void> _ensureDefaultMaintenanceItems(
    BuiltInVehicleCatalog catalog,
  ) async {
    final sync = SyncMetadata(
      status: SyncStatus.synced,
      updatedAt: DateTime.now(),
    );
    final builtInItems = catalog.defaultMaintenanceItems(sync);
    final targetCatalogIds = builtInItems
        .map((item) => item.catalogId!)
        .toSet();
    await database.transaction(() async {
      await (database.delete(database.vehicleDefaultMaintenanceItems)..where(
            (row) =>
                row.catalogId.isNotNull() &
                row.catalogId.isNotIn(targetCatalogIds),
          ))
          .go();
      final existing = await database
          .select(database.vehicleDefaultMaintenanceItems)
          .get();
      final existingByCatalogId = {
        for (final row in existing)
          if (row.catalogId != null) row.catalogId!: row,
      };
      for (final item in builtInItems) {
        final existingRow = existingByCatalogId[item.catalogId];
        if (existingRow == null) {
          await saveVehicleDefaultMaintenanceItem(item);
        } else if (_defaultItemNeedsUpdate(existingRow, item)) {
          await _updateVehicleDefaultMaintenanceItem(existingRow.id, item);
        }
      }
    });
  }

  /// 确保车型目录已入库（同上，单独暴露）。
  Future<void> ensureVehicleModels() async {
    final catalog = await _loadCatalog();
    await _ensureVehicleModels(catalog);
  }

  /// 车型表幂等对账，逻辑与 _ensureDefaultMaintenanceItems 同构；
  /// 另按（品牌, 车型）兜底键识别无 catalogId 的历史行。
  Future<void> _ensureVehicleModels(BuiltInVehicleCatalog catalog) async {
    final sync = SyncMetadata(
      status: SyncStatus.synced,
      updatedAt: DateTime.now(),
    );
    final builtInModels = catalog.vehicleModels(sync);
    final targetCatalogIds = builtInModels
        .map((model) => model.catalogId!)
        .toSet();
    await database.transaction(() async {
      await (database.delete(database.vehicleModels)..where(
            (row) =>
                row.catalogId.isNotNull() &
                row.catalogId.isNotIn(targetCatalogIds),
          ))
          .go();
      final existing = await database.select(database.vehicleModels).get();
      final existingByCatalogId = {
        for (final row in existing)
          if (row.catalogId != null) row.catalogId!: row,
      };
      final existingByLegacyKey = {
        for (final row in existing)
          if (row.catalogId == null)
            _vehicleModelKey(row.brand, row.model): row,
      };
      for (final model in builtInModels) {
        final existingRow =
            existingByCatalogId[model.catalogId] ??
            existingByLegacyKey[_vehicleModelKey(model.brand, model.model)];
        if (existingRow == null) {
          await saveVehicleModel(model);
        } else if (_vehicleModelNeedsUpdate(existingRow, model)) {
          await _updateVehicleModel(existingRow.id, model);
        }
      }
    });
  }

  /// 首启/升级引导总入口：车型目录 + 默认项目模板两张表各做一次幂等对账。
  /// 由 defaultMaintenanceBootstrapProvider（providers.dart）在 AppShell 触发。
  /// 目录 asset 经 _loadCatalog memoize，本方法与两个 ensure 共用一次解析。
  Future<void> ensureBootstrapData() async {
    final catalog = await _loadCatalog();
    await _ensureVehicleModels(catalog);
    await _ensureDefaultMaintenanceItems(catalog);
  }

  /// 单条插入默认项目模板（bootstrap 对账用；生成的 id 自增雪花）。
  Future<int> saveVehicleDefaultMaintenanceItem(
    domain.VehicleDefaultMaintenanceItem item,
  ) async {
    final itemId = SnowflakeIdGenerator.instance.next();
    await database
        .into(database.vehicleDefaultMaintenanceItems)
        .insert(defaultItemCompanion(item, itemId));
    return itemId;
  }

  /// 单条插入车型（bootstrap 用）。template 是推荐动力类型。
  Future<int> saveVehicleModel(domain.VehicleModel model) async {
    final modelId = SnowflakeIdGenerator.instance.next();
    await database
        .into(database.vehicleModels)
        .insert(vehicleModelCompanion(model, modelId));
    return modelId;
  }

  /// 按新实体全量更新车型行（bootstrap 对账用）。
  Future<void> _updateVehicleModel(int id, domain.VehicleModel model) async {
    await (database.update(
      database.vehicleModels,
    )..where((row) => row.id.equals(id))).write(
      VehicleModelsCompanion(
        catalogId: Value(model.catalogId),
        brand: Value(model.brand),
        model: Value(model.model),
        template: Value(model.template.wire),
        sortOrder: Value(model.sortOrder),
        syncStatus: Value(model.sync.status.name),
        updatedAt: Value(model.sync.updatedAt.toIso8601String()),
        version: Value(model.sync.version),
      ),
    );
  }

  /// 按新实体全量更新模板行（bootstrap 对账用）。
  Future<void> _updateVehicleDefaultMaintenanceItem(
    int id,
    domain.VehicleDefaultMaintenanceItem item,
  ) async {
    await (database.update(
      database.vehicleDefaultMaintenanceItems,
    )..where((row) => row.id.equals(id))).write(
      VehicleDefaultMaintenanceItemsCompanion(
        catalogId: Value(item.catalogId),
        powertrainType: Value(item.powertrainType.wire),
        itemName: Value(item.itemName),
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

  /// 车型行与目标实体逐字段比对，决定 bootstrap 是否需要 update
  /// （updatedAt 故意不比，避免每次启动都写库）。
  bool _vehicleModelNeedsUpdate(
    VehicleModelRow row,
    domain.VehicleModel model,
  ) {
    return row.catalogId != model.catalogId ||
        row.brand != model.brand ||
        row.model != model.model ||
        row.template != model.template.wire ||
        row.sortOrder != model.sortOrder ||
        row.syncStatus != model.sync.status.name ||
        row.version != model.sync.version;
  }

  /// 同上，模板表版本。
  bool _defaultItemNeedsUpdate(
    VehicleDefaultMaintenanceItemRow row,
    domain.VehicleDefaultMaintenanceItem item,
  ) {
    return row.catalogId != item.catalogId ||
        row.powertrainType != item.powertrainType.wire ||
        row.itemName != item.itemName ||
        row.remindByMileage != item.remindByMileage ||
        row.remindByTime != item.remindByTime ||
        row.mileageIntervalKm != item.mileageIntervalKm ||
        row.timeIntervalMonths != item.timeIntervalMonths ||
        row.notOverdueUpperLimit != item.notOverdueUpperLimit ||
        row.overdueUpperLimit != item.overdueUpperLimit ||
        row.sortOrder != item.sortOrder ||
        row.syncStatus != item.sync.status.name ||
        row.version != item.sync.version;
  }

  /// 车型目录列表（按 sortOrder 升序），添加车辆向导的选择器数据源。
  Future<List<domain.VehicleModel>> listVehicleModels() async {
    final rows = await (database.select(
      database.vehicleModels,
    )..orderBy([(row) => OrderingTerm.asc(row.sortOrder)])).get();
    return rows.map(vehicleModelFromRow).toList();
  }

  /// 某动力类型的默认保养项目模板（添加车辆向导第二步的初始草稿、
  /// "恢复默认项目"的数据源）。按动力类型取。
  Future<List<domain.VehicleDefaultMaintenanceItem>>
  listDefaultItemsForPowertrain({
    required domain.PowertrainType powertrainType,
  }) async {
    final rows =
        await (database.select(database.vehicleDefaultMaintenanceItems)
              ..where(
                (row) => row.powertrainType.equals(powertrainType.wire),
              )
              ..orderBy([(row) => OrderingTerm.asc(row.sortOrder)]))
            .get();
    return rows.map(defaultItemFromRow).toList();
  }

  /// 车型专属默认保养项目（如思域的 civicFuel 模板，ADR 0004）。
  /// 命中条件全部满足才返回（否则返回 null，调用方回退动力类型通用模板）：
  ///  - （品牌, 车型）能在内置目录里找到条目；
  ///  - 条目带 itemTemplate（车型专属模板）；
  ///  - 调用方选的动力类型与目录推荐动力类型一致（用户改选其他动力
  ///    类型时，专属模板不再适用，按所选动力类型走通用模板）。
  /// 返回的实体不落库（vehicle_default_maintenance_items 表只存五个
  /// 动力类型组），仅作为向导草稿和"恢复"列表的内存数据源。
  Future<List<domain.VehicleDefaultMaintenanceItem>?>
  listDefaultItemsForVehicleModel({
    required String brand,
    required String model,
    required domain.PowertrainType selectedPowertrain,
  }) async {
    final catalog = await _loadCatalog();
    final vehicle = catalog.findVehicle(brand, model);
    final itemTemplate = vehicle?.itemTemplate;
    if (itemTemplate == null ||
        domain.PowertrainType.byWire(vehicle!.template) != selectedPowertrain) {
      return null;
    }
    final specs = catalog.vehicleTemplateItems(itemTemplate);
    if (specs == null) {
      return null;
    }
    final sync = SyncMetadata(
      status: SyncStatus.synced,
      updatedAt: DateTime.now(),
    );
    return [
      for (final (index, spec) in specs.indexed)
        domain.VehicleDefaultMaintenanceItem(
          catalogId: 'vtpl:$itemTemplate:${spec.id}',
          powertrainType: selectedPowertrain,
          itemName: spec.name,
          remindByMileage: spec.remindByMileage,
          remindByTime: spec.remindByTime,
          mileageIntervalKm: spec.mileageIntervalKm,
          timeIntervalMonths: spec.timeIntervalMonths,
          sortOrder: index + 1,
          sync: sync,
        ),
    ];
  }
}

// bootstrap 对账用的"旧数据兜底键"：\u0000 作分隔符保证组合不歧义。
// （只用于车型表；模板表全部行带 catalogId，不需要兜底键。）
String _vehicleModelKey(String brand, String model) => '$brand\u0000$model';
