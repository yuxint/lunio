// 全局基础 UI 组件库（跨 feature 通用，≈ 项目自己的组件规范）。
//
// 与 features/shell/shared/ 的区别：这里的组件不依赖任何业务数据，
// 纯展示/布局原语，任何页面都可以用。包括：
//  - LunioPage / LunioTopBar：页面骨架（标题栏 + 滚动内容）
//  - LunioCard / LunioSection / LunioSheetScaffold：卡片、分组、sheet 头
//  - LunioInlineMessage / LunioStatusBadge / LunioStatusTone：三态提示
//  - LunioPickerTile：可点击的"日期选择"样式输入行
//  - LunioHeroCard：提醒页顶部大渐变卡片（车辆信息）
//  - LunioSegmentedControl：分段选择器（自定义实现，非 Material 的）
//  - LunioPrimaryButton / Secondary / IconButton：三套按钮
//
// 组件一律 StatelessWidget（无状态，数据从构造参数进），颜色全部从
// Theme 的 LunioTokens 取，保证浅深色主题自动适配。
import 'package:flutter/material.dart';

import '../theme/lunio_tokens.dart';

/// 标准页面骨架：ListView + 标题栏 + 子内容。
/// bottomPadding 预留底部导航栏高度，避免内容被遮住。
class LunioPage extends StatelessWidget {
  const LunioPage({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.bottomPadding = 102,
    required this.children,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final double bottomPadding;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.fromLTRB(18, 2, 18, bottomPadding),
      children: [
        LunioTopBar(title: title, subtitle: subtitle, trailing: trailing),
        const SizedBox(height: 12),
        ...children,
      ],
    );
  }
}

/// 页面顶部标题栏（大标题 + 可选副标题 + 右侧动作区）。
class LunioTopBar extends StatelessWidget {
  const LunioTopBar({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.headlineLarge),
              if (subtitle != null) ...[
                const SizedBox(height: 6),
                Text(subtitle!, style: theme.textTheme.bodySmall),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 12), trailing!],
      ],
    );
  }
}

/// 通用卡片容器：token 圆角 + 细边框 + 柔和投影。
class LunioCard extends StatelessWidget {
  const LunioCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(12),
    this.backgroundColor,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor ?? tokens.surface,
        borderRadius: BorderRadius.circular(tokens.radiusLarge),
        border: Border.all(color: tokens.line.withValues(alpha: 0.86)),
        boxShadow: [
          BoxShadow(
            color: tokens.ink.withValues(alpha: 0.08),
            blurRadius: 26,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// 底部 sheet 内容骨架：标题 + 副标题 + 可滚动内容
/// （注意与 shared/modal_feedback.dart 的 _LunioDefaultSheetSurface、
/// shared_widgets.dart 的 PrototypeSheetFrame 是三套并存的 sheet 骨架）。
class LunioSheetScaffold extends StatelessWidget {
  const LunioSheetScaffold({
    super.key,
    required this.title,
    this.subtitle,
    required this.child,
  });

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleLarge),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(subtitle!, style: theme.textTheme.bodySmall),
          ],
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

/// 内容分组：小节标题（+ 可选右侧动作）+ 子项列表。
class LunioSection extends StatelessWidget {
  const LunioSection({
    super.key,
    required this.title,
    required this.children,
    this.trailing,
  });

  final String title;
  final Widget? trailing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            ?trailing,
          ],
        ),
        const SizedBox(height: 8),
        ...children,
      ],
    );
  }
}

/// 行内提示条（表单错误/警告），带图标 + 语义色底。
class LunioInlineMessage extends StatelessWidget {
  const LunioInlineMessage({
    super.key,
    required this.message,
    this.tone = LunioStatusTone.warning,
  });

  final String message;
  final LunioStatusTone tone;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    final (background, foreground) = tone.statusColors(tokens);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(tokens.radiusMedium),
      ),
      child: Row(
        children: [
          Icon(tone.statusIcon, size: 18, color: foreground),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: foreground,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "点击弹出选择器"样式的只读输入行（日期选择等用）。
class LunioPickerTile extends StatelessWidget {
  const LunioPickerTile({
    super.key,
    required this.label,
    required this.value,
    required this.onTap,
    this.enabled = true,
  });

  final String label;
  final String value;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(tokens.radiusMedium),
      child: InputDecorator(
        decoration: InputDecoration(labelText: label, enabled: enabled),
        child: Row(
          children: [
            Expanded(
              child: Text(
                value,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: enabled ? tokens.ink : tokens.subtle,
                  height: 1.2,
                ),
              ),
            ),
            Icon(Icons.chevron_right, color: tokens.subtle),
          ],
        ),
      ),
    );
  }
}

/// 大渐变英雄卡：提醒页顶部的当前车辆卡片
/// （主色渐变底 + 装饰圆环 + 指标格子）。
class LunioHeroCard extends StatelessWidget {
  const LunioHeroCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.metrics,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String subtitle;
  final List<LunioMetric> metrics;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            tokens.primary,
            tokens.primaryStrong,
            Color.lerp(tokens.primaryStrong, tokens.ink, 0.32)!,
          ],
        ),
        borderRadius: BorderRadius.circular(tokens.radiusXl),
        boxShadow: [
          BoxShadow(
            color: tokens.ink.withValues(alpha: 0.14),
            blurRadius: 48,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned(
            right: -72,
            top: -18,
            child: Transform.rotate(
              angle: -0.31,
              child: Container(
                width: 210,
                height: 110,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.12),
                  ),
                ),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          subtitle,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Colors.white.withValues(alpha: 0.76),
                              ),
                        ),
                      ],
                    ),
                  ),
                  if (actionLabel != null)
                    TextButton(
                      onPressed: onAction,
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                        backgroundColor: Colors.white.withValues(alpha: 0.14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            tokens.radiusSmall,
                          ),
                        ),
                      ),
                      child: Text(actionLabel!),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  for (final metric in metrics) ...[
                    Expanded(child: _HeroMetric(metric: metric)),
                    if (metric != metrics.last) const SizedBox(width: 12),
                  ],
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 英雄卡指标格的数据（label + value，如"当前里程 / 12,345"）。
class LunioMetric {
  const LunioMetric({required this.label, required this.value});

  final String label;
  final String value;
}

class _HeroMetric extends StatelessWidget {
  const _HeroMetric({required this.metric});

  final LunioMetric metric;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 82),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              metric.label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Colors.white.withValues(alpha: 0.72),
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 28,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  metric.value,
                  maxLines: 1,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontSize: 23,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 状态徽章（"正常/到期/超期"小标签），配 LunioStatusTone 语义色。
class LunioStatusBadge extends StatelessWidget {
  const LunioStatusBadge({super.key, required this.label, required this.tone});

  final String label;
  final LunioStatusTone tone;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    final (background, foreground) = tone.statusColors(tokens);
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(tokens.radiusSmall),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// 三态语义枚举：与提醒的 normal/warning/danger 一一对应，
/// 这里集中定义"语义 → 颜色/图标"的映射（extension 给枚举加方法）。
enum LunioStatusTone { normal, warning, danger }

extension LunioStatusTonePalette on LunioStatusTone {
  (Color background, Color foreground) statusColors(LunioTokens tokens) {
    return switch (this) {
      LunioStatusTone.normal => (tokens.successSoft, tokens.success),
      LunioStatusTone.warning => (tokens.warningSoft, tokens.warning),
      LunioStatusTone.danger => (tokens.dangerSoft, tokens.danger),
    };
  }

  Color statusForeground(LunioTokens tokens) => statusColors(tokens).$2;

  IconData get statusIcon {
    return switch (this) {
      LunioStatusTone.normal => Icons.check_circle_outline,
      LunioStatusTone.warning => Icons.info_outline,
      LunioStatusTone.danger => Icons.error_outline,
    };
  }
}

/// 自绘分段选择器（选中项白底主色字）。通知频率、记录筛选等用。
/// onSelected 只在点"非当前项"时触发。
class LunioSegmentedControl extends StatelessWidget {
  const LunioSegmentedControl({
    super.key,
    required this.values,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<String> values;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.surface2,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          children: [
            for (var index = 0; index < values.length; index++)
              Expanded(
                child: _SegmentButton(
                  label: values[index],
                  selected: index == selectedIndex,
                  onTap: index == selectedIndex
                      ? null
                      : () => onSelected(index),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SegmentButton extends StatelessWidget {
  const _SegmentButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: Duration.zero,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? tokens.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(tokens.radiusSmall),
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: selected ? tokens.primary : tokens.muted,
            ),
          ),
        ),
      ),
    );
  }
}

/// 主按钮（FilledButton 换肤）。
class LunioPrimaryButton extends StatelessWidget {
  const LunioPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(onPressed: onPressed, child: Text(label));
  }
}

/// 次按钮（灰底，常作"取消"）。
class LunioSecondaryButton extends StatelessWidget {
  const LunioSecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: tokens.surface2,
        foregroundColor: tokens.ink,
      ),
      child: Text(label),
    );
  }
}

/// 方形图标按钮（提醒页右上角"切换车辆"）。
class LunioIconButton extends StatelessWidget {
  const LunioIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      icon: Icon(icon),
      style: IconButton.styleFrom(
        fixedSize: const Size(42, 42),
        backgroundColor: tokens.surface,
        foregroundColor: tokens.ink,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.radiusMedium),
        ),
      ),
    );
  }
}
