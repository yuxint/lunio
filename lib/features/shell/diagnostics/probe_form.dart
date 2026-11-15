// 检测点表单（新增/编辑自定义检测点，票 06）+ 表单 sheet 入口。
//
// 表单走既有表单 sheet 运行时（ADR 0016 showLunioFormSheetNoLoad：装载/
// 守卫/pop/toast/键盘 inset 统一出口，不手写弹窗三明治）；决策体收
// plain-Dart 控制器 ProbeFormController（probe_form_controller.dart，
// FuelRecordFormController 先例）——本文件只做组装与渲染、转发事件。
//
// 删除入口在管理 sheet 的卡片上（照保养项目交互，ADR 0021 修订节），
// 本表单只负责新增/编辑保存；确认框与删除动作在 probe_management_sheet。
//
// ≈ Java 的表单 JSP + BackingBean 装配：widget 只画字段与转发，业务
// 决策在控制器、生命周期在表单运行时、写库在动作层，各在其位。
// ignore_for_file: use_key_in_widget_constructors, library_private_types_in_public_api

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/lunio_tokens.dart';
import '../../../core/widgets/lunio_components.dart';
import '../../../domain/entities/diagnostics_parse_type.dart';
import '../../../domain/entities/diagnostics_probe.dart';
import '../shared/shell_shared.dart';
import 'probe_form_controller.dart';
import 'probe_templates.dart';

/// 检测点表单（新增/编辑共用）：名称 + 指令原文 + 刷新间隔 + 解析类型。
/// 校验失败行内错误文案（不弹窗）；删除在管理 sheet 的卡片上。
/// 本 widget 只渲染字段、构造控制器并转发事件；字段态/校验/归一/载荷
/// 构造全在控制器。
class ProbeForm extends StatefulWidget implements FormSheetHandleWidget {
  const ProbeForm({
    required this.carId,
    required this.handle,
    required this.onSubmit,
    this.probe,
  });

  /// 归属车辆（每车一套，ADR 0021 修订节）。
  final int carId;

  /// 编辑态的既有检测点（null = 新增）。
  final DiagnosticsProbe? probe;

  /// 表单运行时把手（ADR 0016）：saving/行内错误/提交/关闭都经它。
  @override
  final FormSheetHandle<void> handle;

  /// 保存回调（构造实体后调用，实现在入口函数里接动作层）。
  final Future<void> Function(DiagnosticsProbe probe) onSubmit;

  @override
  State<ProbeForm> createState() => ProbeFormState();
}

class ProbeFormState extends State<ProbeForm>
    with FormSheetHandleHost<ProbeForm> {
  /// 表单决策体（probe_form_controller.dart）：字段态、校验阶梯、指令
  /// 归一、载荷构造都在里面，本 State 只持有生命周期并转发事件。
  late final ProbeFormController form;

  bool get isEditing => widget.probe != null;

  @override
  void initState() {
    super.initState();
    form = ProbeFormController(
      carId: widget.carId,
      probe: widget.probe,
      reportError: _reportError,
    );
  }

  /// 行内错误接线（构造注入点）：mounted 守卫防卸载后写把手。
  void _reportError(String? text) {
    if (mounted) {
      setFormError(text);
    }
  }

  @override
  void dispose() {
    form.dispose();
    super.dispose();
  }

  /// 切解析类型：控制器纯赋值，这里只负责重建。
  void _setParseType(DiagnosticsParseType value) {
    setState(() => form.setParseType(value));
  }

  void _applyTemplate(DiagnosticsProbeTemplate template) {
    setState(() {
      form.applyTemplate(
        name: template.name,
        command: template.command,
        parseType: template.parseType,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('推荐模板（可选）', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final template in diagnosticsProbeTemplates)
              ActionChip(
                label: Text(template.name),
                onPressed: saving ? null : () => _applyTemplate(template),
              ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: form.nameController,
          enabled: !saving,
          decoration: const InputDecoration(labelText: '检测点名称'),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: form.commandController,
          enabled: !saving,
          decoration: const InputDecoration(
            labelText: '指令原文',
            helperText: '如 012F、ATRV，仅字母与数字',
          ),
        ),
        const SizedBox(height: 10),
        // 数字输入统一走 LunioNumberField（整数模式自带 digitsOnly 与
        // "完成"收键盘）；范围 5–3600 由控制器提交时校验并报行内错误。
        LunioNumberField(
          controller: form.refreshIntervalController,
          enabled: !saving,
          decimals: 0,
          labelText: '刷新间隔',
          suffixText: '秒',
        ),
        const SizedBox(height: 10),
        Text('解析类型', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in DiagnosticsParseType.values) ...[
              _ParseTypeChip(
                parseType: option,
                selected: option == form.parseType,
                enabled: !saving,
                onTap: () => _setParseType(option),
              ),
            ],
          ],
        ),
        if (errorText != null) ...[
          const SizedBox(height: 10),
          LunioInlineMessage(message: errorText!, tone: LunioStatusTone.danger),
        ],
        const SizedBox(height: 16),
        LunioFormActions(
          confirmLabel: isEditing ? '保存修改' : '保存',
          onCancel: () => widget.handle.close(),
          onConfirm: _submit,
          saving: saving,
        ),
      ],
    );
  }

  /// 提交：控制器校验并构造载荷（失败已报行内错误、留场），非 null 交给
  /// 表单运行时的提交生命周期（ADR 0016）→ 动作层写库（ADR 0007）。
  Future<void> _submit() async {
    final probe = form.submitPayload();
    if (probe == null) {
      return;
    }
    await widget.handle.submit(() => widget.onSubmit(probe));
  }
}

/// 解析类型胶囊（表单内单选，Wrap 布局防长标签溢出——四个枚举文案里
/// "温度（A−40）"较长，一行 Expanded 会溢出，换行更稳）。选中主色底、
/// 未选中描边，与油品胶囊同视觉语言。
class _ParseTypeChip extends StatelessWidget {
  const _ParseTypeChip({
    required this.parseType,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final DiagnosticsParseType parseType;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(tokens.radiusMedium),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? tokens.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(tokens.radiusMedium),
          border: Border.all(
            color: selected ? tokens.primary : tokens.line,
          ),
        ),
        child: Text(
          parseType.label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: selected
                ? Theme.of(context).colorScheme.onPrimary
                : tokens.ink,
          ),
        ),
      ),
    );
  }
}

/// ★ 检测点表单 sheet 入口（管理 sheet 的新增/编辑按钮）：新增与编辑
/// 共用。装载/守卫/pop/toast 时序归 showLunioFormSheetNoLoad（ADR 0016）；
/// 提交经动作层 saveDiagnosticsProbe（ADR 0007）。删除在管理卡片上。
/// 副标题注明"仅用于读取类指令"（spec 安全边界拍板：不做指令白名单）。
Future<void> showProbeFormSheet(
  BuildContext context,
  WidgetRef ref, {
  required int carId,
  DiagnosticsProbe? probe,
}) {
  return showLunioFormSheetNoLoad<void>(
    context: context,
    title: probe == null ? '新增检测点' : '编辑检测点',
    subtitle: '仅用于读取类指令（如标准 PID 查询）',
    builder: (sheetContext, handle) {
      return ProbeForm(
        carId: carId,
        probe: probe,
        handle: handle,
        onSubmit: (value) => saveDiagnosticsProbe(ref, value),
      );
    },
    successMessage: '检测点已保存',
  );
}
