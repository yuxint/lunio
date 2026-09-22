// 加油费用聚合组装层（fuel_cost_stats.dart）：统计页「加油费用」卡与
// 记录页头部"今年加油"共用的聚合口径。与 cost_stats.dart（保养费用）
// 同构但互不掺和——加油没有项目占比/优惠分摊那套结构，口径天然独立。
//
// 唯一口径：一笔加油参与统计的金额 = 实付金额，没填取应付金额
// （实体 [FuelRecord.effectiveCostCents] 的唯一实现点，本文件不再兜底）。
// 全部是纯函数与纯数据，无写库、无副作用，可直接单测。
// Java 类比：无状态聚合工具类（静态方法入参出参全是值对象）。

import '../../../core/date/local_date.dart';
import '../../../domain/entities/fuel_record.dart';

/// 某一年加油费用合计（实付优先、没填取应付，逐条求和）。
/// 记录页头部"今年加油"与统计页年度行共用这一个口径。
int fuelCostCentsForYear(List<FuelRecord> records, int year) {
  var total = 0;
  for (final record in records) {
    if (record.date.year == year) {
      total += record.effectiveCostCents;
    }
  }
  return total;
}

/// 某年 12 个月的加油费用（下标 0 = 1 月）。月份条形图的数据源，
/// 中间无记录月为 0。纯函数。
List<int> fuelMonthlyCents(List<FuelRecord> records, int year) {
  final months = List<int>.filled(12, 0);
  for (final record in records) {
    if (record.date.year == year) {
      months[record.date.month - 1] += record.effectiveCostCents;
    }
  }
  return months;
}

/// 加油费用年度行：年份 + 该年合计（实付优先口径）。
class FuelCostYearRow {
  const FuelCostYearRow({required this.year, required this.costCents});

  final int year;

  /// 该年加油费用合计（分）。
  final int costCents;
}

/// 加油费用聚合结果（一次算齐的只读视图模型，渲染层直接消费）。
class FuelCostStats {
  const FuelCostStats({
    required this.totalCents,
    required this.recordCount,
    required this.yearRows,
  });

  /// 加油总费用（分，实付优先口径）。
  final int totalCents;

  /// 加油记录总条数。
  final int recordCount;

  /// 年度行：首条记录年 → 今年逐年铺满（无记录年补 0，保证年份连续），
  /// **最近年在前**（列表阅读习惯，与保养走势卡的横轴时间方向不同——
  /// 这里是行列表不是时间轴）。
  final List<FuelCostYearRow> yearRows;
}

/// 加油费用聚合唯一入口：全量加油记录 + 生效今天 → 完整视图模型。
/// 纯函数，不感知作用域——调用方传哪份记录就算哪份（作用域永远当前
/// 应用车辆，由上游数据接缝决定）。空记录返回全 0 与空列表。
FuelCostStats buildFuelCostStats({
  required List<FuelRecord> records,
  required LocalDate today,
}) {
  final totalCents = records.fold(
    0,
    (sum, record) => sum + record.effectiveCostCents,
  );
  // 首条记录年（无记录时为今年，年份行退化为空下面已挡）。
  var firstYear = today.year;
  for (final record in records) {
    if (record.date.year < firstYear) {
      firstYear = record.date.year;
    }
  }
  final yearRows = [
    if (records.isNotEmpty)
      for (var year = today.year; year >= firstYear; year--)
        FuelCostYearRow(
          year: year,
          costCents: fuelCostCentsForYear(records, year),
        ),
  ];
  return FuelCostStats(
    totalCents: totalCents,
    recordCount: records.length,
    yearRows: yearRows,
  );
}
