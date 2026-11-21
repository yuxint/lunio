import 'package:flutter_test/flutter_test.dart';
import 'package:lunio/features/shell/diagnostics/fuel_level_gate.dart';

/// 油量门限单测（2026-11-21 二次修订：3 拍极差 ≤5 且三拍严格同侧才移动
/// 卡片，目标取窗口中位数）。序列取自实车日志 docs/car_obd_link/data/。
void main() {
  group('冷启动与播种', () {
    test('无基准首拍直接采纳并起窗', () {
      final gate = FuelLevelGate();
      expect(gate.acceptedPercent, isNull);
      expect(gate.admit(51), 51);
      expect(gate.acceptedPercent, 51);
      expect(gate.windowSampleCount, 1);
    });

    test('seed 播种后，窗口未满的拍保持不更新', () {
      final gate = FuelLevelGate()..seed(40);
      expect(gate.acceptedPercent, 40);
      expect(gate.admit(42), isNull); // 窗口 1
      expect(gate.admit(41), isNull); // 窗口 2
      expect(gate.acceptedPercent, 40);
    });

    test('seed 不覆盖已采纳值', () {
      final gate = FuelLevelGate();
      gate.admit(50);
      gate.seed(90);
      expect(gate.acceptedPercent, 50);
    });
  });

  group('窗口聚合', () {
    test('三拍同侧且极差 ≤5 → 采用中位数', () {
      final gate = FuelLevelGate()..seed(50);
      expect(gate.admit(44), isNull); // 窗口 1
      expect(gate.admit(45), isNull); // 窗口 2
      expect(gate.admit(46), 45); // [44,45,46] 全低于 50 → 中位 45
      expect(gate.acceptedPercent, 45);
    });

    test('混合窗口不推动卡片（回归：行驶中 40→42 的上涨）', () {
      // 11-21 早真实片段：卡片 40，随后原始 40/43/42——中位数是 42，
      // 但窗口里有个 40 与卡片持平，方向不成立，必须保持。
      final gate = FuelLevelGate()..seed(40);
      expect(gate.admit(40), isNull);
      expect(gate.admit(43), isNull);
      expect(gate.admit(42), isNull);
      expect(gate.acceptedPercent, 40);
    });

    test('三拍发散 → 保持现值（晃动尾巴不上卡）', () {
      final gate = FuelLevelGate()..seed(40);
      expect(gate.admit(16), isNull);
      expect(gate.admit(38), isNull);
      expect(gate.admit(31), isNull); // [16,38,31] 极差 22 → 丢弃
      expect(gate.acceptedPercent, 40);
    });

    test('全等窗口视为一致：返回卡片值、不算拒绝', () {
      final gate = FuelLevelGate()..seed(40);
      expect(gate.admit(40), isNull); // 窗口 1
      expect(gate.admit(40), isNull); // 窗口 2
      expect(gate.admit(40), 40); // 三拍全等于卡片
    });

    test('中位数不等于最新值：卡片取中位数而非最新', () {
      final gate = FuelLevelGate()..seed(50);
      gate.admit(45); // [45]
      gate.admit(46); // [45,46]
      expect(gate.admit(44), 45); // [45,46,44] 全低于 50 → 中位 45（最新 44）
      expect(gate.acceptedPercent, 45);
    });

    test('真变化三拍同侧 → 第三拍采纳（不受旧值牵制）', () {
      final gate = FuelLevelGate()..seed(50);
      expect(gate.admit(30), isNull);
      expect(gate.admit(31), isNull);
      expect(gate.admit(30), 30); // [30,31,30] 全低于 50 → 30
    });

    test('窗口滑动：离群值滑出后恢复采纳', () {
      final gate = FuelLevelGate()..seed(40);
      expect(gate.admit(40), isNull); // [40,40]
      expect(gate.admit(27), isNull); // [40,40,27] 极差 13
      expect(gate.admit(40), isNull); // [40,27,40] 极差 13
      expect(gate.admit(40), isNull); // [27,40,40] 极差 13
      expect(gate.admit(39), isNull); // [40,40,39] 混合（40 不平移）
      expect(gate.admit(39), isNull); // [40,39,39] 混合
      expect(gate.admit(39), 39); // [39,39,39] 全低于 40 → 39
    });

    test('窗口状态可读（门限日志用）', () {
      final gate = FuelLevelGate()..seed(40);
      expect(gate.windowSampleCount, 0);
      expect(gate.windowSpan, isNull);
      gate.admit(44);
      gate.admit(40);
      expect(gate.windowSampleCount, 2);
      expect(gate.windowSpan, 4);
    });
  });

  group('手动刷新直显', () {
    test('override 直接定值并清窗，随后重新积窗', () {
      final gate = FuelLevelGate()..seed(40);
      gate.admit(44);
      gate.override(27);
      expect(gate.acceptedPercent, 27);
      expect(gate.windowSampleCount, 0);
      expect(gate.admit(27), isNull); // 窗口重新积累
      expect(gate.acceptedPercent, 27);
    });
  });

  group('实车序列回归', () {
    /// 按门限复算卡片展示序列（被丢弃的拍沿用上一拍卡片值）。
    List<int> replay(List<int> raw) {
      final gate = FuelLevelGate();
      final card = <int>[];
      var last = raw.first;
      for (final value in raw) {
        final admitted = gate.admit(value.toDouble());
        if (admitted != null) {
          last = admitted.round();
        }
        card.add(last);
      }
      return card;
    }

    test('11-21 早 9 拍：27% 不上卡，全程不出现行驶中上涨', () {
      final card = replay([40, 40, 43, 42, 38, 40, 27, 40, 39]);
      expect(card, [40, 40, 40, 40, 40, 40, 40, 40, 40]);
      expect(card, isNot(contains(27)));
      // 严格不增：行驶中油量只可能下降。
      for (var i = 1; i < card.length; i++) {
        expect(card[i], lessThanOrEqualTo(card[i - 1]));
      }
    });

    test('11-20 晚 15 拍：16%/20%/31% 不上卡，末值 40%', () {
      final card = replay(
        [54, 53, 40, 45, 44, 44, 40, 40, 39, 51, 16, 38, 31, 20, 44],
      );
      expect(card, [
        54, 54, 54, 54, 44, 44, 44, 44, 40, 40, 40, 40, 40, 40, 40, //
      ]);
      expect(card, isNot(contains(16)));
      expect(card, isNot(contains(20)));
      expect(card, isNot(contains(31)));
      expect(card, isNot(contains(51)));
    });
  });
}
