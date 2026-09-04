// 备份仓库（BackupRepository）：数据生命周期出口——备份导出、备份
// 恢复、清空数据。≈ Java 里"数据迁移/运维工具"性质的 Service，与
// 日常 CRUD 分开。
//
// 行插入走 entity_row_codec.dart 的共享 Companion 构造：恢复路径与
// 手工录入路径用同一份字段清单（R35 的不变量"恢复的数据过和手工
// 录入同样的规则"在插入层也成立），给表加字段不再需要改恢复循环。
//
// 恢复流程（ADR 0005：只认当前 schemaVersion，不做旧版兼容）：
//  1. 版本校验；2. 事务外两层预校验（引用完整性 + 业务规则）；3. 单一
//  大事务清业务表 → 逐行插入（id 全换新雪花，旧→新映射）；4. 应用车辆
//  指向恢复出的第一辆车；5. 备份带全局加油设置时覆盖省份/油品偏好。
import 'package:drift/drift.dart';

import '../../core/id/snowflake_id_generator.dart';
import '../../domain/rules/applied_car_rules.dart';
import '../../domain/rules/fuel_rules.dart';
import '../../domain/rules/record_rules.dart';
import '../backup/backup_codec.dart';
import '../database/app_database.dart';
import '../preferences/app_preferences.dart';
import 'entity_row_codec.dart';

class BackupRepository {
  /// 构造时注入数据库连接与偏好门面（加油设置回写、抑制键清理的通道）。
  BackupRepository(this.database, this._preferences);

  final AppDatabase database;
  final LunioPreferences _preferences;

  /// 导出备份：4 张业务表 + 加油预测设置全量读取（顺序两次查询拼
  /// itemIds，无 N+1），组装 BackupPayload。
  /// 不含偏好/停车倒计时/油价缓存与手填价/目录。
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
    for (final row in recordItemRows) {
      itemIdsByRecordId
          .putIfAbsent(row.maintenanceRecordId, () => [])
          .add(row.itemId);
    }
    final records = recordRows.map((row) {
      return maintenanceRecordFromRow(row, itemIdsByRecordId[row.id] ?? const []);
    }).toList();
    final fuelPredictionRows = await database.select(
      database.fuelPredictions,
    ).get();
    final fuelPredictions = fuelPredictionRows.map(fuelPredictionFromRow)
        .toList();
    // 全局加油设置（省份/油品）：用户改过才有值，没改过不带进备份。
    final fuelProvince = await _preferences.getFuelProvince();
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
    );
  }

  /// 恢复备份（导入）。流程见文件头。任何一行违反约束抛错则整体回滚
  /// （UI 提示"未写入任何数据"）。
  Future<void> restoreBackupPayload(BackupPayload payload) {
    if (payload.schemaVersion != BackupCodec.currentSchemaVersion) {
      throw UnsupportedError(
        'Unsupported backup schemaVersion: ${payload.schemaVersion}',
      );
    }
    _validateBackupReferences(payload);
    _validateBackupBusinessRules(payload);

    return database.transaction(() async {
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
            .insert(maintenanceRecordCompanion(record, recordId));
        for (final itemId in RecordRules.uniqueItemIds(record.itemIds)) {
          final mappedItemId = itemIdMap[itemId];
          if (mappedItemId == null) {
            throw ArgumentError(
              'Backup maintenance record references missing item',
            );
          }
          await database
              .into(database.maintenanceRecordItems)
              .insert(
                maintenanceRecordItemCompanion(
                  id: SnowflakeIdGenerator.instance.next(),
                  recordId: recordId,
                  carId: carId,
                  itemId: mappedItemId,
                  date: record.date,
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
    });
  }

  /// 清空数据（"我的"页入口）：事务内删 6 张表（4 张业务表
  /// + 加油预测设置表 + 偏好表）。
  /// 语义（用户确认过的口径）：清空车辆、保养项目、保养记录、加油预测
  /// 设置和全部偏好设置（主题、通知、手动日期、开发者模式、停车倒计时、
  /// 油价缓存、手填油价、snooze/ack）；
  /// 默认车辆模型与默认保养项目两张目录表不动。
  /// 清空后 UI 会 invalidate 触发 bootstrap 重新灌车型目录；
  /// 系统通知的取消由调用方（通知协调器 runAllDataClear）负责。
  Future<void> clearAllData() {
    return database.transaction(() async {
      await _preferences.deleteAll();
      await database.delete(database.maintenanceRecordItems).go();
      await database.delete(database.maintenanceRecords).go();
      await database.delete(database.maintenanceItems).go();
      await database.delete(database.fuelPredictions).go();
      await database.delete(database.cars).go();
    });
  }

  /// 恢复备份专用的清库实现（须在事务内调用）：只删 4 张业务表，
  /// 偏好表整体保留（主题、通知设置、手动日期、停车倒计时等不受影响，
  /// R2 修复口径："恢复只替换三类业务数据，偏好保留"）；但按前缀删掉
  /// 提醒抑制键——恢复出来的车/项目拿的是全新雪花 id，旧 snooze/ack
  /// 与新数据在语义上已无关联，不该继续生效。
  Future<void> _clearRestorableDataInTransaction() async {
    await database.delete(database.maintenanceRecordItems).go();
    await database.delete(database.maintenanceRecords).go();
    await database.delete(database.maintenanceItems).go();
    await database.delete(database.fuelPredictions).go();
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
  /// （跨车引用的备份直接拒绝）。
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
  }

  /// 备份业务规则校验（恢复前、事务外执行，R35）：
  /// 项目过实体 validate、记录过 RecordRules.validateRecord——
  /// 与手工录入走同一套规则，篡改过的备份（负金额/负里程/空项目/
  /// 非法间隔）在开事务前就被拒绝，保证"失败时未写入任何数据"。
  /// 校验失败统一包装成中文 ArgumentError（UI 直接展示给用户）。
  void _validateBackupBusinessRules(BackupPayload payload) {
    for (final car in payload.cars) {
      try {
        FuelRules.validateTankCapacity(car.tankCapacityLiters);
      } on ArgumentError catch (error) {
        throw ArgumentError(
          '备份文件中存在无效数据（车辆「${car.brand} ${car.model}」油箱容积）：'
          '${error.message}',
        );
      }
    }
    for (final item in payload.maintenanceItems) {
      try {
        item.validate();
      } on ArgumentError catch (error) {
        throw ArgumentError('备份文件中存在无效数据（保养项目「${item.name}」）：'
            '${error.message}');
      }
    }
    for (final record in payload.records) {
      try {
        RecordRules.validateRecord(record);
      } on ArgumentError catch (error) {
        throw ArgumentError(
          '备份文件中存在无效数据（保养记录 ${record.date}）：${error.message}',
        );
      }
    }
    for (final prediction in payload.fuelPredictions) {
      try {
        prediction.validate();
      } on ArgumentError catch (error) {
        throw ArgumentError(
          '备份文件中存在无效数据（加油预测设置）：${error.message}',
        );
      }
    }
  }
}
