// chart_scale.dart 的纯函数单测：刻度步进阶梯各档边界与不变量扫描、峰
// 刻度兜底分支（超阶梯顶取整到 ¥1 万整数倍）、柱高按峰刻度归一比例
//（含全 0 峰守卫）、滚动模式列宽取整校准的放得下/放不下两分支（含恰好
// 相等边界、滚动范围整柱倍数、退化窄视口 clamp）。不打 widget、不连数
// 据库——直接喂分值与几何值。
// 断言全部用精确值：常量被变异（档位表、比较方向、取整方向等）时至少
// 一条断言会红，即变异验证。
// 收编背景：这些决策原先埋在 cost_stats_page.dart 的 _AxesColumnChart
// State 私有方法里，只能靠 widget 测试渲染后断言几何间接验证（2026-10-01
// 收编，票据 .scratch/arch-1001/issues/07）。

import 'package:flutter_test/flutter_test.dart';
import 'package:lunio/features/shell/records/chart_scale.dart';

void main() {
  group('chartScaleFor（刻度三档步进阶梯）', () {
    test('全 0 柱：最小档兜住，三档仍完整', () {
      // 无花费也有刻度参照（基线/半峰/峰网格线照画）。
      expect(chartScaleFor(0).ticks, [0, 5000, 10000]);
    });

    test('半峰恰好落在档位上：取该档（≥ 含等号）', () {
      // max=¥100 → 半峰 ¥50 → 步进 ¥50。
      expect(chartScaleFor(10000).ticks, [0, 5000, 10000]);
      // max=¥400 → 半峰 ¥200 → 步进 ¥200（¥100 档不够：10000 < 20000）。
      expect(chartScaleFor(40000).ticks, [0, 20000, 40000]);
      // max=¥500 → 半峰 ¥250 → 步进 ¥250。
      expect(chartScaleFor(50000).ticks, [0, 25000, 50000]);
      // max=¥1000 → 半峰 ¥500 → 步进 ¥500。
      expect(chartScaleFor(100000).ticks, [0, 50000, 100000]);
      // 阶梯顶：max=¥2 万 → 半峰 ¥1 万 → 最后一档接住、不走兜底。
      expect(chartScaleFor(2000000).ticks, [0, 1000000, 2000000]);
    });

    test('半峰落在档间：向上取下一个更大的档', () {
      // max=¥100.01 → 半峰 ¥50.005 → ¥50 档不够 → 步进 ¥100。
      expect(chartScaleFor(10001).ticks, [0, 10000, 20000]);
      // max=¥400.01 → 半峰 ¥200.005 → 步进 ¥250（跳过 ¥200 档）。
      expect(chartScaleFor(40001).ticks, [0, 25000, 50000]);
    });

    test('兜底分支：最大柱值刚超阶梯顶（> ¥2 万）', () {
      // 半峰 ¥1 万 + 0.5 分，阶梯顶 ¥1 万不够 → 峰取整到 ¥1 万整数倍向
      // 上 = ¥3 万（ceil 不吃掉峰值），半峰 = 峰 ÷ 2。
      expect(chartScaleFor(2000001).ticks, [0, 1500000, 3000000]);
      // 整百万边界：max=¥2.5 万 → ceil(2.5)=3 → 峰 ¥3 万（非 ¥2 万：
      // ¥2.5 万峰值会被 ¥2 万峰刻度吃掉）。
      expect(chartScaleFor(2500000).ticks, [0, 1500000, 3000000]);
    });

    test('兜底分支：峰值超千万', () {
      // ¥2000 万 + 1 分：ceil(2000.000001)=2001 → 峰 ¥2001 万。
      expect(
        chartScaleFor(2000000001).ticks,
        [0, 1000500000, 2001000000],
      );
    });

    test('不变量：峰 ≥ 最大柱值、半峰 = 峰 ÷ 2、三档严格升序', () {
      // 扫一组代表值（各档边界、兜底段、超千万）：变异档位表 / 比较方
      // 向 / ceil 方向时至少一个输入红。
      const maxValues = [
        0,
        1,
        4999,
        5000,
        9999,
        10000,
        10001,
        40000,
        50000,
        100000,
        1000000,
        1999999,
        2000000,
        2000001,
        2500000,
        999999999,
        2000000001,
        12345678901234,
      ];
      for (final max in maxValues) {
        final scale = chartScaleFor(max);
        expect(scale.ticks, hasLength(3));
        expect(scale.ticks[0], 0);
        expect(scale.ticks[2], greaterThanOrEqualTo(max),
            reason: 'max=$max 时峰刻度被吃掉');
        expect(scale.ticks[1], scale.ticks[2] ~/ 2, reason: 'max=$max');
        expect(scale.ticks[0], lessThan(scale.ticks[1]), reason: 'max=$max');
        expect(scale.ticks[1], lessThan(scale.ticks[2]), reason: 'max=$max');
      }
    });
  });

  group('ChartScale.fractionOf（柱高按峰刻度归一）', () {
    test('常规：0 → 0、半峰 → 0.5、峰 → 1.0，中间线性', () {
      // 与 widget 测试同场景：最大柱 ¥280 → 半峰步进 ¥200、峰刻度 ¥400。
      final scale = chartScaleFor(28000);
      expect(scale.peakCents, 40000);
      expect(scale.fractionOf(0), 0.0);
      expect(scale.fractionOf(20000), 0.5);
      expect(scale.fractionOf(28000), 0.7); // 28000 / 40000。
      expect(scale.fractionOf(40000), 1.0);
    });

    test('全 0 峰守卫：峰为 0 的退化标尺任何柱值比例恒 0（不除零）', () {
      // chartScaleFor 产不出峰 0（全 0 柱也落最小档），守卫防的是直接
      // 构造的退化标尺——直构验证语义（与 cost_stats.dart 里
      // allocateDiscount 的防御性兜底同款惯例）。
      const scale = ChartScale([0, 0, 0]);
      expect(scale.peakCents, 0);
      expect(scale.fractionOf(0), 0.0);
      expect(scale.fractionOf(12345), 0.0);
    });
  });

  group('calibrateColumnWidth（滚动模式列宽取整校准）', () {
    test('放得下：返回 null（等分铺满、不出滚动条）', () {
      expect(
        calibrateColumnWidth(
          columnCount: 2,
          baseColumnWidth: 64,
          viewportWidth: 731,
        ),
        isNull,
      );
    });

    test('恰好相等边界：内容宽 == 视口宽按放得下处理', () {
      // 严格大于才滚动：3 × 64 = 192 == 192 视口时等分铺满每列正好 64，
      // 与校准列宽等价，走无滚动分支。
      expect(
        calibrateColumnWidth(
          columnCount: 3,
          baseColumnWidth: 64,
          viewportWidth: 192,
        ),
        isNull,
      );
    });

    test('放不下：视口取整放下整数根柱、柱宽微调放大', () {
      // 6 × 64 = 384 > 300 → 可见 4 根（floor(300 / 64) = 4）→ 列宽 75。
      expect(
        calibrateColumnWidth(
          columnCount: 6,
          baseColumnWidth: 64,
          viewportWidth: 300,
        ),
        75.0,
      );
    });

    test('放不下不变量：滚动范围恒为列宽整数倍（两缘不露半根柱）', () {
      // 加油月度柱的真实量级：31 个月 × 64 = 1984 > 731 视口。
      final width = calibrateColumnWidth(
        columnCount: 31,
        baseColumnWidth: 64,
        viewportWidth: 731,
      )!;
      expect(width, greaterThanOrEqualTo(64)); // 只放大不缩小。
      final scrollExtent = 31 * width - 731;
      // 初始停最右时左右两缘都是完整的柱：滚动范围 ÷ 列宽 = 整数
      //（浮点容差：31 × (731 / 11) 的舍入误差 << 1e-9）。
      expect(scrollExtent / width % 1.0, closeTo(0, 1e-9));
    });

    test('退化窄视口：比一根基准柱还窄时 clamp 到 1 列（不出 Infinity）', () {
      // 正常布局不可达（Expanded 内视口至少几百 px）；clamp 把原本必崩
      // 的 Infinity（视口 ÷ 0 可见列）变成退化但可用。
      expect(
        calibrateColumnWidth(
          columnCount: 5,
          baseColumnWidth: 64,
          viewportWidth: 30,
        ),
        30.0,
      );
    });
  });
}
