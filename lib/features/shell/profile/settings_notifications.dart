// 我的页"通知提醒"设置 sheet：系统通知状态行 + 应用内通知开关 +
// 到期重复频率三段。从 settings_data.dart 拆出（2026-09-25 备份管线
// 收编动作层时顺手解 trench coat，vehicles.dart 拆分先例）。
//
// 装载/守卫/pop/toast 时序归 showLunioFormSheet（ADR 0016）；写库经
// 动作层 saveNotificationSettings（ADR 0007）。
// ignore_for_file: use_key_in_widget_constructors, library_private_types_in_public_api

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/platform/native_notification_settings.dart';
import '../../../core/theme/lunio_tokens.dart';
import '../../../core/widgets/lunio_components.dart';
import '../../../domain/entities/notification_settings.dart';
import '../reminders/notification_coordinator.dart';
import '../shared/shell_shared.dart';

/// 通知设置 sheet 入口：先 await 偏好 provider 拿到真实设置
/// （加载失败 toast 返回，杜绝 loading 期默认值覆盖真实设置，R6）→
/// 协调器向系统查询真实开关回写偏好 → 弹表单（系统状态行 + 应用内
/// 通知开关 + 重复频率三段）。装载/守卫/pop/toast 时序归
/// showLunioFormSheet（ADR 0016；本 sheet 原先可点遮罩关闭是漂移，
/// 2026-09-25 归一为与其他编辑表单一致的不可关）。
Future<void> showNotificationSettingsSheet(
  BuildContext context,
  WidgetRef ref,
) async {
  LunioNotificationSettings initialSettings = const LunioNotificationSettings(
    systemNotificationsEnabled: false,
    inAppNotificationsEnabled: false,
    dueRepeatFrequency: ReminderRepeatFrequency.weekly,
  );
  return showLunioFormSheet<void>(
    context: context,
    title: '通知提醒',
    load: (handle) async {
      final loadedSettings = await ref.read(notificationSettingsProvider.future);
      final systemNotificationsEnabled = await ref
          .read(notificationCoordinatorProvider)
          .reconcileSystemEnabled();
      initialSettings = loadedSettings.copyWith(
        systemNotificationsEnabled: systemNotificationsEnabled,
      );
    },
    builder: (sheetContext, handle) {
      return NotificationSettingsForm(
        initialSettings: initialSettings,
        handle: handle,
        onOpenSystemSettings: () async {
          final opened =
              await NativeNotificationSettings.openNotificationSettings();
          // pop 归表单运行时；打开失败带一条 info toast（ADR 0016）。
          handle.close(
            toast: opened
                ? null
                : '无法打开系统设置，请在系统设置中搜索 Lunio',
            tone: StatusOverlayTone.info,
          );
        },
        // 对账系统开关 + 批量写偏好收进动作层（ADR 0007），失效在
        // 协调器内部完成；关 sheet 与成功 toast 归表单运行时（ADR 0016）。
        onSubmit: (settings) => saveNotificationSettings(ref, settings),
      );
    },
    successMessage: '设置已保存',
  );
}

/// 通知表单：状态行 + 应用内通知开关 + 到期重复频率三段（每周/每 2 周/
/// 每月）。提交构造 LunioNotificationSettings。提交生命周期（saving/
/// 行内错误）归表单运行时把手（ADR 0016，替代原先手搓的 saving 布尔）。
class NotificationSettingsForm extends StatefulWidget {
  const NotificationSettingsForm({
    required this.initialSettings,
    required this.handle,
    required this.onOpenSystemSettings,
    required this.onSubmit,
  });

  final LunioNotificationSettings initialSettings;

  /// 表单运行时把手（ADR 0016）。
  final FormSheetHandle<void> handle;
  final Future<void> Function() onOpenSystemSettings;
  final Future<void> Function(LunioNotificationSettings settings) onSubmit;

  @override
  State<NotificationSettingsForm> createState() =>
      NotificationSettingsFormState();
}

class NotificationSettingsFormState extends State<NotificationSettingsForm> {
  static const dueRepeatOptions = [
    ReminderRepeatFrequency.weekly,
    ReminderRepeatFrequency.everyTwoWeeks,
    ReminderRepeatFrequency.monthly,
  ];

  late bool inAppNotificationsEnabled;
  late ReminderRepeatFrequency dueRepeatFrequency;

  bool get saving => widget.handle.saving;

  @override
  void initState() {
    super.initState();
    final settings = widget.initialSettings;
    inAppNotificationsEnabled = settings.inAppNotificationsEnabled;
    dueRepeatFrequency = dueRepeatOptions.contains(settings.dueRepeatFrequency)
        ? settings.dueRepeatFrequency
        : ReminderRepeatFrequency.weekly;
  }

  @override
  Widget build(BuildContext context) {
    // 标题与滚动容器由 PrototypeSheetFrame 提供，这里只出内容列。
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SystemNotificationStatusRow(
          enabled: widget.initialSettings.systemNotificationsEnabled,
          onOpenSettings: saving ? null : widget.onOpenSystemSettings,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('应用内通知'),
          value: inAppNotificationsEnabled,
          onChanged: saving
              ? null
              : (value) => setState(() => inAppNotificationsEnabled = value),
        ),
        const SizedBox(height: 6),
        Text('到期后提醒次数', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        LunioSegmentedControl(
          values: dueRepeatOptions.map((frequency) => frequency.label).toList(),
          selectedIndex: dueRepeatOptions.contains(dueRepeatFrequency)
              ? dueRepeatOptions.indexOf(dueRepeatFrequency)
              : 0,
          onSelected: saving
              ? (_) {}
              : (index) => setState(
                  () => dueRepeatFrequency = dueRepeatOptions[index],
                ),
        ),
        const SizedBox(height: 18),
        LunioFormActions(
          confirmLabel: '保存设置',
          onCancel: () => widget.handle.close(),
          onConfirm: _submit,
          saving: saving,
        ),
      ],
    );
  }

  /// 提交：构造设置后交表单运行时（saving/失败行内错误/成功关场+toast
  /// 都在 handle，ADR 0016）。
  Future<void> _submit() {
    return widget.handle.submit(
      () => widget.onSubmit(
        LunioNotificationSettings(
          systemNotificationsEnabled:
              widget.initialSettings.systemNotificationsEnabled,
          inAppNotificationsEnabled: inAppNotificationsEnabled,
          dueRepeatFrequency: dueRepeatFrequency,
        ),
      ),
    );
  }
}

/// 系统通知状态行（只读展示 + "系统设置"跳转原生设置页）。
class SystemNotificationStatusRow extends StatelessWidget {
  const SystemNotificationStatusRow({
    required this.enabled,
    required this.onOpenSettings,
  });

  final bool enabled;
  final Future<void> Function()? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: tokens.surface2,
          borderRadius: BorderRadius.circular(tokens.radiusMedium),
          border: Border.all(color: tokens.line),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('手机系统通知'),
                  const SizedBox(height: 4),
                  Text(
                    enabled ? '系统已开启' : '系统已关闭',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: tokens.muted),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: onOpenSettings == null
                  ? null
                  : () {
                      onOpenSettings!();
                    },
              child: const Text('系统设置'),
            ),
          ],
        ),
      ),
    );
  }
}
