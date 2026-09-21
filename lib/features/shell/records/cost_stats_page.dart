// 费用统计页（/cost-stats）：保养费用全貌的独立 pushed 子页。
//
// 本 App 第一个不挂主壳层的 pushed 路由：从记录页汇总行或我的页设置行
// 经 go_router push 进栈（默认转场，iOS 右滑返回天然可用），返回键由
// LunioTopBar 的 leading 位提供；顶部安全区由 LunioPage 内置 SafeArea
// 解决（页面自带 Scaffold 但不自己处理留白，见 lunio_components.dart）。
// 不在栈内时不渲染底部导航，因此 LunioPage 的 bottomPadding 用小值。
//
// 结构（全部纯读取聚合，无写库、无动作层参与）：
//   1. 汇总卡：总费用 + 今年费用；
//   2. 汇总指标行：保养次数（今年小字）/ 单次均价 / 月均（全程摊薄，
//      不随任何图表联动）/ 上次保养距今；
//   3. 项目占比：横向条形列表——按实付从多到少排、全部项目不截断，
//      头部主数字 = 总费用（守恒锚点：各行相加 ≡ 总费用，2026-09-21），
//      末尾"其他"段吸收无归属的钱；点项目行下钻项目档案 sheet
//      （cost_item_history_sheet.dart）；
//   4. 费用走势：年度曲线——每年一点（= 该年总费用），峰值标注 +
//      上次保养年份高亮；不足两个年份（单年车）整卡不展示
//      （2026-09-21 拍板）。
// 作用域永远是当前应用车辆（2026-09-20 拍板：不提供"全部"/多车切换，
// 想看别的车先去切换应用车辆），当前车辆名在标题副字展示。
// 图表语言：项目占比为 Widget 条形、走势为 CustomPainter 自绘（无图表
// 库），颜色派生自 LunioTokens；动效只做一次性入场（生长/展开），进
// 页面播一次，不做持续循环。所有随入场动画变宽的条形必须包在监听
// [_entrance] 的 AnimatedBuilder 里——历史上按年条漏包导致"有时不
// 渲染、点开才出来"的 bug（动画只重建 AnimatedBuilder 子树）。
// 聚合口径统一收在 cost_stats.dart（纯函数），本文件只负责"把当前车
// 的数据拿到"与渲染；无车辆/无记录时给空态卡。
// Java 类比：一个只读报表页——provider ≈ 按当前车参数化的查询服务，
// 页面本身只做组装结果的表达。
// ignore_for_file: use_key_in_widget_constructors
// ignore_for_file: library_private_types_in_public_api

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
import 'cost_item_history_sheet.dart';
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

/// 费用统计页主组件。
class CostStatsPage extends ConsumerStatefulWidget {
  const CostStatsPage();

  @override
  ConsumerState<CostStatsPage> createState() => CostStatsPageState();
}

class CostStatsPageState extends ConsumerState<CostStatsPage>
    with SingleTickerProviderStateMixin {
  /// 一次性入场动画：进页面、数据首次渲染后播一次（0→1，条形与走势
  /// 共用——条形按宽度生长、走势按宽度展开），完成后不再重播；不做
  /// 持续循环动画（省电、不干扰阅读）。在 initState 创建（延迟初始化
  /// 会在"整页从未进数据分支"的用例里于 dispose 时才首次构造，在失活
  /// 树上找 TickerMode 祖先直接抛异常）。
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
      body = const LoadingPage(title: '费用统计');
    } else if (appliedAsync.hasError) {
      // hasError 已保证 error 非 null（应用车辆与车辆清单同源失败）。
      body = ErrorPage(
        title: '费用统计',
        error: appliedAsync.error!,
        leading: _backKey(),
      );
    } else {
      body = ref.watch(costStatsDataProvider).when(
            loading: () => const LoadingPage(title: '费用统计'),
            error: (error, stackTrace) =>
                ErrorPage(title: '费用统计', error: error, leading: _backKey()),
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
    // 项目档案（点项目行下钻）：按项目名聚合，与占比卡行一一对应。
    final historyByName = <String, CostItemHistory>{
      for (final history
          in buildItemHistories(data.records, data.items))
        history.name: history,
    };
    return LunioPage(
      title: '费用统计',
      subtitle: data.carName == null ? null : '当前车辆：${data.carName}',
      leading: _backKey(),
      bottomPadding: 24,
      children: [
        if (data.carName == null)
          const LunioEmptyCard('请先新增车辆')
        else if (data.records.isEmpty)
          const LunioEmptyCard('暂无保养记录，记一笔保养后这里会生成费用统计。')
        else ...[
          _buildSummaryCard(context, stats),
          const SizedBox(height: 12),
          _buildMetricsCard(context, data.today, stats),
          const SizedBox(height: 12),
          _buildProjectCard(context, stats, historyByName),
          // 走势卡只在两年及以上才展示（单年车没有走势可看）。
          if (stats.years.length >= 2) ...[
            const SizedBox(height: 12),
            _buildTrendCard(context, data.today, stats),
          ],
        ],
      ],
    );
  }

  /// 汇总卡：总费用 + 今年费用两栏。
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
          column('总费用', stats.totalCents),
          Container(width: 1, height: 40, color: tokens.line),
          const SizedBox(width: 14),
          column('今年费用', stats.thisYearCents),
        ],
      ),
    );
  }

  /// 汇总指标行：保养次数（含今年小字）/ 单次均价 / 月均 / 上次保养
  /// 距今。月均 = 总费用 ÷ 首条记录月到当月的自然月数（全程摊薄，
  /// 2026-09-21 拍板：不随任何图表联动——页面也没有窗口切换了）。
  Widget _buildMetricsCard(
    BuildContext context,
    LocalDate today,
    CostStats stats,
  ) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    Widget block(String label, String value, {String? sub}) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: tokens.muted),
              ),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  value,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              if (sub != null)
                Text(
                  sub,
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: tokens.muted, fontSize: 9),
                ),
            ],
          ),
        );
    final lastDate = stats.lastRecordDate;
    final daysAgo = lastDate == null
        ? null
        : today.toDateTime().difference(lastDate.toDateTime()).inDays;
    final lastText = daysAgo == null
        ? '—'
        : daysAgo == 0
            ? '今天'
            : '$daysAgo 天前';
    return LunioCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          block(
            '保养次数',
            stats.recordCount == 0 ? '—' : '${stats.recordCount} 次',
            sub: stats.recordCount == 0
                ? null
                : '今年 ${stats.thisYearRecordCount} 次',
          ),
          block(
            '单次均价',
            stats.recordCount == 0 ? '—' : formatMoneyCents(stats.avgPerVisitCents),
          ),
          block(
            '月均',
            stats.recordCount == 0 ? '—' : formatMoneyCents(stats.monthlyAvgCents),
          ),
          block('上次保养', lastText),
        ],
      ),
    );
  }

  /// 项目占比卡：横向条形列表，按实付从多到少、全部项目不截断；头部
  /// 主数字 = 总费用（守恒锚点：各行相加 ≡ 总费用，口径见
  /// cost_stats.dart 文件头），旁边累计优惠小字；末尾"其他"段（仅有
  /// 缺口时出现）装无归属的钱，不可下钻；点项目行打开该项目档案 sheet
  /// （[showCostItemHistorySheet]）。条形入场时按宽度生长——必须包在
  /// AnimatedBuilder 里，否则动画期间本子树不重建、条形停在进度 0
  /// （历史 bug：按年条漏包导致"有时不渲染、点开才出来"）。
  Widget _buildProjectCard(
    BuildContext context,
    CostStats stats,
    Map<String, CostItemHistory> historyByName,
  ) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    return LunioCard(
      child: LunioSection(
        title: '项目占比',
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '总费用',
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: tokens.muted),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    formatMoneyCents(stats.totalCents),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ],
              ),
              const Spacer(),
              if (stats.totalDiscountCents > 0)
                Text(
                  '累计优惠 ${formatMoneyCents(stats.totalDiscountCents)}',
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(
                        color: tokens.success,
                        fontWeight: FontWeight.w700,
                      ),
                ),
            ],
          ),
          AnimatedBuilder(
            animation: _entrance,
            builder: (context, _) {
              return Column(
                children: [
                  for (final row in stats.topItems)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: _ProjectBarRow(
                        name: row.name,
                        actualCents: row.actualCents,
                        discountCents: row.discountCents,
                        fraction: row.fraction,
                        progress: _entrance.value,
                        barColor: tokens.primary,
                        onTap: () {
                          final history = historyByName[row.name];
                          if (history != null) {
                            showCostItemHistorySheet(context, history);
                          }
                        },
                      ),
                    ),
                  // "其他"段：无归属费用的聚合（简洁模式费用 + 总费用
                  // 超出项目合计的差额），不是项目、不可下钻。
                  if (stats.otherCents > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: _ProjectBarRow(
                        name: '其他',
                        actualCents: stats.otherCents,
                        discountCents: 0,
                        fraction: barMaxFraction(stats),
                        progress: _entrance.value,
                        barColor: tokens.surface3,
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

  /// 费用走势卡：年度平滑曲线——每年一点（= 该年记录总费用合计），
  /// 叠加峰值年标注与上次保养年份空心高亮；不足两年由调用方整卡隐藏。
  /// 入场时从左往右展开（[_WidthRevealClipper] 裁剪，painter 画完整
  /// 图）；画布宽度必须显式撑满（Column 松约束会把 CustomPaint 收敛成
  /// 0 宽画布，曲线整卡不可见，实测翻车）。
  Widget _buildTrendCard(
    BuildContext context,
    LocalDate today,
    CostStats stats,
  ) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    return LunioCard(
      child: LunioSection(
        title: '费用走势',
        children: [
          const SizedBox(height: 6),
          AnimatedBuilder(
            animation: _entrance,
            builder: (context, _) {
              return SizedBox(
                height: 132,
                width: double.infinity,
                child: ClipRect(
                  clipper: _WidthRevealClipper(progress: _entrance.value),
                  child: CustomPaint(
                    key: const ValueKey('cost-trend-paint'),
                    painter: _TrendPainter(
                      points: stats.years,
                      lastRecordDate: stats.lastRecordDate,
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
              for (final point in stats.years)
                Expanded(
                  child: Text(
                    '${point.year}',
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontSize: 9,
                          color: point.year == today.year
                              ? tokens.primary
                              : tokens.muted,
                          fontWeight: point.year == today.year
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

/// 其他段的条宽比例：其他段实付 ÷ 全部行最大实付（与 cost_stats.dart
/// 的行内 fraction 同一把尺——barMax = max(项目实付最大值, 其他段)）。
/// 这里反推最大值而不是让纯函数多发一份字段：占比卡是它唯一的消费者。
double barMaxFraction(CostStats stats) {
  var maxCents = stats.otherCents;
  for (final row in stats.topItems) {
    if (row.actualCents > maxCents) {
      maxCents = row.actualCents;
    }
  }
  return maxCents == 0 ? 0.0 : stats.otherCents / maxCents;
}

/// 项目占比一行：项目名 + 条形（宽度 = 实付比例 × 入场进度，从 0
/// 生长）+ 实付金额 +（有分摊优惠时）省额小字 + 下钻箭头；[onTap]
/// 非空时整行可点打开项目档案。"其他"段同构复用（灰条、无优惠、
/// 无下钻）。
class _ProjectBarRow extends StatelessWidget {
  const _ProjectBarRow({
    required this.name,
    required this.actualCents,
    required this.discountCents,
    required this.fraction,
    required this.progress,
    required this.barColor,
    this.onTap,
  });

  final String name;
  final int actualCents;
  final int discountCents;
  final double fraction;
  final double progress;
  final Color barColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    final widthFactor = (fraction * progress).clamp(0.0, 1.0);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Row(
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 96),
            child: Text(
              name,
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
                          color: barColor,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                  ),
          ),
          const SizedBox(width: 8),
          Text(
            formatMoneyCents(actualCents),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          if (discountCents > 0) ...[
            const SizedBox(width: 4),
            Text(
              '省 ${formatMoneyCents(discountCents)}',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: tokens.success,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
          if (onTap != null) ...[
            const SizedBox(width: 2),
            Icon(
              Icons.chevron_right,
              size: 14,
              color: tokens.muted,
            ),
          ],
        ],
      ),
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

/// 费用走势 painter：年度平滑曲线（三次贝塞尔，控制点取水平偏移的
/// 0.4 倍——费用走势缓变，不需要防过冲的单调插值）+ 曲线下渐变面积，
/// 叠加：有费用的年份实心点、峰值年的「峰值 ¥x」标注（文字画进图内，
/// 钳在画布内）、上次保养年份的空心高亮环；全部为 0 时画浅色基线。
/// 展开动画由外层 [_WidthRevealClipper] 裁剪实现，painter 只画完整图。
class _TrendPainter extends CustomPainter {
  _TrendPainter({
    required this.points,
    required this.lastRecordDate,
    required this.tokens,
  });

  final List<CostYearPoint> points;
  final LocalDate? lastRecordDate;
  final LunioTokens tokens;

  static const _padLeft = 4.0;
  static const _padRight = 4.0;
  static const _padTop = 14.0;
  static const _padBottom = 6.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) {
      return;
    }
    final innerWidth = size.width - _padLeft - _padRight;
    final innerHeight = size.height - _padTop - _padBottom;
    final maxCents = points
        .map((point) => point.costCents)
        .fold(0, (max, cents) => cents > max ? cents : max);
    double yFor(int cents) =>
        maxCents == 0
            ? size.height - _padBottom
            : _padTop +
                (1 - cents / maxCents) * innerHeight;
    Offset pointAt(int index) {
      final x = points.length == 1
          ? _padLeft
          : _padLeft + innerWidth * index / (points.length - 1);
      return Offset(x, yFor(points[index].costCents));
    }

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
    if (maxCents > 0) {
      final area = Path.from(line)
        ..lineTo(last.dx, size.height - _padBottom)
        ..lineTo(first.dx, size.height - _padBottom)
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
          Rect.fromLTWH(0, _padTop, size.width, innerHeight),
        );
      canvas.drawPath(area, areaPaint);
    }
    final linePaint = Paint()
      ..color = maxCents > 0 ? tokens.primaryStrong : tokens.surface3
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(line, linePaint);

    if (maxCents > 0) {
      // 有费用的年份：小实心点（峰值年另有标注，跳过）。
      var peakIndex = 0;
      for (var index = 1; index < points.length; index++) {
        if (points[index].costCents > points[peakIndex].costCents) {
          peakIndex = index;
        }
      }
      final dotPaint = Paint()..color = tokens.primaryStrong;
      for (var index = 0; index < points.length; index++) {
        if (points[index].costCents > 0 && index != peakIndex) {
          canvas.drawCircle(pointAt(index), 2.6, dotPaint);
        }
      }
      // 峰值年：光晕 + 实心点 + 金额标注（钳在画布内）。
      final peak = pointAt(peakIndex);
      canvas.drawCircle(
        peak,
        6.5,
        Paint()..color = tokens.primary.withValues(alpha: 0.25),
      );
      canvas.drawCircle(peak, 3.2, Paint()..color = tokens.primaryStrong);
      _drawLabel(
        canvas,
        size,
        Offset(
          (peak.dx - 26).clamp(_padLeft, size.width - _padRight - 66),
          (peak.dy - 22).clamp(0, size.height - _padBottom - 12),
        ),
        '峰值 ${formatMoneyCents(points[peakIndex].costCents)}',
      );
      // 上次保养年份：空心高亮环（最后一条记录的年份落在跨度内才标）。
      final lastDate = lastRecordDate;
      if (lastDate != null) {
        final index = lastDate.year - points.first.year;
        if (index >= 0 && index < points.length) {
          canvas.drawCircle(
            pointAt(index),
            6,
            Paint()
              ..color = tokens.primary
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.8,
          );
        }
      }
    }
  }

  /// 在图内画一小段说明文字（峰值标注），钳在画布范围内。
  void _drawLabel(Canvas canvas, Size size, Offset at, String text) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: 9,
          color: tokens.muted,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size.width - _padLeft - _padRight);
    painter.paint(canvas, at);
  }

  @override
  bool shouldRepaint(_TrendPainter oldDelegate) =>
      oldDelegate.points != points ||
      oldDelegate.lastRecordDate != lastRecordDate;
}
