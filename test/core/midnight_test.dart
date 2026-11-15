// core 层日期调度纯函数测试（ADR 0025）：untilNextMidnight 的边界。
//
// 锁四类事实：23:59:59 剩 1 秒；整点零点返回整天（不是 0，防零时长
// 定时器自旋）；月末/年末/闰日由本地日历归一化自然进位；正常时刻整数
// 小时差。日期算术与运行日解耦，显式构造时刻。
import 'package:flutter_test/flutter_test.dart';

import 'package:lunio/core/date/midnight.dart';

void main() {
  group('untilNextMidnight', () {
    test('23:59:59 距零点 1 秒', () {
      expect(
        untilNextMidnight(DateTime(2026, 5, 19, 23, 59, 59)),
        const Duration(seconds: 1),
      );
    });

    test('整点零点返回整天，不是 0（防自旋）', () {
      expect(
        untilNextMidnight(DateTime(2026, 5, 19)),
        const Duration(days: 1),
      );
    });

    test('月末跨月：5 月 31 日 20:00 到 6 月 1 日零点', () {
      expect(
        untilNextMidnight(DateTime(2026, 5, 31, 20)),
        const Duration(hours: 4),
      );
    });

    test('年末跨年：12 月 31 日 20:00 到次年 1 月 1 日零点', () {
      expect(
        untilNextMidnight(DateTime(2026, 12, 31, 20)),
        const Duration(hours: 4),
      );
    });

    test('闰年 2 月末：2 月 28 日 20:00 到 2 月 29 日零点', () {
      expect(
        untilNextMidnight(DateTime(2028, 2, 28, 20)),
        const Duration(hours: 4),
      );
    });

    test('非闰年 2 月末：2 月 28 日 20:00 到 3 月 1 日零点', () {
      expect(
        untilNextMidnight(DateTime(2027, 2, 28, 20)),
        const Duration(hours: 4),
      );
    });

    test('正午 12:00 距零点 12 小时', () {
      expect(
        untilNextMidnight(DateTime(2026, 5, 19, 12)),
        const Duration(hours: 12),
      );
    });
  });
}
