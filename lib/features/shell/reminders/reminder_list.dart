// 提醒列表：全部项目平铺（横向量规行）+ 单行卡片 + 点击详情 sheet +
// 进度环画笔（停车倒计时仍共用）。
//
// 2026-09-30 用户拍板去掉 ADR 0018 的分层分组（修订见 docs/adr/0018
// 修订节）：不再分「需要处理 / 其余」两层、没有折叠行与节头，全部项目
// 按紧迫度直接平铺（排序仍在 buildReminderRows：状态差 → 百分比降序 →
// sortOrder）。行形态保持量规行（标题/徽章/量规/百分比/详情行）。
// 空态处理（按优先级）不变：加载中 → 加载失败 → 暂无保养记录 →
// 暂无启用项目 → 正常列表；优先级判断单一出口在 classifyReminderRows。
// 数据自取（watch reminderRowsProvider），不再由页面透传 items/records/today。
// ⚠ 无记录时不显示提醒行（新车主不轰炸），产品约定见 maintenanceNotices。
// 列表用 Column 直排非懒加载（列表项有限，可接受）。
// ignore_for_file: use_key_in_widget_constructors, library_private_types_in_public_api

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/lunio_tokens.dart';
import '../../../core/widgets/lunio_components.dart';
import '../shared/shell_shared.dart';
import 'reminder_rows.dart';

/// 提醒列表容器：自取 reminderRowsProvider，全部项目平铺；空态/错误态
/// 同旧版。
class ReminderList extends ConsumerWidget {
  const ReminderList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final board = ref.watch(reminderRowsProvider);
    return board.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) =>
          LunioEmptyCard('加载失败：${friendlyError(error)}'),
      data: (value) => switch (classifyReminderRows(value)) {
        ReminderRowsNoRecords() => const LunioEmptyCard('暂无保养记录'),
        ReminderRowsNoEnabledItems() => const LunioEmptyCard(
            '暂无启用的保养项目，请先在“我的”里配置保养项目。',
          ),
        ReminderRowsData(:final rows) => _buildBoard(rows),
      },
    );
  }

  /// 正常数据形态：全部量规行平铺（无节头、无折叠），排序继承
  /// buildReminderRows 的紧迫度排序。
  Widget _buildBoard(List<ReminderViewData> rows) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final row in rows) ...[
          ReminderRow(row: row),
          const SizedBox(height: 9),
        ],
      ],
    );
  }
}

/// 单条提醒卡片（ADR 0018 重设计）：横向量规替代进度环——
/// 标题 + 状态徽章 / 量规（按语义色着色，按展示百分比填充）+ 百分比 /
/// 剩余里程/时间详情行。旧版展示数据一项不少，整行可点 → 详情 sheet。
class ReminderRow extends StatelessWidget {
  const ReminderRow({required this.row});

  final ReminderViewData row;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    final color = row.tone.statusForeground(tokens);
    return LunioCard(
      padding: EdgeInsets.zero,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(tokens.radiusLarge),
        child: InkWell(
          onTap: () => showReminderRecordDetail(context, row),
          borderRadius: BorderRadius.circular(tokens.radiusLarge),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        row.title,
                        // 方向稿 A：行标题用 titleSmall（15/w700），整页更紧
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    LunioStatusBadge(label: row.badge, tone: row.tone),
                  ],
                ),
                const SizedBox(height: 9),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Container(
                          height: 8,
                          color: tokens.surface3,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: FractionallySizedBox(
                              widthFactor: (row.displayPercent / 100).clamp(
                                0.0,
                                1.0,
                              ),
                              child: Container(color: color),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 9),
                    SizedBox(
                      // 固定槽宽右对齐：不同位数（7% vs 102%）下量规右端
                      // 不随百分比文字宽度抖动；40 宽容纳 3 位数 + %
                      // 且强制单行（102% 不折行，右缘与上方徽章对齐）。
                      width: 40,
                      child: Text(
                        row.percentText,
                        maxLines: 1,
                        softWrap: false,
                        textAlign: TextAlign.right,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: color,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                for (final detail in row.detailTexts) ...[
                  Text(
                    detail,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (detail != row.detailTexts.last)
                    const SizedBox(height: 2),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 点击提醒行弹出的详情 sheet：上次保养日期/里程 + 距上次时间/里程
/// （参照点 = 今天 / 车辆当前里程；无记录显示占位卡）。
void showReminderRecordDetail(BuildContext context, ReminderViewData row) {
  final record = row.latestRecord;
  showLunioModalSheet<void>(
    context: context,
    builder: (context) {
      final tokens = Theme.of(context).extension<LunioTokens>()!;
      return PrototypeSheetFrame(
        title: row.title,
        subtitle: row.badge == '正常' ? '保养状态正常' : '当前状态：${row.badge}',
        child: record == null
            ? Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: tokens.surface2,
                  borderRadius: BorderRadius.circular(tokens.radiusLarge),
                ),
                child: Text(
                  '暂无上次保养记录',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: tokens.muted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: ReminderRecordMetric(
                          label: '上次保养日期',
                          value: record.date.toString(),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ReminderRecordMetric(
                          label: '上次保养里程',
                          value: '${formatNumber(record.mileageKm)} km',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // 距上次（参照点 = 今天 / 当前里程）：无上一条或差值为负
                  // 时由格式化函数兜底显示 —。
                  Row(
                    children: [
                      Expanded(
                        child: ReminderRecordMetric(
                          label: '距上次时间',
                          value: formatDaysSinceLast(row.daysSinceLatest),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ReminderRecordMetric(
                          label: '距上次里程',
                          value: formatKmSinceLast(row.kmSinceLatest),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
      );
    },
  );
}

/// 详情 sheet 里的指标格（标签 + 值）。
class ReminderRecordMetric extends StatelessWidget {
  const ReminderRecordMetric({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tokens.surface2,
        borderRadius: BorderRadius.circular(tokens.radiusLarge),
        border: Border.all(color: tokens.line.withValues(alpha: 0.72)),
      ),
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
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

/// 进度环画笔（CustomPainter ≈ 自定义 Canvas 绘制）：
/// 背景圆 + 从 12 点方向顺时针的进度弧。提醒列表与停车倒计时共用。
/// ADR 0018 重设计后提醒行改横向量规，本画笔当前只服务停车倒计时卡。
class ReminderProgressRingPainter extends CustomPainter {
  const ReminderProgressRingPainter({
    required this.percent,
    required this.color,
    required this.backgroundColor,
    this.strokeWidth = 6,
  });

  final double percent;
  final Color color;
  final Color backgroundColor;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.shortestSide - strokeWidth) / 2;
    final backgroundPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = strokeWidth;
    final foregroundPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = strokeWidth;
    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawCircle(center, radius, backgroundPaint);
    canvas.drawArc(
      rect,
      -1.5708,
      6.2832 * (percent / 100).clamp(0, 1),
      false,
      foregroundPaint,
    );
  }

  @override
  bool shouldRepaint(ReminderProgressRingPainter oldDelegate) {
    return percent != oldDelegate.percent ||
        color != oldDelegate.color ||
        backgroundColor != oldDelegate.backgroundColor ||
        strokeWidth != oldDelegate.strokeWidth;
  }
}
