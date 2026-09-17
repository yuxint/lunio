// 加油仓库（FuelRepository）：加油域的数据库读写出口。
//
// ≈ Java 里从大 Service 拆出的领域 Service：管四块互不重叠的数据——
//  1. 每车加油预测设置（fuel_predictions 表，剩余油量）；
//  2. 每车加油记录（fuel_records 表，ADR 0014）；
//  3. 油价缓存（上次拉取的单省价表 + 调价预告，JSON 存偏好，ADR 0006/0011）；
//  4. 手填油价（"省份|油品" → 每升价，JSON 存偏好）。
// 后两者是临时数据（不进备份），经 LunioPreferences 的 readRaw/writeRaw
// 原语存取，key 常量登记在本模块（加油域的 key 不进偏好门面）。
//
// 与车辆域的关系：deleteCar 的事务内会调 [deleteForCar] 级联删预测行与
// 加油记录（由主仓库组合调用），其余路径互不依赖。
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:drift/drift.dart';

import '../../core/id/snowflake_id_generator.dart';
import '../../domain/entities/fuel_prediction.dart' as domain;
import '../../domain/entities/fuel_price.dart' as domain;
import '../../domain/entities/fuel_record.dart' as domain;
import '../../domain/entities/sync_metadata.dart';
import '../database/app_database.dart';
import '../preferences/app_preferences.dart';
import 'entity_row_codec.dart';

class FuelRepository {
  /// 构造时注入数据库连接与偏好门面（缓存/手填价的存储通道）。
  FuelRepository(this.database, this._preferences);

  final AppDatabase database;
  final LunioPreferences _preferences;

  /// 油价缓存在偏好表里的 key（临时数据，不进备份）。
  static const _fuelPriceCachePreferenceKey = 'fuelPriceCache';

  /// 手填油价在偏好表里的 key（JSON map："省份|油品code" → 每升价，
  /// 临时数据，不进备份）。
  static const _fuelManualPricesPreferenceKey = 'fuelManualPrices';

  // ---------------- 每车加油预测设置 ----------------

  /// 读某辆车的加油预测设置（剩余油量）；没设置过返回 null
  /// （展示层按默认 50% 处理）。
  Future<domain.FuelPrediction?> getFuelPredictionForCar(int carId) async {
    final row = await (database.select(
      database.fuelPredictions,
    )..where((row) => row.carId.equals(carId))).getSingleOrNull();
    if (row == null) {
      return null;
    }
    return fuelPredictionFromRow(row);
  }

  /// 保存加油预测设置（按 carId upsert：有则更新、无则插入）。
  /// 副作用：syncStatus 记 pendingUpdate、updatedAt 刷新（沿用全库约定）。
  Future<void> saveFuelPrediction(domain.FuelPrediction prediction) async {
    prediction.validate();
    final existingRow = await (database.select(
      database.fuelPredictions,
    )..where((row) => row.carId.equals(prediction.carId))).getSingleOrNull();
    final now = DateTime.now().toIso8601String();
    if (existingRow == null) {
      await database
          .into(database.fuelPredictions)
          .insert(
            FuelPredictionsCompanion.insert(
              id: Value(SnowflakeIdGenerator.instance.next()),
              carId: prediction.carId,
              fuelPercent: prediction.fuelPercent,
              syncStatus: const Value('pendingUpdate'),
              updatedAt: now,
            ),
          );
      return;
    }
    await (database.update(
      database.fuelPredictions,
    )..where((row) => row.id.equals(existingRow.id))).write(
      FuelPredictionsCompanion(
        fuelPercent: Value(prediction.fuelPercent),
        syncStatus: const Value('pendingUpdate'),
        updatedAt: Value(now),
      ),
    );
  }

  /// 删除某辆车的全部加油域数据（预测行 + 加油记录，ADR 0014；删除车辆
  /// 的级联清理专用，须在主仓库的删车事务内调用）。
  Future<void> deleteForCar(int carId) async {
    await (database.delete(
      database.fuelPredictions,
    )..where((row) => row.carId.equals(carId))).go();
    await (database.delete(
      database.fuelRecords,
    )..where((row) => row.carId.equals(carId))).go();
  }

  // ---------------- 每车加油记录（ADR 0014）----------------

  /// 某辆车的全部加油记录，按（日期、里程、id）升序——这是满箱段油耗
  /// 口径（full-to-full）的锚定顺序（ADR 0014），列表展示的"最近 5 条"
  /// 由 UI 在此基准上自行倒序截取。
  Future<List<domain.FuelRecord>> listFuelRecordsForCar(int carId) async {
    final rows =
        await (database.select(database.fuelRecords)
              ..where((row) => row.carId.equals(carId))
              ..orderBy([
                (row) => OrderingTerm.asc(row.date),
                (row) => OrderingTerm.asc(row.mileageKm),
                (row) => OrderingTerm.asc(row.id),
              ]))
            .get();
    return rows.map(fuelRecordFromRow).toList();
  }

  /// 新增加油记录。不联动车辆当前里程（保养记录是唯一写源，ADR 0014）。
  /// 副作用：syncStatus 记 pendingUpdate、updatedAt 刷新（沿用加油域约定）。
  /// 返回新生成的雪花 id。
  Future<int> saveFuelRecord(domain.FuelRecord record) async {
    record.validate();
    final recordId = SnowflakeIdGenerator.instance.next();
    final synced = record.copyWith(
      sync: SyncMetadata(
        status: SyncStatus.pendingUpdate,
        updatedAt: DateTime.now(),
      ),
    );
    await database
        .into(database.fuelRecords)
        .insert(fuelRecordCompanion(synced, recordId));
    return recordId;
  }

  /// 编辑加油记录（按 id 整行更新业务字段；carId 不在更新范围——编辑
  /// 不把记录挪到别的车）。不联动车辆当前里程。
  /// 副作用：syncStatus 记 pendingUpdate、updatedAt 刷新。
  Future<void> updateFuelRecord(domain.FuelRecord record) async {
    final recordId = record.id;
    if (recordId == null) {
      throw ArgumentError('Fuel record id is required');
    }
    record.validate();
    await (database.update(
      database.fuelRecords,
    )..where((row) => row.id.equals(recordId))).write(
      FuelRecordsCompanion(
        date: Value(record.date.toString()),
        mileageKm: Value(record.mileageKm),
        volumeLiters: Value(record.volumeLiters),
        totalCostCents: Value(record.totalCostCents),
        fullTank: Value(record.fullTank),
        syncStatus: Value(SyncStatus.pendingUpdate.name),
        updatedAt: Value(DateTime.now().toIso8601String()),
      ),
    );
  }

  /// 删除单条加油记录（按 id）。
  Future<void> deleteFuelRecord(int recordId) {
    return (database.delete(
      database.fuelRecords,
    )..where((row) => row.id.equals(recordId))).go();
  }

  // ---------------- 油价缓存（临时）----------------

  /// 读油价缓存（上次成功拉取的单省价表 + 调价预告，JSON 存偏好，
  /// 见 docs/adr/0006 与 0011）。
  /// JSON 损坏或结构不符合当前契约（如旧版全国价表缓存）时打日志并返回
  /// null（与停车倒计时同口径，R14）。
  Future<domain.FuelPriceData?> getFuelPriceCache() async {
    final value = await _preferences.readRaw(_fuelPriceCachePreferenceKey);
    if (value == null) {
      return null;
    }
    try {
      final json = jsonDecode(value) as Map<String, Object?>;
      return domain.FuelPriceData.fromJson(json);
    } catch (error) {
      developer.log(
        'FuelRepository: 油价缓存 JSON 损坏，按无缓存处理：$error',
        name: 'lunio.repository',
      );
      return null;
    }
  }

  /// 写油价缓存（整个覆盖：一次拉取的单省价表就是一份完整缓存）。
  Future<void> saveFuelPriceCache(domain.FuelPriceData data) {
    return _preferences.writeRaw(
      _fuelPriceCachePreferenceKey,
      jsonEncode(data.toJson()),
    );
  }

  // ---------------- 手填油价（临时）----------------

  /// 读全部手填油价（key = "省份|油品code"，value = 每升价）。
  /// JSON 损坏时打日志并按空 map 处理。
  Future<Map<String, double>> getFuelManualPrices() async {
    final value =
        await _preferences.readRaw(_fuelManualPricesPreferenceKey);
    if (value == null) {
      return const {};
    }
    try {
      final json = jsonDecode(value) as Map<String, Object?>;
      return json.map((key, value) => MapEntry(key, (value as num).toDouble()));
    } catch (error) {
      developer.log(
        'FuelRepository: 手填油价 JSON 损坏，按无手填处理：$error',
        name: 'lunio.repository',
      );
      return const {};
    }
  }

  /// 读某个"省+油品"组合的手填价；没填过返回 null。
  Future<double?> getFuelManualPrice({
    required String province,
    required domain.FuelGrade grade,
  }) async {
    final prices = await getFuelManualPrices();
    return prices[_fuelManualPriceKey(province, grade)];
  }

  /// 写某个"省+油品"组合的手填价（null = 清除该组合）。
  /// map 清空后把偏好整个删掉，不留空壳数据。
  Future<void> setFuelManualPrice({
    required String province,
    required domain.FuelGrade grade,
    required double? pricePerLiter,
  }) async {
    final prices = Map<String, double>.of(await getFuelManualPrices());
    final key = _fuelManualPriceKey(province, grade);
    if (pricePerLiter == null) {
      prices.remove(key);
    } else {
      prices[key] = pricePerLiter;
    }
    if (prices.isEmpty) {
      await _preferences.writeRaw(_fuelManualPricesPreferenceKey, null);
      return;
    }
    await _preferences.writeRaw(
      _fuelManualPricesPreferenceKey,
      jsonEncode(prices),
    );
  }

  /// 手填油价 map 的 key：省份 + 油品 code（\u0000 分隔防歧义，
  /// 与 bootstrap 兜底键同一手法）。
  static String _fuelManualPriceKey(String province, domain.FuelGrade grade) =>
      '$province\u0000${grade.code}';
}
