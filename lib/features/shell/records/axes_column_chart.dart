// 坐标系柱状图模块（axes_column_chart.dart，2026-10-06 收编）：费用统计
// 页「保养费用」年度柱与「加油费用」月度柱共用的有名字的坐标系柱状图
// 的唯一实现。收编前这段渲染体（柱数据项、纵轴刻度、虚线网格 painter、
// 铺满/滚动/初始停最右/停稳吸附的编排）长在 cost_stats_page.dart 的私有
// 类里——下一轮图表行为调整（滚动条、柱宽）要动全仓最大的统计页文件，
// 私有类型对「下一张同坐标系图接入复用」不可达；收编后调图表行为只改
// 本文件，统计页只剩页面组装。
//
// 与 chart_scale.dart 的分工：那把尺（刻度三档步进、柱高按峰刻度归一、
// 滚动模式列宽取整校准）是纯函数、直接单测 test/features/chart_scale_
// test.dart；本文件是消费尺的渲染皮（算尺在 chart_scale.dart、画图在这
// 里），几何常量（列宽/柱宽/槽高）作为视觉 token 收在本模块内部。
//
// 入场动画契约：柱高随 [entrance] 长高——整图包在监听动画的
// AnimatedBuilder 里。历史上按年条漏包导致"有时不渲染、点开才出来"的
// bug（动画只重建 AnimatedBuilder 子树），调用方传入的动画与组件内部
// 的包法都要维持这一约定。
// Java 类比：报表页抽出来的自定义图表控件（JFreeChart 的一个简化柱状
// 图变体），数据项与标尺注入、渲染细节收口在控件内。
// ignore_for_file: library_private_types_in_public_api

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/lunio_tokens.dart';
import '../shared/shell_shared.dart';
import 'chart_scale.dart';

/// 坐标系柱状图的一列数据（2026-09-24 A 方案）：柱值 + 轴标签。刻度与
/// 柱高比例由 [AxesColumnChart] 按全部柱值统一计算（同一把尺）；柱体
/// 颜色统一主色（2026-09-24 第五轮拍板，无高亮语义）。
class AxesColumnItem {
  const AxesColumnItem({
    required this.valueCents,
    required this.axisLabel,
    required this.barKey,
  });

  /// 柱值（分）；0 = 无花费，柱顶不标金额（只留灰色基线桩）。
  final int valueCents;

  /// 柱下轴标签（年度柱「2024」/ 月度柱「26.9」）。
  final String axisLabel;

  /// 柱体 key（widget 测试按 key 断言柱存在与几何）。
  final Key barKey;
}

/// 坐标系柱状图（2026-09-24 A 方案；同日第五轮行为统一）：左侧纵轴固
/// 定（0 / 半峰 / 峰三条刻度金额，步进自适应取整、峰刻度 ≥ 最大柱值）
/// + 横向虚线网格线 + 柱列；柱顶标金额、轴标签在柱下，柱体统一主色。
/// 行为单一（第五轮拍板，保养年度柱与加油月度柱同一套）：列放得下视
/// 口时等分铺满、无滚动条；放不下时定宽横向滚动，底部 3dp 细滚动条
/// （2026-09-26 起滑动时淡入、停稳淡出）、初始停最右——纵轴不随滚动
/// 消失，金额参照始终可见。柱高随入场
/// 动画长高——整图包在监听 [entrance] 的 AnimatedBuilder 里（入场
/// 动画契约见文件头：漏包导致条形停在进度 0 的历史 bug）。
class AxesColumnChart extends StatefulWidget {
  const AxesColumnChart({
    super.key,
    required this.items,
    required this.entrance,
  });

  final List<AxesColumnItem> items;

  final Animation<double> entrance;

  @override
  State<AxesColumnChart> createState() => _AxesColumnChartState();
}

class _AxesColumnChartState extends State<AxesColumnChart> {
  /// 纵轴列宽 / 滚动模式列宽（第五轮 48→64：一屏约 4~5 个月，拉开柱
  /// 顶金额的间距）/ 柱体宽（年度柱与月度柱统一）/ 金额槽高 / 柱区高 /
  /// 轴标签槽高（含上间距）。金额槽 16 = 12px 字号的实际行高
  /// （2026-09-24 二轮提字号：槽只有 12 时 FittedBox 会把 12px 文字再
  /// 缩回 ~9px，等于白提——槽高必须 ≥ 字号行高，提字号才算数）。
  static const _axisWidth = 34.0;
  static const _columnWidth = 64.0;
  static const _barWidth = 16.0;
  static const _amountSlot = 16.0;
  static const _barMaxHeight = 96.0;
  static const _labelSlot = 18.0;

  /// 列总高：金额槽 + 间距 + 柱区 + 轴标签槽。
  static const _plotHeight =
      _amountSlot + 3 + _barMaxHeight + 4 + _labelSlot;

  final ScrollController _scroll = ScrollController();

  /// 初始定位只做一次：之后的重建（数据刷新/入场动画重建）不再打断
  /// 用户的滚动位置。
  bool _jumpedToEnd = false;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// 内容比视口宽时跳到最右端。maxScrollExtent 要等首帧布局后才有值，
  /// 挂 postFrameCallback 读。
  void _scheduleJumpToEnd() {
    if (_jumpedToEnd) {
      return;
    }
    _jumpedToEnd = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) {
        return;
      }
      if (_scroll.position.maxScrollExtent > 0) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  /// 刻度金额文案（整数元，不带小数——轴上两位小数太挤）。
  String _tickLabel(int cents) => '¥${(cents / 100).round()}';

  @override
  Widget build(BuildContext context) {
    _scheduleJumpToEnd();
    return AnimatedBuilder(
      animation: widget.entrance,
      builder: (context, _) {
        final tokens = Theme.of(context).extension<LunioTokens>()!;
        final maxCents = widget.items.fold(
          0,
          (max, item) => item.valueCents > max ? item.valueCents : max,
        );
        // 同一把尺（2026-10-01 收编为 chart_scale.dart 纯函数，直接单
        // 测）：刻度三档 + 柱高归一比例，年度柱与月度柱共用。
        final scale = chartScaleFor(maxCents);
        // 柱区底部（基线）在列内的 y 坐标；柱高按峰刻度归一（而非按最
        // 大柱值），柱顶不会越过峰刻度线。
        final baseY = _plotHeight - _labelSlot;
        double yFor(int cents) =>
            baseY - scale.fractionOf(cents) * _barMaxHeight;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 纵轴：固定在左，不随滚动区移动（滚动时金额参照可见）。
            SizedBox(
              width: _axisWidth,
              height: _plotHeight,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  for (final tick in scale.ticks)
                    Positioned(
                      top: yFor(tick) - 6,
                      right: 0,
                      child: SizedBox(
                        width: _axisWidth - 4,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: Text(
                            _tickLabel(tick),
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  fontSize: 10.5,
                                  color: tokens.subtle,
                                ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // 统一行为（第五轮）：内容宽（列数 × 列宽）放得下视口
                  // 就等分铺满、无滚动条；放不下才定宽横向滚动 + 底部细
                  // 滚动条（2026-09-26 起滑动时才显示拇指）。保养年度柱
                  // 与加油月度柱走同一套逻辑；取整校准收编在
                  // chart_scale.dart 的 calibrateColumnWidth（直接单测），
                  // 返回 null 即放得下。
                  final columnWidth = calibrateColumnWidth(
                    columnCount: widget.items.length,
                    baseColumnWidth: _columnWidth,
                    viewportWidth: constraints.maxWidth,
                  );
                  if (columnWidth == null) {
                    return _plot(context, scale, yFor, tokens);
                  }
                  // 校准列宽：视口取整放下整数根柱——柱宽在 64 基础上微
                  // 调放大（≤ 一柱的分摊），滚动范围因此必然是柱宽整数倍
                  // ——初始停最右时左右两缘都是完整的月/年，不露半根
                  //（2026-09-24 五轮复验反馈）。
                  _scheduleJumpToEnd();
                  // 滚动条样式（3dp/圆角 2/滑动时拇指淡入淡出）与垂直
                  // 两处（档位列表/加油记录卡）的共享组件
                  // LunioSnapScrollWindow 同款，但本图未接入该组件：
                  // 横向滚动拇指画在底边、吸附步长是运行时取整校准的
                  // 动态列宽（非"定行高"前提）、让位是底边 6dp 而非右
                  // 缩进 12dp、还有初始停最右的编排——塞进组件要加五个
                  // 参数，组件会变成参数管道而三明治没少。全局调滚动条
                  // 手感时记得与 scroll_window.dart 同步这两行样式。
                  return Scrollbar(
                    controller: _scroll,
                    thickness: 3,
                    radius: const Radius.circular(2),
                    // 底边留 6dp 给滚动条：拇指画在留白条上，与轴标签
                    // 拉开间距（五轮复验反馈：3dp 太贴）。
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        controller: _scroll,
                        // 停稳吸附整柱（2026-09-24 复验反馈，与加满预估
                        // 同一套吸附物理，按校准后的柱宽取整步长）——手动
                        // 拖停后两缘仍保持完整的月/年；纯手势层对齐，
                        // 不做任何持久化。
                        physics: RowSnapScrollPhysics(rowExtent: columnWidth),
                        child: _plot(
                          context,
                          scale,
                          yFor,
                          tokens,
                          columnWidth: columnWidth,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  /// 绘图区：虚线网格线（三条，含基线）铺满全宽 + 柱列。[columnWidth]
  /// 为 null（放得下）宽 = 视口宽、柱列等分；否则（滚动模式）宽 = 列数
  /// × [columnWidth]（随内容一起滚，列宽由 chart_scale.dart 的
  /// calibrateColumnWidth 取整校准过）。
  Widget _plot(
    BuildContext context,
    ChartScale scale,
    double Function(int) yFor,
    LunioTokens tokens, {
    double? columnWidth,
  }) {
    final stretch = columnWidth == null;
    return SizedBox(
      height: _plotHeight,
      width: stretch ? null : widget.items.length * columnWidth,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (final tick in scale.ticks)
            Positioned(
              left: 0,
              right: 0,
              top: yFor(tick),
              child: SizedBox(
                height: 1,
                width: double.infinity,
                child: CustomPaint(
                  painter: _DashedLinePainter(color: tokens.line),
                ),
              ),
            ),
          Positioned.fill(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final item in widget.items)
                  _column(
                    context,
                    item,
                    scale,
                    widget.entrance.value,
                    columnWidth: columnWidth,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 柱状一列：金额槽（0 元留空）+ 柱体（高按峰刻度归一
  /// （[scale.fractionOf]）、随入场动画长高；0 元画 2dp 灰桩，有花费统
  /// 一主色）+ 轴标签。铺满模式等分视口、滚动模式定宽（[columnWidth]）。
  Widget _column(
    BuildContext context,
    AxesColumnItem item,
    ChartScale scale,
    double progress, {
    double? columnWidth,
  }) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    final hasCost = item.valueCents > 0;
    final fraction = scale.fractionOf(item.valueCents);
    final barHeight = hasCost
        ? (fraction * _barMaxHeight * progress).clamp(3.0, _barMaxHeight)
        : 2.0;
    final Widget column = SizedBox(
      width: columnWidth,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: _amountSlot,
            child: hasCost
                ? FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.center,
                    child: Text(
                      formatMoneyCents(item.valueCents),
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(
                            fontSize: 12,
                            color: tokens.muted,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  )
                : null,
          ),
          const SizedBox(height: 3),
          SizedBox(
            height: _barMaxHeight,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                key: item.barKey,
                width: _barWidth,
                height: barHeight,
                decoration: BoxDecoration(
                  color: hasCost ? tokens.primary : tokens.line,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            item.axisLabel,
            textAlign: TextAlign.center,
            maxLines: 1,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontSize: 11,
                  color: tokens.muted,
                  fontWeight: FontWeight.w500,
                ),
          ),
        ],
      ),
    );
    return columnWidth == null ? Expanded(child: column) : column;
  }
}

/// 横向虚线网格线（1dp 高、3px 划 3px 空）。
class _DashedLinePainter extends CustomPainter {
  const _DashedLinePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    const dash = 3.0;
    for (var x = 0.0; x < size.width; x += dash * 2) {
      canvas.drawLine(
        Offset(x, 0.5),
        Offset(math.min(x + dash, size.width), 0.5),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DashedLinePainter oldDelegate) =>
      oldDelegate.color != color;
}
