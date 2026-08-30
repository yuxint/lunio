// shell 内部共享 UI 组件（带一定业务形态的小组件，比 core/widgets 更上层）。
//
// 复用度统计（引用次数，含定义处）：
//  - SmallActionButton 18 处 / PrototypeSheetFrame 11 处 —— 高复用，核心组件
//  - LoadingPage / ErrorPage —— 三页统一 loading/error 占位（§5.2）
//  - IntervalNumberInputRow —— 记录表单与项目表单共用的间隔输入行（§5.3.1）
//  - FilterBar / ChoiceChipButton 已回收为记录页私有组件（单一调用点）
//
// PrototypeSheetFrame：自绘 sheet 骨架（drag handle + 标题 + 滚动内容），
// 与 modal_feedback 的 _LunioDefaultSheetSurface 是两套并存实现。
// ignore_for_file: use_key_in_widget_constructors, library_private_types_in_public_api

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/lunio_tokens.dart';
import '../../../core/widgets/lunio_components.dart';
import 'formatters.dart';


/// 项目名 pill 组：Wrap 自动换行（每行尽量塞满），用于记录卡/项目卡的
/// 项目标签展示。原先的手写装箱算法（TextPainter 量宽 + 贪心塞行）
/// 与 Wrap 等价且存在 painter 未 dispose 的泄漏隐患，已删除（R22）。
class ItemPills extends StatelessWidget {
  const ItemPills({required this.labels});

  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    final textStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: tokens.ink,
      fontWeight: FontWeight.w700,
    );
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final label in labels) ItemPill(label: label, style: textStyle),
      ],
    );
  }
}

/// 单个项目名 pill（小圆角胶囊）。
class ItemPill extends StatelessWidget {
  const ItemPill({required this.label, required this.style});

  final String label;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    return Container(
      constraints: const BoxConstraints(minHeight: 28),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: tokens.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: tokens.line.withValues(alpha: 0.72)),
      ),
      child: Center(
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: style,
        ),
      ),
    );
  }
}

/// 小尺寸动作按钮（全项目最高频复用组件）：
/// danger/primary/secondary/muted 四种语义色 + 可选 tooltip；
/// onPressed 为 null 时自动置灰。
class SmallActionButton extends StatelessWidget {
  const SmallActionButton({
    required this.label,
    required this.onPressed,
    this.danger = false,
    this.primary = false,
    this.secondary = false,
    this.muted = false,
    this.tooltip,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool danger;
  final bool primary;
  final bool secondary;
  final bool muted;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    final backgroundColor = danger
        ? tokens.dangerSoft
        : primary
        ? tokens.primarySoft
        : secondary
        ? tokens.secondarySoft
        : muted
        ? tokens.surface3
        : tokens.surface2;
    final foregroundColor = onPressed == null
        ? tokens.subtle
        : danger
        ? tokens.danger
        : primary
        ? tokens.primary
        : secondary
        ? tokens.secondary
        : muted
        ? tokens.muted
        : tokens.ink;
    return SizedBox(
      height: 34,
      child: Tooltip(
        message: tooltip ?? label,
        child: TextButton(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            backgroundColor: backgroundColor,
            foregroundColor: foregroundColor,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(11),
            ),
          ),
          child: Text(label),
        ),
      ),
    );
  }
}

/// 表单类 sheet 的统一骨架：drag handle + 标题/副标题 + 可滚动内容 +
/// bottomInset（预留给键盘）。配合 showLunioModalSheet(transparent) 使用。
class PrototypeSheetFrame extends StatelessWidget {
  const PrototypeSheetFrame({
    required this.title,
    required this.child,
    this.subtitle,
    this.bottomInset = 0,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    final content = Padding(
      padding: EdgeInsets.fromLTRB(18, 12, 18, 18 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 48,
              height: 5,
              decoration: BoxDecoration(
                color: tokens.line,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleLarge),
                    if (subtitle != null) ...[
                      const SizedBox(height: 5),
                      Text(
                        subtitle!,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
    final sheet = Container(
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        boxShadow: [
          BoxShadow(
            color: tokens.ink.withValues(alpha: 0.18),
            blurRadius: 54,
            offset: const Offset(0, -20),
          ),
        ],
      ),
      child: SingleChildScrollView(child: content),
    );
    return sheet;
  }
}


/// 页面级加载占位（提醒/记录/我的三页统一使用，§5.2）。
class LoadingPage extends StatelessWidget {
  const LoadingPage({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return LunioPage(
      title: title,
      children: const [Center(child: CircularProgressIndicator())],
    );
  }
}

/// 页面级错误占位（提醒/记录/我的三页统一使用，§5.2）。
class ErrorPage extends StatelessWidget {
  const ErrorPage({required this.title, required this.error});

  final String title;
  final Object error;

  @override
  Widget build(BuildContext context) {
    return LunioPage(
      title: title,
      children: [LunioCard(child: Text('加载失败：${friendlyError(error)}'))],
    );
  }
}

/// 数字间隔输入行：标题 + 116px 数字输入框（单位后缀）+ 可选右侧开关。
/// §5.3.1 合并原两套近似实现：
///  - 记录表单第二步（无开关）：只传 title/controller/unit/enabled；
///  - 项目表单（带"按里程/按时间"开关）：再传 switchValue/onSwitchChanged。
/// switchValue / onSwitchChanged 均为 null 时不渲染开关；有开关时输入框
/// 可用性 = 开关值 && 回调可用 && enabled（saving 期调用方传 null 回调：
/// 开关保持渲染但置禁用态，输入框整体禁用，布局不跳变）。
class IntervalNumberInputRow extends StatelessWidget {
  const IntervalNumberInputRow({
    required this.title,
    required this.controller,
    required this.unit,
    this.enabled = true,
    this.switchValue,
    this.onSwitchChanged,
  });

  final String title;
  final TextEditingController controller;
  final String unit;

  /// 无开关版的输入框可用性。
  final bool enabled;

  /// 开关当前值（onSwitchChanged 非 null 时使用）。
  final bool? switchValue;
  final ValueChanged<bool>? onSwitchChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    // hasSwitch 以 switchValue 为准：saving 期调用方回调传 null 但开关值
    // 仍在，开关要继续渲染（置禁用态）而不是从布局中消失。
    final hasSwitch = switchValue != null || onSwitchChanged != null;
    final inputEnabled = hasSwitch
        ? (switchValue ?? false) && onSwitchChanged != null && enabled
        : enabled;
    return Container(
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: tokens.surface2,
        borderRadius: BorderRadius.circular(tokens.radiusMedium),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: inputEnabled ? tokens.ink : tokens.subtle,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 116,
            child: TextField(
              controller: controller,
              enabled: inputEnabled,
              keyboardType: TextInputType.text,
              textInputAction: TextInputAction.done,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onSubmitted: (_) => FocusScope.of(context).unfocus(),
              textAlign: TextAlign.center,
              decoration: numberInputDecoration(suffixText: unit).copyWith(
                fillColor: inputEnabled
                    ? tokens.surface
                    : tokens.surface3.withValues(alpha: 0.55),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                constraints: const BoxConstraints(minHeight: 46),
              ),
            ),
          ),
          if (hasSwitch) ...[
            const SizedBox(width: 8),
            Switch(value: switchValue ?? false, onChanged: onSwitchChanged),
          ],
        ],
      ),
    );
  }
}
