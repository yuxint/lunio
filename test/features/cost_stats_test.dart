// cost_stats.dart 的纯函数单测：总费用权威值口径、年度分组、项目占比
// 的 null 口径（项目费用 ?? 材料+工时、全缺跳过）、Top N 截断、近 12 个
// 月窗口边界。不打 widget、不连数据库——直接构造实体（仿
// record_rows_test 的构造手法）。
// 断言全部用精确值：常量被变异（窗口长度、口径分支、排序方向等）时
// 至少一条断言会红，即变异验证。

import 'package:flutter_test/flutter_test.dart';
import 'package:lunio/core/date/local_date.dart';
import 'package:lunio/domain/entities/maintenance_item.dart';
import 'package:lunio/domain/entities/maintenance_record.dart';
import 'package:lunio/domain/entities/sync_metadata.dart';
import 'package:lunio/features/shell/records/cost_stats.dart';

final _sync = SyncMetadata(
  status: SyncStatus.synced,
  updatedAt: DateTime(2026, 1, 1),
);

/// 固定"今天"= 2026-05-19（与 widget 夹具的生效今天同月，便于对窗口）。
final _today = const LocalDate(2026, 5, 19);

MaintenanceItem _item({required int id, required String name}) =>
    MaintenanceItem(
      id: id,
      carsId: 1,
      name: name,
      enabled: true,
      remindByMileage: false,
      remindByTime: true,
      timeIntervalMonths: 6,
      sortOrder: id,
      sync: _sync,
    );

MaintenanceRecord _record({
  required LocalDate date,
  required int costCents,
  List<int> itemIds = const [],
  List<RecordItemCost> itemCosts = const [],
}) => MaintenanceRecord(
  carId: 1,
  date: date,
  itemIds: itemIds,
  itemCosts: itemCosts,
  costCents: costCents,
  mileageKm: 10000,
  sync: _sync,
);

RecordItemCost _cost({
  int? itemId = 1, int? material, int? labor, int? cost,
}) =>
    RecordItemCost(
      itemId: itemId!,
      materialCents: material,
      laborCents: labor,
      costCents: cost,
    );

void main() {
  group('空记录', () {
    test('全 0 + 空列表 + 12 个月补 0', () {
      final stats = buildCostStats(
        records: const [],
        items: const [],
        today: _today,
      );
      expect(stats.totalCents, 0);
      expect(stats.thisYearCents, 0);
      expect(stats.years, isEmpty);
      expect(stats.topItems, isEmpty);
      expect(stats.months, hasLength(12));
      expect(stats.months.every((point) => point.costCents == 0), isTrue);
      // 窗口 = 2025-06 起、2026-05 止（含当月，往前推 11 个月）。
      expect(stats.months.first.year, 2025);
      expect(stats.months.first.month, 6);
      expect(stats.months.last.year, 2026);
      expect(stats.months.last.month, 5);
    });
  });

  group('总额与今年花费（记录总费用权威值）', () {
    test('总费用与项目费用合计不一致时仍按总费用（ADR 0010）', () {
      final stats = buildCostStats(
        records: [
          _record(
            date: const LocalDate(2026, 5, 19),
            costCents: 28000,
            itemIds: [1],
            itemCosts: [_cost(material: 15000, labor: 8000, cost: 23000)],
          ),
        ],
        items: [_item(id: 1, name: '机油')],
        today: _today,
      );
      expect(stats.totalCents, 28000);
      expect(stats.thisYearCents, 28000);
    });

    test('今年只计今年记录，去年不计', () {
      final stats = buildCostStats(
        records: [
          _record(date: const LocalDate(2025, 12, 31), costCents: 10000),
          _record(date: const LocalDate(2026, 1, 1), costCents: 5000),
        ],
        items: const [],
        today: _today,
      );
      expect(stats.totalCents, 15000);
      expect(stats.thisYearCents, 5000);
    });
  });

  group('costCentsForYear 按年求和', () {
    test('只累计指定年份', () {
      final cents = costCentsForYear([
        _record(date: const LocalDate(2024, 1, 1), costCents: 100),
        _record(date: const LocalDate(2025, 6, 1), costCents: 200),
        _record(date: const LocalDate(2025, 7, 1), costCents: 300),
      ], 2025);
      expect(cents, 500);
    });
  });

  group('按年横条', () {
    test('年份升序 + 相对最大年的条宽比例', () {
      final stats = buildCostStats(
        records: [
          _record(date: const LocalDate(2026, 2, 1), costCents: 20000),
          _record(date: const LocalDate(2025, 3, 1), costCents: 30000),
          _record(date: const LocalDate(2024, 4, 1), costCents: 10000),
        ],
        items: const [],
        today: _today,
      );
      expect(stats.years, hasLength(3));
      expect(stats.years[0].year, 2024);
      expect(stats.years[0].costCents, 10000);
      expect(stats.years[0].fraction, closeTo(1 / 3, 1e-9));
      expect(stats.years[1].year, 2025);
      expect(stats.years[1].costCents, 30000);
      expect(stats.years[1].fraction, 1.0);
      expect(stats.years[2].year, 2026);
      expect(stats.years[2].costCents, 20000);
      expect(stats.years[2].fraction, closeTo(2 / 3, 1e-9));
    });
  });

  group('项目占比口径', () {
    test('项目费用优先于材料+工时；缺失时回退；单边缺失按 0', () {
      final stats = buildCostStats(
        records: [
          // 项目费用填了：取项目费用 200（无视 材料150+工时80=230）。
          _record(
            date: const LocalDate(2026, 5, 1),
            costCents: 0,
            itemIds: [1],
            itemCosts: [
              _cost(itemId: 1, material: 15000, labor: 8000, cost: 20000),
            ],
          ),
          // 项目费用缺：取材料+工时 = 230。
          _record(
            date: const LocalDate(2026, 5, 2),
            costCents: 0,
            itemIds: [2],
            itemCosts: [_cost(itemId: 2, material: 15000, labor: 8000)],
          ),
          // 工时缺：材料 50 按 50 计（缺失一边按 0）。
          _record(
            date: const LocalDate(2026, 5, 3),
            costCents: 0,
            itemIds: [3],
            itemCosts: [_cost(itemId: 3, material: 5000)],
          ),
        ],
        items: [
          _item(id: 1, name: '机油'),
          _item(id: 2, name: '机滤'),
          _item(id: 3, name: '空调滤'),
        ],
        today: _today,
      );
      final byName = {
        for (final row in stats.topItems) row.name: row.costCents,
      };
      expect(byName['机油'], 20000);
      expect(byName['机滤'], 23000);
      expect(byName['空调滤'], 5000);
      // 占比分母 = 项目口径总和 200+230+50 = 480（不含记录总费用）。
      final oil = stats.topItems.firstWhere((row) => row.name == '机油');
      expect(oil.share, closeTo(20000 / 48000, 1e-9));
    });

    test('三项全缺跳过该行；itemCosts 空的记录不进占比', () {
      final stats = buildCostStats(
        records: [
          _record(
            date: const LocalDate(2026, 5, 1),
            costCents: 99000,
            itemIds: [1],
            itemCosts: [_cost(itemId: 1)], // 三项全缺 → 跳过。
          ),
          _record(
            date: const LocalDate(2026, 5, 2),
            costCents: 10000,
            itemIds: [2], // 无 itemCosts → 该行无计费值。
          ),
        ],
        items: [_item(id: 1, name: '机油'), _item(id: 2, name: '机滤')],
        today: _today,
      );
      expect(stats.topItems, isEmpty);
      // 总额口径不受影响：仍按记录总费用。
      expect(stats.totalCents, 109000);
    });

    test('清单外项目归「未知项目」；同名项目跨记录合并', () {
      final stats = buildCostStats(
        records: [
          _record(
            date: const LocalDate(2026, 5, 1),
            costCents: 0,
            itemIds: [99],
            itemCosts: [_cost(itemId: 99, cost: 10000)],
          ),
          _record(
            date: const LocalDate(2026, 5, 2),
            costCents: 0,
            itemIds: [1, 2],
            itemCosts: [
              _cost(itemId: 1, cost: 3000),
              _cost(itemId: 2, cost: 2000),
            ],
          ),
        ],
        items: [
          _item(id: 1, name: '机油'),
          _item(id: 2, name: '机油'), // 不同 id、同名（多车合并的形态）。
        ],
        today: _today,
      );
      expect(stats.topItems, hasLength(2));
      expect(stats.topItems[0].name, '未知项目');
      expect(stats.topItems[0].costCents, 10000);
      expect(stats.topItems[1].name, '机油');
      expect(stats.topItems[1].costCents, 5000); // 同名两条合计。
    });

    test('Top N 截断 + 降序 + 平局按名称稳定排序；占比分母含未进榜项目', () {
      final records = [
        for (var i = 0; i < 4; i++)
          _record(
            date: LocalDate(2026, 5, i + 1),
            costCents: 0,
            itemIds: [i + 1],
            itemCosts: [_cost(itemId: i + 1, cost: (6 - i) * 1000)],
          ),
        // 与第 5 名同为 2000 的平局项：平局必须落在截断线上才能观察
        // tie-break 方向——名称更小者进榜（项目5 进、项目6 出），
        // 比较器方向变异（升/降互换或删掉）在这里才会红。
        _record(
          date: const LocalDate(2026, 5, 10),
          costCents: 0,
          itemIds: [5],
          itemCosts: [_cost(itemId: 5, cost: 2000)],
        ),
        _record(
          date: const LocalDate(2026, 5, 11),
          costCents: 0,
          itemIds: [6],
          itemCosts: [_cost(itemId: 6, cost: 2000)],
        ),
      ];
      final stats = buildCostStats(
        records: records,
        items: [
          for (var i = 0; i < 6; i++) _item(id: i + 1, name: '项目${i + 1}'),
        ],
        today: _today,
      );
      expect(stats.topItems, hasLength(5));
      // 降序：6000, 5000, 4000, 3000, 2000。
      expect(
        stats.topItems.map((row) => row.costCents).toList(),
        [6000, 5000, 4000, 3000, 2000],
      );
      // 平局方向：项目5 与项目6 同为 2000，名称更小的项目5 占第 5 名。
      expect(stats.topItems.last.name, '项目5');
      // 占比分母 = 全部 6 项之和 = 22000（含未进榜的 2000×1）。
      expect(stats.topItems[0].share, closeTo(6000 / 22000, 1e-9));
    });

    test('条宽比例相对 Top 内最大值', () {
      final stats = buildCostStats(
        records: [
          _record(
            date: const LocalDate(2026, 5, 1),
            costCents: 0,
            itemIds: [1],
            itemCosts: [_cost(itemId: 1, cost: 40000)],
          ),
          _record(
            date: const LocalDate(2026, 5, 2),
            costCents: 0,
            itemIds: [2],
            itemCosts: [_cost(itemId: 2, cost: 10000)],
          ),
        ],
        items: [_item(id: 1, name: '机油'), _item(id: 2, name: '机滤')],
        today: _today,
      );
      expect(stats.topItems[0].fraction, 1.0);
      expect(stats.topItems[1].fraction, closeTo(0.25, 1e-9));
    });
  });

  group('近 12 个月走势', () {
    test('窗口边界：11 个月前计入、12 个月前不计、当月计入', () {
      final stats = buildCostStats(
        records: [
          // 窗口起点当月（2025-06）：计入。
          _record(date: const LocalDate(2025, 6, 30), costCents: 100),
          // 窗口外一个月（2025-05）：不计。
          _record(date: const LocalDate(2025, 5, 31), costCents: 999),
          // 当月（2026-05）：计入。
          _record(date: const LocalDate(2026, 5, 19), costCents: 300),
        ],
        items: const [],
        today: _today,
      );
      expect(stats.months.first.costCents, 100); // 2025-06。
      expect(stats.months[11].costCents, 300); // 2026-05。
      // 其余月份全部为 0（含窗口外的 2025-05 不出现在任何点位）。
      expect(
        stats.months.sublist(1, 11).every((point) => point.costCents == 0),
        isTrue,
      );
      // 条高相对峰值月（300）。
      expect(stats.months.first.fraction, closeTo(100 / 300, 1e-9));
      expect(stats.months[11].fraction, 1.0);
    });

    test('同月多条记录合并；跨年 12 个点连续（12月→1月）', () {
      final stats = buildCostStats(
        records: [
          _record(date: const LocalDate(2025, 12, 1), costCents: 100),
          _record(date: const LocalDate(2025, 12, 20), costCents: 50),
        ],
        items: const [],
        today: const LocalDate(2026, 2, 15),
      );
      // 窗口 = 2025-03 ~ 2026-02，2025-12 是第 10 个点。
      expect(stats.months, hasLength(12));
      expect(stats.months.first.year, 2025);
      expect(stats.months.first.month, 3);
      final december = stats.months[9];
      expect(december.year, 2025);
      expect(december.month, 12);
      expect(december.costCents, 150);
    });
  });

  group('优惠分摊（2026-09-20）', () {
    test('按计费值权重分摊，最大余数法守恒', () {
      // 总费用 300，机油计费 200 + 机滤 150 → 总优惠 50。
      // 机油 exact 28.57 → 28.57 分摊 2857 分；机滤 exact 21.43 →
      // floor 2142 + 最大余数补 1 分 = 2143，合计正好 5000（守恒）。
      final stats = buildCostStats(
        records: [
          _record(
            date: const LocalDate(2026, 5, 1),
            costCents: 30000,
            itemIds: [1, 2],
            itemCosts: [
              _cost(itemId: 1, cost: 20000),
              _cost(itemId: 2, cost: 15000),
            ],
          ),
        ],
        items: [_item(id: 1, name: '机油'), _item(id: 2, name: '机滤')],
        today: _today,
      );
      expect(stats.totalDiscountCents, 5000);
      expect(stats.itemTotalCents, 35000);
      expect(stats.itemsActualCents, 30000);
      final oil = stats.topItems[0];
      expect(oil.name, '机油');
      expect(oil.discountCents, 2857);
      expect(oil.actualCents, 17143);
      final filter = stats.topItems[1];
      expect(filter.discountCents, 2143);
      expect(filter.actualCents, 12857);
    });

    test('负差值按无优惠计（clamp 到 0）', () {
      // 总费用 300 > 计费值合计 200：不加价展示，优惠按 0。
      final stats = buildCostStats(
        records: [
          _record(
            date: const LocalDate(2026, 5, 1),
            costCents: 30000,
            itemIds: [1],
            itemCosts: [_cost(itemId: 1, cost: 20000)],
          ),
        ],
        items: [_item(id: 1, name: '机油')],
        today: _today,
      );
      expect(stats.totalDiscountCents, 0);
      expect(stats.itemsActualCents, 20000);
      expect(stats.topItems.single.discountCents, 0);
      expect(stats.topItems.single.actualCents, 20000);
    });

    test('没有任何计费值的记录不参与优惠统计', () {
      // 简洁模式只填总费用：Σ计费值 = 0，差值 ≤ 0 自然为无优惠——
      // 口径自动成立，无需特判。
      final stats = buildCostStats(
        records: [
          _record(
            date: const LocalDate(2026, 5, 1),
            costCents: 99000,
            itemIds: [1],
            itemCosts: [_cost(itemId: 1)], // 三项全缺。
          ),
          _record(date: const LocalDate(2026, 5, 2), costCents: 50000),
        ],
        items: [_item(id: 1, name: '机油')],
        today: _today,
      );
      expect(stats.totalDiscountCents, 0);
      expect(stats.topItems, isEmpty);
      expect(stats.itemsActualCents, 0);
      // 总额口径不受影响。
      expect(stats.totalCents, 149000);
    });

    test('跨记录按项目名合并优惠；优惠与无优惠记录混合', () {
      final stats = buildCostStats(
        records: [
          // 有优惠：总费用 80 < 机油计费 100 → 优惠 20 全归机油。
          _record(
            date: const LocalDate(2026, 5, 1),
            costCents: 8000,
            itemIds: [1],
            itemCosts: [_cost(itemId: 1, cost: 10000)],
          ),
          // 无优惠：计费合计 = 总费用。
          _record(
            date: const LocalDate(2026, 5, 2),
            costCents: 6000,
            itemIds: [1, 2],
            itemCosts: [
              _cost(itemId: 1, cost: 3000),
              _cost(itemId: 2, cost: 3000),
            ],
          ),
          // 有优惠：总费用 40 < 机滤计费 50 → 优惠 10 全归机滤。
          _record(
            date: const LocalDate(2026, 5, 3),
            costCents: 4000,
            itemIds: [2],
            itemCosts: [_cost(itemId: 2, cost: 5000)],
          ),
        ],
        items: [_item(id: 1, name: '机油'), _item(id: 2, name: '机滤')],
        today: _today,
      );
      expect(stats.totalDiscountCents, 3000);
      expect(stats.itemTotalCents, 21000);
      expect(stats.itemsActualCents, 18000);
      // 降序：机油 130 > 机滤 80。
      expect(stats.topItems[0].name, '机油');
      expect(stats.topItems[0].discountCents, 2000);
      expect(stats.topItems[0].actualCents, 11000);
      expect(stats.topItems[1].discountCents, 1000);
      expect(stats.topItems[1].actualCents, 7000);
    });

    test('单条分摊不越过该项目计费值；多项守恒', () {
      // 总费用 10，计费 A 70 + B 2 + C 3 = 75 → 优惠 65。
      // A exact 60.67 → 6066 + 余数 1 = 6067（≤ 7000）、B 173、C 260，
      // 合计 6500 守恒。
      final stats = buildCostStats(
        records: [
          _record(
            date: const LocalDate(2026, 5, 1),
            costCents: 1000,
            itemIds: [1, 2, 3],
            itemCosts: [
              _cost(itemId: 1, cost: 7000),
              _cost(itemId: 2, cost: 200),
              _cost(itemId: 3, cost: 300),
            ],
          ),
        ],
        items: [
          _item(id: 1, name: '甲'),
          _item(id: 2, name: '乙'),
          _item(id: 3, name: '丙'),
        ],
        today: _today,
      );
      expect(stats.totalDiscountCents, 6500);
      final discounts = {
        for (final row in stats.topItems) row.name: row.discountCents,
      };
      expect(discounts['甲'], 6067);
      expect(discounts['乙'], 173);
      expect(discounts['丙'], 260);
      // 每项分摊 ≤ 计费值。
      for (final row in stats.topItems) {
        expect(row.discountCents, lessThanOrEqualTo(row.costCents));
      }
    });
  });
}
