// 加油预测领域规则测试：全量档位表、金额/油量计算、油价刷新判断、
// 容积校验（Car 上，v8 起）与加油预测实体校验。
import 'package:flutter_test/flutter_test.dart';
import 'package:lunio/domain/entities/fuel_prediction.dart';
import 'package:lunio/domain/entities/fuel_price.dart';
import 'package:lunio/domain/entities/sync_metadata.dart';
import 'package:lunio/domain/rules/fuel_rules.dart';

void main() {
  group('FuelRules.allTierPercents', () {
    test('全量档位表：100% 到 0% 每 2% 一档，共 51 档', () {
      final tiers = FuelRules.allTierPercents;
      expect(tiers.length, 51);
      expect(tiers.first, 100);
      expect(tiers.last, 0);
      // 首尾与中间抽查：每档严格 -2。
      expect(tiers[1], 98);
      expect(tiers[25], 50);
      expect(tiers[50], 0);
      for (var i = 1; i < tiers.length; i++) {
        expect(tiers[i - 1] - tiers[i], FuelRules.percentStep);
      }
    });

    test('50% 的下标是 25（默认档定位用）', () {
      expect(FuelRules.allTierPercents.indexOf(50), 25);
    });
  });

  group('FuelRules.validateTankCapacity', () {
    test('null 合法（未填写）', () {
      expect(() => FuelRules.validateTankCapacity(null), returnsNormally);
    });

    test('1–999、最多四位小数，合法值通过', () {
      for (final liters in [1.0, 55.0, 64.5, 55.1234, 999.0]) {
        expect(
          () => FuelRules.validateTankCapacity(liters),
          returnsNormally,
          reason: '$liters 应合法',
        );
      }
    });

    test('越界/超过四位小数抛 ArgumentError', () {
      expect(() => FuelRules.validateTankCapacity(0.5), throwsArgumentError);
      expect(() => FuelRules.validateTankCapacity(1000), throwsArgumentError);
      expect(
        () => FuelRules.validateTankCapacity(55.55555),
        throwsArgumentError,
      );
    });
  });

  group('FuelRules 金额计算', () {
    test('加满油量 = (100-剩余)/100 × 容积', () {
      expect(
        FuelRules.litersToFill(fuelPercent: 50, tankCapacityLiters: 55),
        27.5,
      );
      expect(
        FuelRules.litersToFill(fuelPercent: 0, tankCapacityLiters: 55),
        55,
      );
      expect(
        FuelRules.litersToFill(fuelPercent: 100, tankCapacityLiters: 55),
        0,
      );
    });

    test('加满金额四舍五入到分', () {
      // 27.5 升 × 7.45 元 = 204.875 → 20488 分（四舍五入）。
      expect(
        FuelRules.fullTankCostCents(
          fuelPercent: 50,
          tankCapacityLiters: 55,
          pricePerLiter: 7.45,
        ),
        20488,
      );
      // 整数 case：20 升 × 7.50 元 = 150.00 元。
      expect(
        FuelRules.fullTankCostCents(
          fuelPercent: 80,
          tankCapacityLiters: 100,
          pricePerLiter: 7.5,
        ),
        15000,
      );
    });
  });

  group('FuelRules.shouldRefreshFuelPrices', () {
    final now = DateTime(2026, 8, 31, 12);

    test('无缓存需要拉取', () {
      expect(
        FuelRules.shouldRefreshFuelPrices(
          lastFetchedAt: null,
          cachedProvince: null,
          currentProvince: '湖北',
          now: now,
        ),
        isTrue,
      );
    });

    test('缓存省份与当前省份不同需要拉取', () {
      expect(
        FuelRules.shouldRefreshFuelPrices(
          lastFetchedAt: now.subtract(const Duration(days: 1)),
          cachedProvince: '湖南',
          currentProvince: '湖北',
          now: now,
        ),
        isTrue,
      );
    });

    test('10 个自然日内不需要拉取，满 10 天需要', () {
      final nineDaysAgo = now.subtract(const Duration(days: 9));
      final tenDaysAgo = now.subtract(const Duration(days: 10));
      expect(
        FuelRules.shouldRefreshFuelPrices(
          lastFetchedAt: nineDaysAgo,
          cachedProvince: '湖北',
          currentProvince: '湖北',
          now: now,
        ),
        isFalse,
      );
      expect(
        FuelRules.shouldRefreshFuelPrices(
          lastFetchedAt: tenDaysAgo,
          cachedProvince: '湖北',
          currentProvince: '湖北',
          now: now,
        ),
        isTrue,
      );
    });
  });

  group('FuelPrediction 实体校验', () {
    final sync = SyncMetadata(status: SyncStatus.synced, updatedAt: DateTime(2026));

    test('剩余油量 0-100 合法值通过', () {
      expect(
        () => FuelPrediction(carId: 1, fuelPercent: 50, sync: sync),
        returnsNormally,
      );
      expect(
        () => FuelPrediction(carId: 1, fuelPercent: 0, sync: sync),
        returnsNormally,
      );
      expect(
        () => FuelPrediction(carId: 1, fuelPercent: 100, sync: sync),
        returnsNormally,
      );
    });

    test('剩余油量超出 0-100 抛 ArgumentError', () {
      expect(
        () => FuelPrediction(carId: 1, fuelPercent: 101, sync: sync),
        throwsArgumentError,
      );
      expect(
        () => FuelPrediction(carId: 1, fuelPercent: -1, sync: sync),
        throwsArgumentError,
      );
    });
  });

  group('FuelGrade', () {
    test('code 往返解析', () {
      for (final grade in FuelGrade.values) {
        expect(FuelGrade.tryParse(grade.code), grade);
      }
    });
  });
}
