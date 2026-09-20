// 花费统计组装层（cost_stats.dart）：记录页头部"今年花费"汇总行与
// 独立统计页（/cost-stats）共用的聚合口径。
//
// 职责：输入全量保养记录 + 项目清单 + 生效今天，输出总花费、今年花费、
// 按年横条、项目占比 Top N、近 12 个月走势、优惠分摊六份视图模型。与
// record_rows.dart 同构（features 层纯函数组装，无 provider、无副作用）；
// 统计页的数据接缝（按作用域拉记录/项目）在 cost_stats_page.dart，
// 本文件只管"拿到数据后怎么算"。
// Java 类比：一个无状态聚合工具类（静态方法入参出参全是值对象），
// widget 只是渲染皮。
//
// 口径（spec 拍板，与 ADR 0010 的软提示模型一致）：
//  - 总额/年度/月度一律用记录总费用 costCents（权威值，实体必填）；
//    与项目费用合计不一致时仍按总费用算，不做读时修正；
//  - 项目占比＝项目费用 ?? 材料+工时（缺失的一边按 0），三项全缺跳过
//    该行——未填不按 0 计，占比不失真也不虚增；
//  - 项目占比按"项目名"聚合（经项目清单解析，查不到归"未知项目"），
//    多车"全部"作用域下不同车的同名项目自然合并成一类；
//  - 优惠分摊（2026-09-20）：记录级总优惠 = Σ计费值 − 记录总费用
//    （负差值 = 无优惠，按 0 计；没有任何计费值的记录 Σ=0 差值必 ≤ 0，
//    自然不参与，无需特判），按各项目计费值权重摊到项目，最大余数法
//    取整保证分摊合计与总优惠严格相等。纯读时派生，不改存储值。
//
// 本文件全部是纯函数与纯数据，无写库、无副作用，可直接单测。

import '../../../core/date/local_date.dart';
import '../../../domain/entities/maintenance_item.dart';
import '../../../domain/entities/maintenance_record.dart';
import '../shared/shell_shared.dart';

/// 项目占比排行榜长度（Top N 的 N）。
const costStatsTopItemCount = 5;

/// 近 12 个月走势的窗口长度（含当月）。
const costStatsMonthWindow = 12;

/// 某一年花费合计（记录总费用权威值逐条求和）。
/// 记录页"今年花费"汇总行与年度分组共用这一个口径。
int costCentsForYear(List<MaintenanceRecord> records, int year) {
  var total = 0;
  for (final record in records) {
    if (record.date.year == year) {
      total += record.costCents;
    }
  }
  return total;
}

/// 年度横条：年份 + 花费 + 条宽比例（相对最大年，0~1，自绘横条用）。
class CostYearBar {
  const CostYearBar({
    required this.year,
    required this.costCents,
    required this.fraction,
  });

  final int year;
  final int costCents;

  /// 条宽比例：本年花费 ÷ 最大年花费（花费为 0 时为 0）。
  final double fraction;
}

/// 项目占比行：项目名 + 花费 + 占比 + 条宽比例 + 分摊优惠/实付。
class CostItemShareRow {
  const CostItemShareRow({
    required this.name,
    required this.costCents,
    required this.share,
    required this.fraction,
    required this.discountCents,
    required this.actualCents,
  });

  final String name;
  final int costCents;

  /// 占比：本项目花费 ÷ 项目口径总花费（分母含未进 Top N 的项目，
  /// 0~1；分母为 0 时为 0）。
  final double share;

  /// 条宽比例：本项目花费 ÷ Top 内最大花费（0~1）。
  final double fraction;

  /// 分摊优惠（分）：本项目名聚合到的优惠之和（优惠分摊口径见文件头），
  /// 恒 ≤ [costCents]（单条记录内分摊不会超过该项目计费值）。
  final int discountCents;

  /// 实付（分）= [costCents] − [discountCents]。
  final int actualCents;
}

/// 月度走势点：年 + 月 + 花费 + 条高比例（相对峰值月，0~1）。
class CostMonthPoint {
  const CostMonthPoint({
    required this.year,
    required this.month,
    required this.costCents,
    required this.fraction,
  });

  final int year;
  final int month;
  final int costCents;

  /// 条高比例：本月花费 ÷ 窗口内峰值月花费（0~1）。
  final double fraction;
}

/// 花费统计聚合结果（一次算齐的只读视图模型，渲染层直接消费）。
class CostStats {
  const CostStats({
    required this.totalCents,
    required this.thisYearCents,
    required this.years,
    required this.topItems,
    required this.months,
    required this.totalDiscountCents,
    required this.itemsActualCents,
    required this.itemTotalCents,
  });

  /// 总花费（全部记录总费用之和）。
  final int totalCents;

  /// 今年（生效今天所在年）花费。
  final int thisYearCents;

  /// 按年横条（年份升序）。
  final List<CostYearBar> years;

  /// 项目占比 Top N（花费降序，最多 [costStatsTopItemCount] 行）。
  final List<CostItemShareRow> topItems;

  /// 近 12 个月走势（旧 → 新，含当月，固定 [costStatsMonthWindow] 个点）。
  final List<CostMonthPoint> months;

  /// 累计优惠（分）：所有参与记录分摊到项目上的优惠之和（0 = 无优惠）。
  final int totalDiscountCents;

  /// 项目口径实付合计（分）= [itemTotalCents] − [totalDiscountCents]。
  /// 环形图环心的金额用它；与记录总费用口径（[totalCents]）不同源，
  /// 展示时不要混用。
  final int itemsActualCents;

  /// 项目口径计费值合计（分），项目占比的分母（含未进 Top N 的项目）。
  final int itemTotalCents;
}

/// 单条项目费用行的计费值：项目费用优先，缺则材料+工时（缺失一边按 0），
/// 三项全缺返回 null（调用方跳过该行）。这是"项目占比"口径的唯一实现点。
int? itemCostValue(RecordItemCost cost) {
  if (cost.costCents != null) {
    return cost.costCents;
  }
  if (cost.materialCents != null || cost.laborCents != null) {
    return (cost.materialCents ?? 0) + (cost.laborCents ?? 0);
  }
  return null;
}

/// 把一笔记录级优惠按权重（各项目计费值占比）分摊并累计进
/// [discountByName]。最大余数法：先按比例向下取整，再把剩余的分数
/// 逐分给小数部分最大的项目（平局按传入顺序，保证可复现）——分摊
/// 合计与总优惠严格相等，不留一分钱差额。每项分摊 ≤ 该项计费值
/// （优惠 ≤ 计费值合计，取整后 ≤ 向上取整 ≤ 计费值）。纯函数。
void allocateDiscount(
  List<MapEntry<String, int>> entries,
  int discount,
  Map<String, int> discountByName,
) {
  final valueSum = entries.fold(0, (sum, entry) => sum + entry.value);
  if (valueSum <= 0) {
    return; // 权重全 0 无从分摊（当前口径下不可达，防御性兜底）。
  }
  final floors = <int>[];
  final remainders = <int>[];
  var allocated = 0;
  for (final entry in entries) {
    final exact = entry.value * discount / valueSum;
    final floor = exact.floor();
    floors.add(floor);
    // 小数部分放大成整数便于精确比较（分摊精度到分，1e9 足够）。
    remainders.add(((exact - floor) * 1000000000).round());
    allocated += floor;
  }
  // Σexact = discount，所以剩余分数 = discount − Σfloor < 项目数。
  var left = discount - allocated;
  final order = List<int>.generate(entries.length, (index) => index)
    ..sort((a, b) => remainders[b].compareTo(remainders[a]));
  for (var index = 0; index < order.length && left > 0; index++) {
    floors[order[index]] += 1;
    left -= 1;
  }
  for (var index = 0; index < entries.length; index++) {
    final name = entries[index].key;
    discountByName[name] = (discountByName[name] ?? 0) + floors[index];
  }
}

/// 花费统计聚合唯一入口：全量记录 + 项目清单 + 生效今天 → 完整视图模型。
/// 纯函数，不感知作用域——调用方传哪份记录就算哪份（单车/全部由上游
/// 数据接缝决定）。空记录返回全 0 与空列表（页面据此渲染空态）。
CostStats buildCostStats({
  required List<MaintenanceRecord> records,
  required List<MaintenanceItem> items,
  required LocalDate today,
  int topItemCount = costStatsTopItemCount,
}) {
  final totalCents = records.fold(0, (sum, record) => sum + record.costCents);

  // 按年分组（年份升序）；条宽相对最大年。
  final centsByYear = <int, int>{};
  for (final record in records) {
    centsByYear[record.date.year] =
        (centsByYear[record.date.year] ?? 0) + record.costCents;
  }
  final maxYearCents =
      centsByYear.values.fold(0, (max, cents) => cents > max ? cents : max);
  final years = [
    for (final year in (centsByYear.keys.toList()..sort()))
      CostYearBar(
        year: year,
        costCents: centsByYear[year]!,
        fraction: maxYearCents == 0 ? 0.0 : centsByYear[year]! / maxYearCents,
      ),
  ];

  // 项目占比 + 优惠分摊：按解析出的项目名聚合计费值（口径见
  // itemCostValue）。优惠按记录逐条分摊后累计到项目名上。
  final centsByName = <String, int>{};
  final discountByName = <String, int>{};
  for (final record in records) {
    final entries = <MapEntry<String, int>>[];
    for (final cost in record.itemCosts) {
      final value = itemCostValue(cost);
      if (value == null) {
        continue;
      }
      final name = itemById(items, cost.itemId)?.name ?? '未知项目';
      centsByName[name] = (centsByName[name] ?? 0) + value;
      entries.add(MapEntry(name, value));
    }
    if (entries.isEmpty) {
      continue;
    }
    final valueSum = entries.fold(0, (sum, entry) => sum + entry.value);
    // 总优惠 = Σ计费值 − 记录总费用；负差值（总费用更高）= 无优惠。
    // 没有任何计费值的记录在上面 continue——"简洁模式记录不参与"
    // 由这两条口径自然成立，无需特判。
    final discount = valueSum - record.costCents;
    if (discount <= 0) {
      continue;
    }
    allocateDiscount(entries, discount, discountByName);
  }
  final totalDiscountCents = discountByName.values
      .fold(0, (sum, cents) => sum + cents);
  final itemTotalCents =
      centsByName.values.fold(0, (sum, cents) => sum + cents);
  final namesByCents = centsByName.keys.toList()
    ..sort((left, right) {
      final byCents = centsByName[right]!.compareTo(centsByName[left]!);
      // 花费相同按名称稳定排序，保证 Top N 截断结果可复现。
      return byCents != 0 ? byCents : left.compareTo(right);
    });
  final maxItemCents =
      namesByCents.isEmpty ? 0 : centsByName[namesByCents.first]!;
  final topItems = [
    for (final name in namesByCents.take(topItemCount))
      CostItemShareRow(
        name: name,
        costCents: centsByName[name]!,
        share: itemTotalCents == 0 ? 0.0 : centsByName[name]! / itemTotalCents,
        fraction:
            maxItemCents == 0 ? 0.0 : centsByName[name]! / maxItemCents,
        discountCents: discountByName[name] ?? 0,
        actualCents: centsByName[name]! - (discountByName[name] ?? 0),
      ),
  ];

  // 近 12 个月走势：窗口 = 含当月往前推 11 个月（旧 → 新，固定 12 个点，
  // 无记录的月补 0，保证横轴月份连续）。月份 key = 年*12+(月-1)。
  final startMonth = LocalDate(today.year, today.month, 1)
      .addMonths(-(costStatsMonthWindow - 1));
  final startKey = startMonth.year * 12 + startMonth.month - 1;
  final centsByMonthKey = <int, int>{};
  for (final record in records) {
    final key = record.date.year * 12 + record.date.month - 1;
    if (key >= startKey && key < startKey + costStatsMonthWindow) {
      centsByMonthKey[key] = (centsByMonthKey[key] ?? 0) + record.costCents;
    }
  }
  final maxMonthCents = centsByMonthKey.values
      .fold(0, (max, cents) => cents > max ? cents : max);
  final months = [
    for (var offset = 0; offset < costStatsMonthWindow; offset++)
      CostMonthPoint(
        year: (startKey + offset) ~/ 12,
        month: (startKey + offset) % 12 + 1,
        costCents: centsByMonthKey[startKey + offset] ?? 0,
        fraction: maxMonthCents == 0
            ? 0.0
            : (centsByMonthKey[startKey + offset] ?? 0) / maxMonthCents,
      ),
  ];

  return CostStats(
    totalCents: totalCents,
    thisYearCents: costCentsForYear(records, today.year),
    years: years,
    topItems: topItems,
    months: months,
    totalDiscountCents: totalDiscountCents,
    itemsActualCents: itemTotalCents - totalDiscountCents,
    itemTotalCents: itemTotalCents,
  );
}
