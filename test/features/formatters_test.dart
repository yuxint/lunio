// formatters.dart 的 parseMoneyCents（表单金额「元文本 → 分」唯一解析
// 接缝）直接单测：trim、空/非法 = null（未填）、元→分四舍五入的半分
// 进位与亚分舍去、负数原样过接缝（符号校验归调用方的校验阶梯）。
// 不打 widget、不连数据库——纯函数直喂文本。
// 收编背景：保养记录表单总费用、加油记录表单三个金额、手填油价表单
// 原先各自手写「double.tryParse → ×100 → round」，取整口径分散在各
// 控制器测试里守着；2026-10-01 收编到接缝后口径的唯一实现点在这里
// 直接守卫（票据 .scratch/arch-1001/issues/08）。
// 断言全部用精确值：取整方向、trim、空串语义被变异时至少一条会红。

import 'package:flutter_test/flutter_test.dart';
import 'package:lunio/features/shell/shared/formatters.dart';

void main() {
  group('parseMoneyCents（元文本 → 分，唯一解析接缝）', () {
    test('空与纯空白 → null（= 未填）', () {
      expect(parseMoneyCents(''), isNull);
      expect(parseMoneyCents('   '), isNull);
    });

    test('非法文本 → null', () {
      expect(parseMoneyCents('abc'), isNull);
      expect(parseMoneyCents('8.1.5'), isNull);
      expect(parseMoneyCents('.'), isNull);
    });

    test('首尾空白照常解析（trim）', () {
      expect(parseMoneyCents(' 8.15 '), 815);
      expect(parseMoneyCents('\t300\n'), 30000);
    });

    test('元→分四舍五入：常规两位小数与整数', () {
      expect(parseMoneyCents('8.15'), 815);
      expect(parseMoneyCents('300'), 30000);
      expect(parseMoneyCents('270.50'), 27050);
      expect(parseMoneyCents('0.01'), 1);
      expect(parseMoneyCents('99.99'), 9999);
    });

    test('三位小数：半分进位（Dart round 远离零取半）与亚分舍去', () {
      // 300.005 元 → 30000.5 分 → 进位 30001（控制器单测锁定的口径）。
      expect(parseMoneyCents('300.005'), 30001);
      // 0.005 元 → 0.5 分 → 进位 1 分。
      expect(parseMoneyCents('0.005'), 1);
      // 0.004 元 → 0.4 分 → 舍去 0 分。
      expect(parseMoneyCents('0.004'), 0);
    });

    test('负数原样过接缝：符号校验归调用方，接缝只解析取整', () {
      expect(parseMoneyCents('-1'), -100);
      expect(parseMoneyCents('-0.5'), -50);
      // -0.004 元取整到 0 分（亚分负值不保留符号）。
      expect(parseMoneyCents('-0.004'), 0);
    });
  });
}
