// 提醒列表：待关注项目卡片列表 + 单行卡片 + 点击详情 sheet + 进度环画笔。
//
// 空态处理（按优先级）：加载中 → 项目/记录加载失败 → 无任何记录
// （"记录首保后再生成提醒"）→ 无启用项目 → 正常列表。
// ⚠ 无记录时不显示提醒行（新车主不轰炸），产品口径见 maintenanceNotices。
// 列表用 Column 直排非懒加载（列表项有限，可接受）。
// ignore_for_file: use_key_in_widget_constructors, library_private_types_in_public_api

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/date/local_date.dart';
import '../../../core/theme/lunio_tokens.dart';
import '../../../core/widgets/lunio_components.dart';
import '../../../domain/entities/car.dart';
import '../../../domain/entities/maintenance_item.dart';
import '../../../domain/entities/maintenance_record.dart';
import '../shared/shell_shared.dart';
import 'reminder_notifications.dart';

/// 提醒列表容器：处理各种空态/错误态后渲染 ReminderRow 列表。
class ReminderList extends StatelessWidget {
  const ReminderList({
    required this.car,
    required this.items,
    required this.records,
    required this.today,
  });

  final Car car;
  final AsyncValue<List<MaintenanceItem>> items;
  final AsyncValue<List<MaintenanceRecord>> records;
  final LocalDate today;

  @override
  Widget build(BuildContext context) {
    if (items.isLoading || records.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (items.hasError) {
      return LunioCard(child: Text('保养项目加载失败：${friendlyError(items.error!)}'));
    }
    if (records.hasError) {
      return LunioCard(
        child: Text('保养记录加载失败：${friendlyError(records.error!)}'),
      );
    }
    if ((records.value ?? const <MaintenanceRecord>[]).isEmpty) {
      return LunioCard(
        child: Text(
          '暂无保养记录，记录首保后再生成保养提醒。',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }
    final rows = buildReminderRows(
      car: car,
      items: items.value ?? const [],
      records: records.value ?? const [],
      today: today,
    );
    if (rows.isEmpty) {
      return LunioCard(
        child: Text(
          '暂无启用的保养项目，请先在“我的”里配置保养项目。',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }
    return Column(
      children: [
        for (final row in rows) ...[
          ReminderRow(row: row),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

/// 单条提醒卡片：进度环（百分比）+ 项目名 + 状态徽章 + 剩余里程/时间文案。
/// 整行可点 → 弹出上次保养详情 sheet。
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
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                SizedBox.square(
                  dimension: 58,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CustomPaint(
                        size: const Size.square(58),
                        painter: ReminderProgressRingPainter(
                          percent: row.displayPercent.toDouble(),
                          color: color,
                          backgroundColor: tokens.surface3,
                        ),
                      ),
                      SizedBox(
                        width: 44,
                        height: 22,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            row.percentText,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: color,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              row.title,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          LunioStatusBadge(label: row.badge, tone: row.tone),
                        ],
                      ),
                      const SizedBox(height: 6),
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 点击提醒行弹出的详情 sheet：上次保养日期/里程（无记录显示占位卡）。
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
                ],
              ),
      );
    },
  );
}

/// 详情 sheet 里的指标格（标签 + 值）。
class ReminderRecordMetric extends StatelessWidget {
  const ReminderRecordMetric({required this.label, required this.value});

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
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
    );
  }
}

/// 进度环画笔（CustomPainter ≈ 自定义 Canvas 绘制）：
/// 背景圆 + 从 12 点方向顺时针的进度弧。提醒列表与停车倒计时共用。
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
