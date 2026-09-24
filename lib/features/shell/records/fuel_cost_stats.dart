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
/// 记录页头部"今年加油"与统计页汇总卡"今年加油"栏共用这一个口径。
int fuelCostCentsForYear(List<FuelRecord> records, int year) {
  var total = 0;
  for (final record in records) {
    if (record.date.year == year) {
      total += record.effectiveCostCents;
    }
  }
  return total;
}

/// 一个自然月的加油费用（实付优先口径），月份柱状图的数据点。
/// [year]/[month] 用于柱下「26.9」式轴标签，不参与求和。
class FuelCostMonthPoint {
  const FuelCostMonthPoint({
    required this.year,
    required this.month,
    required this.costCents,
  });

  final int year;
  final int month;

  /// 该月加油费用合计（分；无记录月为 0）。
  final int costCents;
}

/// 年月 → 可比较整数键（年*12 + 月-1，同 cost_stats.dart 的月均口径）。
int _monthKey(LocalDate date) => date.year * 12 + date.month - 1;

/// 全历史逐月加油费用：首条加油记录月 → 生效当月逐月铺满（含中间无
/// 记录月，费用为 0），时间升序——2026-09-23 拍板加油费用卡删年度行，
/// 月份图改为全历史连续时间轴、横向滚动。生效今天被手动日期拨到过去
/// 时（异常数据：存在晚于"今天"的记录），终点顺延到最后一条记录月，
/// 保证任何一笔钱都不从图上消失。纯函数。
List<FuelCostMonthPoint> fuelMonthlyCents(
  List<FuelRecord> records,
  LocalDate today,
) {
  if (records.isEmpty) {
    return const [];
  }
  var firstKey = _monthKey(today);
  var lastKey = firstKey;
  final centsByMonth = <int, int>{};
  for (final record in records) {
    final key = _monthKey(record.date);
    centsByMonth[key] = (centsByMonth[key] ?? 0) + record.effectiveCostCents;
    if (key < firstKey) {
      firstKey = key;
    }
    if (key > lastKey) {
      lastKey = key;
    }
  }
  return [
    for (var key = firstKey; key <= lastKey; key++)
      FuelCostMonthPoint(
        year: key ~/ 12,
        month: key % 12 + 1,
        costCents: centsByMonth[key] ?? 0,
      ),
  ];
}

/// 加油费用聚合结果（一次算齐的只读视图模型，渲染层直接消费）。
class FuelCostStats {
  const FuelCostStats({
    required this.totalCents,
    required this.recordCount,
    required this.monthlyAvgCents,
  });

  /// 加油总费用（分，实付优先口径）。
  final int totalCents;

  /// 加油记录总条数。
  final int recordCount;

  /// 月均（分）= 总费用 ÷ 首条加油记录月到当月的自然月数（含首尾与
  /// 中间无记录月，全程摊薄）——口径与保养"月均"一致（CONTEXT.md 词条），
  /// 只是输入换成加油记录；2026-09-24 拍板顶替加油卡头部的"N 笔"。
  /// 无记录时为 0；全部记录晚于生效今天（异常数据）时按 1 个月摊。
  final int monthlyAvgCents;
}

/// 加油费用聚合唯一入口：全量加油记录 + 生效今天 → 完整视图模型
/// （2026-09-24 起卡头两数字 = 总费用 + 月均；逐月明细由
/// [fuelMonthlyCents] 单独出）。纯函数，不感知作用域——调用方传哪份
/// 记录就算哪份（作用域永远当前应用车辆，由上游数据接缝决定）。
/// 空记录返回全 0。
FuelCostStats buildFuelCostStats({
  required List<FuelRecord> records,
  required LocalDate today,
}) {
  final totalCents = records.fold(
    0,
    (sum, record) => sum + record.effectiveCostCents,
  );
  var monthSpan = 0;
  if (records.isNotEmpty) {
    var firstKey = _monthKey(records.first.date);
    for (final record in records) {
      final key = _monthKey(record.date);
      if (key < firstKey) {
        firstKey = key;
      }
    }
    monthSpan = _monthKey(today) - firstKey + 1;
    if (monthSpan < 1) {
      // 全部记录晚于生效今天（异常数据）时按 1 个月摊，避免负数/除 0。
      monthSpan = 1;
    }
  }
  return FuelCostStats(
    totalCents: totalCents,
    recordCount: records.length,
    monthlyAvgCents:
        monthSpan == 0 ? 0 : (totalCents / monthSpan).round(),
  );
}
