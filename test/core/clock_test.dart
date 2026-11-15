// core 层格式化测试：formatReadingTime 读数时刻显示（2026-11-15）。
// 与运行日解耦：now 显式注入，今天/跨天两形态锁死。
import 'package:flutter_test/flutter_test.dart';

import 'package:lunio/core/format/clock.dart';

void main() {
  group('formatReadingTime', () {
    test('今天显 HH:mm:ss（视觉不变）', () {
      final now = DateTime(2026, 11, 15, 20, 0, 0);
      final at = DateTime(2026, 11, 15, 8, 5, 9);
      expect(formatReadingTime(at, now: now), '08:05:09');
    });

    test('非今天显 M/d HH:mm:ss（跨天带日期）', () {
      final now = DateTime(2026, 11, 15, 20, 0, 0);
      final at = DateTime(2026, 11, 14, 8, 5, 9);
      expect(formatReadingTime(at, now: now), '11/14 08:05:09');
    });

    test('跨年同样带日期', () {
      final now = DateTime(2026, 11, 15);
      final at = DateTime(2025, 12, 31, 23, 59, 59);
      expect(formatReadingTime(at, now: now), '12/31 23:59:59');
    });
});
}
