// 车辆诊断业务规则直测（票 05）：油量卡升数估算纯函数。
// 变异口径：把 percent/100 改成 percent 直乘（漏除 100）→ 首个用例红；
// 把 null 容积分支改成返回 0 → 第二个用例红。
import 'package:flutter_test/flutter_test.dart';
import 'package:lunio/domain/rules/diagnostics_rules.dart';

void main() {
  group('DiagnosticsRules.estimateFuelLiters', () {
    test('百分比 × 容积 = 升数（96/255≈37.6% × 55L ≈ 20.7L，语料值）', () {
      final percent = 96 * 100 / 255; // 37.6471%
      final liters = DiagnosticsRules.estimateFuelLiters(percent, 55);
      expect(liters!, closeTo(20.7, 0.1));
    });

    test('容积未填返回 null（页面只显百分比、不提示去填，story 11）', () {
      expect(DiagnosticsRules.estimateFuelLiters(37.6, null), isNull);
    });

    test('0% 与 100% 边界（0 升 / 整箱容积）', () {
      expect(DiagnosticsRules.estimateFuelLiters(0, 55), equals(0.0));
      expect(DiagnosticsRules.estimateFuelLiters(100, 55), equals(55.0));
    });
  });

  group('DiagnosticsRules.estimateFuel（ADR 0022 双油量）', () {
    test('思域口径：23.137% × 40.487 可用 + 6.513 储备 = 15.879 估算总', () {
      final estimate = DiagnosticsRules.estimateFuel(
        percent: 59 / 255 * 100, // CSV 原始 59/255 = 23.137%
        tankCapacityLiters: 40.487,
        totalTankCapacityLiters: 47,
      );
      expect(estimate, isNotNull);
      expect(estimate!.usableLiters, closeTo(9.37, 0.01));
      expect(estimate.reserveLiters, closeTo(6.513, 0.001));
      expect(estimate.totalLiters, closeTo(15.88, 0.01));
    });

    test('总容积未填或小于可用容积：只返回可用，不造负储备', () {
      final noTotal = DiagnosticsRules.estimateFuel(
        percent: 50,
        tankCapacityLiters: 40,
      );
      expect(noTotal!.usableLiters, 20);
      expect(noTotal.reserveLiters, isNull);
      expect(noTotal.totalLiters, isNull);

      final dirty = DiagnosticsRules.estimateFuel(
        percent: 50,
        tankCapacityLiters: 40,
        totalTankCapacityLiters: 30,
      );
      expect(dirty!.totalLiters, isNull);
      expect(
        DiagnosticsRules.estimateFuel(
          percent: 50,
          totalTankCapacityLiters: 47,
        ),
        isNull,
      );
    });

    test('0% / 100% 边界：总油量 = 储备 / 总容积', () {
      final empty = DiagnosticsRules.estimateFuel(
        percent: 0,
        tankCapacityLiters: 40,
        totalTankCapacityLiters: 47,
      )!;
      expect(empty.usableLiters, 0);
      expect(empty.totalLiters, closeTo(7, 0.001));

      final full = DiagnosticsRules.estimateFuel(
        percent: 100,
        tankCapacityLiters: 40,
        totalTankCapacityLiters: 47,
      )!;
      expect(full.usableLiters, 40);
      expect(full.totalLiters, closeTo(47, 0.001));
    });
  });
}
