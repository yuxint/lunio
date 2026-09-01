// 加油预测的业务规则（≈ Java 里的计算/校验工具类，纯函数可测试）。
//
// 覆盖三块：
//  1. 加满金额与所需油量的计算（分=cent 存 int，避免浮点累加误差）；
//  2. 档位表（100% 到 0% 每 2% 一档，滚动定档用，见 CONTEXT.md"档位"）；
//  3. 油价缓存"该不该重新拉"的判断（10 个自然日规则，见 ADR 0001）。
//  4. 油箱容积校验（容积在 Car 上，写库/恢复备份前调用）。
//  5. 预估下次油价（调价预告变动中值参与计算，见 ADR 0006）。
import '../entities/fuel_price.dart';

class FuelRules {
  FuelRules._();

  /// 剩余油量的档位步进（%）。
  static const int percentStep = 2;

  /// 油价缓存的"新鲜期"（自然日）。距上次成功拉取超过该天数就重新拉。
  /// 真实调价窗口是 10 个工作日，这里放宽到 10 个自然日，
  /// 宁可多拉一两次也不让缓存过期没发现。
  static const int priceRefreshDays = 10;

  /// 全量档位表：100% 到 0% 每 [percentStep] 一档，共 51 档。
  /// 加满预估列表按它渲染；列表第一行停在哪档，剩余油量就是哪档。
  static List<int> get allTierPercents => [
    for (var percent = 100; percent >= 0; percent -= percentStep) percent,
  ];

  /// 油箱容积校验（Car.tankCapacityLiters，写库/恢复备份前调用）：
  /// null 合法（未填写）；有值时 1–999 升，最多四位小数。
  /// （小数位数判定：放大 10000 倍取整再回除，能还原说明小数不超过 4 位；
  /// 直接比较乘积会有浮点误差，如 55.1 × 10000 不精确等于 551000。）
  static void validateTankCapacity(double? liters) {
    if (liters == null) {
      return;
    }
    if (liters < 1 || liters > 999) {
      throw ArgumentError.value(
        liters,
        'tankCapacityLiters',
        'must be between 1 and 999',
      );
    }
    if ((liters * 10000).roundToDouble() / 10000 != liters) {
      throw ArgumentError.value(
        liters,
        'tankCapacityLiters',
        'at most four decimal places',
      );
    }
  }

  /// 需要加的油量（升）=（100 − 剩余油量）÷ 100 × 油箱容积。
  static double litersToFill({
    required int fuelPercent,
    required double tankCapacityLiters,
  }) {
    return (100 - fuelPercent) / 100 * tankCapacityLiters;
  }

  /// 油箱里当前的油量（升）= 剩余油量 ÷ 100 × 油箱容积。
  /// 加满预估表头"当前油量"列的取值，与 [litersToFill] 互补。
  static double litersInTank({
    required int fuelPercent,
    required double tankCapacityLiters,
  }) {
    return fuelPercent / 100 * tankCapacityLiters;
  }

  /// 加满金额（分）= 油量 × 每升价 × 100，四舍五入到分。
  /// 用 int 分承载金额，与保养记录 costCents 的约定一致。
  static int fullTankCostCents({
    required int fuelPercent,
    required double tankCapacityLiters,
    required double pricePerLiter,
  }) {
    return (litersToFill(
              fuelPercent: fuelPercent,
              tankCapacityLiters: tankCapacityLiters,
            ) *
            pricePerLiter *
            100)
        .round();
  }

  /// 油价缓存是否需要重新拉取：没有缓存，或距上次拉取超过
  /// [priceRefreshDays] 个自然日，都算需要。
  /// （缓存是全国价表，换省不用重新拉，见 docs/adr/0006。）
  static bool shouldRefreshFuelPrices({
    required DateTime? lastFetchedAt,
    required DateTime now,
  }) {
    if (lastFetchedAt == null) {
      return true;
    }
    return now.difference(lastFetchedAt).inDays >= priceRefreshDays;
  }

  /// 预估调价后每升价 = 当前生效价 + 涨跌方向 × 变动中值，
  /// 四舍五入到分。"调价后价格"列与"预估下次油价"块都基于它，
  /// 先取整到分保证两处展示一致。
  static double predictedPricePerLiter({
    required double currentPricePerLiter,
    required FuelAdjustmentForecast forecast,
  }) {
    final signedChange = forecast.trend == FuelPriceTrend.up
        ? forecast.midChangePerLiter
        : -forecast.midChangePerLiter;
    final predicted = currentPricePerLiter + signedChange;
    return (predicted * 100).round() / 100;
  }
}
