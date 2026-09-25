// 我的页"手动日期"设置 sheet（开发者模式专属）：开关 + 日期选择，
// 可选范围 1990 ~ 今天+10 年。从 settings_data.dart 拆出（2026-09-25
// 备份管线收编动作层时顺手解 trench coat，vehicles.dart 拆分先例）。
//
// 装载/守卫/pop/toast 时序归 showLunioFormSheet（ADR 0016）；写库经
// 动作层 saveManualDate（ADR 0007），invalidate 后 effectiveTodayProvider
// 重算，提醒进度全部按新"今天"计算。
// ignore_for_file: use_key_in_widget_constructors, library_private_types_in_public_api

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/date/local_date.dart';
import '../../../core/widgets/lunio_components.dart';
import '../shared/shell_shared.dart';

/// 手动日期 sheet 入口：关闭/清空 → 写 manualDateEnabled=false +
/// manualDate=null；开启 → 写两个偏好。
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
  showLunioFormSheet<void>(
    context: context,
    title: '手动日期',
    subtitle: '开启后，保养提醒里的“今天”会使用该日期。',
    builder: (sheetContext, handle) {
      return ManualDateForm(
        initialDate: initialDate,
        fallbackDate: fallbackDate,
        handle: handle,
        // 写库+失效收进动作层（ADR 0007）；关 sheet 与成功 toast 归
        // 表单运行时（ADR 0016）。
        onSubmit: (date) => saveManualDate(ref, date),
      );
    },
    successMessage: '手动日期已保存',
  );
}

/// 手动日期表单（开关 + 日期选择，可选范围 1990 ~ 今天+10 年）。
class ManualDateForm extends StatefulWidget {
  const ManualDateForm({
    required this.initialDate,
    required this.fallbackDate,
    required this.handle,
    required this.onSubmit,
  });

  final LocalDate? initialDate;
  final LocalDate fallbackDate;

  /// 表单运行时把手（ADR 0016）：saving/行内错误/提交/关闭都经它。
  final FormSheetHandle<void> handle;
  final Future<void> Function(LocalDate? date) onSubmit;

  @override
  State<ManualDateForm> createState() => ManualDateFormState();
}

class ManualDateFormState extends State<ManualDateForm> {
  // ---- 提交运行时（ADR 0016）：saving/行内错误/提交/关闭统一在把手
  // 上。以下转发让既有调用点零改动。
  bool get saving => widget.handle.saving;
  String? get errorText => widget.handle.errorText;

  late LocalDate selectedDate;
  late bool enabled;

  @override
  void initState() {
    super.initState();
    enabled = widget.initialDate != null;
    selectedDate = widget.initialDate ?? widget.fallbackDate;
  }

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
          onCancel: () => widget.handle.close(),
          onConfirm: _submit,
          saving: saving,
        ),
      ],
    );
  }

  /// 提交：开关关 = null（清除），开 = 所选日期；生命周期归表单运行时。
  Future<void> _submit() {
    final date = enabled ? selectedDate : null;
    return widget.handle.submit(() => widget.onSubmit(date));
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
