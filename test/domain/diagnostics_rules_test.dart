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
}
