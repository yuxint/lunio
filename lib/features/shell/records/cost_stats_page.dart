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
//   3. 项目占比：100% 堆叠条 + 紧凑明细行（2026-09-24 C 方案改版，
//      替代每行条形轨道）——按实付降序分段、主色深→浅、"其他"段灰色；
//      行 = 色点 | 项目名 | 百分比 | 省额 | 实付，三个数值列固定槽右对
//      齐；头部一行 = 总费用标签 + 金额 + 累计优惠（2026-09-24 第五轮
//      压扁，守恒锚点：各行相加 ≡ 总费用），点项目行下钻项目档案
//      （cost_item_history_sheet.dart）；
//   4. 保养费用（2026-09-24 由"保养费用走势"改名并改 A 方案坐标系
//      柱状图）——每年一柱 = 该年总费用，柱色统一主色（第五轮：删今
//      年柱高亮），纵轴刻度 + 虚线网格线、柱顶标金额；图表行为与加油
//      卡统一：放得下铺满卡宽、超一屏横向滚动（底部滚动条、初始停最
//      右）；不足 2 条记录整卡不展示；
//   5. 加油费用卡（2026-09-22 新增，ADR 0015，固定页面最后；2026-09-23
//      删年度行，2026-09-24 加坐标系，同日第五轮头部一行化）：头部一行
//      = 总费用 + 月均（"N 笔"删除，月均口径见 fuel_cost_stats.dart）
//      + 全历史连续月度柱（纵轴固定左侧 + 虚线网格线，柱顶标金额、
//      「26.9」式轴标签）；金额口径 = 实付优先、没填取应付。
// 作用域永远是当前应用车辆（2026-09-20 拍板：不提供"全部"/多车切换，
// 想看别的车先去切换应用车辆），当前车辆名在标题副字展示。
// 图表语言：柱形为 Widget 组装、网格线为自绘虚线 painter（无图表库），
// 颜色派生自 LunioTokens；动效只做一次性入场（条形生长/堆叠条长出），
// 进页面播一次，不做持续循环。所有随入场动画变宽/变高的条形必须包在
// 监听 [_entrance] 的 AnimatedBuilder 里——历史上按年条漏包导致"有时
// 不渲染、点开才出来"的 bug（动画只重建 AnimatedBuilder 子树）。
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
              _YearTrendCard(years: stats.years, entrance: _entrance),
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
                      ?.copyWith(color: tokens.muted, fontSize: 10),
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

  /// 项目占比卡（2026-09-24 C 方案改版）：一条 100% 堆叠条看结构 +
  /// 紧凑行列表看明细，替代原"每行一条形轨道"的列表。头部一行 = 总
  /// 费用标签 + 金额（15/w800，2026-09-24 第五轮由两行压成一行）+ 累
  /// 计优惠小字（守恒锚点：各行相加 ≡ 总费用）；堆叠条按实付降序分段
  /// （主色透明度由深到浅），"其他"段灰色吸收无归属的钱；明细行 =
  /// 色点 | 项目名 | 百分比 | 省额 | 实付，三个数值列固定槽右对齐（百
  /// 分比/省额/实付各自成一条垂直线，2026-09-24 用户点名要求），无优
  /// 惠的行省槽留空。点项目行下钻项目档案 sheet
  /// （cost_item_history_sheet.dart），"其他"段不可下钻。
  Widget _buildProjectCard(
    BuildContext context,
    CostStats stats,
    Map<String, CostItemHistory> historyByName,
  ) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    // 堆叠条与明细行共用同一份行清单（其他段收尾，仅在有缺口时出现）。
    final rows = [
      ...stats.topItems,
      if (stats.otherCents > 0)
        CostItemShareRow(
          name: '其他',
          costCents: 0,
          discountCents: 0,
          actualCents: stats.otherCents,
          fraction: 0,
        ),
    ];
    return LunioCard(
      child: LunioSection(
        title: '项目占比',
        children: [
          // 头部一行：标签 12 muted + 金额 15/w800 基线对齐，右侧累计
          // 优惠（无优惠整段省略，不留占位）。
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '总费用',
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: tokens.muted),
              ),
              const SizedBox(width: 6),
              Text(
                formatMoneyCents(stats.totalCents),
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
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
          const SizedBox(height: 10),
          // 100% 堆叠条：分段宽度 = 实付占比（flex 按分值），入场时整体
          // 从左往右长出（FractionallySizedBox 随入场动画放大）。
          AnimatedBuilder(
            animation: _entrance,
            builder: (context, _) {
              return Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: _entrance.value.clamp(0.0, 1.0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(7),
                    child: SizedBox(
                      height: 14,
                      child: Row(
                        children: [
                          for (var i = 0; i < rows.length; i++)
                            Flexible(
                              flex: rows[i].actualCents,
                              fit: FlexFit.tight,
                              child: Container(
                                key: ValueKey('cost-seg-${rows[i].name}'),
                                color: _stackColor(context, rows, i),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 10),
          Column(
            children: [
              for (var i = 0; i < rows.length; i++)
                _shareRow(
                  context,
                  row: rows[i],
                  color: _stackColor(context, rows, i),
                  totalCents: stats.totalCents,
                  history: historyByName[rows[i].name],
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// 堆叠条/色点的分段颜色：项目行按实付名次取主色透明度阶梯（深→
  /// 浅），"其他"段固定灰（surface3）。[rows] 为含其他段的完整行清单。
  Color _stackColor(
    BuildContext context,
    List<CostItemShareRow> rows,
    int index,
  ) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    if (rows[index].name == '其他') {
      return tokens.surface3;
    }
    return tokens.primary.withValues(
      alpha: (0.85 - index * 0.14).clamp(0.30, 0.85),
    );
  }

  /// 占比明细一行：色点 | 项目名（截断）| 百分比 | 省额 | 实付。三个
  /// 数值列固定槽右对齐（FittedBox 只缩不放），无优惠的行省槽留空、
  /// 保证省额列竖向对齐；[history] 为空（"其他"段）整行不可点。行内
  /// 不再画条形轨道——结构感由上方堆叠条承担。
  Widget _shareRow(
    BuildContext context, {
    required CostItemShareRow row,
    required Color color,
    required int totalCents,
    required CostItemHistory? history,
  }) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    final pct = totalCents == 0
        ? 0
        : (row.actualCents / totalCents * 100).round();
    return InkWell(
      onTap: history == null
          ? null
          : () => showCostItemHistorySheet(context, history),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                row.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              key: ValueKey('cost-pct-${row.name}'),
              width: 34,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(
                  '$pct%',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: tokens.muted,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              key: ValueKey('cost-save-${row.name}'),
              width: 52,
              child: row.discountCents > 0
                  ? FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        '省 ${formatMoneyCents(row.discountCents)}',
                        style: Theme.of(context)
                            .textTheme
                            .labelSmall
                            ?.copyWith(
                              color: tokens.success,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 6),
            SizedBox(
              key: ValueKey('cost-amt-${row.name}'),
              width: 64,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(
                  formatMoneyCents(row.actualCents),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
/// 加油费用卡（2026-09-22 新增，ADR 0015；2026-09-23 删年度行；
/// 2026-09-24 加坐标系，同日第五轮头部一行化）：头部一行 = 「总费用」
/// 标签 + 金额（15/w800）+ 右侧「月均」（"N 笔"删除，月均 = 总费用 ÷
/// 首条加油记录月到当月全程摊薄，口径见 fuel_cost_stats.dart）+ 全历
/// 史连续月度柱（[_AxesColumnChart]：纵轴固定左侧 + 虚线网格线，柱顶
/// 标金额、「26.9」式轴标签，超一屏滚动/底部滚动条/初始停最右）。金额
/// 口径 = 实付优先、没填取应付，与保养各卡的守恒/优惠口径互不掺和。
class _FuelCostCard extends StatelessWidget {
  const _FuelCostCard({
    required this.fuelRecords,
    required this.today,
    required this.entrance,
  });

  final List<FuelRecord> fuelRecords;
  final LocalDate today;

  /// 页面级一次性入场动画（0→1）：月份柱按高度长高，与其他卡共用同一
  /// 份进度（页面文件头注释的历史 bug：条形必须包在监听动画的
  /// AnimatedBuilder 里）。
  final Animation<double> entrance;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    final stats = buildFuelCostStats(records: fuelRecords, today: today);
    final months = fuelMonthlyCents(fuelRecords, today);
    return LunioCard(
      child: LunioSection(
        title: '加油费用',
        children: [
          // 头部一行：总费用标签 + 金额基线对齐，右侧月均小字（与占比
          // 卡的"累计优惠"同位同层级）。
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
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
              const SizedBox(width: 6),
              Text(
                formatMoneyCents(stats.totalCents),
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              Text(
                '月均 ${formatMoneyCents(stats.monthlyAvgCents)}',
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: tokens.muted),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _AxesColumnChart(
            entrance: entrance,
            items: [
              for (final point in months)
                _ColumnItem(
                  valueCents: point.costCents,
                  axisLabel: '${point.year % 100}.${point.month}',
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

/// 保养费用卡（2026-09-24 改版：由"保养费用走势"改名并改 A 方案坐标
/// 系柱状图；同日第五轮：柱色统一主色、删今年柱高亮、图表行为与加油
/// 卡统一）：每年一柱 = 该年记录总费用合计（复用 stats.years 的年度聚
/// 合），纵轴刻度 + 虚线网格线、柱顶标金额；放得下铺满卡宽、年份多到
/// 超一屏才横向滚动（底部滚动条、初始停最右，见 [_AxesColumnChart]）。
/// 不足 2 条记录由调用方整卡隐藏（cost_stats_page 的内容组装处）。
class _YearTrendCard extends StatelessWidget {
  const _YearTrendCard({
    required this.years,
    required this.entrance,
  });

  /// 年度柱数据（首条记录年 → 今年升序，含无记录年，口径同占比卡的
  /// 记录总费用权威值）。
  final List<CostYearPoint> years;

  final Animation<double> entrance;

  @override
  Widget build(BuildContext context) {
    return LunioCard(
      child: LunioSection(
        title: '保养费用',
        children: [
          const SizedBox(height: 6),
          _AxesColumnChart(
            entrance: entrance,
            items: [
              for (final point in years)
                _ColumnItem(
                  valueCents: point.costCents,
                  axisLabel: '${point.year}',
                  barKey: ValueKey('cost-year-bar-${point.year}'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 坐标系柱状图的一列数据（2026-09-24 A 方案）：柱值 + 轴标签。刻度与
/// 柱高比例由 [_AxesColumnChart] 按全部柱值统一计算（同一把尺）；柱体
/// 颜色统一主色（2026-09-24 第五轮拍板，无高亮语义）。
class _ColumnItem {
  const _ColumnItem({
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
/// 动画长高——整图包在监听 [entrance] 的 AnimatedBuilder 里（页面文件
/// 头注释的历史 bug：漏包导致条形停在进度 0）。
class _AxesColumnChart extends StatefulWidget {
  const _AxesColumnChart({
    required this.items,
    required this.entrance,
  });

  final List<_ColumnItem> items;
  final Animation<double> entrance;

  @override
  State<_AxesColumnChart> createState() => _AxesColumnChartState();
}

class _AxesColumnChartState extends State<_AxesColumnChart> {
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

  /// 刻度三档（0 / 半峰 / 峰）：步进取整到常见金额档（¥50 → ¥1 万），
  /// 取第一个 ≥ 最大柱值一半的步进，峰刻度 = 步进 × 2 ≥ 最大柱值——
  /// 最高柱顶不会顶穿网格线。返回 [0, 半峰, 峰]，单位分。
  List<int> _ticks(int maxValueCents) {
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
        return [0, step, step * 2];
      }
    }
    final top = (maxValueCents / 1000000).ceil() * 1000000;
    return [0, top ~/ 2, top];
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
        final ticks = _ticks(maxCents);
        final topTick = ticks[2];
        // 柱区底部（基线）在列内的 y 坐标；柱高按峰刻度归一（而非按最
        // 大柱值），柱顶不会越过峰刻度线。
        final baseY = _plotHeight - _labelSlot;
        double yFor(int cents) => baseY -
            (topTick == 0 ? 0.0 : (cents / topTick) * _barMaxHeight);
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
                  for (final tick in ticks)
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
                  // 与加油月度柱走同一套逻辑。
                  final needsScroll =
                      widget.items.length * _columnWidth >
                          constraints.maxWidth;
                  if (!needsScroll) {
                    return _plot(context, ticks, yFor, tokens);
                  }
                  // 视口取整放下整数根柱：柱宽在 64 基础上微调放大（≤+
                  // 一柱的分摊），滚动范围因此必然是柱宽整数倍——初始停
                  // 最右时左右两缘都是完整的月/年，不露半根（2026-09-24
                  // 五轮复验反馈）。
                  final visibleColumns =
                      (constraints.maxWidth / _columnWidth).floor();
                  final columnWidth =
                      constraints.maxWidth / visibleColumns;
                  _scheduleJumpToEnd();
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
                          ticks,
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
  /// × [columnWidth]（随内容一起滚，列宽由调用方取整校准过）。
  Widget _plot(
    BuildContext context,
    List<int> ticks,
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
          for (final tick in ticks)
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
                    ticks[2],
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

  /// 柱状一列：金额槽（0 元留空）+ 柱体（高按峰刻度归一、随入场动画
  /// 长高；0 元画 2dp 灰桩，有花费统一主色）+ 轴标签。铺满模式等分视
  /// 口、滚动模式定宽（[columnWidth]）。
  Widget _column(
    BuildContext context,
    _ColumnItem item,
    int topTick,
    double progress, {
    double? columnWidth,
  }) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    final hasCost = item.valueCents > 0;
    final fraction = topTick == 0 ? 0.0 : item.valueCents / topTick;
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
