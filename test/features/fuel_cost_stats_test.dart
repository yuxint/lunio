// 加油费用聚合测试（fuel_cost_stats.dart，ADR 0015；2026-09-23 改版：
// 月度序列改全历史连续时间轴、删年度行模型）：逐月铺满补 0、记录晚于
// 生效今天的防御顺延、实付优先口径（没填取应付）、空记录空态。
import 'package:flutter_test/flutter_test.dart';
import 'package:lunio/core/date/local_date.dart';
import 'package:lunio/domain/entities/fuel_price.dart';
import 'package:lunio/domain/entities/fuel_record.dart';
import 'package:lunio/features/shell/records/fuel_cost_stats.dart';

void main() {
  final today = const LocalDate(2026, 9, 21);

  FuelRecord record(
    String date, {
    int unitPriceCents = 815,
    int payableCents = 30000,
    int? actualCents,
  }) {
    return FuelRecord(
      carId: 1,
      date: LocalDate.parse(date),
      grade: FuelGrade.gasoline92,
      unitPriceCents: unitPriceCents,
      payableCents: payableCents,
      actualCents: actualCents,
    );
  }

  group('fuelCostCentsForYear（实付优先口径）', () {
    test('实付填了取实付，没填取应付', () {
      final records = [
        record('2026-09-01', payableCents: 30000, actualCents: 27000),
        record('2026-09-15', payableCents: 30000),
      ];
      // 270 + 300 = ¥570.00。
      expect(fuelCostCentsForYear(records, 2026), 57000);
    });
  });

  group('fuelMonthlyCents（全历史逐月序列）', () {
    test('首条记录月铺到当月，时间升序，无记录月补 0', () {
      final records = [
        record('2026-01-10', payableCents: 10000),
        record('2026-03-02', payableCents: 20000, actualCents: 18000),
      ];
      final months = fuelMonthlyCents(records, today);
      // 2026-01 → 2026-09 共 9 个月。
      expect(months, hasLength(9));
      expect(months.first.year, 2026);
      expect(months.first.month, 1);
      expect(months[0].costCents, 10000);
      expect(months[1].costCents, 0); // 2 月补 0。
      expect(months[2].costCents, 18000);
      expect(months.last.month, 9);
    });

    test('跨年序列：2024-03 → 2026-09 共 31 个月，中间年月补 0', () {
      final months = fuelMonthlyCents([record('2024-03-15')], today);
      expect(months, hasLength(31));
      expect(months.first.year, 2024);
      expect(months.first.month, 3);
      expect(months[1].costCents, 0); // 2024-04 起补 0。
      expect(months.last.year, 2026);
      expect(months.last.month, 9);
    });

    test('记录晚于生效今天（手动日期异常）：终点顺延不丢钱', () {
      final months = fuelMonthlyCents(
        [record('2026-09-01', payableCents: 30000)],
        const LocalDate(2026, 1, 1),
      );
      // 生效今天在 2026-01，但 9 月有记录：序列铺到 9 月，钱不消失。
      expect(months, hasLength(9));
      expect(months.last.year, 2026);
      expect(months.last.month, 9);
      expect(months.last.costCents, 30000);
    });

    test('空记录：空序列', () {
      expect(fuelMonthlyCents(const [], today), isEmpty);
    });
  });

  group('buildFuelCostStats', () {
    test('总额与笔数（实付优先口径）', () {
      final stats = buildFuelCostStats(
        records: [
          record('2024-03-01', payableCents: 10000),
          record('2026-09-01', payableCents: 30000, actualCents: 27000),
        ],
      );
      // 100（应付）+ 270（实付）= ¥370.00。
      expect(stats.totalCents, 37000);
      expect(stats.recordCount, 2);
    });

    test('空记录：全 0', () {
      final stats = buildFuelCostStats(records: const []);
      expect(stats.totalCents, 0);
      expect(stats.recordCount, 0);
    });
  });
}
