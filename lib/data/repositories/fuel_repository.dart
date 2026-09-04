// 加油预测仓库（FuelRepository）：加油域的数据库读写出口。
//
// ≈ Java 里从大 Service 拆出的领域 Service：管三块互不重叠的数据——
//  1. 每车加油预测设置（fuel_predictions 表，剩余油量）；
//  2. 油价缓存（上次拉取的全国价表 + 调价预告，JSON 存偏好，ADR 0006）；
//  3. 手填油价（"省份|油品" → 每升价，JSON 存偏好）。
// 后两者是临时数据（不进备份），经 LunioPreferences 的 readRaw/writeRaw
// 原语存取，key 常量登记在本模块（加油域的 key 不进偏好门面）。
//
// 与车辆域的关系：deleteCar 的事务内会调 [deleteForCar] 级联删预测行
// （由主仓库组合调用），其余路径互不依赖。
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:drift/drift.dart';

import '../../core/id/snowflake_id_generator.dart';
import '../../domain/entities/fuel_prediction.dart' as domain;
import '../../domain/entities/fuel_price.dart' as domain;
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

  /// 删除某辆车的预测行（删除车辆的级联清理专用，须在主仓库的删车
  /// 事务内调用）。
  Future<void> deleteForCar(int carId) {
    return (database.delete(
      database.fuelPredictions,
    )..where((row) => row.carId.equals(carId))).go();
  }

  // ---------------- 油价缓存（临时）----------------

  /// 读油价缓存（上次成功拉取的全国价表 + 调价预告，JSON 存偏好，
  /// 见 docs/adr/0006）。
  /// JSON 损坏或结构不符合当前契约（如旧版单省缓存）时打日志并返回
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

  /// 写油价缓存（整个覆盖：一次拉取的全国价表就是一份完整缓存）。
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
