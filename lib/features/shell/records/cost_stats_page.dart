// 花费统计页（/cost-stats）：保养花费全貌的独立 pushed 子页。
//
// 本 App 第一个不挂主壳层的 pushed 路由：从记录页汇总行或我的页设置行
// 经 go_router push 进栈（默认转场，iOS 右滑返回天然可用），返回键由
// LunioTopBar 的 leading 位提供。不在栈内时不渲染底部导航，因此
// LunioPage 的 bottomPadding 用小值。
//
// 结构（全部纯读取聚合，无写库、无动作层参与）：
//   1. 车辆切换 chips：默认当前应用车辆，可切任意单车 / "全部"；
//   2. 汇总卡：总花费 + 今年花费；
//   3. 按年花费横条（自绘，无图表库）；
//   4. 项目占比 Top N（项目名经项目清单解析）；
//   5. 近 12 个月走势（12 根月度小柱）。
// 聚合口径统一收在 cost_stats.dart（纯函数），本文件只负责"按作用域把
// 数据拿到"与渲染；无记录时给空态卡。
// Java 类比：一个只读报表页——provider 家族 ≈ 按作用域参数化的查询
// 服务，页面本身只做组装结果的表达。
// ignore_for_file: use_key_in_widget_constructors
// ignore_for_file: library_private_types_in_public_api

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/date/local_date.dart';
import '../../../core/theme/lunio_tokens.dart';
import '../../../core/widgets/lunio_components.dart';
import '../../../domain/entities/car.dart';
import '../../../domain/entities/maintenance_item.dart';
import '../../../domain/entities/maintenance_record.dart';
import '../shared/shell_shared.dart';
import 'cost_stats.dart';

/// 一个作用域（单车 carId / null=全部）下统计页要用的全部数据：
/// 车辆清单（chips 标签用）、记录、项目清单（项目名解析用）、生效今天。
class CostStatsPageData {
  const CostStatsPageData({
    required this.cars,
    required this.records,
    required this.items,
    required this.today,
  });

  final List<Car> cars;
  final List<MaintenanceRecord> records;
  final List<MaintenanceItem> items;
  final LocalDate today;
}

/// 统计页数据接缝：按作用域聚合记录与项目清单。单车作用域直接取按车
/// family（[recordsForCarProvider] / [maintenanceItemsForCarProvider]）；
/// "全部"（carId=null）逐车取同一批 family 实例后合并——复用既有按车
/// 查询，无新 SQL，family 缓存也让"单车 ↔ 全部"来回切换不重复查库。
/// 失效随家族走：写库后 [invalidateVehicleProviders] 整族逐出，这里
/// watch 上游自动重算。
final costStatsDataProvider =
    FutureProvider.family<CostStatsPageData, int?>((ref, carId) async {
  final today = await ref.watch(effectiveTodayProvider.future);
  final cars = await ref.watch(carsProvider.future);
  final scopeCarIds = carId != null
      ? [carId]
      : [for (final car in cars) if (car.id != null) car.id!];
  final records = <MaintenanceRecord>[];
  final items = <MaintenanceItem>[];
  for (final id in scopeCarIds) {
    records.addAll(await ref.watch(recordsForCarProvider(id).future));
    items.addAll(await ref.watch(maintenanceItemsForCarProvider(id).future));
  }
  return CostStatsPageData(
    cars: cars,
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

class CostStatsPageState extends ConsumerState<CostStatsPage> {
  /// 选中的作用域：null = "全部"，非 null = 该车 id。
  /// 初始值要等当前应用车辆解析出来（见 build 的默认作用域规则），
  /// 用户一旦手动点过 chips（hasUserChosen）就不再跟随。
  int? selectedCarId;
  bool hasUserChosen = false;

  /// pushed 子页的返回键：数据分支给 LunioPage 的 leading 位，
  /// 作用域解析失败/数据加载失败的 ErrorPage 分支也要给——否则页内
  /// 没有任何返回途径（只剩 iOS 右滑/系统返回手势）。
  Widget _backKey() => LunioIconButton(
        icon: Icons.arrow_back_ios_new,
        tooltip: '返回',
        onPressed: () => context.pop(),
      );

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    // 默认作用域 = 当前应用车辆；无车时落到 null（"全部"，实际渲染空态）。
    // 默认作用域解析阶段（用户还没点过 chips）：车辆清单或应用车辆任一
    // 未就绪时整页 loading，避免先用"全部"拉一遍再切换；任一解析失败
    // 直接错误页兜底（带返回键），不留在加载态。
    final appliedAsync = ref.watch(appliedCarProvider);
    final carsAsync = ref.watch(carsProvider);
    final appliedCarId = appliedAsync.maybeWhen(
      data: (car) => car?.id,
      orElse: () => null,
    );
    final carsReady = carsAsync.maybeWhen(
      data: (_) => true,
      orElse: () => false,
    );
    final int? scope;
    if (hasUserChosen) {
      scope = selectedCarId;
    } else if (carsReady) {
      scope = appliedCarId;
    } else {
      scope = null;
    }
    // 默认作用域解析只在前两个分支处理（用户点过 chips 后车辆清单的
    // 失败由数据 provider 的 error 分支兜住）。
    final resolvingScope =
        !hasUserChosen && (carsAsync.isLoading || appliedAsync.isLoading);
    final scopeFailed =
        !hasUserChosen && (carsAsync.hasError || appliedAsync.hasError);
    final Widget body;
    if (resolvingScope) {
      body = const LoadingPage(title: '花费统计');
    } else if (scopeFailed) {
      // 车辆清单失败优先报（应用车辆由它派生，通常一起失败）；
      // scopeFailed 已保证至少一个 error，这里取到的不会是 null。
      final gateError = carsAsync.maybeWhen(
            error: (error, _) => error,
            orElse: () => appliedAsync.maybeWhen(
              error: (error, _) => error,
              orElse: () => null,
            ),
          )!;
      body = ErrorPage(title: '花费统计', error: gateError, leading: _backKey());
    } else {
      body = ref.watch(costStatsDataProvider(scope)).when(
            loading: () => const LoadingPage(title: '花费统计'),
            error: (error, stackTrace) =>
                ErrorPage(title: '花费统计', error: error, leading: _backKey()),
            data: (data) => _buildContent(context, data, scope),
          );
    }
    // pushed 子页不经过 AppShell，Scaffold（页面底色）要自己提供——
    // 页内的 InkWell/chips 需要 Material 祖先，与 AppShell 同款底色。
    return Scaffold(backgroundColor: tokens.background, body: body);
  }

  Widget _buildContent(
    BuildContext context,
    CostStatsPageData data,
    int? scope,
  ) {
    final stats = buildCostStats(
      records: data.records,
      items: data.items,
      today: data.today,
    );
    return LunioPage(
      title: '花费统计',
      leading: _backKey(),
      bottomPadding: 24,
      children: [
        if (data.cars.isNotEmpty) ...[
          _buildScopeChips(context, data, scope),
          const SizedBox(height: 14),
        ],
        if (data.cars.isEmpty)
          const LunioEmptyCard('请先新增车辆')
        else if (data.records.isEmpty)
          const LunioEmptyCard('暂无保养记录，记一笔保养后这里会生成花费统计。')
        else ...[
          _buildSummaryCard(context, stats),
          const SizedBox(height: 12),
          _buildYearCard(context, stats),
          const SizedBox(height: 12),
          _buildItemCard(context, stats),
          const SizedBox(height: 12),
          _buildTrendCard(context, data.today, stats),
        ],
      ],
    );
  }

  /// 车辆切换 chips：每辆车一枚 + 最后一枚"全部"（scope=null）。
  Widget _buildScopeChips(
    BuildContext context,
    CostStatsPageData data,
    int? scope,
  ) {
    final labels = [
      for (final car in data.cars)
        if (car.id != null)
          (carId: car.id!, label: '${car.brand} ${car.model}'),
      (carId: null, label: '全部'),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final entry in labels)
          _ScopeChip(
            label: entry.label,
            selected: entry.carId == scope,
            onTap: () => setState(() {
              selectedCarId = entry.carId;
              hasUserChosen = true;
            }),
          ),
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

  /// 按年花费横条卡（年份升序）。
  Widget _buildYearCard(BuildContext context, CostStats stats) {
    return LunioCard(
      child: LunioSection(
        title: '按年花费',
        children: [
          for (final year in stats.years)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _LabeledBar(
                label: '${year.year}年',
                barFraction: year.fraction,
                valueText: formatMoneyCents(year.costCents),
              ),
            ),
        ],
      ),
    );
  }

  /// 项目占比 Top N 卡（项目名 + 横条 + 金额 + 占比）。
  Widget _buildItemCard(BuildContext context, CostStats stats) {
    return LunioCard(
      child: LunioSection(
        title: '项目占比',
        children: [
          for (final item in stats.topItems)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _LabeledBar(
                label: item.name,
                barFraction: item.fraction,
                valueText:
                    '${formatMoneyCents(item.costCents)} '
                    '${(item.share * 100).toStringAsFixed(0)}%',
              ),
            ),
        ],
      ),
    );
  }

  /// 近 12 个月走势卡：12 根月度小柱（旧 → 新），标题行右侧给峰值金额。
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
          SizedBox(
            height: 88,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final point in stats.months)
                  Expanded(
                    child: _MonthColumn(
                      point: point,
                      isCurrentMonth: point.year == today.year &&
                          point.month == today.month,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 作用域选择 chip（样式对齐记录页筛选条：选中 = primarySoft 底 + 主色字）。
class _ScopeChip extends StatelessWidget {
  const _ScopeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        constraints: const BoxConstraints(minHeight: 34),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? tokens.primarySoft : tokens.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? tokens.primary.withValues(alpha: 0.34)
                : tokens.line,
          ),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: selected ? tokens.primary : tokens.ink,
              ),
        ),
      ),
    );
  }
}

/// 带标签的横条行：左侧固定宽标签 + 中间比例条 + 右侧数值文案。
/// 按年花费与项目占比共用（条宽 = fraction × 可用宽度，0 时不画）。
class _LabeledBar extends StatelessWidget {
  const _LabeledBar({
    required this.label,
    required this.barFraction,
    required this.valueText,
  });

  final String label;
  final double barFraction;
  final String valueText;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
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
          child: barFraction <= 0
              ? const SizedBox.shrink()
              : Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: barFraction,
                    child: Container(
                      height: 8,
                      decoration: BoxDecoration(
                        color: tokens.primary.withValues(alpha: 0.82),
                        borderRadius: BorderRadius.circular(4),
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

/// 走势图的一根月度小柱：柱体（峰值比例高度，无花费月份画浅色矮柱）+
/// 底部月份标签（当月高亮主色）。
class _MonthColumn extends StatelessWidget {
  const _MonthColumn({required this.point, required this.isCurrentMonth});

  final CostMonthPoint point;
  final bool isCurrentMonth;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Container(
          height: 4 + point.fraction * 56,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          decoration: BoxDecoration(
            color: point.costCents > 0
                ? tokens.primary.withValues(alpha: 0.82)
                : tokens.surface3,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '${point.month}月',
          maxLines: 1,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontSize: 9,
                color: isCurrentMonth ? tokens.primary : tokens.muted,
                fontWeight: isCurrentMonth ? FontWeight.w800 : FontWeight.w500,
              ),
        ),
      ],
    );
  }
}
