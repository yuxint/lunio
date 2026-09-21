// 项目档案 sheet：费用统计页项目占比卡的钻取层（点项目行打开）。
//
// 展示单个保养项目的累计口径（次数/累计实付/单次均价/累计优惠）与
// 逐次明细（日期倒序：日期、里程、实付 + 优惠小字）。数据由
// cost_stats.dart 的 buildItemHistories 聚合（与环形图同一套分摊口径，
// 数字互相对得上）；本文件只负责呈现，纯只读、无写点。
// Java 类比：一个只读明细弹层——报表页里点某一行弹出的下钻视图。
import 'package:flutter/material.dart';

import '../../../core/theme/lunio_tokens.dart';
import '../shared/shell_shared.dart';
import 'cost_stats.dart';

/// 打开项目档案 sheet。
Future<void> showCostItemHistorySheet(
  BuildContext context,
  CostItemHistory history,
) {
  return showLunioModalSheet(
    context: context,
    builder: (context) => _CostItemHistorySheet(history: history),
  );
}

class _CostItemHistorySheet extends StatelessWidget {
  const _CostItemHistorySheet({required this.history});

  final CostItemHistory history;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.72;
    return PrototypeSheetFrame(
      title: history.name,
      subtitle: '累计实付 ${formatMoneyCents(history.totalActualCents)}'
          '${history.totalDiscountCents > 0 ? '（优惠 ${formatMoneyCents(history.totalDiscountCents)}）' : ''}',
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 汇总块：次数 / 单次均价 / 累计计费值 三格。
              Row(
                children: [
                  _metricBlock(context, tokens, '次数', '${history.count} 次'),
                  _metricBlock(
                    context,
                    tokens,
                    '单次均价',
                    history.count == 0
                        ? '—'
                        : formatMoneyCents(history.avgActualCents),
                  ),
                  _metricBlock(
                    context,
                    tokens,
                    '累计计费',
                    formatMoneyCents(history.totalValueCents),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (history.entries.isEmpty)
                Text(
                  '没有可统计的费用明细（记录未填费用）。',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: tokens.muted),
                )
              else ...[
                Text(
                  '逐次明细',
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                for (final entry in history.entries)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: _HistoryRow(entry: entry),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 汇总三格中的格：标签 + 数值。
  Widget _metricBlock(
    BuildContext context,
    LunioTokens tokens,
    String label,
    String value,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: tokens.surface2,
          borderRadius: BorderRadius.circular(12),
        ),
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
          ],
        ),
      ),
    );
  }
}

/// 逐次明细一行：左侧日期 + 里程，右侧实付（+ 优惠小字）。
class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.entry});

  final CostItemHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                entry.date.toString(),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Text(
                '${entry.mileageKm} km',
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: tokens.muted),
              ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              formatMoneyCents(entry.actualCents),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            if (entry.discountCents > 0)
              Text(
                '省 ${formatMoneyCents(entry.discountCents)}',
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
      ],
    );
  }
}
