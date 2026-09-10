// 记录详情弹窗（records/record_detail_sheet.dart）：记录页两种视图的
// 整卡点击入口（ADR 0010）。按周期视图看整条记录，按项目视图只看单个
// 项目。与 Java Web 类比：一个自带数据装配的只读详情对话框——弹窗自己
// watch provider 取数，而不是让列表页把整份全量记录当参数层层传进来，
// 列表页只告诉它"要展示哪条记录/哪个项目"。
//
// 数据自取（watch appliedCar 的记录与项目两个 provider）：弹窗是模态的，
// 打开时数据必已加载（卡片本身就渲染自同一 provider）；provider 值取
// 不到时按空数据处理（距上次显示占位、项目名显示"未知项目"），不另设
// loading 分支。展示永远取存储值，不做读时修正（ADR 0010）。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/theme/lunio_tokens.dart';
import '../../../domain/entities/maintenance_item.dart';
import '../../../domain/entities/maintenance_record.dart';
import '../../../domain/rules/record_rules.dart';
import '../shared/shell_shared.dart';

/// ★ 记录详情弹窗（记录页两种视图的整卡点击入口，ADR 0010）：
///  - focusItemId 为空（按周期视图）：看整条记录——日期/里程/总费用
///    指标格 + 备注 + 全部项目费用清单；
///  - focusItemId 非空（按项目视图）：只看该项目——日期/里程 + 距上次
///    时间/里程（参照点 = 该项目上一条记录 → 本条）+ 材料费/工时费
///    一行 + 项目费用格。
/// 数据自取：调用方只给 record + focusItemId，"距上次"找上一条所需的
/// 全量记录知识收进 [_RecordDetailContent] 内部，列表卡片不再透传
/// carRecords。不一致的项目费用/总费用加黄色警告角标。
void showRecordDetailSheet(
  BuildContext context, {
  required MaintenanceRecord record,
  int? focusItemId,
}) {
  showLunioModalSheet<void>(
    context: context,
    builder: (sheetContext) =>
        _RecordDetailContent(record: record, focusItemId: focusItemId),
  );
}

/// 弹窗内容：watch 全量记录与项目两个 provider 后按模式装配指标格。
class _RecordDetailContent extends StatelessWidget {
  const _RecordDetailContent({required this.record, this.focusItemId});

  final MaintenanceRecord record;

  /// 非空 = 按项目视图，只展示该项目（标题也换成项目名）。
  final int? focusItemId;

  @override
  Widget build(BuildContext context) {
    // focusItemId 是字段，Dart 不做字段类型提升；收进 final 局部变量后
    // 判空分支里就能收窄成 int。
    final focusId = focusItemId;
    return Consumer(
      builder: (context, ref, _) {
        // 弹窗是模态的，打开时数据必已加载（卡片渲染自同一 provider）；
        // 值取不到时按空数据处理，不另设 loading 分支。
        final carRecords = ref.watch(appliedCarRecordsProvider).value ??
            const <MaintenanceRecord>[];
        final items = ref.watch(appliedCarMaintenanceItemsProvider).value ??
            const <MaintenanceItem>[];
        final costsByItemId = <int, RecordItemCost>{
          for (final cost in record.itemCosts) cost.itemId: cost,
        };
        final focusCost = focusId == null ? null : costsByItemId[focusId];
        final totalMismatch = RecordRules.totalCostMismatch(
          totalCostCents: record.costCents,
          itemCosts: record.itemCosts,
        );
        final Widget content;
        if (focusId == null) {
          content = Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _dateMileageRow(record),
              const SizedBox(height: 10),
              _RecordMetricTile(
                label: '总费用',
                value: formatMoneyCents(record.costCents),
                warning: totalMismatch,
              ),
              if ((record.note ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                _RecordNoteBlock(note: record.note!.trim()),
              ],
              const SizedBox(height: 14),
              Text(
                '项目费用',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 8),
              for (final itemId in record.itemIds)
                _ItemCostListRow(
                  name: itemById(items, itemId)?.name ?? '未知项目',
                  cost: costsByItemId[itemId],
                ),
            ],
          );
        } else {
          // 距上次参照点 = 该项目上一条记录 → 本条（从全量记录里找，
          // 严格早于本条日期的最新一条）；项目首条或差值为负显示 —。
          final previousRecord = RecordRules.previousRecordForItem(
            records: carRecords,
            itemId: focusId,
            beforeDate: record.date,
          );
          final materialCents = focusCost?.materialCents;
          final laborCents = focusCost?.laborCents;
          // 材料费/工时费都未填时整行不显示；只填一格另一格显示 —。
          final hasSplitCosts = materialCents != null || laborCents != null;
          content = Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _dateMileageRow(record),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _RecordMetricTile(
                      label: '距上次时间',
                      value: formatDaysSinceLast(
                        RecordRules.daysSinceLast(
                          baselineRecord: previousRecord,
                          untilDate: record.date,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _RecordMetricTile(
                      label: '距上次里程',
                      value: formatKmSinceLast(
                        RecordRules.kmSinceLast(
                          baselineRecord: previousRecord,
                          untilMileageKm: record.mileageKm,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (hasSplitCosts) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _RecordMetricTile(
                        label: '材料费',
                        value: materialCents == null
                            ? '—'
                            : formatMoneyCents(materialCents),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _RecordMetricTile(
                        label: '工时费',
                        value:
                            laborCents == null
                                ? '—'
                                : formatMoneyCents(laborCents),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 10),
              _RecordMetricTile(
                label: '项目费用',
                value: focusCost?.costCents == null
                    ? '—'
                    : formatMoneyCents(focusCost!.costCents!),
                warning: focusCost != null &&
                    RecordRules.itemCostMismatch(focusCost),
              ),
            ],
          );
        }
        return PrototypeSheetFrame(
          title: focusId == null
              ? '保养记录'
              : itemById(items, focusId)?.name ?? '未知项目',
          // 副标题只在按周期视图显示总费用；按项目视图没有总费用概念。
          subtitle: focusId == null
              ? '整条记录总费用 ${formatMoneyCents(record.costCents)}'
              : null,
          child: content,
        );
      },
    );
  }
}

/// 两种模式共用的头部两格：保养日期 + 保养里程。
Row _dateMileageRow(MaintenanceRecord record) {
  return Row(
    children: [
      Expanded(
        child: _RecordMetricTile(
          label: '保养日期',
          value: record.date.toString(),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: _RecordMetricTile(
          label: '保养里程',
          value: '${formatNumber(record.mileageKm)} km',
        ),
      ),
    ],
  );
}

/// 详情弹窗里的指标格（标签 + 值，风格与提醒页详情一致）。
/// warning 为 true 时值旁加黄色警告角标（费用不一致提示，ADR 0010）。
class _RecordMetricTile extends StatelessWidget {
  const _RecordMetricTile({
    required this.label,
    required this.value,
    this.warning = false,
  });

  final String label;
  final String value;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tokens.surface2,
        borderRadius: BorderRadius.circular(tokens.radiusLarge),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: tokens.muted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          if (warning)
            Icon(Icons.warning_amber_rounded, size: 20, color: tokens.warning),
        ],
      ),
    );
  }
}

/// 详情弹窗的备注块（surface2 容器整行展示）。
class _RecordNoteBlock extends StatelessWidget {
  const _RecordNoteBlock({required this.note});

  final String note;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tokens.surface2,
        borderRadius: BorderRadius.circular(tokens.radiusLarge),
      ),
      child: Text(note, style: Theme.of(context).textTheme.bodyMedium),
    );
  }
}

/// 详情弹窗项目费用清单的一行：项目名 + 项目费用（未填显示占位 —），
/// 填了材料/工时的用小字标注；项目费用与材料+工时不一致时加黄色
/// 警告角标（ADR 0010）。
class _ItemCostListRow extends StatelessWidget {
  const _ItemCostListRow({required this.name, this.cost});

  final String name;
  final RecordItemCost? cost;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    final splitParts = <String>[
      if (cost?.materialCents != null)
        '材料 ${formatMoneyCents(cost!.materialCents!)}',
      if (cost?.laborCents != null) '工时 ${formatMoneyCents(cost!.laborCents!)}',
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (splitParts.isNotEmpty)
                  Text(
                    splitParts.join(' / '),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: tokens.muted,
                    ),
                  ),
              ],
            ),
          ),
          if (cost != null && RecordRules.itemCostMismatch(cost!))
            Icon(Icons.warning_amber_rounded, size: 18, color: tokens.warning),
          const SizedBox(width: 6),
          Text(
            cost?.costCents == null ? '—' : formatMoneyCents(cost!.costCents!),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: tokens.primary,
            ),
          ),
        ],
      ),
    );
  }
}
