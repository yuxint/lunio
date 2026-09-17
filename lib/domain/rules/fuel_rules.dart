// 加油预测的业务规则（≈ Java 里的计算/校验工具类，纯函数可测试）。
//
// 覆盖三块：
//  1. 加满金额与所需油量的计算（分=cent 存 int，避免浮点累加误差）；
//  2. 档位表（100% 到 0% 每 2% 一档，滚动定档用，见 CONTEXT.md"档位"）；
//  3. 油价缓存"该不该重新拉"的判断（10 个自然日规则，见 ADR 0001）。
//  4. 油箱容积校验（容积在 Car 上，写库/恢复备份前调用）。
//  5. 预估下次油价（调价预告变动中值参与计算，见 ADR 0006）。
//  6. 加油记录的满箱段油耗口径（full-to-full，见 ADR 0014 与
//     CONTEXT.md"满箱段"词条）。
import '../../core/date/local_date.dart';
import '../entities/fuel_price.dart';
import '../entities/fuel_record.dart';

/// 一个满箱段（full-to-full）：从锚点（上一次加满）到闭合条（这一次
/// 加满）之间的计算区间。段数据只含聚合值，不持有实体引用，行内
/// "本段油耗"按 [closingRecordId] 挂到对应记录行。
///
/// [FuelRules.fuelTankSegments] 返回的都是有效段：段里程 > 0 才会产出
/// （里程非增的段折叠为空，不进结果），因此平均值直接对返回列表求和。
class FuelTankSegment {
  const FuelTankSegment({
    required this.closingRecordId,
    required this.liters,
    required this.km,
    required this.costCents,
  });

  /// 闭合该段的加油记录 id（这次加满的那条）。
  final int closingRecordId;

  /// 段升数 = 锚点之后至闭合条（含）的升数之和——部分加油（没加满）
  /// 的升数计入所在段，但不闭合段。
  final double liters;

  /// 段里程 = 闭合条里程 − 锚点里程（恒 > 0，非正的段已折叠）。
  final int km;

  /// 段金额（分），口径与 [liters] 相同（锚点后至闭合条含）。
  final int costCents;

  /// 本段百公里油耗（L/100km）= 段升数 ÷ 段里程 × 100。行内"本段
  /// 油耗"与摘要行平均油耗（[FuelRules.averageFuelConsumptionPer100Km]）
  /// 是"单段 / 多段聚合"两级，公式同源。
  double get consumptionPer100Km => liters / km * 100;
}

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
  /// （缓存是当前省份的单省价表，换省由控制器按省份不匹配另行处理，
  /// 见 docs/adr/0011。）
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

  /// 调价预告是否已过期（ADR 0011 修订，2026-09-12）：调价日早于
  /// [today] 即过期，按无预告处理（"预估下次油价"块与"调价后价格"
  /// 列都回落到占位）。调价发生在预告日 24 时（当天末尾），预告日
  /// 当天价格未变，仍算有效。
  ///
  /// 预告原文只有月/日没有年份；调价窗口约 10 个工作日（≤16 自然日），
  /// 预告日只可能在今天前后一个月内，按"离今天最近的同月日"定年——
  /// 跨年缓存（今天 1 月、缓存里"12月28日"）自然落到去年判过期，
  /// 反之 12 月底读到"1月5日"的预告落到明年判有效。
  static bool isForecastExpired({
    required FuelAdjustmentForecast forecast,
    required LocalDate today,
  }) {
    final todayDate = DateTime(today.year, today.month, today.day);
    DateTime candidateFor(int year) =>
        DateTime(year, forecast.month, forecast.day);
    var nearest = candidateFor(today.year);
    for (final year in [today.year - 1, today.year + 1]) {
      final candidate = candidateFor(year);
      if (candidate.difference(todayDate).abs() <
          nearest.difference(todayDate).abs()) {
        nearest = candidate;
      }
    }
    return nearest.isBefore(todayDate);
  }

  // ---------------- 加油记录的满箱段油耗（ADR 0014） ----------------

  /// 满箱段划分（full-to-full 口径，ADR 0014）：
  ///
  ///  - 输入须是已入库的记录（id 非空，排序与段闭合都要用）；
  ///  - 内部按（日期、里程、id）升序重排（与仓库列表查询的固定排序
  ///    一致，不依赖调用方先排序）；
  ///  - 一条记录"闭合一段"当且仅当它加满且存在更早的满箱记录（锚点）；
  ///    首条满箱只做锚点不闭合段；
  ///  - 段里程 ≤ 0（补录乱序、同日里程相同等）视为该段无效，折叠为空
  ///    ——不出负数油耗，也不参与平均值；
  ///  - 非满箱记录只贡献升数/金额，永不闭合段。
  static List<FuelTankSegment> fuelTankSegments(List<FuelRecord> records) {
    final ordered = [...records]..sort((left, right) {
      final byDate = left.date.compareTo(right.date);
      if (byDate != 0) {
        return byDate;
      }
      final byMileage = left.mileageKm.compareTo(right.mileageKm);
      if (byMileage != 0) {
        return byMileage;
      }
      return left.id!.compareTo(right.id!);
    });
    final segments = <FuelTankSegment>[];
    // 当前锚点（上一次加满的记录）；null = 还没见过满箱（首条满箱前）。
    FuelRecord? anchor;
    // 锚点之后至当前记录（含）的累计升数/金额：遇到锚点清零重启。
    var litersSinceAnchor = 0.0;
    var costSinceAnchor = 0;
    for (final record in ordered) {
      litersSinceAnchor += record.volumeLiters;
      costSinceAnchor += record.totalCostCents;
      if (!record.fullTank) {
        continue;
      }
      if (anchor != null) {
        final km = record.mileageKm - anchor.mileageKm;
        if (km > 0) {
          segments.add(
            FuelTankSegment(
              closingRecordId: record.id!,
              liters: litersSinceAnchor,
              km: km,
              costCents: costSinceAnchor,
            ),
          );
        }
      }
      // 无论是否闭合，加满的记录都成为下一段的锚点，累计值清零重启。
      anchor = record;
      litersSinceAnchor = 0;
      costSinceAnchor = 0;
    }
    return segments;
  }

  /// 平均百公里油耗（L/100km）= 有效段升数和 ÷ 有效段里程和 × 100。
  /// 无有效段返回 null（调用方不显示摘要行）。
  static double? averageFuelConsumptionPer100Km(
    List<FuelTankSegment> segments,
  ) {
    if (segments.isEmpty) {
      return null;
    }
    final totalLiters = segments.fold<double>(0, (sum, s) => sum + s.liters);
    final totalKm = segments.fold<int>(0, (sum, s) => sum + s.km);
    if (totalKm <= 0) {
      return null;
    }
    return totalLiters / totalKm * 100;
  }

  /// 平均每公里油费（元）= 有效段金额和 ÷ 有效段里程和，换算成元。
  /// 无有效段返回 null。与油耗同口径（分→元除以 100）。
  static double? averageCostPerKm(List<FuelTankSegment> segments) {
    if (segments.isEmpty) {
      return null;
    }
    final totalCostCents = segments.fold<int>(0, (sum, s) => sum + s.costCents);
    final totalKm = segments.fold<int>(0, (sum, s) => sum + s.km);
    if (totalKm <= 0) {
      return null;
    }
    return totalCostCents / totalKm / 100;
  }
}
