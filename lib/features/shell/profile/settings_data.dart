// 我的页"数据与工具"区：备份导出/导入、清空数据、通知设置 sheet、
// 手动日期 sheet，以及设置行/主题行/版本 footer 等静态组件。
//
// ⚠ 跨层依赖：本文件直接 import data 层的 BackupCodec 做 JSON 编解码
// （绕过 Repository/Service，审查报告 §3）。
// ignore_for_file: use_key_in_widget_constructors, library_private_types_in_public_api

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/date/local_date.dart';
import '../../../core/platform/native_files.dart';
import '../../../core/platform/native_notification_settings.dart';
import '../../../core/theme/lunio_tokens.dart';
import '../../../core/widgets/lunio_components.dart';
import '../../../data/backup/backup_codec.dart';
import '../../../domain/entities/notification_settings.dart';
import '../reminders/notification_coordinator.dart';
import '../shared/shell_shared.dart';

/// 通知设置行的副标题（参数未用，固定文案，R30）。
String notificationSettingsSubtitle(LunioNotificationSettings settings) {
  return '手机系统通知、应用内通知';
}

/// 版本 footer（连点 5 次触发开发者模式切换；开启后文案带"开发者模式"）。
class VersionFooter extends StatelessWidget {
  const VersionFooter({
    required this.developerModeEnabled,
    required this.onTap,
  });

  final bool developerModeEnabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    return Center(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            developerModeEnabled ? '版本 1.0.0 · 开发者模式' : '版本 1.0.0',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: tokens.muted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

/// 通用设置行（标题+副标题+右侧动作按钮，整行不可点只有按钮可点）。
class ProfileSettingRow extends StatelessWidget {
  const ProfileSettingRow({
    required this.title,
    required this.subtitle,
    required this.trailingLabel,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String trailingLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: tokens.surface,
          borderRadius: BorderRadius.circular(tokens.radiusLarge),
          border: Border.all(color: tokens.line),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 5),
                  Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            const SizedBox(width: 12),
            TextButton(
              onPressed: onTap,
              style: TextButton.styleFrom(
                backgroundColor: tokens.surface2,
                foregroundColor: tokens.primary,
                minimumSize: const Size(0, 34),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(tokens.radiusSmall),
                  side: BorderSide(color: tokens.line),
                ),
              ),
              child: Text(trailingLabel),
            ),
          ],
        ),
      ),
    );
  }
}

/// 主题模式三段选择（跟随系统/浅色/深色）→ onChanged → 写偏好 →
/// themeModePreferenceProvider 刷新 → MaterialApp.themeMode 生效。
class ThemeModeSettingRow extends StatelessWidget {
  const ThemeModeSettingRow({required this.mode, required this.onChanged});

  final ThemeMode mode;
  final ValueChanged<ThemeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(tokens.radiusLarge),
        border: Border.all(color: tokens.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('主题模式', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          LunioSegmentedControl(
            values: const ['跟随系统', '浅色', '深色'],
            selectedIndex: switch (mode) {
              ThemeMode.light => 1,
              ThemeMode.dark => 2,
              ThemeMode.system => 0,
            },
            onSelected: (index) {
              final nextMode = switch (index) {
                1 => ThemeMode.light,
                2 => ThemeMode.dark,
                _ => ThemeMode.system,
              };
              if (nextMode == mode) {
                return;
              }
              onChanged(nextMode);
            },
          ),
        ],
      ),
    );
  }
}

/// ★ 备份导出：Repository 全量读表 → BackupCodec 编码 JSON →
/// 原生文件桥弹系统保存框（文件名 lunio-backup-yyyyMMdd-HHmmss.json）→
/// toast 反馈。失败 toast 带原始错误（含异常栈字符串）。
Future<void> exportBackup(BuildContext context, WidgetRef ref) async {
  try {
    final payload = await ref
        .read(lunioRepositoryProvider)
        .exportBackupPayload();
    const codec = BackupCodec();
    final json = codec.encode(payload);
    final saved = await NativeFiles.exportJsonFile(
      filename: _backupFilename(DateTime.now()),
      content: json,
    );
    if (saved && context.mounted) {
      showStatusOverlay(context, '备份完成', StatusOverlayTone.success);
    }
  } catch (error) {
    if (context.mounted) {
      showStatusOverlay(context, '备份失败：$error', StatusOverlayTone.error);
    }
  }
}

/// ★ 恢复备份：确认框（明示"先清空业务数据、偏好保留"）→
/// 原生文件桥选文件 → 解码（版本不符抛 UnsupportedError）→
/// 协调器 runBackupRestore：升代数作废在途同步任务（R8）→ restore
/// 事务恢复（偏好保留，抑制键清除）→ 取消 8000/8900 系旧数据残留通知
/// （空备份时同步引擎不会重排，显式取消；停车 9001/9002 不动——倒计时
/// 偏好保留且仍有效）→ invalidateAllAppDataProviders 全量刷新。
/// 失败分支：唯一约束冲突 → 弹"未写入任何数据"对话框（事务已回滚）；
/// 其他错误 → toast。
Future<void> restoreBackupFromFile(BuildContext context, WidgetRef ref) async {
  final confirmed = await showConfirmDialog(
    context: context,
    title: '恢复数据',
    message:
        '恢复会先清空本地车辆、保养项目、保养记录，再写入备份文件中的数据。'
        '主题、通知等偏好设置会保留。该操作不可撤销。',
    confirmLabel: '恢复',
  );
  if (confirmed != true) {
    return;
  }
  try {
    final json = await NativeFiles.pickJsonFile();
    if (json == null) {
      return;
    }
    const codec = BackupCodec();
    final payload = codec.decode(json);
    await ref
        .read(notificationCoordinatorProvider)
        .runBackupRestore(
          () => ref
              .read(lunioRepositoryProvider)
              .restoreBackupPayload(payload),
        );
    invalidateAllAppDataProviders(ref);
    if (context.mounted) {
      showStatusOverlay(context, '恢复完成', StatusOverlayTone.success);
    }
  } catch (error) {
    if (context.mounted) {
      if (isUniqueConstraintError(error)) {
        await showMessageDialog(
          context: context,
          title: '恢复失败',
          message: '恢复文件中的部分数据重复或冲突，本次恢复未写入任何数据。',
          tone: StatusOverlayTone.error,
        );
      } else {
        showStatusOverlay(context, '恢复失败：$error', StatusOverlayTone.error);
      }
    }
  }
}

/// 备份文件名：lunio-backup-20260825-143025.json。
String _backupFilename(DateTime dateTime) {
  String twoDigits(int value) => value.toString().padLeft(2, '0');
  return 'lunio-backup-'
      '${dateTime.year}'
      '${twoDigits(dateTime.month)}'
      '${twoDigits(dateTime.day)}-'
      '${twoDigits(dateTime.hour)}'
      '${twoDigits(dateTime.minute)}'
      '${twoDigits(dateTime.second)}.json';
}

/// ★ 清空数据：确认框（明示目录表保留）→ 协调器 runAllDataClear：
/// 升代数（作废在途通知任务，R8）→ clearAllData 事务删 5 张表（业务
/// 4 张 + 偏好）→ 取消停车 9001/9002 与保养/里程 8000/8900 系系统通知
/// （偏好已删，倒计时偏好和通知开关都不复存在，残留通知必须显式取消）
/// → invalidate 全量刷新（bootstrap provider 失效后车型目录会自动重灌）
/// → 成功 overlay。
Future<void> clearAllData(BuildContext context, WidgetRef ref) async {
  final confirmed = await showConfirmDialog(
    context: context,
    title: '清空数据',
    message:
        '确定清空本地车辆、保养项目、保养记录和偏好设置？'
        '默认车辆模型与默认保养项目目录会保留。该操作不可撤销。',
    confirmLabel: '清空',
  );
  if (confirmed != true) {
    return;
  }
  try {
    await ref
        .read(notificationCoordinatorProvider)
        .runAllDataClear(
          () => ref.read(lunioRepositoryProvider).clearAllData(),
        );
    invalidateAllAppDataProviders(ref);
    if (context.mounted) {
      showStatusOverlay(context, '已清空数据', StatusOverlayTone.success);
    }
  } catch (error) {
    if (context.mounted) {
      showStatusOverlay(context, '清空失败：$error', StatusOverlayTone.error);
    }
  }
}

/// ★ 通知设置 sheet 入口：先 await 偏好 provider 拿到真实设置
/// （加载失败 toast 返回，杜绝 loading 期默认值覆盖真实设置，R6）→
/// 协调器向系统查询真实开关回写偏好 →
/// 弹表单（系统状态行 + 应用内通知开关 + 重复频率三段）。
Future<void> showNotificationSettingsSheet(
  BuildContext context,
  WidgetRef ref,
) async {
  final LunioNotificationSettings loadedSettings;
  try {
    loadedSettings = await ref.read(notificationSettingsProvider.future);
  } catch (error) {
    if (context.mounted) {
      showStatusOverlay(context, '设置加载失败', StatusOverlayTone.error);
    }
    return;
  }
  var initialSettings = loadedSettings;
  final systemNotificationsEnabled = await ref
      .read(notificationCoordinatorProvider)
      .reconcileSystemEnabled();
  if (!context.mounted) {
    return;
  }
  initialSettings = initialSettings.copyWith(
    systemNotificationsEnabled: systemNotificationsEnabled,
  );
  showLunioModalSheet<void>(
    context: context,
    builder: (sheetContext) {
      return PrototypeSheetFrame(
        title: '通知提醒',
        bottomInset: MediaQuery.of(sheetContext).viewInsets.bottom,
        child: NotificationSettingsForm(
          initialSettings: initialSettings,
          onOpenSystemSettings: () async {
            final opened =
                await NativeNotificationSettings.openNotificationSettings();
            if (sheetContext.mounted) {
              Navigator.of(sheetContext).pop();
            }
            if (!opened && context.mounted) {
              showStatusOverlay(
                context,
                '无法打开系统设置，请在系统设置中搜索 Lunio',
                StatusOverlayTone.info,
              );
            }
          },
          onSubmit: (settings) async {
            final coordinator = ref.read(notificationCoordinatorProvider);
            final systemNotificationsEnabled = await coordinator
                .reconcileSystemEnabled();
            // 保存内部批量写 3 个偏好 key 并失效偏好缓存。
            await coordinator.saveNotificationSettings(
              settings.copyWith(
                systemNotificationsEnabled: systemNotificationsEnabled,
              ),
            );
            if (sheetContext.mounted) {
              Navigator.of(sheetContext).pop();
            }
            if (context.mounted) {
              showStatusOverlay(
                context,
                '设置已保存',
                StatusOverlayTone.success,
              );
            }
          },
        ),
      );
    },
  );
}

/// 通知表单：状态行 + 应用内通知开关 + 到期重复频率三段（每周/每 2 周/
/// 每月）。提交构造 LunioNotificationSettings。
class NotificationSettingsForm extends StatefulWidget {
  const NotificationSettingsForm({
    required this.initialSettings,
    required this.onOpenSystemSettings,
    required this.onSubmit,
  });

  final LunioNotificationSettings initialSettings;
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
  bool saving = false;

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
          onCancel: () => Navigator.of(context).pop(),
          onConfirm: _submit,
          saving: saving,
        ),
      ],
    );
  }

  /// 提交：saving 态防重复点击 → onSubmit（外层保存偏好+关 sheet）。
  Future<void> _submit() async {
    setState(() => saving = true);
    try {
      await widget.onSubmit(
        LunioNotificationSettings(
          systemNotificationsEnabled:
              widget.initialSettings.systemNotificationsEnabled,
          inAppNotificationsEnabled: inAppNotificationsEnabled,
          dueRepeatFrequency: dueRepeatFrequency,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => saving = false);
      }
    }
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

/// ★ 手动日期 sheet（开发者模式专属）：开关 + 日期选择。
/// 关闭/清空 → 写 manualDateEnabled=false + manualDate=null；
/// 开启 → 写两个偏好；invalidate 后 effectiveTodayProvider 重算，
/// 提醒进度全部按新"今天"计算。
void showManualDateSheet(BuildContext context, WidgetRef ref) {
  final initialDate = ref
      .read(manualDatePreferenceProvider)
      .maybeWhen(data: (value) => value, orElse: () => null);
  final fallbackDate = ref
      .read(effectiveTodayProvider)
      .maybeWhen(
        data: (value) => value,
        orElse: () => LocalDate.fromDateTime(DateTime.now()),
      );
  showLunioModalSheet<void>(
    context: context,
    builder: (sheetContext) {
      return PrototypeSheetFrame(
        title: '手动日期',
        subtitle: '开启后，保养提醒里的“今天”会使用该日期。',
        bottomInset: MediaQuery.of(sheetContext).viewInsets.bottom,
        child: ManualDateForm(
          initialDate: initialDate,
          fallbackDate: fallbackDate,
          onSubmit: (date) async {
            final repository = ref.read(lunioRepositoryProvider);
            if (date == null) {
              await repository.setPreferenceValue('manualDateEnabled', 'false');
              await repository.setPreferenceValue('manualDate', null);
            } else {
              await repository.setPreferenceValue('manualDateEnabled', 'true');
              await repository.setPreferenceValue(
                'manualDate',
                date.toString(),
              );
            }
            invalidatePreferenceProviders(ref);
            if (sheetContext.mounted) {
              Navigator.of(sheetContext).pop();
            }
            if (context.mounted) {
              showStatusOverlay(
                context,
                '手动日期已保存',
                StatusOverlayTone.success,
              );
            }
          },
        ),
      );
    },
  );
}

/// 手动日期表单（开关 + 日期选择，可选范围 1990 ~ 今天+10 年）。
class ManualDateForm extends StatefulWidget {
  const ManualDateForm({
    required this.initialDate,
    required this.fallbackDate,
    required this.onSubmit,
  });

  final LocalDate? initialDate;
  final LocalDate fallbackDate;
  final Future<void> Function(LocalDate? date) onSubmit;

  @override
  State<ManualDateForm> createState() => ManualDateFormState();
}

class ManualDateFormState extends State<ManualDateForm> {
  late LocalDate selectedDate;
  late bool enabled;
  bool saving = false;
  String? errorText;

  @override
  void initState() {
    super.initState();
    enabled = widget.initialDate != null;
    selectedDate = widget.initialDate ?? widget.fallbackDate;
  }

  @override
  void dispose() => super.dispose();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('启用手动日期'),
          value: enabled,
          onChanged: saving ? null : (value) => setState(() => enabled = value),
        ),
        if (enabled) ...[
          const SizedBox(height: 12),
          LunioPickerTile(
            label: '日期',
            value: formatDateForUser(selectedDate),
            enabled: !saving,
            onTap: _pickDate,
          ),
        ],
        if (errorText != null) ...[
          const SizedBox(height: 10),
          LunioInlineMessage(message: errorText!, tone: LunioStatusTone.danger),
        ],
        const SizedBox(height: 18),
        LunioFormActions(
          confirmLabel: '保存日期',
          onCancel: () => Navigator.of(context).pop(),
          onConfirm: _submit,
          saving: saving,
        ),
      ],
    );
  }

  /// 提交：开关关 = null（清除），开 = 所选日期。
  Future<void> _submit() async {
    final date = enabled ? selectedDate : null;
    setState(() {
      saving = true;
      errorText = null;
    });
    try {
      await widget.onSubmit(date);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        saving = false;
        errorText = friendlyError(error);
      });
    }
  }

  Future<void> _pickDate() async {
    final picked = await showSimpleDatePicker(
      context,
      initialDate: selectedDate,
      firstDate: const LocalDate(1990, 1, 1),
      lastDate: LocalDate.fromDateTime(
        DateTime.now().add(const Duration(days: 3650)),
      ),
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() => selectedDate = picked);
  }
}
