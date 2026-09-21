// 费用统计组装层（cost_stats.dart）：记录页头部"今年费用"汇总行与
// 独立统计页（/cost-stats）共用的聚合口径。
//
// 职责：输入全量保养记录 + 项目清单 + 生效今天，输出总费用、今年费用、
// 年度走势、项目占比（含"其他"段）、汇总指标五份视图模型。与
// record_rows.dart 同构（features 层纯函数组装，无 provider、无副作用）；
// 统计页的数据接缝（按作用域拉记录/项目）在 cost_stats_page.dart，
// 本文件只管"拿到数据后怎么算"。
// Java 类比：一个无状态聚合工具类（静态方法入参出参全是值对象），
// widget 只是渲染皮。
//
// 口径（spec 拍板，与 ADR 0010 的软提示模型一致）：
//  - 总额/年度/月度一律用记录总费用 costCents（权威值，实体必填）；
//    与项目费用合计不一致时仍按总费用算，不做读时修正；
//  - 项目计费值＝项目费用（没填则该项目不参与统计）。材料费/工时费
//    不参与读侧口径——"材料/工时任一有值 ⇒ 项目费用必有值"的数据
//    不变量由写点的 normalizeItemCost 共同保证（2026-09-21 拍板删除
//    读侧兜底分支，口径唯一）；
//  - 项目占比按"项目名"聚合（经项目清单解析，查不到归"未知项目"），
//    列出全部项目不截断，按实付从多到少排；
//  - 优惠分摊：记录级总优惠 = Σ项目费用 − 记录总费用（负差值 = 无
//    优惠，按 0 计；没有任何项目费用的记录 Σ=0 差值必 ≤ 0，自然不
//    参与，无需特判），按各项目费用权重摊到项目，最大余数法取整保证
//    分摊合计与总优惠严格相等。纯读时派生，不改存储值；
//  - 守恒（2026-09-21）：总费用 ≡ Σ项目实付 + 其他段。其他段吸收
//    无法归属到项目的钱——简洁模式记录（没填项目费用）的全部费用 +
//    单条记录"总费用超出项目费用合计"的差额——保证汇总卡总费用与
//    占比卡各行相加永远相等，不再出现"总花费 ≠ 项目实付"的口径缺口。
//
// 本文件全部是纯函数与纯数据，无写库、无副作用，可直接单测。

import '../../../core/date/local_date.dart';
import '../../../domain/entities/maintenance_item.dart';
import '../../../domain/entities/maintenance_record.dart';
import '../shared/shell_shared.dart';

/// 某一年费用合计（记录总费用权威值逐条求和）。
/// 记录页"今年费用"汇总行与年度分组共用这一个口径。
int costCentsForYear(List<MaintenanceRecord> records, int year) {
  var total = 0;
  for (final record in records) {
    if (record.date.year == year) {
      total += record.costCents;
    }
  }
  return total;
}

/// 年度走势点：年份 + 该年总费用 + 条高比例（相对峰值年，0~1）。
class CostYearPoint {
  const CostYearPoint({
    required this.year,
    required this.costCents,
    required this.fraction,
  });

  final int year;
  final int costCents;

  /// 条高比例：本年费用 ÷ 峰值年费用（费用为 0 时为 0）。
  final double fraction;
}

/// 项目占比行：项目名 + 计费值 + 分摊优惠/实付 + 条宽比例。
class CostItemShareRow {
  const CostItemShareRow({
    required this.name,
    required this.costCents,
    required this.discountCents,
    required this.actualCents,
    required this.fraction,
  });

  final String name;

  /// 计费值（项目口径，口径见 [itemCostValue]）。
  final int costCents;

  /// 分摊优惠（分）：本项目名聚合到的优惠之和（优惠分摊口径见文件头），
  /// 恒 ≤ [costCents]（单条记录内分摊不会超过该项目费用）。
  final int discountCents;

  /// 实付（分）= [costCents] − [discountCents]。
  final int actualCents;

  /// 条宽比例：本项目实付 ÷ 全部行（含"其他"段）最大实付（0~1），
  /// 同一把尺子保证各行条宽可比、"其他"条不越界。
  final double fraction;
}

/// 费用统计聚合结果（一次算齐的只读视图模型，渲染层直接消费）。
class CostStats {
  const CostStats({
    required this.totalCents,
    required this.thisYearCents,
    required this.years,
    required this.topItems,
    required this.otherCents,
    required this.totalDiscountCents,
    required this.recordCount,
    required this.thisYearRecordCount,
    required this.avgPerVisitCents,
    required this.monthlyAvgCents,
    required this.lastRecordDate,
  });

  /// 总费用（全部记录总费用之和）。守恒锚点：Σ[topItems] 实付 +
  /// [otherCents] 恒等于此值。
  final int totalCents;

  /// 今年（生效今天所在年）费用。
  final int thisYearCents;

  /// 年度走势点（首条记录年 → 今年，年份升序，中间无记录年补 0
  /// 保证横轴连续；无记录时为空——单年车由页面整卡隐藏走势）。
  final List<CostYearPoint> years;

  /// 项目占比行（全部项目不截断，实付降序，平局按名称稳定排序）。
  final List<CostItemShareRow> topItems;

  /// 其他段（分）：无项目可归属的费用——简洁模式记录的全部费用 +
  /// 单条记录"总费用超出项目费用合计"的差额（0 = 无缺口，页面不渲染）。
  final int otherCents;

  /// 累计优惠（分）：所有参与记录分摊到项目上的优惠之和（0 = 无优惠）。
  final int totalDiscountCents;

  /// 保养记录总条数（不看费用是否填写）。
  final int recordCount;

  /// 今年（生效今天所在年）记录条数。
  final int thisYearRecordCount;

  /// 单次平均费用（分）= 总费用 ÷ 记录条数（记录总费用口径；
  /// 无记录时为 0）。
  final int avgPerVisitCents;

  /// 月均（分）= 总费用 ÷ 自然月跨度（首条记录月 → 当月，含首尾与
  /// 中间无记录月，全程摊薄；2026-09-21 拍板不随任何图表切换联动）。
  /// 无记录时为 0。
  final int monthlyAvgCents;

  /// 最后一条保养记录的日期（无记录时为 null）。「上次保养距今」用。
  final LocalDate? lastRecordDate;
}

/// 项目计费值：参与费用统计的金额 = 项目费用；没填返回 null（该项目
/// 不参与统计）。材料费/工时费不做读侧兜底——"材料/工时任一有值 ⇒
/// 项目费用必有值"的不变量由写点的 normalizeItemCost 保证（2026-09-21
/// 拍板删除兜底分支）。这是项目占比、优惠分摊、项目档案共用的唯一
/// 口径实现点。
int? itemCostValue(RecordItemCost cost) => cost.costCents;

/// 把一笔记录级优惠按权重（各项目费用占比）分摊，返回每项的分摊
/// 优惠。最大余数法：先按比例向下取整，再把剩余的分数逐分给小数部分
/// 最大的项（平局按传入顺序，保证可复现）——分摊合计与 [discount]
/// 严格相等，不留一分钱差额。每项分摊 ≤ 该项费用（优惠 ≤ 费用
/// 合计，取整后 ≤ 向上取整 ≤ 费用）。纯函数；K 由调用方选（项目名
/// 或项目 id）。
Map<K, int> allocateDiscount<K>(
  List<MapEntry<K, int>> entries,
  int discount,
) {
  final result = <K, int>{
    for (final entry in entries) entry.key: 0,
  };
  final valueSum = entries.fold(0, (sum, entry) => sum + entry.value);
  if (valueSum <= 0 || discount <= 0) {
    return result; // 权重全 0 无从分摊（当前口径下不可达，防御性兜底）。
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
    result[entries[index].key] = floors[index];
  }
  return result;
}

/// 项目档案里的单次明细：日期、里程、计费值、分摊优惠、实付。
class CostItemHistoryEntry {
  const CostItemHistoryEntry({
    required this.date,
    required this.mileageKm,
    required this.valueCents,
    required this.discountCents,
    required this.actualCents,
  });

  final LocalDate date;
  final int mileageKm;

  /// 该次该项目的计费值（项目口径，同 [itemCostValue]）。
  final int valueCents;

  /// 该次记录的总优惠分摊到本项目的部分（0 = 该次无优惠）。
  final int discountCents;

  /// 实付 = [valueCents] − [discountCents]。
  final int actualCents;
}

/// 单个保养项目的档案：累计计费值/实付/优惠、次数、单次均价、逐次明细
/// （日期倒序）。「项目占比 → 点项目 → 项目档案 sheet」的数据源。
class CostItemHistory {
  const CostItemHistory({
    required this.name,
    required this.entries,
    required this.totalValueCents,
    required this.totalActualCents,
    required this.totalDiscountCents,
  });

  final String name;

  /// 逐次明细（日期倒序；只含有计费值的次数——费用全空的记录无从
  /// 计算金额，不进档案）。
  final List<CostItemHistoryEntry> entries;

  /// 累计计费值（分）。
  final int totalValueCents;

  /// 累计实付（分）= [totalValueCents] − [totalDiscountCents]。
  final int totalActualCents;

  /// 累计分摊优惠（分）。
  final int totalDiscountCents;

  /// 次数（= [entries].length，有计费值的次数）。
  int get count => entries.length;

  /// 单次均价（分）= 累计实付 ÷ 次数（次数为 0 时为 0）。
  int get avgActualCents =>
      count == 0 ? 0 : (totalActualCents / count).round();
}

/// 项目档案聚合唯一入口：逐条记录跑与 [buildCostStats] 同一套优惠分摊
/// （保证档案里的分摊数字与占比卡一致），按项目 id 收单次明细后按日期
/// 倒序。纯函数。
List<CostItemHistory> buildItemHistories(
  List<MaintenanceRecord> records,
  List<MaintenanceItem> items,
) {
  // itemId → 聚合累加器。
  final entriesByItem = <int, List<CostItemHistoryEntry>>{};
  final valueByItem = <int, int>{};
  final discountByItem = <int, int>{};
  for (final record in records) {
    final namedEntries = <MapEntry<int, int>>[];
    for (final cost in record.itemCosts) {
      final value = itemCostValue(cost);
      if (value == null) {
        continue;
      }
      namedEntries.add(MapEntry(cost.itemId, value));
    }
    if (namedEntries.isEmpty) {
      continue;
    }
    // 该记录的优惠分摊（与占比卡同口径，按项目 id 直接分摊）。
    final valueSum =
        namedEntries.fold(0, (sum, entry) => sum + entry.value);
    final discount = valueSum - record.costCents;
    final discountByItemId =
        discount > 0 ? allocateDiscount(namedEntries, discount) : null;
    for (final entry in namedEntries) {
      final itemDiscount = discountByItemId?[entry.key] ?? 0;
      entriesByItem
          .putIfAbsent(entry.key, () => [])
          .add(
            CostItemHistoryEntry(
              date: record.date,
              mileageKm: record.mileageKm,
              valueCents: entry.value,
              discountCents: itemDiscount,
              actualCents: entry.value - itemDiscount,
            ),
          );
      valueByItem[entry.key] = (valueByItem[entry.key] ?? 0) + entry.value;
      discountByItem[entry.key] =
          (discountByItem[entry.key] ?? 0) + itemDiscount;
    }
  }
  final histories = <CostItemHistory>[];
  for (final itemId in entriesByItem.keys) {
    final entries = entriesByItem[itemId]!
      ..sort((a, b) {
        final byDate = _dateKey(b.date).compareTo(_dateKey(a.date));
        // 同日多条（同车同日唯一约束在记录级，这里防御性按里程倒序）。
        return byDate != 0 ? byDate : b.mileageKm.compareTo(a.mileageKm);
      });
    histories.add(
      CostItemHistory(
        name: itemById(items, itemId)?.name ?? '未知项目',
        entries: entries,
        totalValueCents: valueByItem[itemId] ?? 0,
        totalDiscountCents: discountByItem[itemId] ?? 0,
        totalActualCents:
            (valueByItem[itemId] ?? 0) - (discountByItem[itemId] ?? 0),
      ),
    );
  }
  // 累计计费值降序（与项目占比排序同向），保证档案列表可复现。
  histories.sort((a, b) => b.totalValueCents.compareTo(a.totalValueCents));
  return histories;
}

/// LocalDate → 可比较整数键（年*10000+月*100+日），免依赖实体比较接口。
int _dateKey(LocalDate date) =>
    date.year * 10000 + date.month * 100 + date.day;

/// 费用统计聚合唯一入口：全量记录 + 项目清单 + 生效今天 → 完整视图模型。
/// 纯函数，不感知作用域——调用方传哪份记录就算哪份（作用域永远当前
/// 应用车辆，由上游数据接缝决定）。空记录返回全 0 与空列表（页面据此
/// 渲染空态）。
CostStats buildCostStats({
  required List<MaintenanceRecord> records,
  required List<MaintenanceItem> items,
  required LocalDate today,
}) {
  final totalCents = records.fold(0, (sum, record) => sum + record.costCents);
  final recordCount = records.length;

  // 年度走势：从首条记录年到今年逐点铺满，无记录年补 0 保证横轴连续。
  final centsByYear = <int, int>{};
  var firstYear = today.year;
  for (final record in records) {
    final year = record.date.year;
    centsByYear[year] = (centsByYear[year] ?? 0) + record.costCents;
    if (year < firstYear) {
      firstYear = year;
    }
  }
  final maxYearCents =
      centsByYear.values.fold(0, (max, cents) => cents > max ? cents : max);
  final years = [
    if (records.isNotEmpty)
      for (var year = firstYear; year <= today.year; year++)
        CostYearPoint(
          year: year,
          costCents: centsByYear[year] ?? 0,
          fraction:
              maxYearCents == 0 ? 0.0 : (centsByYear[year] ?? 0) / maxYearCents,
        ),
  ];

  // 项目占比 + 优惠分摊 + 其他段：一次遍历同步完成。项目按解析出的
  // 项目名聚合计费值（口径见 itemCostValue）；优惠按记录逐条分摊后
  // 累计到项目名上；无归属的钱（简洁模式费用、总费用超出合计的差额）
  // 计入其他段，保证守恒。
  final centsByName = <String, int>{};
  final discountByName = <String, int>{};
  var otherCents = 0;
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
      // 简洁模式记录：钱花了但没有项目可归属，全额进其他段。
      otherCents += record.costCents;
      continue;
    }
    final valueSum = entries.fold(0, (sum, entry) => sum + entry.value);
    // 总费用超出项目费用合计的差额同样无处归属 → 其他段（负差值 =
    // 有优惠，走下面的分摊，不动其他段）。
    if (record.costCents > valueSum) {
      otherCents += record.costCents - valueSum;
    }
    // 总优惠 = Σ计费值 − 记录总费用；负差值按无优惠计。"没有任何
    // 计费值的记录不参与"由上面的 continue 自然成立，无需特判。
    final discount = valueSum - record.costCents;
    if (discount <= 0) {
      continue;
    }
    final allocated = allocateDiscount(entries, discount);
    for (final finalEntry in allocated.entries) {
      discountByName[finalEntry.key] =
          (discountByName[finalEntry.key] ?? 0) + finalEntry.value;
    }
  }
  final totalDiscountCents = discountByName.values
      .fold(0, (sum, cents) => sum + cents);

  // 实付 = 计费值 − 分摊优惠；条宽同一把尺（含其他段的最大实付）。
  final actualByName = <String, int>{
    for (final entry in centsByName.entries)
      entry.key: entry.value - (discountByName[entry.key] ?? 0),
  };
  var barMaxCents = otherCents;
  for (final actual in actualByName.values) {
    if (actual > barMaxCents) {
      barMaxCents = actual;
    }
  }
  // 实付从多到少（页面条形列表的展示顺序）；平局按名称稳定排序。
  final namesByActual = actualByName.keys.toList()
    ..sort((left, right) {
      final byActual = actualByName[right]!.compareTo(actualByName[left]!);
      return byActual != 0 ? byActual : left.compareTo(right);
    });
  final topItems = [
    for (final name in namesByActual)
      CostItemShareRow(
        name: name,
        costCents: centsByName[name]!,
        discountCents: discountByName[name] ?? 0,
        actualCents: actualByName[name]!,
        fraction:
            barMaxCents == 0 ? 0.0 : actualByName[name]! / barMaxCents,
      ),
  ];

  // 月均：首条记录月 → 当月的自然月数（含首尾与中间无记录月，
  // 全程摊薄）。
  var firstMonthKey = -1;
  for (final record in records) {
    final key = record.date.year * 12 + record.date.month - 1;
    if (firstMonthKey == -1 || key < firstMonthKey) {
      firstMonthKey = key;
    }
  }
  final todayKey = today.year * 12 + today.month - 1;
  var monthSpan = 0;
  if (firstMonthKey >= 0) {
    monthSpan = todayKey - firstMonthKey + 1;
    if (monthSpan < 1) {
      // 全部记录晚于生效今天（异常数据）时按 1 个月摊，避免除 0。
      monthSpan = 1;
    }
  }

  // 汇总指标：次数（总/今年）、单次均价、上次保养日期。
  final thisYearRecordCount = records
      .where((record) => record.date.year == today.year)
      .length;
  LocalDate? lastRecordDate;
  var lastRecordKey = -1;
  for (final record in records) {
    final key = _dateKey(record.date);
    if (key > lastRecordKey) {
      lastRecordKey = key;
      lastRecordDate = record.date;
    }
  }

  return CostStats(
    totalCents: totalCents,
    thisYearCents: costCentsForYear(records, today.year),
    years: years,
    topItems: topItems,
    otherCents: otherCents,
    totalDiscountCents: totalDiscountCents,
    recordCount: recordCount,
    thisYearRecordCount: thisYearRecordCount,
    avgPerVisitCents:
        recordCount == 0 ? 0 : (totalCents / recordCount).round(),
    monthlyAvgCents:
        monthSpan == 0 ? 0 : (totalCents / monthSpan).round(),
    lastRecordDate: lastRecordDate,
  );
}
