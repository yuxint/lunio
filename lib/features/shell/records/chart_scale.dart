// 坐标系柱状图的刻度标尺纯函数（chart_scale.dart，2026-10-01 收编）：
// 坐标系柱状图模块 AxesColumnChart（axes_column_chart.dart，保养年度柱
// + 加油月度柱共用）标尺计算的唯一实现。
//
// 职责（全部纯函数与不可变值对象，无 widget、无副作用，可直接单测）：
//   1. 刻度三档步进阶梯（chartScaleFor）：0 / 半峰 / 峰三条刻度——步进
//      取整到常见金额档（¥50 → ¥1 万），取第一个不小于最大柱值一半的
//      步进，峰刻度 = 步进 × 2 ≥ 最大柱值，最高柱顶不会顶穿网格线；
//   2. 柱高按峰刻度归一（ChartScale.fractionOf）：柱值占峰刻度的比例
//      （0~1），柱顶不会越过峰刻度线；
//   3. 滚动模式列宽取整校准（calibrateColumnWidth）：内容放得下视口返
//      回 null（调用方等分铺满、不出滚动条）；放不下返回校准列宽——视
//      口取整放下整数根柱、柱宽在基准宽上微调放大（分摊 ≤ 一柱），滚动
//      范围因此恒为柱宽整数倍，初始停最右时左右两缘都是完整的柱。
//
// 在 App 中的位置：只被坐标系柱状图模块 axes_column_chart.dart 消费
// （年度柱与月度柱同一把尺、间接服务费用统计页）；下一张同坐标系图
// （比如项目维度的月度趋势）接入时复用本文件——调刻度档位只改这一
// 处，直接跑单测验证。
// ≈ Java Web 里报表页抽出来的标尺工具类（静态工厂 + 不可变值对象），
// 图表组件只管渲染皮。
//
// 边界约定：金额（分）一律非负——柱值来自费用合计；几何常量（基准列
// 宽等）是视觉 token，由调用方注入（先例：RowSnapScrollPhysics 收
// rowExtent），本文件不自定义。

/// 坐标系柱状图的一把刻度标尺：三档刻度 + 按峰刻度的归一比例。
///
/// 经 [chartScaleFor] 按最大柱值构造；构造器公开仅供测试直构退化标尺
/// （全 0 刻度）验证 [fractionOf] 的守卫，正常路径不要手拼。
class ChartScale {
  const ChartScale(this.ticks);

  /// 三档刻度（分）：[0, 半峰, 峰]，恒严格升序，峰 ≥ 构造时的最大柱值。
  final List<int> ticks;

  /// 峰刻度（分）= ticks[2]。归一比例的分母、柱高的满格线。
  int get peakCents => ticks[2];

  /// 柱值的归一比例（0~1）= 柱值 ÷ 峰刻度；峰为 0（全 0 刻度的退化标尺）
  /// 恒 0——不除零，所有柱都是基线桩。图表的 y 坐标换算与柱高共用同一
  /// 份比例（同一把尺）。
  double fractionOf(int cents) => peakCents == 0 ? 0.0 : cents / peakCents;
}

/// 按最大柱值算一把刻度标尺（0 / 半峰 / 峰三档）。
///
/// 步进阶梯：¥50 → ¥1 万的常见金额档（5000 → 1000000 分，升序），取第
/// 一个不小于 [maxValueCents] 一半的档作半峰步进——峰刻度 = 步进 × 2 ≥
/// [maxValueCents]，柱顶不顶穿峰刻度网格线；全 0 柱落最小档
/// [0, ¥50, ¥100]，坐标参照（基线/半峰/峰）照常可画。
/// 兜底分支：[maxValueCents] 超过阶梯顶（> ¥2 万）时峰取整到 ¥1 万的
/// 整数倍向上（ceil 不吃掉峰值），半峰 = 峰 ÷ 2（¥1 万是偶数分值，
/// 恒整除）。
ChartScale chartScaleFor(int maxValueCents) {
  const steps = [
    5000,
    10000,
    20000,
    25000,
    50000,
    100000,
    200000,
    250000,
    500000,
    1000000,
  ];
  for (final step in steps) {
    if (step >= maxValueCents / 2) {
      return ChartScale([0, step, step * 2]);
    }
  }
  final top = (maxValueCents / 1000000).ceil() * 1000000;
  return ChartScale([0, top ~/ 2, top]);
}

/// 滚动模式的列宽取整校准：内容宽（[columnCount] × [baseColumnWidth]）
/// 放得下 [viewportWidth] 时返回 null——调用方等分铺满、不出滚动条；放
/// 不下时返回校准列宽：视口取整放下整数根柱（floor），列宽 = 视口宽 ÷
/// 可见列数（在基准宽上微调放大，分摊 ≤ 一柱）。
///
/// 滚动范围（列数 × 列宽 − 视口宽）因此恒为列宽的整数倍——初始停最右
/// 时左右两缘都是完整的柱，不露半根。恰好相等（内容宽 == 视口宽）按放
/// 得下处理：等分铺满每列正好基准宽，与校准列宽等价。视口比一根基准柱
/// 还窄的退化布局（正常页面不可达）clamp 到 1 列——返回视口宽本身，宁
/// 可柱变窄也不出 Infinity。
double? calibrateColumnWidth({
  required int columnCount,
  required double baseColumnWidth,
  required double viewportWidth,
}) {
  if (columnCount * baseColumnWidth <= viewportWidth) {
    return null;
  }
  final visibleColumns = (viewportWidth / baseColumnWidth).floor();
  if (visibleColumns < 1) {
    return viewportWidth;
  }
  return viewportWidth / visibleColumns;
}
