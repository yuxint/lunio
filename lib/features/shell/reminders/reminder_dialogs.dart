// 应用内提醒弹窗（AppShell 检测到到期项时弹出）：保养提醒 + 里程更新两类。
//
// 两个动作的语义（返回值由通知同步控制器处理副作用）：
//  - acknowledged（"知道了"）：当天不再弹（控制器经协调器写当日 ack 偏好）；
//  - snoozed（"15 天内不再提醒"）：这里经协调器写 snooze 偏好
//    （系统通知和应用内弹窗一起静默 15 天）。
// 点遮罩关闭返回 null（什么都不写，下次签名变化/resume 还会弹）。
// 两类弹窗共用同一骨架 _ReminderDialog（标题+内容+snooze/ack 动作行，
// 2026-09-26 收编——此前是同一套 saving 旗/按钮行/pop 机器手写两遍）；
// 卡片外壳统一走 shared 的 LunioDialogCard/LunioDialogActions。
// ignore_for_file: use_key_in_widget_constructors, library_private_types_in_public_api

import 'package:flutter/material.dart';

import '../../../core/date/local_date.dart';
import '../../../core/theme/lunio_tokens.dart';
import '../../../domain/entities/car.dart';
import '../shared/shell_shared.dart';
import 'notification_coordinator.dart';
import 'reminder_notifications.dart';
import 'reminder_rows.dart';

/// 弹窗动作结果枚举。
enum ReminderDialogAction { acknowledged, snoozed }

/// 到期详情长文案（应用内弹窗用，含超期量；兜底复用通知侧的
/// 到期原因短文案）。
String dueNoticeText(ReminderViewData row) {
  final details = <String>[];
  final daysRemaining = row.progress.daysRemaining;
  if (row.item.remindByTime && daysRemaining != null && daysRemaining <= 0) {
    details.add(
      daysRemaining == 0
          ? '时间今日到期'
          : '已超 ${formatReminderDuration(daysRemaining.abs())}',
    );
  }
  final mileageRemaining = row.progress.mileageRemainingKm;
  if (row.item.remindByMileage &&
      mileageRemaining != null &&
      mileageRemaining <= 0) {
    details.add(
      mileageRemaining == 0
          ? '里程已到期'
          : '已超 ${formatNumber(mileageRemaining.abs())}km',
    );
  }
  if (details.isEmpty) {
    return dueReasonText(row);
  }
  return details.join(' · ');
}

/// 保养提醒弹窗：一次列出全部到期项（每项一段）。
/// "15 天内不再提醒"经协调器逐项写 snooze 偏好后返回 snoozed。
Future<ReminderDialogAction?> showMaintenanceReminderDialog({
  required BuildContext context,
  required LunioNotificationCoordinator coordinator,
  required Car car,
  required List<ReminderViewData> maintenanceNotices,
  required LocalDate today,
}) {
  return showLunioDialog<ReminderDialogAction>(
    context: context,
    barrierDismissible: true,
    builder: (context) {
      return _ReminderDialog(
        title: '保养提醒',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (index, notice) in maintenanceNotices.indexed) ...[
              if (index > 0) const SizedBox(height: 10),
              ReminderNotificationSegment(
                title: notice.title,
                body: dueNoticeText(notice),
              ),
            ],
          ],
        ),
        onSnooze: () async {
          final itemIds = [
            for (final notice in maintenanceNotices)
              if (notice.item.id != null) notice.item.id!,
          ];
          if (itemIds.isNotEmpty) {
            await coordinator.snoozeMaintenanceItems(itemIds, today);
          }
        },
      );
    },
  );
}

/// 里程更新提醒弹窗（按车 snooze）。
Future<ReminderDialogAction?> showMileageUpdateReminderDialog({
  required BuildContext context,
  required LunioNotificationCoordinator coordinator,
  required Car car,
  required LocalDate today,
}) {
  return showLunioDialog<ReminderDialogAction>(
    context: context,
    barrierDismissible: true,
    builder: (context) {
      return _ReminderDialog(
        title: '更新当前里程',
        child: Text(
          '建议更新 ${car.brand} ${car.model} 的当前里程。',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        onSnooze: () async {
          final carId = car.id;
          if (carId == null) {
            return;
          }
          await coordinator.snoozeMileageUpdate(carId, today);
        },
      );
    },
  );
}

/// 两类提醒弹窗的公共骨架：标题 + 内容段 + 「15 天内不再提醒 /
/// 知道了」动作行（卡片外壳 LunioDialogCard）。saving 期间两键禁用、
/// 次键文案换「处理中...」；snooze 完成后 pop(snoozed)，"知道了"直接
/// pop(acknowledged)，副作用由通知同步控制器按返回值处理。
class _ReminderDialog extends StatefulWidget {
  const _ReminderDialog({
    required this.title,
    required this.child,
    required this.onSnooze,
  });

  final String title;

  /// 内容主体（保养弹窗=到期项分段卡列表，里程弹窗=一句话正文）。
  final Widget child;

  /// 点「15 天内不再提醒」时执行的静默写入（经协调器，见各 show 入口）。
  final Future<void> Function() onSnooze;

  @override
  State<_ReminderDialog> createState() => _ReminderDialogState();
}

class _ReminderDialogState extends State<_ReminderDialog> {
  bool saving = false;

  @override
  Widget build(BuildContext context) {
    return LunioDialogCard(
      title: widget.title,
      actions: LunioDialogActions(
        secondaryLabel: saving ? '处理中...' : '15 天内不再提醒',
        onSecondaryPressed: saving ? null : _snooze,
        primaryLabel: '知道了',
        onPrimaryPressed: saving
            ? null
            : () =>
                  Navigator.of(context).pop(ReminderDialogAction.acknowledged),
      ),
      child: widget.child,
    );
  }

  Future<void> _snooze() async {
    setState(() => saving = true);
    await widget.onSnooze();
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop(ReminderDialogAction.snoozed);
  }
}

/// 弹窗里单个到期项的分段卡（项目名 + 到期详情）。
class ReminderNotificationSegment extends StatelessWidget {
  const ReminderNotificationSegment({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tokens.surface2,
        borderRadius: BorderRadius.circular(tokens.radiusMedium),
        border: Border.all(color: tokens.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          Text(body, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}
