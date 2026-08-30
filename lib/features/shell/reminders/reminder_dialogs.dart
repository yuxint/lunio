// 应用内提醒弹窗（AppShell 检测到到期项时弹出）：保养提醒 + 里程更新两类。
//
// 两个动作的语义（返回值由 AppShell 处理副作用）：
//  - acknowledged（"知道了"）：当天不再弹（AppShell 写当日 ack 偏好）；
//  - snoozed（"15 天内不再提醒"）：这里直接写 snooze 偏好
//    （系统通知和应用内弹窗一起静默 15 天）。
// 点遮罩关闭返回 null（什么都不写，下次签名变化/resume 还会弹）。
// ignore_for_file: use_key_in_widget_constructors, library_private_types_in_public_api

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/date/local_date.dart';
import '../../../core/theme/lunio_tokens.dart';
import '../../../core/widgets/lunio_components.dart';
import '../../../domain/entities/car.dart';
import '../shared/shell_shared.dart';
import 'reminder_notifications.dart';

/// 弹窗动作结果枚举。
enum ReminderDialogAction { acknowledged, snoozed }

/// 保养提醒弹窗：一次列出全部到期项（每项一段）。
/// "15 天内不再提醒"逐项写 snooze 偏好后返回 snoozed。
Future<ReminderDialogAction?> showMaintenanceReminderDialog({
  required BuildContext context,
  required WidgetRef ref,
  required Car car,
  required List<ReminderViewData> maintenanceNotices,
  required LocalDate today,
}) {
  return showLunioDialog<ReminderDialogAction>(
    context: context,
    barrierDismissible: true,
    builder: (context) {
      return _MaintenanceReminderDialog(
        car: car,
        maintenanceNotices: maintenanceNotices,
        today: today,
        onSnoozeAll: () async {
          final repository = ref.read(lunioRepositoryProvider);
          final until = snoozeUntilDate(today).toString();
          for (final notice in maintenanceNotices) {
            final itemId = notice.item.id;
            if (itemId != null) {
              await repository.setPreferenceValue(
                maintenanceReminderSnoozeKey(itemId),
                until,
              );
            }
          }
        },
      );
    },
  );
}

/// 里程更新提醒弹窗（按车 snooze）。
Future<ReminderDialogAction?> showMileageUpdateReminderDialog({
  required BuildContext context,
  required WidgetRef ref,
  required Car car,
  required LocalDate today,
}) {
  return showLunioDialog<ReminderDialogAction>(
    context: context,
    barrierDismissible: true,
    builder: (context) {
      return _MileageUpdateReminderDialog(
        car: car,
        onSnooze: () async {
          final carId = car.id;
          if (carId == null) {
            return;
          }
          await ref
              .read(lunioRepositoryProvider)
              .setPreferenceValue(
                mileageUpdateSnoozeKey(carId),
                snoozeUntilDate(today).toString(),
              );
        },
      );
    },
  );
}

/// 保养提醒弹窗内容（可滚动，防到期项太多溢出）。
class _MaintenanceReminderDialog extends StatefulWidget {
  const _MaintenanceReminderDialog({
    required this.car,
    required this.maintenanceNotices,
    required this.today,
    required this.onSnoozeAll,
  });

  final Car car;
  final List<ReminderViewData> maintenanceNotices;
  final LocalDate today;
  final Future<void> Function() onSnoozeAll;

  @override
  State<_MaintenanceReminderDialog> createState() =>
      _MaintenanceReminderDialogState();
}

class _MaintenanceReminderDialogState
    extends State<_MaintenanceReminderDialog> {
  bool saving = false;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      backgroundColor: Colors.transparent,
      child: Container(
        width: double.infinity,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.82,
        ),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: tokens.surface,
          borderRadius: BorderRadius.circular(tokens.radiusLarge),
          border: Border.all(color: tokens.line),
          boxShadow: [
            BoxShadow(
              color: tokens.ink.withValues(alpha: 0.16),
              blurRadius: 36,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('保养提醒', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              for (final notice in widget.maintenanceNotices) ...[
                ReminderNotificationSegment(
                  title: notice.title,
                  body: dueNoticeText(notice),
                ),
                const SizedBox(height: 10),
              ],
              Row(
                children: [
                  Expanded(
                    child: LunioSecondaryButton(
                      label: saving ? '处理中...' : '15 天内不再提醒',
                      onPressed: saving ? null : _snoozeAll,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: saving
                          ? null
                          : () => Navigator.of(
                              context,
                            ).pop(ReminderDialogAction.acknowledged),
                      child: const Text('知道了'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _snoozeAll() async {
    setState(() => saving = true);
    await widget.onSnoozeAll();
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop(ReminderDialogAction.snoozed);
  }
}

/// 里程更新弹窗内容。
class _MileageUpdateReminderDialog extends StatefulWidget {
  const _MileageUpdateReminderDialog({
    required this.car,
    required this.onSnooze,
  });

  final Car car;
  final Future<void> Function() onSnooze;

  @override
  State<_MileageUpdateReminderDialog> createState() =>
      _MileageUpdateReminderDialogState();
}

class _MileageUpdateReminderDialogState
    extends State<_MileageUpdateReminderDialog> {
  bool saving = false;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      backgroundColor: Colors.transparent,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: tokens.surface,
          borderRadius: BorderRadius.circular(tokens.radiusLarge),
          border: Border.all(color: tokens.line),
          boxShadow: [
            BoxShadow(
              color: tokens.ink.withValues(alpha: 0.16),
              blurRadius: 36,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('更新当前里程', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              '建议更新 ${widget.car.brand} ${widget.car.model} 的当前里程。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: LunioSecondaryButton(
                    label: saving ? '处理中...' : '15 天内不再提醒',
                    onPressed: saving ? null : _snooze,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: saving
                        ? null
                        : () => Navigator.of(
                            context,
                          ).pop(ReminderDialogAction.acknowledged),
                    child: const Text('知道了'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
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
