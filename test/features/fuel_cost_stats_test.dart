// 加油费用聚合测试（fuel_cost_stats.dart，ADR 0015）：年度行铺满与
// 倒序、月度 12 桶、实付优先口径（没填取应付）、空记录空态。
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

  group('fuelCostCentsForYear / fuelMonthlyCents（实付优先口径）', () {
    test('实付填了取实付，没填取应付', () {
      final records = [
        record('2026-09-01', payableCents: 30000, actualCents: 27000),
        record('2026-09-15', payableCents: 30000),
      ];
      // 270 + 300 = ¥570.00。
      expect(fuelCostCentsForYear(records, 2026), 57000);
    });

    test('月度桶按月份落位，无记录月为 0', () {
      final records = [
        record('2026-01-10', payableCents: 10000),
        record('2026-03-02', payableCents: 20000, actualCents: 18000),
      ];
      final months = fuelMonthlyCents(records, 2026);
      expect(months, hasLength(12));
      expect(months[0], 10000);
      expect(months[2], 18000);
      expect(months[1], 0);
      // 跨年记录不串桶。
      expect(fuelMonthlyCents(records, 2025), everyElement(0));
    });
  });

  group('buildFuelCostStats', () {
    test('年度行从今年倒序铺回首条记录年，中间无记录年补 0', () {
      final stats = buildFuelCostStats(
        records: [
          record('2024-03-01', payableCents: 10000),
          record('2026-09-01', payableCents: 30000),
        ],
        today: today,
      );
      // 2026 / 2025（补 0）/ 2024，最近年在前。
      expect(
        stats.yearRows.map((row) => (row.year, row.costCents)).toList(),
        [(2026, 30000), (2025, 0), (2024, 10000)],
      );
      expect(stats.totalCents, 40000);
      expect(stats.recordCount, 2);
    });

    test('空记录：总额 0、年度行为空', () {
      final stats = buildFuelCostStats(records: const [], today: today);
      expect(stats.totalCents, 0);
      expect(stats.recordCount, 0);
      expect(stats.yearRows, isEmpty);
    });
  });
}
