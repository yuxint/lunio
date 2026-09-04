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

import 'dart:math' as math;

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
      child: Align(
        alignment: Alignment.center,
        // widthFactor=1：按文字内容宽度收缩。ItemPills 改用 Wrap 后，
        // 子项拿到的是"整行剩余空间"的松约束，Center 会把自身撑满，
        // 导致每个 pill 独占一行（回归 bug）。
        widthFactor: 1.0,
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

/// 表单/信息类 sheet 的统一骨架（全项目唯一，§5.3.2 收敛）：drag handle +
/// 标题/副标题 + 可滚动内容 + bottomInset（预留给键盘）。
/// 配合 showLunioModalSheet 使用（内部即透明底，调用方不再传表面参数）。
/// 底部会自动叠加系统安全区高度（全面屏圆角/Home 横条），把内容抬离
/// 屏幕底边；与键盘高度取较大值，避免键盘弹起时双重预留。
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
    // 弹层不走 SafeArea（贴底绘制），这里手动读取底部安全区：
    // 无圆角/无横条的老设备该值为 0，布局不受影响。
    final safeBottom = MediaQuery.of(context).padding.bottom;
    final content = Padding(
      padding: EdgeInsets.fromLTRB(
        18,
        12,
        18,
        18 + math.max(safeBottom, bottomInset),
      ),
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
      // 表面容器自带底色，ListTile/SwitchListTile 的调试断言要求其
      // Material 祖先在底色容器之内（否则报"背景/水波纹不可见"），
      // 因此内容包一层透明 Material 作为绘制底板。
      child: Material(
        type: MaterialType.transparency,
        child: SingleChildScrollView(child: content),
      ),
    );
    return sheet;
  }
}

/// 表单 sheet 底部的"取消 + 确认"动作行（§5.3.5 收敛：原 9 处手写
/// Row(Secondary+Primary) 样板统一到这里）。
///  - [saving] 为 true 时确认按钮置灰、文案切到 [confirmSavingLabel]；
///  - [enabled] 为 false 时确认按钮置灰（表单校验未通过等场景）；
///  - [onCancel] / [onConfirm] 传 null 表示对应按钮禁用（与
///    LunioSecondaryButton/LunioPrimaryButton 的可空回调语义一致）；
///  - 确认文案各表单不同（保存记录/开始计时/确定…），由 [confirmLabel]
///    传入；保存中通用文案默认"保存中"。
class LunioFormActions extends StatelessWidget {
  const LunioFormActions({
    required this.confirmLabel,
    required this.onCancel,
    required this.onConfirm,
    this.cancelLabel = '取消',
    this.confirmSavingLabel = '保存中',
    this.saving = false,
    this.enabled = true,
  });

  final String cancelLabel;
  final String confirmLabel;
  final String confirmSavingLabel;
  final VoidCallback? onCancel;
  final VoidCallback? onConfirm;
  final bool saving;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: LunioSecondaryButton(label: cancelLabel, onPressed: onCancel),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: LunioPrimaryButton(
            label: saving ? confirmSavingLabel : confirmLabel,
            onPressed: saving || !enabled ? null : onConfirm,
          ),
        ),
      ],
    );
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
      children: [LunioEmptyCard('加载失败：${friendlyError(error)}')],
    );
  }
}


/// 数字输入框：数字键盘 + "完成"收起键盘 + 小数位约束 + 标准外观的五件套。
/// 过去 6 个表单各手写一遍这五件（键盘类型/收键盘/格式约束/外观/禁用态），
/// 小数位正则还各处不同——现在只有这里一份。
class LunioNumberField extends StatelessWidget {
  const LunioNumberField({
    super.key,
    required this.controller,
    this.labelText,
    this.suffixText,
    this.decimals = 0,
    this.maxIntegerDigits,
    this.enabled = true,
    this.autofocus = false,
    this.alwaysFloatLabel = false,
    this.onTap,
    this.onChanged,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String? labelText;
  final String? suffixText;

  /// 允许的小数位：0 = 纯整数（digitsOnly，默认）；null = 不限位数
  /// （费用输入的历史行为）；n = 最多 n 位小数（可配合
  /// [maxIntegerDigits] 限整数部分位数，如油箱容积 3 位整数 4 位小数）。
  final int? decimals;

  /// 整数部分最大位数（null = 不限；仅在 decimals > 0 时生效）。
  final int? maxIntegerDigits;
  final bool enabled;
  final bool autofocus;

  /// 标签是否始终浮在框顶（油箱容积用：空值时标签不落回占位位置）。
  final bool alwaysFloatLabel;

  /// 点击输入框（记录/车辆表单的"点进来清 0"交互）。
  final VoidCallback? onTap;

  final ValueChanged<String>? onChanged;

  /// 键盘"完成"回调；null 时默认只收起键盘。
  final ValueChanged<String>? onSubmitted;

  /// 清掉纯 0 / 0.00 占位值（新增表单预填占位，点进来即清空方便直接输入）。
  static void clearLeadingZero(TextEditingController controller) {
    if (controller.text == '0' || controller.text == '0.00') {
      controller.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      autofocus: autofocus,
      keyboardType: TextInputType.numberWithOptions(
        decimal: decimals == null || decimals! > 0,
      ),
      textInputAction: TextInputAction.done,
      inputFormatters: [
        if (decimals != null && decimals == 0)
          FilteringTextInputFormatter.digitsOnly
        else if (decimals == null)
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
        else
          FilteringTextInputFormatter.allow(
            RegExp('^\\d{0,${maxIntegerDigits ?? ''}}\\.?\\d{0,$decimals}'),
          ),
      ],
      onTap: onTap,
      onChanged: onChanged,
      onSubmitted: (value) {
        // 各表单"完成"都不换行：默认收起键盘，回调可选追加。
        FocusScope.of(context).unfocus();
        onSubmitted?.call(value);
      },
      decoration: numberInputDecoration(
        labelText: labelText,
        suffixText: suffixText,
      ).copyWith(
        floatingLabelBehavior: alwaysFloatLabel
            ? FloatingLabelBehavior.always
            : null,
      ),
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
              // 数字输入统一用数字键盘（与油箱容积同款方式）。
              keyboardType: const TextInputType.numberWithOptions(),
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
