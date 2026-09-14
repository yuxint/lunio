// 油价域状态接缝的单元测试：油价控制器（FuelPriceController）与生效链
// 三个 provider（生效价/生效预告/预估价）。
//
// 依赖全部可替换：内存数据库 + 假数据源（带拉取计数）+ override 后的
// ProviderContainer 驱动真实装配（与 notification_coordinator_test 同
// 手法），锁死：
//  - build：新鲜同省缓存直出不拉源；过期/无缓存自动拉取并写缓存；
//    换省返回 null 且不拉源（ADR 0011 用户决策）；拉取失败退旧缓存；
//  - manualRefresh：成功覆盖缓存返回 true，失败保旧返回 false；
//  - 生效价：手填优先，无手填取数据源当前省当前油品价；
//  - 生效预告：过期按无预告（ADR 0011 修订），"今天"未加载按无预告；
//  - 预估价：生效价 + 预告变动中值，四舍五入到分。
//
// 时间控制：新鲜期判定靠 DB 直写老 fetchedAt 触发（生产代码不注入
// 时钟）；"今天"靠 override 生效日期 provider 固定。
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunio/app/providers.dart';
import 'package:lunio/core/date/local_date.dart';
import 'package:lunio/data/database/app_database.dart';
import 'package:lunio/data/preferences/app_preferences.dart';
import 'package:lunio/domain/entities/fuel_price.dart';
import 'package:lunio/features/shell/fuel/fuel_prices.dart';

/// 假数据源：返回固定价表或抛错，并记录拉取次数（断言"没拉源"用）。
/// [result] 与 [throwOnFetch] 可变，用例中途可改（先成功后失败等）。
class _CountingFakeSource implements FuelPriceSource {
  FuelPriceData? result;
  Object? throwOnFetch;
  int fetchCount = 0;

  @override
  Future<FuelPriceData> fetchPrices({required String province}) async {
    fetchCount++;
    if (throwOnFetch != null) {
      throw throwOnFetch!;
    }
    return result!;
  }
}

/// 默认省（直读偏好门面真值常量，不手写"湖北"字面量）。
final _defaultProvince = LunioPreferences.defaultFuelProvince;

/// 与默认省不同的另一个真实省份（换省用例用）。
final _otherProvince =
    fuelProvinces.firstWhere((p) => p != _defaultProvince);

FuelPriceData _priceData({
  String? province,
  DateTime? fetchedAt,
  double price92 = 8.10,
  FuelAdjustmentForecast? forecast,
}) {
  return FuelPriceData(
    province: province ?? _defaultProvince,
    fetchedAt: fetchedAt ?? DateTime.now(),
    pricesByGrade: {FuelGrade.gasoline92: price92},
    forecast: forecast,
  );
}

/// 12月20日调价的涨价预告（"今天"为 2026-09-13 时未过期）。
FuelAdjustmentForecast _futureForecast() => const FuelAdjustmentForecast(
      month: 12,
      day: 20,
      trend: FuelPriceTrend.up,
      minChangePerLiter: 0.10,
      maxChangePerLiter: 0.30,
    );

/// 8月20日调价的预告（"今天"为 2026-09-13 时已过期）。
FuelAdjustmentForecast _expiredForecast() => const FuelAdjustmentForecast(
      month: 8,
      day: 20,
      trend: FuelPriceTrend.up,
      minChangePerLiter: 0.10,
      maxChangePerLiter: 0.30,
    );

/// N 天前的本地时刻（构造过期缓存用）。
DateTime _daysAgo(int days) =>
    DateTime.now().subtract(Duration(days: days));

void main() {
  late AppDatabase database;
  late ProviderContainer container;
  late _CountingFakeSource fakeSource;

  /// 固定"今天"= 2026-09-13 的标准装配；[today] 传永不完成的 future
  /// 可模拟"生效日期还没加载出来"。
  ProviderContainer buildContainer({Future<LocalDate>? today}) {
    return ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(database),
      fuelPriceSourceProvider.overrideWithValue(fakeSource),
      effectiveTodayProvider.overrideWith(
        (ref) => today ?? Future.value(const LocalDate(2026, 9, 13)),
      ),
    ]);
  }

  setUp(() {
    database = AppDatabase.inMemory();
    fakeSource = _CountingFakeSource();
    container = buildContainer();
  });

  tearDown(() async {
    container.dispose();
    await database.close();
  });

  /// 预热控制器与生效链依赖（先播种缓存再预热，避免误触自动拉取；
  /// 生效日期也要预热，否则派生 provider 读到 AsyncLoading 当无预告）。
  Future<void> warm() async {
    await container.read(fuelPriceControllerProvider.future);
    await container.read(fuelManualPriceProvider.future);
    await container.read(effectiveTodayProvider.future);
  }

  Future<void> seedCache(FuelPriceData data) async {
    await container.read(fuelRepositoryProvider).saveFuelPriceCache(data);
  }

  group('FuelPriceController.build', () {
    test('新鲜同省缓存直接返回，不打数据源', () async {
      await seedCache(_priceData(price92: 7.61));

      final result = await container.read(fuelPriceControllerProvider.future);

      expect(result?.province, _defaultProvince);
      expect(result?.pricesByGrade[FuelGrade.gasoline92], 7.61);
      expect(fakeSource.fetchCount, 0);
    });

    test('无缓存自动拉取并写缓存', () async {
      fakeSource.result = _priceData(price92: 8.05);

      final result = await container.read(fuelPriceControllerProvider.future);

      expect(result?.pricesByGrade[FuelGrade.gasoline92], 8.05);
      expect(fakeSource.fetchCount, 1);
      final cached =
          await container.read(fuelRepositoryProvider).getFuelPriceCache();
      expect(cached?.pricesByGrade[FuelGrade.gasoline92], 8.05);
    });

    test('过期缓存（超过 10 个自然日）自动拉取覆盖', () async {
      await seedCache(
        _priceData(price92: 7.61, fetchedAt: _daysAgo(11)),
      );
      fakeSource.result = _priceData(price92: 8.05);

      final result = await container.read(fuelPriceControllerProvider.future);

      expect(result?.pricesByGrade[FuelGrade.gasoline92], 8.05);
      expect(fakeSource.fetchCount, 1);
    });

    test('换省后缓存归属不匹配：返回 null 且不自动拉取', () async {
      await seedCache(_priceData(province: _defaultProvince));
      await container
          .read(lunioPreferencesProvider)
          .setFuelProvince(_otherProvince);
      container.invalidate(fuelProvinceProvider);

      final result = await container.read(fuelPriceControllerProvider.future);

      expect(result, isNull);
      expect(fakeSource.fetchCount, 0);
    });

    test('拉取失败退回旧缓存', () async {
      await seedCache(
        _priceData(price92: 7.61, fetchedAt: _daysAgo(11)),
      );
      fakeSource.throwOnFetch = Exception('网络不可用');

      final result = await container.read(fuelPriceControllerProvider.future);

      expect(result?.pricesByGrade[FuelGrade.gasoline92], 7.61);
      expect(fakeSource.fetchCount, 1);
    });
  });

  group('FuelPriceController.manualRefresh', () {
    test('成功覆盖缓存与状态，返回 true', () async {
      await seedCache(_priceData(price92: 7.61));
      await warm();
      fakeSource.result = _priceData(price92: 8.05);

      final ok = await container
          .read(fuelPriceControllerProvider.notifier)
          .manualRefresh();
      final state = container.read(fuelPriceControllerProvider).value;

      expect(ok, isTrue);
      expect(state?.pricesByGrade[FuelGrade.gasoline92], 8.05);
      final cached =
          await container.read(fuelRepositoryProvider).getFuelPriceCache();
      expect(cached?.pricesByGrade[FuelGrade.gasoline92], 8.05);
    });

    test('失败保留原状态与缓存，返回 false', () async {
      await seedCache(_priceData(price92: 7.61));
      await warm();
      fakeSource.throwOnFetch = Exception('网络不可用');

      final ok = await container
          .read(fuelPriceControllerProvider.notifier)
          .manualRefresh();
      final state = container.read(fuelPriceControllerProvider).value;

      expect(ok, isFalse);
      expect(state?.pricesByGrade[FuelGrade.gasoline92], 7.61);
      final cached =
          await container.read(fuelRepositoryProvider).getFuelPriceCache();
      expect(cached?.pricesByGrade[FuelGrade.gasoline92], 7.61);
    });
  });

  group('生效价 effectiveFuelPriceProvider', () {
    test('无手填取数据源当前省当前油品价', () async {
      await seedCache(_priceData(price92: 8.10));
      await warm();

      expect(container.read(effectiveFuelPriceProvider), 8.10);
    });

    test('手填价优先于数据源价', () async {
      await seedCache(_priceData(price92: 8.10));
      await container
          .read(fuelRepositoryProvider)
          .setFuelManualPrice(
            province: _defaultProvince,
            grade: FuelGrade.gasoline92,
            pricePerLiter: 7.99,
          );
      container.invalidate(fuelManualPriceProvider);
      await warm();

      expect(container.read(effectiveFuelPriceProvider), 7.99);
    });

    test('缓存里没有当前油品的价 → null', () async {
      await seedCache(_priceData(price92: 8.10));
      await container
          .read(lunioPreferencesProvider)
          .setFuelGrade(FuelGrade.gasoline98);
      container.invalidate(fuelGradeProvider);
      container.invalidate(fuelManualPriceProvider);
      await warm();

      expect(container.read(effectiveFuelPriceProvider), isNull);
    });
  });

  group('生效预告 effectiveFuelForecastProvider', () {
    test('未过期预告透出，过期预告按无预告', () async {
      await seedCache(_priceData(forecast: _futureForecast()));
      await warm();
      expect(container.read(effectiveFuelForecastProvider), isNotNull);

      // 覆写缓存为过期预告，重建控制器状态后再读。
      await seedCache(_priceData(forecast: _expiredForecast()));
      container.invalidate(fuelPriceControllerProvider);
      await warm();
      expect(container.read(effectiveFuelForecastProvider), isNull);
    });

    test('"今天"未加载完成按无预告处理', () async {
      final pendingContainer = buildContainer(
        today: Completer<LocalDate>().future,
      );
      addTearDown(pendingContainer.dispose);
      await seedCache(_priceData(forecast: _futureForecast()));
      await pendingContainer.read(fuelPriceControllerProvider.future);

      expect(
        pendingContainer.read(effectiveFuelForecastProvider),
        isNull,
      );
    });
  });

  group('预估价 predictedFuelPriceProvider', () {
    test('生效价 + 涨价预告中值，四舍五入到分', () async {
      await seedCache(
        _priceData(price92: 8.10, forecast: _futureForecast()),
      );
      await warm();

      // 8.10 + (0.10 + 0.30) / 2 = 8.30
      expect(container.read(predictedFuelPriceProvider), 8.30);
    });

    test('无预告（含过期）或无生效价 → null', () async {
      await seedCache(_priceData(price92: 8.10));
      await warm();
      expect(container.read(predictedFuelPriceProvider), isNull);
    });
  });
}
