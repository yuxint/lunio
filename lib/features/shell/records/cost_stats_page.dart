// 花费统计页（/cost-stats）：保养花费全貌的独立 pushed 子页。
//
// 本 App 第一个不挂主壳层的 pushed 路由：从记录页汇总行或我的页设置行
// 经 go_router push 进栈（默认转场，iOS 右滑返回天然可用），返回键由
// LunioTopBar 的 leading 位提供；顶部安全区由 LunioPage 内置 SafeArea
// 解决（页面自带 Scaffold 但不自己处理留白，见 lunio_components.dart）。
// 不在栈内时不渲染底部导航，因此 LunioPage 的 bottomPadding 用小值。
//
// 结构（全部纯读取聚合，无写库、无动作层参与）：
//   1. 汇总卡：总花费 + 今年花费；
//   2. 按年花费：渐变胶囊条 + 入场生长动画；
//   3. 项目占比：自绘环形图——一段一项目，段内"实付实色 + 优惠同色
//      半透明"，环心 = 项目口径实付合计 + 累计优惠，旁列图例；
//   4. 近 12 个月走势：平滑曲线 + 渐变面积填充，峰值月打点高亮。
// 作用域永远是当前应用车辆（2026-09-20 拍板：不提供"全部"/多车切换，
// 想看别的车先去切换应用车辆），当前车辆名在标题副字展示。
// 三张图表全部 CustomPainter 自绘、无图表库，颜色派生自 LunioTokens；
// 动效只做一次性入场（生长/扇开/展开），进页面播一次，不做持续循环。
// 聚合口径统一收在 cost_stats.dart（纯函数），本文件只负责"把当前车
// 的数据拿到"与渲染；无车辆/无记录时给空态卡。
// Java 类比：一个只读报表页——provider ≈ 按当前车参数化的查询服务，
// 页面本身只做组装结果的表达。
// ignore_for_file: use_key_in_widget_constructors
// ignore_for_file: library_private_types_in_public_api

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/date/local_date.dart';
import '../../../core/theme/lunio_tokens.dart';
import '../../../core/widgets/lunio_components.dart';
import '../../../domain/entities/maintenance_item.dart';
import '../../../domain/entities/maintenance_record.dart';
import '../shared/shell_shared.dart';
import 'cost_stats.dart';

/// 统计页要用的全部数据：当前应用车辆名（null = 无车）、该车记录、
/// 项目清单（项目名解析用）、生效今天。
class CostStatsPageData {
  const CostStatsPageData({
    required this.carName,
    required this.records,
    required this.items,
    required this.today,
  });

  /// 当前应用车辆显示名（"品牌 型号"）；null = 没有应用车辆（无车）。
  final String? carName;

  final List<MaintenanceRecord> records;
  final List<MaintenanceItem> items;
  final LocalDate today;
}

/// 统计页数据接缝：当前应用车辆的记录与项目清单。直接取按车 family
/// （[recordsForCarProvider] / [maintenanceItemsForCarProvider]），复用
/// 既有按车查询、无新 SQL；失效随家族走——写库后
/// [invalidateVehicleProviders] 整族逐出，这里 watch 上游自动重算。
/// 应用车辆未解析时整页在 build 门卫里 loading，本 provider 只在解析
/// 完成后才会被 watch。
final costStatsDataProvider = FutureProvider<CostStatsPageData>((ref) async {
  final today = await ref.watch(effectiveTodayProvider.future);
  final car = await ref.watch(appliedCarProvider.future);
  if (car == null || car.id == null) {
    return CostStatsPageData(
      carName: null,
      records: const [],
      items: const [],
      today: today,
    );
  }
  final records = await ref.watch(recordsForCarProvider(car.id!).future);
  final items = await ref.watch(maintenanceItemsForCarProvider(car.id!).future);
  return CostStatsPageData(
    carName: '${car.brand} ${car.model}',
    records: records,
    items: items,
    today: today,
  );
});

/// 花费统计页主组件。
class CostStatsPage extends ConsumerStatefulWidget {
  const CostStatsPage();

  @override
  ConsumerState<CostStatsPage> createState() => CostStatsPageState();
}

class CostStatsPageState extends ConsumerState<CostStatsPage>
    with SingleTickerProviderStateMixin {
  /// 一次性入场动画：进页面、数据首次渲染后播一次（0→1，三张图共用
  /// ——年条按宽度生长、环形按弧度扇开、走势按宽度展开），完成后不再
  /// 重播；不做持续循环动画（省电、不干扰阅读）。在 initState 创建
  /// （延迟初始化会在"整页从未进数据分支"的用例里于 dispose 时才首次
  /// 构造，在失活树上找 TickerMode 祖先直接抛异常）。
  late final AnimationController _entrance;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
  }

  bool _entranceStarted = false;

  /// pushed 子页的返回键：数据分支给 LunioPage 的 leading 位，
  /// 作用域解析失败/数据加载失败的 ErrorPage 分支也要给——否则页内
  /// 没有任何返回途径（只剩 iOS 右滑/系统返回手势）。
  Widget _backKey() => LunioIconButton(
        icon: Icons.arrow_back_ios_new,
        tooltip: '返回',
        onPressed: () => context.pop(),
      );

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    // 作用域 = 当前应用车辆：应用车辆未就绪（含其上游车辆清单 loading）
    // 时整页 loading；任一解析失败直接错误页兜底（带返回键），不留在
    // 加载态。应用车辆由车辆清单派生（providers.dart），一份门卫即可。
    final appliedAsync = ref.watch(appliedCarProvider);
    final Widget body;
    if (appliedAsync.isLoading) {
      body = const LoadingPage(title: '花费统计');
    } else if (appliedAsync.hasError) {
      // hasError 已保证 error 非 null（应用车辆与车辆清单同源失败）。
      body = ErrorPage(
        title: '花费统计',
        error: appliedAsync.error!,
        leading: _backKey(),
      );
    } else {
      body = ref.watch(costStatsDataProvider).when(
            loading: () => const LoadingPage(title: '花费统计'),
            error: (error, stackTrace) =>
                ErrorPage(title: '花费统计', error: error, leading: _backKey()),
            data: (data) => _buildContent(context, data),
          );
    }
    // pushed 子页不经过 AppShell，Scaffold（页面底色）要自己提供——
    // 页内的 InkWell/chips 需要 Material 祖先，与 AppShell 同款底色。
    return Scaffold(backgroundColor: tokens.background, body: body);
  }

  Widget _buildContent(BuildContext context, CostStatsPageData data) {
    // 数据首次渲染后再启动入场动画（loading → data 切换后的第一帧），
    // 避免动画在加载期空跑。
    if (!_entranceStarted) {
      _entranceStarted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _entrance.forward();
        }
      });
    }
    final stats = buildCostStats(
      records: data.records,
      items: data.items,
      today: data.today,
    );
    return LunioPage(
      title: '花费统计',
      subtitle: data.carName == null ? null : '当前车辆：${data.carName}',
      leading: _backKey(),
      bottomPadding: 24,
      children: [
        if (data.carName == null)
          const LunioEmptyCard('请先新增车辆')
        else if (data.records.isEmpty)
          const LunioEmptyCard('暂无保养记录，记一笔保养后这里会生成花费统计。')
        else ...[
          _buildSummaryCard(context, stats),
          const SizedBox(height: 12),
          _buildYearCard(context, stats),
          const SizedBox(height: 12),
          _buildDonutCard(context, stats),
          const SizedBox(height: 12),
          _buildTrendCard(context, data.today, stats),
        ],
      ],
    );
  }

  /// 汇总卡：总花费 + 今年花费两栏。
  Widget _buildSummaryCard(BuildContext context, CostStats stats) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    Widget column(String label, int cents) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: tokens.muted,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                formatMoneyCents(cents),
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: tokens.primary,
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ],
          ),
        );
    return LunioCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          column('总花费', stats.totalCents),
          Container(width: 1, height: 40, color: tokens.line),
          const SizedBox(width: 14),
          column('今年花费', stats.thisYearCents),
        ],
      ),
    );
  }

  /// 按年花费卡：渐变胶囊条，入场时按宽度生长（年份升序）。
  Widget _buildYearCard(BuildContext context, CostStats stats) {
    return LunioCard(
      child: LunioSection(
        title: '按年花费',
        children: [
          for (final year in stats.years)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: AnimatedBuilder(
                animation: _entrance,
                builder: (context, _) => _GradientBarRow(
                  label: '${year.year}年',
                  barFraction: year.fraction,
                  valueText: formatMoneyCents(year.costCents),
                  progress: _entrance.value,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 项目占比环形卡：左侧环形（一段一项目，段内"实付实色 + 优惠同色
  /// 半透明"——环的外貌 = 项目原价构成，被优惠吃掉的部分一眼可见；
  /// Top N 之外的费用聚成一枚"其他"段，保证环是完整的圆），环心 =
  /// 项目口径实付合计 + 累计优惠副行；右侧图例逐项列实付/优惠。
  Widget _buildDonutCard(BuildContext context, CostStats stats) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    final slices = <_DonutSlice>[
      for (var index = 0; index < stats.topItems.length; index++)
        (
          name: stats.topItems[index].name,
          value: stats.topItems[index].costCents,
          actual: stats.topItems[index].actualCents,
          discount: stats.topItems[index].discountCents,
          color: _sliceColor(tokens, index),
        ),
    ];
    final topValue = slices.fold(0, (sum, slice) => sum + slice.value);
    final topDiscount = slices.fold(0, (sum, slice) => sum + slice.discount);
    final othersValue = stats.itemTotalCents - topValue;
    final othersDiscount = stats.totalDiscountCents - topDiscount;
    if (othersValue > 0) {
      slices.add((
        name: '其他',
        value: othersValue,
        actual: othersValue - othersDiscount,
        discount: othersDiscount,
        color: tokens.surface3,
      ));
    }
    return LunioCard(
      child: LunioSection(
        title: '项目占比',
        children: [
          AnimatedBuilder(
            animation: _entrance,
            builder: (context, _) {
              return Row(
                children: [
                  SizedBox(
                    width: 148,
                    height: 148,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CustomPaint(
                          size: const Size(148, 148),
                          painter: _DonutPainter(
                            slices: slices,
                            progress: _entrance.value,
                            tokens: tokens,
                          ),
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '项目实付',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(color: tokens.muted),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              formatMoneyCents(stats.itemsActualCents),
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            if (stats.totalDiscountCents > 0) ...[
                              const SizedBox(height: 2),
                              Text(
                                '优惠 ${formatMoneyCents(stats.totalDiscountCents)}',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(
                                      color: tokens.success,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final slice in slices)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: _LegendRow(slice: slice),
                          ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  /// 近 12 个月走势卡：平滑曲线 + 曲线下渐变面积（入场时从左往右展开），
  /// 峰值月打点高亮；标题行右侧给峰值金额。
  Widget _buildTrendCard(
    BuildContext context,
    LocalDate today,
    CostStats stats,
  ) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    final peakCents = stats.months.fold(
      0,
      (max, point) => point.costCents > max ? point.costCents : max,
    );
    return LunioCard(
      child: LunioSection(
        title: '近 12 个月走势',
        trailing: peakCents > 0
            ? Text(
                '峰值 ${formatMoneyCents(peakCents)}',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: tokens.muted,
                    ),
              )
            : null,
        children: [
          const SizedBox(height: 6),
          AnimatedBuilder(
            animation: _entrance,
            builder: (context, _) {
              return SizedBox(
                height: 110,
                child: ClipRect(
                  clipper: _WidthRevealClipper(progress: _entrance.value),
                  child: CustomPaint(
                    painter: _TrendPainter(
                      points: stats.months,
                      progress: _entrance.value,
                      tokens: tokens,
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              for (final point in stats.months)
                Expanded(
                  child: Text(
                    '${point.month}月',
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontSize: 9,
                          color: point.year == today.year &&
                                  point.month == today.month
                              ? tokens.primary
                              : tokens.muted,
                          fontWeight: point.year == today.year &&
                                  point.month == today.month
                              ? FontWeight.w800
                              : FontWeight.w500,
                        ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 环形切片的图例行：色点 + 项目名 + 实付 +（有优惠时）省额小字。
class _LegendRow extends StatelessWidget {
  const _LegendRow({required this.slice});

  final _DonutSlice slice;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: slice.color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            slice.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          formatMoneyCents(slice.actual),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        if (slice.discount > 0) ...[
          const SizedBox(width: 4),
          Text(
            '省 ${formatMoneyCents(slice.discount)}',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: tokens.success,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ],
    );
  }
}

/// 带标签的渐变胶囊条行：左侧固定宽标签 + 中间比例条（宽度 = 比例 ×
/// 入场进度，从 0 生长）+ 右侧数值文案。按年花费专用。
class _GradientBarRow extends StatelessWidget {
  const _GradientBarRow({
    required this.label,
    required this.barFraction,
    required this.valueText,
    required this.progress,
  });

  final String label;
  final double barFraction;
  final String valueText;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    final widthFactor = (barFraction * progress).clamp(0.0, 1.0);
    return Row(
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 96),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: widthFactor <= 0
              ? const SizedBox.shrink()
              : Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: widthFactor,
                    child: Container(
                      height: 12,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [tokens.primary, tokens.primaryStrong],
                        ),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                ),
        ),
        const SizedBox(width: 8),
        Text(
          valueText,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
      ],
    );
  }
}

/// 走势卡的左→右展开裁剪：露出宽 = 宽度 × 入场进度。
class _WidthRevealClipper extends CustomClipper<Rect> {
  const _WidthRevealClipper({required this.progress});

  final double progress;

  @override
  Rect getClip(Size size) {
    return Rect.fromLTWH(
      0,
      0,
      size.width * progress.clamp(0.0, 1.0),
      size.height,
    );
  }

  @override
  bool shouldReclip(_WidthRevealClipper oldClipper) =>
      oldClipper.progress != progress;
}

/// 环形图切片数据：计费值（决定角度）+ 实付/优惠（决定段内两截）+ 颜色。
typedef _DonutSlice = ({
  String name,
  int value,
  int actual,
  int discount,
  Color color,
});

/// 环形图分段配色：主色系的五档深浅（主色 → 次强调 → 两档向文本色
/// 插值），派生自 LunioTokens、深浅色主题都成立；不做硬编码色值。
/// 超出五段的部分回到第一档（当前 Top 5 + "其他"最多六段，不会触发）。
Color _sliceColor(LunioTokens tokens, int index) {
  switch (index % 5) {
    case 0:
      return tokens.primary;
    case 1:
      return tokens.secondary;
    case 2:
      return Color.lerp(tokens.primary, tokens.ink, 0.45)!;
    case 3:
      return Color.lerp(tokens.secondary, tokens.ink, 0.45)!;
    default:
      return Color.lerp(tokens.primary, tokens.ink, 0.72)!;
  }
}

/// 项目占比环形图 painter：一段一项目，段内先实色弧（实付）后同色
/// 半透明弧（优惠），切片间留细缝；入场进度乘在总弧度上（扇开）。
/// 全 0（有记录但没有任何项目计费值）画一圈浅色轨道兜底。
class _DonutPainter extends CustomPainter {
  _DonutPainter({
    required this.slices,
    required this.progress,
    required this.tokens,
  });

  final List<_DonutSlice> slices;
  final double progress;
  final LunioTokens tokens;

  static const _strokeWidth = 20.0;

  /// 相邻切片的间隔（弧度）；切片太窄时不留缝，避免视觉断裂。
  static const _gap = 0.035;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - _strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeWidth;
    final totalValue = slices.fold(0, (sum, slice) => sum + slice.value);
    if (totalValue <= 0) {
      paint.color = tokens.surface3;
      canvas.drawCircle(center, radius, paint);
      return;
    }
    final sweepTotal = 2 * math.pi * progress.clamp(0.0, 1.0);
    var start = -math.pi / 2;
    for (final slice in slices) {
      final span = slice.value / totalValue * sweepTotal;
      final gap = span > _gap * 3 ? _gap : 0.0;
      final drawStart = start + gap / 2;
      final drawSpan = span - gap;
      if (drawSpan > 0) {
        final actualSpan =
            slice.value > 0 ? drawSpan * slice.actual / slice.value : drawSpan;
        paint.color = slice.color;
        canvas.drawArc(rect, drawStart, actualSpan, false, paint);
        if (slice.discount > 0 && slice.value > 0) {
          paint.color = slice.color.withValues(alpha: 0.38);
          canvas.drawArc(
            rect,
            drawStart + actualSpan,
            drawSpan - actualSpan,
            false,
            paint,
          );
        }
      }
      start += span;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.slices != slices;
}

/// 近 12 个月走势 painter：平滑曲线（三次贝塞尔，控制点取水平偏移的
/// 0.4 倍——金额走势缓变，不需要防过冲的单调插值）+ 曲线下渐变面积，
/// 峰值月打点（外圈光晕 + 实心点）；全部为 0 时画浅色基线。
/// 展开动画由外层 [_WidthRevealClipper] 裁剪实现，painter 只画完整图。
class _TrendPainter extends CustomPainter {
  _TrendPainter({
    required this.points,
    required this.progress,
    required this.tokens,
  });

  final List<CostMonthPoint> points;
  final double progress;
  final LunioTokens tokens;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) {
      return;
    }
    const padLeft = 4.0;
    const padRight = 4.0;
    const padTop = 10.0;
    const padBottom = 4.0;
    final innerWidth = size.width - padLeft - padRight;
    final innerHeight = size.height - padTop - padBottom;
    Offset pointAt(int index) {
      final x = points.length == 1
          ? padLeft
          : padLeft + innerWidth * index / (points.length - 1);
      final y =
          padTop + (1 - points[index].fraction.clamp(0.0, 1.0)) * innerHeight;
      return Offset(x, y);
    }

    final maxFraction = points
        .map((point) => point.fraction)
        .fold(0.0, (max, fraction) => fraction > max ? fraction : max);
    final first = pointAt(0);
    final last = pointAt(points.length - 1);
    final line = Path()..moveTo(first.dx, first.dy);
    for (var index = 1; index < points.length; index++) {
      final previous = pointAt(index - 1);
      final current = pointAt(index);
      final dx = (current.dx - previous.dx) * 0.4;
      line.cubicTo(
        previous.dx + dx,
        previous.dy,
        current.dx - dx,
        current.dy,
        current.dx,
        current.dy,
      );
    }
    if (maxFraction > 0) {
      final area = Path.from(line)
        ..lineTo(last.dx, size.height - padBottom)
        ..lineTo(first.dx, size.height - padBottom)
        ..close;
      final areaPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            tokens.primary.withValues(alpha: 0.32),
            tokens.primary.withValues(alpha: 0.02),
          ],
        ).createShader(
          Rect.fromLTWH(0, padTop, size.width, innerHeight),
        );
      canvas.drawPath(area, areaPaint);
    }
    final linePaint = Paint()
      ..color = maxFraction > 0 ? tokens.primaryStrong : tokens.surface3
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(line, linePaint);
    if (maxFraction > 0) {
      var peakIndex = 0;
      for (var index = 1; index < points.length; index++) {
        if (points[index].fraction > points[peakIndex].fraction) {
          peakIndex = index;
        }
      }
      final peak = pointAt(peakIndex);
      canvas.drawCircle(
        peak,
        6.5,
        Paint()..color = tokens.primary.withValues(alpha: 0.25),
      );
      canvas.drawCircle(
        peak,
        3.2,
        Paint()..color = tokens.primaryStrong,
      );
    }
  }

  @override
  bool shouldRepaint(_TrendPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.points != points;
}
