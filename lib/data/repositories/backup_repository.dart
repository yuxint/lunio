// 备份仓库（BackupRepository）：数据生命周期出口——备份导出、备份
// 恢复、清空数据。≈ Java 里"数据迁移/运维工具"性质的 Service，与
// 日常 CRUD 分开。
//
// 行插入走 entity_row_codec.dart 的共享 Companion 构造：恢复路径与
// 手工录入路径用同一份字段清单（R35 的不变量"恢复的数据过和手工
// 录入同样的规则"在插入层也成立），给表加字段不再需要改恢复循环。
//
// 恢复流程（接受 v1–v4——v1 缺项目费用、v1/v2 缺加油记录、v1–v3 缺
// 自定义检测点，纯增量缺失按空读入，ADR 0010/0014/0021；其余版本拒收）：
//  1. 版本校验；2. 事务外两层预校验（引用完整性 + 业务规则）；3. 单一
//  大事务清业务表 → 逐行插入（id 全换新雪花，旧→新映射）；4. 应用车辆
//  指向恢复出的第一辆车；5. 备份带全局加油设置时覆盖省份/油品偏好。
import 'package:drift/drift.dart';

import '../../core/id/snowflake_id_generator.dart';
import '../../core/date/local_date.dart';
import '../../domain/entities/maintenance_record.dart' show RecordItemCost;
import '../../domain/errors/lunio_error.dart';
import '../../domain/rules/applied_car_rules.dart';
import '../../domain/rules/fuel_rules.dart';
import '../../domain/rules/record_rules.dart';
import '../backup/backup_codec.dart';
import '../database/app_database.dart';
import '../preferences/app_preferences.dart';
import 'entity_row_codec.dart';
import 'unique_constraint.dart';

class BackupRepository {
  /// 构造时注入数据库连接与偏好门面（加油设置回写、抑制键清理的通道）。
  BackupRepository(this.database, this._preferences);

  final AppDatabase database;
  final LunioPreferences _preferences;

  /// 导出备份：4 张业务表 + 加油预测设置 + 加油记录 + 自定义检测点
  /// 全量读取（顺序查询拼 itemIds，无 N+1），组装 BackupPayload。
  /// 不含偏好/停车倒计时/油价缓存与手填价/目录/内置检测点（内置三条
  /// 恢复后由 bootstrap 幂等重建，ADR 0021）。
  Future<BackupPayload> exportBackupPayload() async {
    final cars = (await database.select(database.cars).get())
        .map(carFromRow)
        .toList();
    final items = (await database.select(database.maintenanceItems).get())
        .map(maintenanceItemFromRow)
        .toList();
    final recordRows = await database.select(database.maintenanceRecords).get();
    final recordItemRows = await database
        .select(database.maintenanceRecordItems)
        .get();
    final itemIdsByRecordId = <int, List<int>>{};
    final itemCostsByRecordId = <int, List<RecordItemCost>>{};
    for (final row in recordItemRows) {
      itemIdsByRecordId
          .putIfAbsent(row.maintenanceRecordId, () => [])
          .add(row.itemId);
      final cost = recordItemCostFromRow(row);
      if (cost != null) {
        itemCostsByRecordId
            .putIfAbsent(row.maintenanceRecordId, () => [])
            .add(cost);
      }
    }
    final records = recordRows.map((row) {
      return maintenanceRecordFromRow(
        row,
        itemIdsByRecordId[row.id] ?? const [],
        itemCostsByRecordId[row.id] ?? const [],
      );
    }).toList();
    final fuelPredictionRows = await database.select(
      database.fuelPredictions,
    ).get();
    final fuelPredictions = fuelPredictionRows.map(fuelPredictionFromRow)
        .toList();
    final fuelRecordRows = await database.select(database.fuelRecords).get();
    final fuelRecords = fuelRecordRows.map(fuelRecordFromRow).toList();
    // 检测点：段只导自定义项（catalogKey 为 null 的行），内置三条不进
    // 备份——恢复后由 bootstrap 幂等重建，对齐车型目录先例（ADR 0021）。
    // 启停是用户数据，自定义项停用态也导出。
    final probeRows = await database.select(database.diagnosticsProbes).get();
    final diagnosticsProbes = probeRows
        .where((row) => row.catalogKey == null)
        .map(diagnosticsProbeFromRow)
        // 最后读数是设备派生临时数据，不进备份（2026-11-15，ADR 0021
        // 修订节）：payload 是备份的内存形态，这里剥干净，恢复后从零积累。
        .map(
          (probe) => probe.copyWith(
            lastValue: null,
            lastPercent: null,
            lastReadingAt: null,
          ),
        )
        .toList();
    // 全局加油设置（省份/油品）：用户改过才有值，没改过不带进备份。
    // 这里故意用原始读而不是 getFuelProvince()/getFuelGrade()——两个
    // getter 都会兜底产品默认值，会把"没改过"读成"改成了默认值"。
    final fuelProvince = await _preferences.readRaw(
      LunioPreferences.fuelProvinceKey,
    );
    final fuelGradeCode = await _preferences.readRaw(
      LunioPreferences.fuelGradeKey,
    );
    return BackupPayload(
      schemaVersion: BackupCodec.currentSchemaVersion,
      cars: cars,
      maintenanceItems: items,
      records: records,
      fuelPrediction: fuelProvince == null || fuelGradeCode == null
          ? null
          : BackupFuelPreference(
              province: fuelProvince,
              gradeCode: fuelGradeCode,
            ),
      fuelPredictions: fuelPredictions,
      fuelRecords: fuelRecords,
      // 检测点段：只含上面筛出的自定义项，内置不进备份（ADR 0021）。
      diagnosticsProbes: diagnosticsProbes,
    );
  }

  /// 导出备份的 JSON 字符串：[exportBackupPayload] 组装 payload 后经
  /// BackupCodec 编码。编码收在 data 层（备份契约的一部分），动作层与
  /// UI 只拿字符串，不再直接摸 codec。口径同 payload：不含偏好/停车
  /// 倒计时/油价缓存与手填价/目录。
  Future<String> exportBackupJson() async {
    final payload = await exportBackupPayload();
    return const BackupCodec().encode(payload);
  }

  /// 解码备份 JSON 字符串为 [BackupPayload]：版本 ∉ {1,2,3,4} 抛
  /// UnsupportedError；v1/v2/v3 兼容读（纯增量缺失按空，ADR
  /// 0010/0014/0021），含旧结构加油条目的 v3 条目解码即拒（ADR 0015）。
  /// 恢复编排从这取 payload，再交 [restoreBackupPayload] 落库。
  BackupPayload decodeBackupJson(String json) {
    return const BackupCodec().decode(json);
  }

  /// 恢复备份（导入）。流程见文件头。任何一行违反约束抛错则整体回滚
  /// （UI 提示"未写入任何数据"）。事务边界包 guardUniqueConstraint：
  /// 预校验只覆盖保养记录的同车同日查重，payload 内部的重复车辆
  /// （cars {brand,model,roadDate}）/同名项目（{carsId,name}）等仍靠
  /// 表级唯一约束拦，撞上时翻译成 typed uniqueConstraint（预校验拦不住
  /// 的最后防线，恢复 UI 按 kind 弹"未写入任何数据"对话框，ADR 0009
  /// 2026-10-01 修订节）。
  /// 检测点段重插说明：全局表不挂车、无引用重映射负担，行 id 重新
  /// 生成雪花（条目不带 id，沿 fuelRecords 先例，ADR 0021）；恢复完成
  /// 后内置三条由 bootstrap 幂等重建、自定义项随段存活（恢复/清空后
  /// 的失效与 bootstrap 重灌触发见 providers.dart 的
  /// invalidateAllAppDataProviders）。
  /// 版本检查与 codec 一致：接受 v1–v4（ADR 0010/0014/0021 的纯增量兼容）。
  Future<void> restoreBackupPayload(BackupPayload payload) {
    if (!BackupCodec.supportedSchemaVersions.contains(payload.schemaVersion)) {
      throw UnsupportedError(
        'Unsupported backup schemaVersion: ${payload.schemaVersion}',
      );
    }
    _validateBackupReferences(payload);
    _validateBackupBusinessRules(payload);

    return guardUniqueConstraint(() => database.transaction(() async {
      await _clearRestorableDataInTransaction();
      final carIdMap = <int, int>{};
      final itemIdMap = <int, int>{};
      int? firstRestoredCarId;

      for (final car in payload.cars) {
        final sourceId = car.id;
        if (sourceId == null) {
          throw ArgumentError('Backup car id is required');
        }
        final carId = SnowflakeIdGenerator.instance.next();
        await database.into(database.cars).insert(carCompanion(car, carId));
        carIdMap[sourceId] = carId;
        firstRestoredCarId ??= carId;
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
        final itemId = SnowflakeIdGenerator.instance.next();
        await database
            .into(database.maintenanceItems)
            .insert(
              maintenanceItemCompanion(
                // 备份里的 carsId 是旧库的车辆 id，重映射为新雪花 id。
                item.copyWith(carsId: carId),
                itemId,
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
        final recordId = SnowflakeIdGenerator.instance.next();
        await database
            .into(database.maintenanceRecords)
            .insert(
              // 备份里的 carId 是旧库的车辆 id，主表与关联表一样重映射
              // 为新雪花 id（漏换会让恢复出的记录挂到不存在的旧 id 下，
              // 公开查询查不到）。
              maintenanceRecordCompanion(record, recordId, carId: carId),
            );
        final costsByItemId = <int, RecordItemCost>{
          for (final cost in record.itemCosts) cost.itemId: cost,
        };
        for (final itemId in RecordRules.uniqueItemIds(record.itemIds)) {
          final mappedItemId = itemIdMap[itemId];
          if (mappedItemId == null) {
            throw ArgumentError(
              'Backup maintenance record references missing item',
            );
          }
          // 项目费用按备份里的旧 itemId 取值，随行恢复（金额本身不需要
          // 重映射，只有 itemId 要换成新雪花 id）。"材料/工时有值但项目
          // 费用为空"的旧备份条目（不变量落地前版本导出的备份文件）由
          // companion 内置 normalize 补齐（数据不变量，2026-09-20 落地、
          // 2026-09-25 收编为写 seam 单点），恢复不把违规数据带进新库。
          final cost = costsByItemId[itemId];
          await database
              .into(database.maintenanceRecordItems)
              .insert(
                maintenanceRecordItemCompanion(
                  id: SnowflakeIdGenerator.instance.next(),
                  recordId: recordId,
                  carId: carId,
                  itemId: mappedItemId,
                  date: record.date,
                  cost: cost,
                ),
              );
        }
      }

      await _preferences.setAppliedCarId(firstRestoredCarId);
      await _ensureAppliedCarInTransaction();
      // 备份带全局加油设置（省份/油品）时恢复；没带（用户没改过）则
      // 保持用户当前的省份/油品不动。
      final fuelPreference = payload.fuelPrediction;
      if (fuelPreference != null) {
        await _preferences.writeRawAll({
          LunioPreferences.fuelProvinceKey: fuelPreference.province,
          LunioPreferences.fuelGradeKey: fuelPreference.gradeCode,
        });
      }
      // 每车加油设置：按新车辆 id 重插（车辆本身已换成新雪花 id）。
      // 容积是 cars 条目的字段（随车恢复），这里只插剩余油量。
      for (final prediction in payload.fuelPredictions) {
        final carId = carIdMap[prediction.carId];
        if (carId == null) {
          throw ArgumentError(
            'Backup fuel prediction references missing car',
          );
        }
        await database
            .into(database.fuelPredictions)
            .insert(
              fuelPredictionCompanion(
                prediction.copyWith(carId: carId),
                SnowflakeIdGenerator.instance.next(),
              ),
            );
      }

      // 加油记录：与加油预测同一套重映射——备份里的 carId 换成新雪花
      // id，行 id 重新生成（备份条目不带 id，ADR 0014）。
      for (final fuelRecord in payload.fuelRecords) {
        final carId = carIdMap[fuelRecord.carId];
        if (carId == null) {
          throw ArgumentError('Backup fuel record references missing car');
        }
        await database
            .into(database.fuelRecords)
            .insert(
              fuelRecordCompanion(
                fuelRecord.copyWith(carId: carId),
                SnowflakeIdGenerator.instance.next(),
              ),
            );
      }

      // 自定义检测点（备份 v5，ADR 0021 修订节）：每车一套，carId 经
      // carIdMap 重映射到恢复后的新雪花 id；行 id 重新生成雪花（条目
      // 不带 id，沿 fuelRecords 先例）。catalogKey 显式清一次：decode
      // 产物恒为 null，这里兜住手拼 payload，防止内置 key 走漏成
      // "种子外内置行"被对账清掉。
      for (final probe in payload.diagnosticsProbes) {
        final carId = carIdMap[probe.carId];
        if (carId == null) {
          throw ArgumentError(
            'Backup diagnostics probe references missing car',
          );
        }
        await database
            .into(database.diagnosticsProbes)
            .insert(
              diagnosticsProbeCompanion(
                probe.copyWith(catalogKey: null, carId: carId),
                SnowflakeIdGenerator.instance.next(),
              ),
            );
      }
    }));
  }

  /// 清空数据（"我的"页入口）：事务内删 8 张表（4 张业务表
  /// + 加油预测设置表 + 加油记录表 + 检测点表 + 偏好表）。
  /// 语义（用户确认过的口径）：清空车辆、保养项目、保养记录、加油预测
  /// 设置、加油记录、检测点（自定义+内置行一并删；内置不再全局重灌，
  /// 下次新增车辆时按车播种）和全部偏好设置（主题、通知、手动日期、
  /// 开发者模式、停车倒计时、油价缓存、手填油价、snooze/ack）；
  /// 默认车辆模型与默认保养项目两张目录表不动。
  /// 清空后 UI 会 invalidate 触发 bootstrap 重新灌车型目录；检测点种子
  /// 随新增车辆播种；系统通知的取消由调用方（通知协调器
  /// runAllDataClear）负责。
  Future<void> clearAllData() {
    return database.transaction(() async {
      await _preferences.deleteAll();
      await database.delete(database.maintenanceRecordItems).go();
      await database.delete(database.maintenanceRecords).go();
      await database.delete(database.maintenanceItems).go();
      await database.delete(database.fuelPredictions).go();
      await database.delete(database.fuelRecords).go();
      await database.delete(database.diagnosticsProbes).go();
      await database.delete(database.cars).go();
    });
  }

  /// 恢复备份专用的清库实现（须在事务内调用）：只删 7 张业务表
  /// （4 张主业务表 + 加油预测设置 + 加油记录 + 检测点），偏好表整体
  /// 保留（主题、通知设置、手动日期、停车倒计时等不受影响，R2 修复
  /// 口径："恢复只替换业务数据，偏好保留"）；但按前缀删掉提醒抑制键
  /// ——恢复出来的车/项目拿的是全新雪花 id，旧 snooze/ack 与新数据在
  /// 语义上已无关联，不该继续生效。加油记录清表是备份 v3 补上的：不删
  /// 会把恢复前残留的旧加油记录留在库里，变成指向已删车辆的孤儿行
  /// （ADR 0014）。检测点清表配合备份 v5：清掉的内置行随每车 bootstrap
  /// 重灌重建、自定义行由备份 diagnosticsProbes 段按 carId 重映射重插
  /// （ADR 0021 修订节）。
  Future<void> _clearRestorableDataInTransaction() async {
    await database.delete(database.maintenanceRecordItems).go();
    await database.delete(database.maintenanceRecords).go();
    await database.delete(database.maintenanceItems).go();
    await database.delete(database.fuelPredictions).go();
    await database.delete(database.fuelRecords).go();
    await database.delete(database.diagnosticsProbes).go();
    await database.delete(database.cars).go();
    await _preferences.clearReminderSuppressionKeys();
  }

  /// 事务内保证应用车辆有效（恢复备份收尾时调用）：与主仓库同一份
  /// [AppliedCarRules] 规则（无车清空、失效回退 id 最小车），仅在
  /// 结果与当前偏好不一致时写回。
  Future<void> _ensureAppliedCarInTransaction() async {
    final rows = await (database.select(
      database.cars,
    )..orderBy([(row) => OrderingTerm.asc(row.id)]))
        .get();
    final cars = rows.map(carFromRow).toList();
    final storedCarId = await _preferences.getAppliedCarId();
    final resolvedCarId = AppliedCarRules.resolveAppliedCarId(
      cars: cars,
      storedCarId: storedCarId,
    );
    if (resolvedCarId != storedCarId) {
      await _preferences.setAppliedCarId(resolvedCarId);
    }
  }

  /// 备份引用完整性校验（恢复前、事务外执行）：
  /// cars/items 的 id 齐全且不重复；每个 item 的 carsId 存在；
  /// 每条 record 的 carId 存在、每个 itemId 存在且与 record 同车
  /// （跨车引用的备份直接拒绝）；加油预测设置与加油记录的 carId 存在。
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
    for (final prediction in payload.fuelPredictions) {
      if (!carIds.contains(prediction.carId)) {
        throw ArgumentError('Backup fuel prediction references missing car');
      }
    }
    for (final fuelRecord in payload.fuelRecords) {
      if (!carIds.contains(fuelRecord.carId)) {
        throw ArgumentError('Backup fuel record references missing car');
      }
    }
  }

  /// 备份业务规则校验（恢复前、事务外执行，R35）：
  /// 项目过实体 validate、记录过 RecordRules.validateRecord、加油预测
  /// 设置与加油记录过实体 validate——与手工录入走同一套规则，篡改过的
  /// 备份（负金额/负里程/空项目/非法间隔）在开事务前就被拒绝，保证
  /// "失败时未写入任何数据"；末段做保养记录的同车同日查重（跨行）。
  /// 校验失败统一抛 LunioErrorException(backupInvalidData)（ADR 0009
  /// 修订节），message 即用户可读中文，恢复 UI 弹对话框展示。
  void _validateBackupBusinessRules(BackupPayload payload) {
    for (final car in payload.cars) {
      try {
        FuelRules.validateTankCapacity(car.tankCapacityLiters);
      } on ArgumentError catch (error) {
        throw LunioErrorException(
          LunioErrorKind.backupInvalidData,
          '备份文件中存在无效数据（车辆「${car.brand} ${car.model}」油箱容积）：'
          '${error.message}',
        );
      }
    }
    for (final item in payload.maintenanceItems) {
      try {
        item.validate();
      } on ArgumentError catch (error) {
        throw LunioErrorException(
          LunioErrorKind.backupInvalidData,
          '备份文件中存在无效数据（保养项目「${item.name}」）：'
          '${error.message}',
        );
      }
    }
    for (final record in payload.records) {
      try {
        RecordRules.validateRecord(record);
      } on ArgumentError catch (error) {
        throw LunioErrorException(
          LunioErrorKind.backupInvalidData,
          '备份文件中存在无效数据（保养记录 ${record.date}）：${error.message}',
        );
      }
    }
    for (final prediction in payload.fuelPredictions) {
      try {
        prediction.validate();
      } on ArgumentError catch (error) {
        throw LunioErrorException(
          LunioErrorKind.backupInvalidData,
          '备份文件中存在无效数据（加油预测设置）：${error.message}',
        );
      }
    }
    for (final fuelRecord in payload.fuelRecords) {
      try {
        fuelRecord.validate();
      } on ArgumentError catch (error) {
        throw LunioErrorException(
          LunioErrorKind.backupInvalidData,
          '备份文件中存在无效数据（加油记录 ${fuelRecord.date}）：${error.message}',
        );
      }
    }
    // 检测点（备份 v4 新增段，ADR 0021）：实体构造即校验，此处兜手拼
    // payload（与加油记录同先例）；文案点出条目名，方便定位坏条目。
    for (final probe in payload.diagnosticsProbes) {
      try {
        probe.validate();
      } on ArgumentError catch (error) {
        throw LunioErrorException(
          LunioErrorKind.backupInvalidData,
          '备份文件中存在无效数据（检测点「${probe.name}」）：${error.message}',
        );
      }
    }
    // 同车同日查重（跨行检查，上面几段都是逐行）：表级唯一约束
    // {carId,date} 的业务前置检查，与手工录入路径主仓库的
    // _ensureRecordIsUnique 同一条规则（那边抛 typed
    // duplicateMaintenanceRecord）。真实导出的备份不可能含重复（源库
    // 表级唯一约束挡着），出现即文件被手工编辑过或来自外来工具——
    // 整文件拒绝（全有全无，"失败时未写入任何数据"），不跳过重复行。
    // 范围只有保养记录：fuel_records 故意没有 {carId,date} 唯一约束
    // （ADR 0014，同车同日多箱合法）。重映射不会制造重复（旧 id → 新
    // 雪花 id 是单射），在重映射前的原始 carId 上查即充分；此时引用
    // 完整性校验已过，record.carId 必能在 payload.cars 里反查到。
    final countByCarDate = <(int, LocalDate), int>{};
    for (final record in payload.records) {
      final key = (record.carId, record.date);
      countByCarDate[key] = (countByCarDate[key] ?? 0) + 1;
    }
    // 反查车名用于文案（引用完整性校验已过，正常必能查到；兜底显示
    // "未知"，不影响拒绝本身）。
    final carsById = {
      for (final car in payload.cars)
        if (car.id != null) car.id!: car,
    };
    for (final record in payload.records) {
      final count = countByCarDate[(record.carId, record.date)]!;
      if (count > 1) {
        final car = carsById[record.carId];
        final carLabel = car == null ? '未知' : '${car.brand} ${car.model}';
        throw LunioErrorException(
          LunioErrorKind.backupInvalidData,
          '备份文件中有重复的保养记录：车辆「$carLabel」在 ${record.date} '
          '有 $count 条。同车同日只能有一条。',
        );
      }
    }
  }
}
