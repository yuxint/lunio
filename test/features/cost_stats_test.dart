// cost_stats.dart 的纯函数单测：总费用权威值口径、年度走势（首年到
// 今年补 0）、项目占比口径（计费值=项目费用、全缺跳过、实付降序、
// 其他段守恒）、月均全程摊薄、优惠分摊守恒。不打 widget、不连数据库
// ——直接构造实体（仿 record_rows_test 的构造手法）。
// 断言全部用精确值：常量被变异（口径分支、排序方向、分母口径等）时
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

/// 固定"今天"= 2026-05-19（与 widget 夹具的生效今天同月，便于对跨度）。
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

/// 守恒断言（口径锚点）：Σ项目实付 + 其他段 ≡ 总费用（cost_stats.dart
/// 文件头"守恒"条目的测试面）。
void _expectConservation(CostStats stats) {
  final actualSum = stats.topItems
      .fold(0, (sum, row) => sum + row.actualCents);
  expect(actualSum + stats.otherCents, stats.totalCents);
}

void main() {
  group('空记录', () {
    test('全 0 + 空列表（走势点位也为空，页面据此隐藏走势卡）', () {
      final stats = buildCostStats(
        records: const [],
        items: const [],
        today: _today,
      );
      expect(stats.totalCents, 0);
      expect(stats.thisYearCents, 0);
      expect(stats.years, isEmpty);
      expect(stats.topItems, isEmpty);
      expect(stats.otherCents, 0);
      expect(stats.monthlyAvgCents, 0);
    });
  });

  group('总额与今年费用（记录总费用权威值）', () {
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
      // 项目口径只用项目费用 23000；总费用多出的 5000 进其他段。
      expect(stats.topItems.single.costCents, 23000);
      expect(stats.otherCents, 5000);
      _expectConservation(stats);
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

  group('年度走势', () {
    test('首条记录年 → 今年逐点铺满，比例相对峰值年', () {
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

    test('中间无记录年补 0，横轴连续', () {
      final stats = buildCostStats(
        records: [
          _record(date: const LocalDate(2026, 2, 1), costCents: 20000),
          _record(date: const LocalDate(2024, 4, 1), costCents: 10000),
        ],
        items: const [],
        today: _today,
      );
      expect(stats.years.map((point) => point.year).toList(),
          [2024, 2025, 2026]);
      expect(stats.years[1].year, 2025);
      expect(stats.years[1].costCents, 0);
      expect(stats.years[1].fraction, 0.0);
    });

    test('同一年多条记录合并；单年只有一个点位', () {
      final stats = buildCostStats(
        records: [
          _record(date: const LocalDate(2026, 2, 1), costCents: 5000),
          _record(date: const LocalDate(2026, 5, 1), costCents: 20000),
        ],
        items: const [],
        today: _today,
      );
      expect(stats.years, hasLength(1));
      expect(stats.years.single.costCents, 25000);
      expect(stats.years.single.fraction, 1.0);
    });
  });

  group('项目占比口径', () {
    test('计费值 = 项目费用；材料/工时不参与读侧口径', () {
      final stats = buildCostStats(
        records: [
          // 项目费用 200 权威：无视 材料150+工时80=230。
          _record(
            date: const LocalDate(2026, 5, 1),
            costCents: 20000,
            itemIds: [1],
            itemCosts: [
              _cost(itemId: 1, material: 15000, labor: 8000, cost: 20000),
            ],
          ),
        ],
        items: [_item(id: 1, name: '机油')],
        today: _today,
      );
      expect(stats.topItems.single.costCents, 20000);
      // 总费用 = 项目费用 → 无优惠、无其他段。
      expect(stats.topItems.single.actualCents, 20000);
      expect(stats.otherCents, 0);
    });

    test('项目费用没填即不参与统计（材料/工时有值也不兜底）；该记录费用进其他段', () {
      final stats = buildCostStats(
        records: [
          // 三项全缺 → 项目不进占比。
          _record(
            date: const LocalDate(2026, 5, 1),
            costCents: 99000,
            itemIds: [1],
            itemCosts: [_cost(itemId: 1)],
          ),
          // 材料/工时有值但项目费用没填（不变量外的存量形态）：同样
          // 不兜底，不进占比；记录费用进其他段守恒。
          _record(
            date: const LocalDate(2026, 5, 2),
            costCents: 10000,
            itemIds: [2],
            itemCosts: [_cost(itemId: 2, material: 15000, labor: 8000)],
          ),
          // 连 itemCosts 都没有（简洁模式）。
          _record(
            date: const LocalDate(2026, 5, 3),
            costCents: 50000,
            itemIds: [3],
          ),
        ],
        items: [
          _item(id: 1, name: '机油'),
          _item(id: 2, name: '机滤'),
          _item(id: 3, name: '空调滤'),
        ],
        today: _today,
      );
      expect(stats.topItems, isEmpty);
      // 三条记录的费用全部无归属 → 其他段全额吸收，守恒成立。
      expect(stats.otherCents, 159000);
      _expectConservation(stats);
    });

    test('清单外项目归「未知项目」；同名项目跨记录合并', () {
      final stats = buildCostStats(
        records: [
          _record(
            date: const LocalDate(2026, 5, 1),
            costCents: 10000,
            itemIds: [99],
            itemCosts: [_cost(itemId: 99, cost: 10000)],
          ),
          _record(
            date: const LocalDate(2026, 5, 2),
            costCents: 5000,
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
      expect(stats.topItems[0].actualCents, 10000);
      expect(stats.topItems[1].name, '机油');
      expect(stats.topItems[1].actualCents, 5000); // 同名两条合计。
    });

    test('全部项目列出（不截断）+ 实付降序 + 平局按名称稳定排序', () {
      final records = [
        for (var i = 0; i < 4; i++)
          _record(
            date: LocalDate(2026, 5, i + 1),
            costCents: (6 - i) * 1000,
            itemIds: [i + 1],
            itemCosts: [_cost(itemId: i + 1, cost: (6 - i) * 1000)],
          ),
        // 与项目5 实付同为 2000 的平局项：名称更小者排前（项目5 在前），
        // 比较器方向变异（升/降互换或删掉）在这里才会红。
        _record(
          date: const LocalDate(2026, 5, 10),
          costCents: 2000,
          itemIds: [5],
          itemCosts: [_cost(itemId: 5, cost: 2000)],
        ),
        _record(
          date: const LocalDate(2026, 5, 11),
          costCents: 2000,
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
      // 不截断：6 个项目全部列出。
      expect(stats.topItems, hasLength(6));
      // 实付降序：6000, 5000, 4000, 3000, 2000, 2000。
      expect(
        stats.topItems.map((row) => row.actualCents).toList(),
        [6000, 5000, 4000, 3000, 2000, 2000],
      );
      // 平局方向：项目5 与项目6 同为 2000，名称更小的项目5 排前。
      expect(stats.topItems[4].name, '项目5');
      expect(stats.topItems[5].name, '项目6');
      _expectConservation(stats);
    });

    test('条宽比例相对全部行（含其他段）最大实付', () {
      final stats = buildCostStats(
        records: [
          _record(
            date: const LocalDate(2026, 5, 1),
            costCents: 40000,
            itemIds: [1],
            itemCosts: [_cost(itemId: 1, cost: 40000)],
          ),
          _record(
            date: const LocalDate(2026, 5, 2),
            costCents: 10000,
            itemIds: [2],
            itemCosts: [_cost(itemId: 2, cost: 10000)],
          ),
          // 简洁模式 80000：其他段成为最大行，所有条以它为满宽基准。
          _record(date: const LocalDate(2026, 5, 3), costCents: 80000),
        ],
        items: [_item(id: 1, name: '机油'), _item(id: 2, name: '机滤')],
        today: _today,
      );
      expect(stats.otherCents, 80000);
      expect(stats.topItems[0].fraction, closeTo(40000 / 80000, 1e-9));
      expect(stats.topItems[1].fraction, closeTo(10000 / 80000, 1e-9));
    });
  });

  group('优惠分摊（2026-09-20）', () {
    test('按项目费用权重分摊，最大余数法守恒', () {
      // 总费用 300，机油计费 200 + 机滤 150 → 总优惠 50。
      // 机油 exact 28.57 → 2857 分；机滤 exact 21.43 →
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
      final oil = stats.topItems[0];
      expect(oil.name, '机油');
      expect(oil.discountCents, 2857);
      expect(oil.actualCents, 17143);
      final filter = stats.topItems[1];
      expect(filter.discountCents, 2143);
      expect(filter.actualCents, 12857);
      _expectConservation(stats);
    });

    test('总费用超出项目合计：差额进其他段，项目实付不被摊高', () {
      // 总费用 300 > 计费值合计 200：不加价展示，优惠按 0，多出的
      // 100 归其他段（归属诚实，机油不被"摊"到 300）。
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
      expect(stats.topItems.single.discountCents, 0);
      expect(stats.topItems.single.actualCents, 20000);
      expect(stats.otherCents, 10000);
      _expectConservation(stats);
    });

    test('没有任何计费值的记录不参与优惠统计，费用进其他段', () {
      // 简洁模式只填总费用：Σ计费值 = 0，差值 ≤ 0 自然为无优惠——
      // 口径自动成立，无需特判。
      final stats = buildCostStats(
        records: [
          _record(
            date: const LocalDate(2026, 5, 1),
            costCents: 99000,
            itemIds: [1],
            itemCosts: [_cost(itemId: 1)], // 项目费用没填。
          ),
          _record(date: const LocalDate(2026, 5, 2), costCents: 50000),
        ],
        items: [_item(id: 1, name: '机油')],
        today: _today,
      );
      expect(stats.totalDiscountCents, 0);
      expect(stats.topItems, isEmpty);
      expect(stats.otherCents, 149000);
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
      expect(stats.otherCents, 0);
      // 实付降序：机油 110 > 机滤 70。
      expect(stats.topItems[0].name, '机油');
      expect(stats.topItems[0].discountCents, 2000);
      expect(stats.topItems[0].actualCents, 11000);
      expect(stats.topItems[1].discountCents, 1000);
      expect(stats.topItems[1].actualCents, 7000);
      _expectConservation(stats);
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
      _expectConservation(stats);
    });

    test('守恒样例（grill 定稿例）：优惠 + 简洁模式 + 超额差额混合', () {
      // A 详细模式：机油 300 + 机滤 100 = 400，总费用 380（优惠 20：
      // 机油摊 15、机滤摊 5 → 实付 285/95）；B 简洁模式 200；C 漏填：
      // 洗车 50、总费用 80（差额 30）。总费用 660 = 285+95+50+230。
      final stats = buildCostStats(
        records: [
          _record(
            date: const LocalDate(2026, 5, 1),
            costCents: 38000,
            itemIds: [1, 2],
            itemCosts: [
              _cost(itemId: 1, cost: 30000),
              _cost(itemId: 2, cost: 10000),
            ],
          ),
          _record(date: const LocalDate(2026, 5, 2), costCents: 20000),
          _record(
            date: const LocalDate(2026, 5, 3),
            costCents: 8000,
            itemIds: [3],
            itemCosts: [_cost(itemId: 3, cost: 5000)],
          ),
        ],
        items: [
          _item(id: 1, name: '机油'),
          _item(id: 2, name: '机滤'),
          _item(id: 3, name: '洗车'),
        ],
        today: _today,
      );
      expect(stats.totalCents, 66000);
      expect(stats.totalDiscountCents, 2000);
      // 实付降序：机油 285 > 机滤 95 > 洗车 50。
      expect(
        stats.topItems.map((row) => row.name).toList(),
        ['机油', '机滤', '洗车'],
      );
      expect(stats.topItems[0].actualCents, 28500);
      expect(stats.topItems[0].discountCents, 1500);
      expect(stats.topItems[1].actualCents, 9500);
      expect(stats.topItems[1].discountCents, 500);
      expect(stats.topItems[2].actualCents, 5000);
      // 其他段 = 简洁模式 200 + 超额差额 30 = 230。
      expect(stats.otherCents, 23000);
      _expectConservation(stats);
    });
  });

  group('汇总指标', () {
    test('次数/今年次数/单次均价/上次保养日期', () {
      final stats = buildCostStats(
        records: [
          _record(date: const LocalDate(2026, 5, 1), costCents: 28000),
          _record(date: const LocalDate(2025, 3, 1), costCents: 10000),
        ],
        items: const [],
        today: _today,
      );
      expect(stats.recordCount, 2);
      expect(stats.thisYearRecordCount, 1);
      // 38000 ÷ 2 = 19000。
      expect(stats.avgPerVisitCents, 19000);
      expect(stats.lastRecordDate, const LocalDate(2026, 5, 1));
      // 空记录：全 0 + 上次为 null。
      final empty = buildCostStats(
        records: const [],
        items: const [],
        today: _today,
      );
      expect(empty.recordCount, 0);
      expect(empty.avgPerVisitCents, 0);
      expect(empty.lastRecordDate, isNull);
    });

    test('月均 = 总费用 ÷ 首条记录月到当月的自然月数（全程摊薄）', () {
      // 首条 2025-03 → 今天 2026-05：跨度 15 个月（含首尾与中间无
      // 记录月），38000/15 = 2533.33 → 2533。
      final stats = buildCostStats(
        records: [
          _record(date: const LocalDate(2026, 5, 1), costCents: 28000),
          _record(date: const LocalDate(2025, 3, 1), costCents: 10000),
        ],
        items: const [],
        today: _today,
      );
      expect(stats.monthlyAvgCents, 2533);
      // 同月两条只算一个月：28000/1 = 28000。
      final single = buildCostStats(
        records: [
          _record(date: const LocalDate(2026, 5, 1), costCents: 28000),
          _record(date: const LocalDate(2026, 5, 20), costCents: 12000),
        ],
        items: const [],
        today: _today,
      );
      expect(single.monthlyAvgCents, 40000);
      // 全部记录晚于生效今天（异常数据）：按 1 个月摊，不除 0。
      final future = buildCostStats(
        records: [
          _record(date: const LocalDate(2026, 6, 1), costCents: 28000),
        ],
        items: const [],
        today: _today,
      );
      expect(future.monthlyAvgCents, 28000);
    });
  });

  group('项目档案（2026-09-21）', () {
    test('逐次明细日期倒序 + 计费值/分摊优惠/实付', () {
      final histories = buildItemHistories(
        [
          _record(
            date: const LocalDate(2026, 5, 1),
            costCents: 30000,
            itemIds: [1, 2],
            itemCosts: [
              _cost(itemId: 1, cost: 20000),
              _cost(itemId: 2, cost: 15000),
            ],
          ),
          _record(
            date: const LocalDate(2025, 3, 1),
            costCents: 10000,
            itemIds: [1],
            itemCosts: [_cost(itemId: 1, cost: 10000)],
          ),
        ],
        [_item(id: 1, name: '机油'), _item(id: 2, name: '机滤')],
      );
      expect(histories.map((history) => history.name).toList(), [
        '机油',
        '机滤',
      ]); // 累计计费值降序。
      final oil = histories.first;
      expect(oil.count, 2);
      expect(oil.totalValueCents, 30000);
      expect(oil.totalDiscountCents, 2857); // 与占比卡同一分摊结果。
      expect(oil.totalActualCents, 27143);
      expect(oil.avgActualCents, 13572); // 27143 ÷ 2 四舍五入。
      // 日期倒序：2026 在前。
      expect(oil.entries.first.date, const LocalDate(2026, 5, 1));
      expect(oil.entries.first.valueCents, 20000);
      expect(oil.entries.first.discountCents, 2857);
      expect(oil.entries.first.actualCents, 17143);
      expect(oil.entries.last.date, const LocalDate(2025, 3, 1));
      expect(oil.entries.last.discountCents, 0);
      final filter = histories.last;
      expect(filter.count, 1);
      expect(filter.totalDiscountCents, 2143);
      expect(filter.avgActualCents, 12857);
    });

    test('无计费值记录不进档案；未知项目照常聚合', () {
      final histories = buildItemHistories(
        [
          // 费用全空的记录（今年那两条 ¥0.00 的形态）：不进档案。
          _record(
            date: const LocalDate(2026, 4, 12),
            costCents: 0,
            itemIds: [1],
            itemCosts: [_cost(itemId: 1)],
          ),
          _record(
            date: const LocalDate(2026, 3, 7),
            costCents: 0,
            itemIds: [1],
          ),
          _record(
            date: const LocalDate(2026, 5, 1),
            costCents: 8000,
            itemIds: [99],
            itemCosts: [_cost(itemId: 99, cost: 10000)],
          ),
        ],
        [_item(id: 1, name: '机油')],
      );
      expect(histories, hasLength(1));
      expect(histories.single.name, '未知项目');
      expect(histories.single.count, 1);
      // 机油今年两次都没填费用 → 档案里不存在机油。
    });
  });
}
