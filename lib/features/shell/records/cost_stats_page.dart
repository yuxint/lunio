// 费用统计页（/cost-stats）：保养费用全貌的独立 pushed 子页。
//
// 本 App 第一个不挂主壳层的 pushed 路由：从记录页汇总行或我的页设置行
// 经 go_router push 进栈（默认转场，iOS 右滑返回天然可用），返回键由
// LunioTopBar 的 leading 位提供；顶部安全区由 LunioPage 内置 SafeArea
// 解决（页面自带 Scaffold 但不自己处理留白，见 lunio_components.dart）。
// 不在栈内时不渲染底部导航，因此 LunioPage 的 bottomPadding 用小值。
//
// 结构（全部纯读取聚合，无写库、无动作层参与）：
//   1. 汇总卡：总费用 + 今年保养（有加油记录追加今年加油栏）；
//   2. 汇总指标行：保养次数（今年小字）/ 单次均价 / 月均（全程摊薄，
//      不随任何图表联动）/ 上次保养距今；
//   3. 项目占比：横向条形列表——按实付从多到少排、全部项目不截断，
//      头部主数字 = 总费用（守恒锚点：各行相加 ≡ 总费用，2026-09-21），
//      末尾"其他"段吸收无归属的钱；点项目行下钻项目档案 sheet
//      （cost_item_history_sheet.dart）；
//   4. 保养费用走势：年度柱状图（2026-09-23 改版，取代年度曲线）——
//      每年一柱 = 该年总费用，横向滚动、柱顶标金额、今年柱主色高亮；
//      不足 2 条记录整卡不展示（单年车多条记录也展示）；
//   5. 加油费用卡（2026-09-22 新增，ADR 0015，固定页面最后；
//      2026-09-23 改版删年度行）：头部总费用 + N 笔 + 全历史连续月度
//      柱（横向滚动、初始停最右、柱顶标金额、「26.9」式轴标签）；金额
//      口径 = 实付优先、没填取应付（fuel_cost_stats.dart）。
// 作用域永远是当前应用车辆（2026-09-20 拍板：不提供"全部"/多车切换，
// 想看别的车先去切换应用车辆），当前车辆名在标题副字展示。
// 图表语言：全部为 Widget 柱形（无图表库、无 CustomPainter），颜色派
// 生自 LunioTokens；动效只做一次性入场（条形生长），进页面播一次，
// 不做持续循环。所有随入场动画变宽/变高的条形必须包在监听 [_entrance]
// 的 AnimatedBuilder 里——历史上按年条漏包导致"有时不渲染、点开才
// 出来"的 bug（动画只重建 AnimatedBuilder 子树）。
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
import '../../../domain/entities/fuel_record.dart';
import '../../../domain/entities/maintenance_item.dart';
import '../../../domain/entities/maintenance_record.dart';
import '../shared/shell_shared.dart';
import 'cost_item_history_sheet.dart';
import 'cost_stats.dart';
import 'fuel_cost_stats.dart';

/// 统计页要用的全部数据：当前应用车辆名（null = 无车）、该车记录、
/// 加油记录、项目清单（项目名解析用）、生效今天。
class CostStatsPageData {
  const CostStatsPageData({
    required this.carName,
    required this.records,
    required this.fuelRecords,
    required this.items,
    required this.today,
  });

  /// 当前应用车辆显示名（"品牌 型号"）；null = 没有应用车辆（无车）。
  final String? carName;

  final List<MaintenanceRecord> records;

  /// 当前应用车辆的加油记录（加油费用卡数据源）。
  final List<FuelRecord> fuelRecords;
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
      fuelRecords: const [],
      items: const [],
      today: today,
    );
  }
  final records = await ref.watch(recordsForCarProvider(car.id!).future);
  final items = await ref.watch(maintenanceItemsForCarProvider(car.id!).future);
  final fuelRecords = await ref.watch(
    fuelRecordsForCarProvider(car.id!).future,
  );
  return CostStatsPageData(
    carName: '${car.brand} ${car.model}',
    records: records,
    fuelRecords: fuelRecords,
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
  /// 一次性入场动画：进页面、数据首次渲染后播一次（0→1，各卡条形
  /// 共用——占比条按宽度生长、柱状图按高度长高），完成后不再重播；不
  /// 做持续循环动画（省电、不干扰阅读）。在 initState 创建（延迟初始化
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
        else if (data.records.isEmpty && data.fuelRecords.isEmpty)
          const LunioEmptyCard('暂无保养/加油记录，记一笔后这里会生成费用统计。')
        else ...[
          // 保养汇总卡（保养记录非空才渲染）；加油费用卡固定放页面
          // 最后（2026-09-22 二轮反馈），保养区只有加油时降为轻提示。
          if (data.records.isNotEmpty) ...[
            _buildSummaryCard(
              context,
              stats,
              hasFuel: data.fuelRecords.isNotEmpty,
              thisYearFuelCents: fuelCostCentsForYear(
                data.fuelRecords,
                data.today.year,
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (data.records.isEmpty)
            const LunioEmptyCard('暂无保养记录，记一笔保养后这里会生成保养费用统计。')
          else ...[
            _buildMetricsCard(context, data.today, stats),
            const SizedBox(height: 12),
            _buildProjectCard(context, stats, historyByName),
            // 走势卡在 2 条及以上记录才展示（2026-09-23 拍板，替换原
            // "两个年份"规则：单年车多条记录也有年度柱可看，1 条记录
            // 没有对比意义）。
            if (data.records.length >= 2) ...[
              const SizedBox(height: 12),
              _YearTrendCard(
                years: stats.years,
                thisYear: data.today.year,
                entrance: _entrance,
              ),
            ],
          ],
          if (data.fuelRecords.isNotEmpty) ...[
            const SizedBox(height: 12),
            _FuelCostCard(
              fuelRecords: data.fuelRecords,
              today: data.today,
              entrance: _entrance,
            ),
          ],
        ],
      ],
    );
  }

  /// 汇总卡：总费用 + 今年保养两栏；有加油记录时追加"今年加油"第三栏
  /// （2026-09-22 二轮反馈：无加油记录不显示该栏，不留 ¥0.00 占位）。
  /// 总费用口径仍是保养记录总费用（占比卡的守恒锚点），加油看下方
  /// 加油费用卡。
  Widget _buildSummaryCard(
    BuildContext context,
    CostStats stats, {
    required bool hasFuel,
    required int thisYearFuelCents,
  }) {
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
          // 2026-09-22 改名：加油费用卡进页后"今年费用"有歧义，
          // 明示为保养口径（加油看下方加油费用卡）。
          column('今年保养', stats.thisYearCents),
          if (hasFuel) ...[
            Container(width: 1, height: 40, color: tokens.line),
            const SizedBox(width: 14),
            column('今年加油', thisYearFuelCents),
          ],
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
  /// （[showCostItemHistorySheet]）。列表用 Table 三列布局——项目名列
  /// 与数值列都取全表最宽（IntrinsicColumnWidth），所有行的条形从同
  /// 一起点、同一把像素尺开始画（项目名宽窄不一或实付位数不同都会让
  /// 各行条形的起点/轨道长度参差，比例随之失真）；条形入场时按宽度
  /// 生长——必须包在 AnimatedBuilder 里，否则动画期间本子树不重建、
  /// 条形停在进度 0（历史 bug：按年条漏包导致"有时不渲染、点开才
  /// 出来"）。
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
              return Table(
                columnWidths: const {
                  // 项目名列与数值列取全表最宽：条形统一起点 + 统一轨道。
                  0: IntrinsicColumnWidth(),
                  1: FlexColumnWidth(),
                  2: IntrinsicColumnWidth(),
                },
                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                children: [
                  for (final row in stats.topItems)
                    _projectBarRow(
                      context,
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
                  // "其他"段：无归属费用的聚合（简洁模式费用 + 总费用
                  // 超出项目合计的差额），不是项目、不可下钻。
                  if (stats.otherCents > 0)
                    _projectBarRow(
                      context,
                      name: '其他',
                      actualCents: stats.otherCents,
                      discountCents: 0,
                      fraction: barMaxFraction(stats),
                      progress: _entrance.value,
                      barColor: tokens.surface3,
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  /// 条形列表一行（TableRow）：项目名 | 条形轨道 | 实付（+省额+下钻
  /// 箭头）。三个单元格各自包 TableRowInkWell（高亮横跨整行），[onTap]
  /// 为空（"其他"段）时整行不响应；"其他"行灰条、无优惠无箭头。
  TableRow _projectBarRow(
    BuildContext context, {
    required String name,
    required int actualCents,
    required int discountCents,
    required double fraction,
    required double progress,
    required Color barColor,
    VoidCallback? onTap,
  }) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    final widthFactor = (fraction * progress).clamp(0.0, 1.0);
    TableCell cell(Widget child) => TableCell(
          child: TableRowInkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: child,
            ),
          ),
        );
    return TableRow(
      children: [
        cell(
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 96),
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ),
        cell(
          // 轨道左右各留 8px：条形不贴项目名与金额（比例尺仍全表统一）。
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: widthFactor <= 0
                ? const SizedBox(height: 12)
                : Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: widthFactor,
                      child: Container(
                        // key 供 widget 测试断言"统一起点 + 同一比例尺"。
                        key: ValueKey('cost-bar-$name'),
                        height: 12,
                        decoration: BoxDecoration(
                          color: barColor,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                  ),
          ),
        ),
        cell(
          // 固定宽槽右对齐（2026-09-23 拍板）：实付槽 + 省槽各占固定
          // 宽度、文本右对齐（FittedBox 只缩不放），没有优惠的行省槽
          // 留空——两列各自成一条垂直线，不再跟着实付位数左右漂。
          Row(
            children: [
              SizedBox(
                width: 64,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    formatMoneyCents(actualCents),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              SizedBox(
                width: 56,
                child: discountCents > 0
                    ? FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Text(
                          '省 ${formatMoneyCents(discountCents)}',
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: tokens.success,
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                      )
                    : null,
              ),
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
        ),
      ],
    );
  }

}

/// 加油费用卡（2026-09-22 新增，ADR 0015；2026-09-23 改版删年度行）：
/// 头部「总费用 + N 笔」+ 全历史连续月度柱（[_BarStrip]：横向滚动、
/// 初始停最右、柱顶标金额、「26.9」式轴标签）。金额口径 = 实付优先、
/// 没填取应付（fuel_cost_stats.dart 纯函数），与保养各卡的守恒/优惠
/// 口径互不掺和。
class _FuelCostCard extends StatelessWidget {
  const _FuelCostCard({
    required this.fuelRecords,
    required this.today,
    required this.entrance,
  });

  final List<FuelRecord> fuelRecords;
  final LocalDate today;

  /// 页面级一次性入场动画（0→1）：月份柱按高度长高，与其他卡共用同一
  /// 份进度（页面注释的历史 bug：条形必须包在监听动画的 AnimatedBuilder
  /// 里）。
  final Animation<double> entrance;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    final stats = buildFuelCostStats(records: fuelRecords);
    final months = fuelMonthlyCents(fuelRecords, today);
    var maxMonthCents = 0;
    for (final point in months) {
      if (point.costCents > maxMonthCents) {
        maxMonthCents = point.costCents;
      }
    }
    return LunioCard(
      child: LunioSection(
        title: '加油费用',
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    // 2026-09-22 二轮反馈：与记录页头部/汇总卡同词——
                    // 本卡作用域就是加油，"总费用"即加油总花费。
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
              Text(
                '${stats.recordCount} 笔',
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: tokens.muted),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _BarStrip(
            entrance: entrance,
            items: [
              for (final point in months)
                _BarStripItem(
                  amountCents: point.costCents,
                  barFraction: maxMonthCents == 0
                      ? 0.0
                      : point.costCents / maxMonthCents,
                  barColor: tokens.primary,
                  axisLabel: '${point.year % 100}.${point.month}',
                  highlight: false,
                  barKey: ValueKey(
                    'fuel-month-bar-${point.year}-${point.month}',
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 保养费用走势卡（2026-09-23 改版：年度曲线改年度柱状图）：每年一柱
/// = 该年记录总费用合计（复用 stats.years 的年度聚合），横向滚动、
/// 柱顶标金额、今年柱主色高亮（往年浅色）；曲线的三装饰（峰值浮标/
/// 上次保养空心环/渐变面积）随改版删除。不足 2 条记录由调用方整卡
/// 隐藏（cost_stats_page 的内容组装处）。
class _YearTrendCard extends StatelessWidget {
  const _YearTrendCard({
    required this.years,
    required this.thisYear,
    required this.entrance,
  });

  /// 年度柱数据（首条记录年 → 今年升序，含无记录年，口径同占比卡的
  /// 记录总费用权威值）。
  final List<CostYearPoint> years;

  /// 生效今天所在年（高亮柱）。
  final int thisYear;

  final Animation<double> entrance;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    return LunioCard(
      child: LunioSection(
        title: '保养费用走势',
        children: [
          const SizedBox(height: 6),
          // 一屏约 3 柱（2026-09-24 反馈）：列宽 = 视口宽 ÷ 3，柱距随
          // 机型自适应；柱体加粗到 28 配合拉开的柱距。
          LayoutBuilder(
            builder: (context, constraints) {
              return _BarStrip(
                columnWidth: constraints.maxWidth / 3,
                barWidth: 28,
                entrance: entrance,
                items: [
                  for (final point in years)
                    _BarStripItem(
                      amountCents: point.costCents,
                      barFraction: point.fraction,
                      barColor: point.year == thisYear
                          ? tokens.primary
                          : tokens.primarySoft,
                      axisLabel: '${point.year}',
                      highlight: point.year == thisYear,
                      barKey: ValueKey('cost-year-bar-${point.year}'),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// 柱状条的一列数据：柱顶金额 + 柱体比例 + 轴标签。走势年度柱与加油
/// 月度柱共用（[_BarStrip]），渲染层不感知业务语义。
class _BarStripItem {
  const _BarStripItem({
    required this.amountCents,
    required this.barFraction,
    required this.barColor,
    required this.axisLabel,
    required this.highlight,
    required this.barKey,
  });

  /// 柱顶金额（分）；0 = 无花费，不标金额（只留灰色基线桩）。
  final int amountCents;

  /// 柱高比例（0~1，相对本组最大值，调用方算好）。
  final double barFraction;

  /// 柱体颜色（调用方按高亮语义给：今年主色/其余浅色）。
  final Color barColor;

  /// 柱下轴标签（年度柱「2024」/ 月度柱「26.9」）。
  final String axisLabel;

  /// 高亮列：柱顶金额与轴标签加粗主色（当前只有一个消费者=今年柱）。
  final bool highlight;

  /// 柱体 key（widget 测试按 key 断言柱存在与几何）。
  final Key barKey;
}

/// 横向滚动的柱状条（走势年度柱与加油月度柱共用，2026-09-23）：每列
/// 固定 48px——柱顶金额槽 + 柱体 + 轴标签；内容比视口宽时初始定位到
/// 最右端（最近的时间在视野内，2026-09-23 拍板）。柱高随入场动画
/// 长高——整条包在监听 [entrance] 的 AnimatedBuilder 里（页面注释的
/// 历史 bug：漏包导致"有时不渲染、点开才出来"）。
class _BarStrip extends StatefulWidget {
  const _BarStrip({
    required this.items,
    required this.entrance,
    this.columnWidth = 48,
    this.barWidth = 16,
  });

  final List<_BarStripItem> items;
  final Animation<double> entrance;

  /// 列宽。加油月度柱用默认 48（一屏约 7 个月）；保养走势卡传视口宽
  /// ÷ 3（一屏约 3 柱、柱距拉开，2026-09-24 反馈），由调用方用
  /// LayoutBuilder 按实际视口算——任何机型都正好一屏 3 柱。
  final double columnWidth;

  /// 柱体宽。走势柱加粗到 28（列宽变大后 16 太瘦），月度柱默认 16。
  final double barWidth;

  @override
  State<_BarStrip> createState() => _BarStripState();
}

class _BarStripState extends State<_BarStrip> {
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

  @override
  Widget build(BuildContext context) {
    _scheduleJumpToEnd();
    return AnimatedBuilder(
      animation: widget.entrance,
      builder: (context, _) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          controller: _scroll,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final item in widget.items)
                _barColumn(context, item, widget.entrance.value),
            ],
          ),
        );
      },
    );
  }

  /// 柱状一列（宽 = [_BarStrip.columnWidth]）：金额槽（固定高，0 元
  /// 留空保证各行柱体对齐）+ 柱体（高相对组内最大，随入场动画长高；
  /// 0 元画 2dp 灰桩）+ 轴标签。金额居中在柱体正上方（列宽加大后
  /// 右对齐会漂离柱体）。
  Widget _barColumn(
    BuildContext context,
    _BarStripItem item,
    double progress,
  ) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    const maxBarHeight = 44.0;
    final hasCost = item.amountCents > 0;
    final barHeight = hasCost
        ? (item.barFraction * maxBarHeight * progress).clamp(3.0, maxBarHeight)
        : 2.0;
    final amountColor =
        item.highlight ? tokens.ink : tokens.muted;
    final axisColor = item.highlight ? tokens.primary : tokens.muted;
    return SizedBox(
      width: widget.columnWidth,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 12,
            child: hasCost
                ? FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.center,
                    child: Text(
                      formatMoneyCents(item.amountCents),
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(
                            fontSize: 9,
                            color: amountColor,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  )
                : null,
          ),
          const SizedBox(height: 3),
          SizedBox(
            height: maxBarHeight,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                key: item.barKey,
                width: widget.barWidth,
                height: barHeight,
                decoration: BoxDecoration(
                  color: hasCost ? item.barColor : tokens.line,
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
                  fontSize: 9,
                  color: axisColor,
                  fontWeight: item.highlight ? FontWeight.w800 : FontWeight.w500,
                ),
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

