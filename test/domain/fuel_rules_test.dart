// 加油预测领域规则测试：全量档位表、金额/油量计算、油价刷新判断、
// 容积校验（Car 上）与加油预测实体校验。
import 'package:flutter_test/flutter_test.dart';
import 'package:lunio/core/date/local_date.dart';
import 'package:lunio/domain/entities/fuel_prediction.dart';
import 'package:lunio/domain/entities/fuel_price.dart';
import 'package:lunio/domain/entities/fuel_record.dart';
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
        FuelRules.shouldRefreshFuelPrices(lastFetchedAt: null, now: now),
        isTrue,
      );
    });

    test('10 个自然日内不需要拉取，满 10 天需要', () {
      final nineDaysAgo = now.subtract(const Duration(days: 9));
      final tenDaysAgo = now.subtract(const Duration(days: 10));
      expect(
        FuelRules.shouldRefreshFuelPrices(
          lastFetchedAt: nineDaysAgo,
          now: now,
        ),
        isFalse,
      );
      expect(
        FuelRules.shouldRefreshFuelPrices(
          lastFetchedAt: tenDaysAgo,
          now: now,
        ),
        isTrue,
      );
    });
  });

  group('FuelRules.litersInTank', () {
    test('当前油量 = 剩余油量 × 容积，与 litersToFill 互补', () {
      // 50% × 55 升 = 27.5 升。
      expect(
        FuelRules.litersInTank(fuelPercent: 50, tankCapacityLiters: 55),
        27.5,
      );
      // 满箱/空箱两端。
      expect(
        FuelRules.litersInTank(fuelPercent: 100, tankCapacityLiters: 55),
        55,
      );
      expect(
        FuelRules.litersInTank(fuelPercent: 0, tankCapacityLiters: 55),
        0,
      );
      // 互补关系：当前油量 + 需加油量 = 容积。
      final capacity = 48.0;
      expect(
        FuelRules.litersInTank(fuelPercent: 36, tankCapacityLiters: capacity) +
            FuelRules.litersToFill(
              fuelPercent: 36,
              tankCapacityLiters: capacity,
            ),
        capacity,
      );
    });
  });

  group('FuelRules.predictedPricePerLiter', () {
    test('区间取中值：8.10 + (0.05~0.06 的中值 0.055) → 四舍五入到分 8.15', () {
      final forecast = FuelAdjustmentForecast(
        month: 9,
        day: 11,
        trend: FuelPriceTrend.up,
        minChangePerLiter: 0.05,
        maxChangePerLiter: 0.06,
      );
      expect(
        FuelRules.predictedPricePerLiter(
          currentPricePerLiter: 8.10,
          forecast: forecast,
        ),
        8.15,
      );
    });

    test('下调取负向：7.50 − 0.10 → 7.40', () {
      final forecast = FuelAdjustmentForecast(
        month: 9,
        day: 11,
        trend: FuelPriceTrend.down,
        minChangePerLiter: 0.10,
        maxChangePerLiter: 0.10,
      );
      expect(
        FuelRules.predictedPricePerLiter(
          currentPricePerLiter: 7.50,
          forecast: forecast,
        ),
        7.40,
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

  group('FuelRules.isForecastExpired', () {
    FuelAdjustmentForecast forecast(int month, int day) =>
        FuelAdjustmentForecast(
          month: month,
          day: day,
          trend: FuelPriceTrend.up,
          minChangePerLiter: 0.05,
          maxChangePerLiter: 0.06,
        );

    test('调价日当天仍有效（调价发生在 24 时，当天价格未变）', () {
      expect(
        FuelRules.isForecastExpired(
          forecast: forecast(9, 11),
          today: const LocalDate(2026, 9, 11),
        ),
        isFalse,
      );
    });

    test('调价日次日过期（9-11 调价，9-12 即过期）', () {
      expect(
        FuelRules.isForecastExpired(
          forecast: forecast(9, 11),
          today: const LocalDate(2026, 9, 12),
        ),
        isTrue,
      );
    });

    test('未来预告有效，定年取离今天最近的同月日（不是想当然取明年）', () {
      // 今天 5-19，"9月11日"最近的候选是当年 9-11（未来）→ 有效；
      // 若错取明年会仍是未来碰巧同结论，用次日过期案反向锁死定年：
      // 今天 9-12 时"9月11日"必须落到当年（昨天）判过期而非明年（未来）。
      expect(
        FuelRules.isForecastExpired(
          forecast: forecast(9, 11),
          today: const LocalDate(2026, 5, 19),
        ),
        isFalse,
      );
    });

    test('跨年缓存过期：今天 1 月，缓存里"12月28日"落到去年判过期', () {
      expect(
        FuelRules.isForecastExpired(
          forecast: forecast(12, 28),
          today: const LocalDate(2027, 1, 3),
        ),
        isTrue,
      );
    });

    test('跨年缓存有效：12 月底读到"1月5日"预告落到明年判有效', () {
      expect(
        FuelRules.isForecastExpired(
          forecast: forecast(1, 5),
          today: const LocalDate(2026, 12, 30),
        ),
        isFalse,
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

  group('FuelRules 满箱段油耗（ADR 0014）', () {
    // 造数捷径：id 自增保证（日期、里程、id）排序稳定，fullTank 默认加满。
    var nextId = 0;
    FuelRecord record(
      String date, {
      required int mileageKm,
      double volumeLiters = 40,
      int totalCostCents = 30000,
      bool fullTank = true,
    }) {
      nextId += 1;
      return FuelRecord(
        id: nextId,
        carId: 1,
        date: LocalDate.parse(date),
        mileageKm: mileageKm,
        volumeLiters: volumeLiters,
        totalCostCents: totalCostCents,
        fullTank: fullTank,
      );
    }

    setUp(() => nextId = 0);

    test('空列表与单条记录：无段', () {
      expect(FuelRules.fuelTankSegments(const []), isEmpty);
      expect(
        FuelRules.fuelTankSegments([
          record('2026-05-01', mileageKm: 10000),
        ]),
        isEmpty,
        reason: '单条记录无论是否加满都不闭合段',
      );
      expect(
        FuelRules.averageFuelConsumptionPer100Km(
          FuelRules.fuelTankSegments([]),
        ),
        isNull,
      );
      expect(FuelRules.averageCostPerKm(FuelRules.fuelTankSegments([])), isNull);
    });

    test('两次加满闭合一段；首条满箱只做锚点不闭合', () {
      final segments = FuelRules.fuelTankSegments([
        record('2026-05-01', mileageKm: 10000),
        record('2026-05-10', mileageKm: 10500, volumeLiters: 30,
            totalCostCents: 25000),
      ]);
      expect(segments, hasLength(1));
      expect(segments.first.km, 500);
      expect(segments.first.liters, 30);
      expect(segments.first.costCents, 25000);
    });

    test('部分加油计入所在段升数但不闭合段', () {
      final segments = FuelRules.fuelTankSegments([
        record('2026-05-01', mileageKm: 10000),
        // 中间加半箱：贡献升数与金额，不闭合段（无本段油耗）。
        record('2026-05-05', mileageKm: 10200, volumeLiters: 15,
            totalCostCents: 12000, fullTank: false),
        record('2026-05-10', mileageKm: 10500, volumeLiters: 20,
            totalCostCents: 16000),
      ]);
      expect(segments, hasLength(1));
      expect(segments.first.closingRecordId, 3);
      expect(segments.first.liters, 35, reason: '部分加油 15 升计入所在段');
      expect(segments.first.costCents, 28000);
      // 行内本段油耗 = 本段 35 升 ÷ 500 km × 100 = 7.0（与均值同源公式）。
      expect(segments.first.consumptionPer100Km, closeTo(7.0, 1e-9));
      // 平均油耗 = 35 升 ÷ 500 km × 100 = 7.0（浮点累计误差用 closeTo）。
      expect(
        FuelRules.averageFuelConsumptionPer100Km(segments),
        closeTo(7.0, 1e-9),
      );
      // 每公里油费 = 280 元 ÷ 500 km = 0.56 元/km。
      expect(FuelRules.averageCostPerKm(segments), 0.56);
    });

    test('首条记录非满箱：不产生锚点，其后的满箱仍是首锚点不出段', () {
      final segments = FuelRules.fuelTankSegments([
        record('2026-05-01', mileageKm: 10000, fullTank: false),
        record('2026-05-10', mileageKm: 10500),
      ]);
      expect(segments, isEmpty, reason: '首个满箱之前的部分加油不进入任何段');
    });

    test('段里程非增（同里程/倒退）折叠为无效段，不计入均值', () {
      final segments = FuelRules.fuelTankSegments([
        record('2026-05-01', mileageKm: 10000),
        // 同日同里程补录的"加满"：段里程 = 0，折叠。
        record('2026-05-01', mileageKm: 10000, volumeLiters: 30),
        // 里程倒退的补录：段里程 < 0，折叠。
        record('2026-05-02', mileageKm: 9900, volumeLiters: 30),
        // 正常前行的第三次加满：对上一锚点（倒退那条）是 +600，有效。
        record('2026-05-10', mileageKm: 10500, volumeLiters: 30),
      ]);
      expect(segments, hasLength(1), reason: '只有最后一段有效');
      expect(segments.first.km, 600);
      expect(segments.first.liters, 30, reason: '锚点切换后累计清零重启');
      // 均值只用有效段：30 ÷ 600 × 100 = 5.0。
      expect(FuelRules.averageFuelConsumptionPer100Km(segments), 5.0);
    });

    test('输入乱序时按（日期、里程、id）升序内部重排', () {
      final segments = FuelRules.fuelTankSegments([
        record('2026-05-10', mileageKm: 10500, volumeLiters: 20,
            totalCostCents: 16000),
        record('2026-05-01', mileageKm: 10000),
      ]);
      expect(segments, hasLength(1));
      expect(segments.first.km, 500, reason: '按日期排序后锚点在前');
    });

    test('多条满箱链：逐段闭合，均值按全段求和', () {
      final segments = FuelRules.fuelTankSegments([
        record('2026-05-01', mileageKm: 10000),
        record('2026-05-10', mileageKm: 10500, volumeLiters: 30,
            totalCostCents: 25000),
        record('2026-05-20', mileageKm: 11000, volumeLiters: 32,
            totalCostCents: 26000),
      ]);
      expect(segments, hasLength(2));
      expect(segments[0].km, 500);
      expect(segments[1].km, 500);
      // 均值 = (30+32) ÷ (500+500) × 100 = 6.2。
      expect(FuelRules.averageFuelConsumptionPer100Km(segments), closeTo(6.2, 1e-9));
      // 每公里 = (250+260) ÷ 1000 = 0.51 元。
      expect(FuelRules.averageCostPerKm(segments), 0.51);
    });
  });
}
