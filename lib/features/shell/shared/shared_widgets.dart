// shell 内部共享 UI 组件（带一定业务形态的小组件，比 core/widgets 更上层）。
//
// 复用度统计（引用次数，含定义处）：
//  - SmallActionButton 18 处 / PrototypeSheetFrame 11 处 —— 高复用，核心组件
//  - FilterBar、ChoiceChipButton、LoadingPage、ErrorPage —— 各只有记录页/
//    提醒页单一调用点，属"放错位置的组件"（过度提取，见审查报告 §复用）
//
// PrototypeSheetFrame：自绘 sheet 骨架（drag handle + 标题 + 滚动内容），
// 与 modal_feedback 的 _LunioDefaultSheetSurface 是两套并存实现。
// ignore_for_file: use_key_in_widget_constructors, library_private_types_in_public_api

import 'package:flutter/material.dart';

import '../../../core/theme/lunio_tokens.dart';
import '../../../core/widgets/lunio_components.dart';
import 'formatters.dart';

/// 横向可滚动的多选筛选条（chip 选中态 + 右下角小对勾）。
/// 目前只有记录页的年份/项目筛选在用。
class FilterBar extends StatelessWidget {
  const FilterBar({
    required this.labels,
    required this.selectedIndexes,
    required this.onSelected,
  });

  final List<String> labels;
  final Set<int> selectedIndexes;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var index = 0; index < labels.length; index++) ...[
            Builder(
              builder: (context) {
                final selected = selectedIndexes.contains(index);
                return InkWell(
                  onTap: () => onSelected(index),
                  borderRadius: BorderRadius.circular(12),
                  overlayColor: WidgetStateProperty.all(Colors.transparent),
                  splashColor: Colors.transparent,
                  highlightColor: Colors.transparent,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        height: 34,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: selected ? tokens.primarySoft : tokens.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: selected
                                ? tokens.primary.withValues(alpha: 0.34)
                                : tokens.line,
                          ),
                        ),
                        child: Text(
                          labels[index],
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(
                                color: selected ? tokens.primary : tokens.ink,
                              ),
                        ),
                      ),
                      if (selected)
                        Positioned(
                          right: 2,
                          bottom: 2,
                          child: Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              color: tokens.primary,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: tokens.surface,
                                width: 1.5,
                              ),
                            ),
                            child: const Icon(
                              Icons.check,
                              size: 9,
                              color: Colors.white,
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
            if (index != labels.length - 1) const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

/// 项目名 pill 组：按手写装箱算法分行（见 _packedPillRows），
/// 保证每行尽量塞满。用于记录卡/项目卡的项目标签展示。
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
    final textScaler = MediaQuery.textScalerOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final rows = _packedPillRows(
          labels: labels,
          maxWidth: constraints.maxWidth,
          textStyle: textStyle,
          textScaler: textScaler,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) ...[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (
                    var itemIndex = 0;
                    itemIndex < rows[rowIndex].length;
                    itemIndex++
                  ) ...[
                    if (itemIndex > 0) const SizedBox(width: 6),
                    SizedBox(
                      width: rows[rowIndex][itemIndex].width,
                      child: ItemPill(
                        label: rows[rowIndex][itemIndex].label,
                        style: textStyle,
                      ),
                    ),
                  ],
                ],
              ),
              if (rowIndex < rows.length - 1) const SizedBox(height: 6),
            ],
          ],
        );
      },
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

class _PackedPill {
  const _PackedPill({required this.label, required this.width});

  final String label;
  final double width;
}

/// pill 装箱布局算法：贪心塞行（宽度按文本实测 + padding + 余量，
/// 下限 58px；放不下就换行）。⚠ Flutter 自带 Wrap 组件即可实现等价布局。
List<List<_PackedPill>> _packedPillRows({
  required List<String> labels,
  required double maxWidth,
  required TextStyle? textStyle,
  required TextScaler textScaler,
}) {
  if (labels.isEmpty) {
    return const [];
  }
  if (!maxWidth.isFinite || maxWidth <= 0) {
    return [
      labels.map((label) => _PackedPill(label: label, width: 0)).toList(),
    ];
  }
  const spacing = 6.0;
  const horizontalPadding = 18.0;
  const measurementSlack = 4.0;
  const minPillWidth = 58.0;
  final remaining = labels
      .map(
        (label) => _PackedPill(
          label: label,
          width:
              (_measureTextWidth(label, textStyle, textScaler) +
                      horizontalPadding +
                      measurementSlack)
                  .clamp(minPillWidth, maxWidth),
        ),
      )
      .toList();
  final rows = <List<_PackedPill>>[];
  while (remaining.isNotEmpty) {
    final row = <_PackedPill>[];
    var usedWidth = 0.0;
    while (remaining.isNotEmpty) {
      var selectedIndex = -1;
      for (var index = 0; index < remaining.length; index++) {
        final extraSpacing = row.isEmpty ? 0.0 : spacing;
        if (usedWidth + extraSpacing + remaining[index].width <= maxWidth) {
          selectedIndex = index;
          break;
        }
      }
      if (selectedIndex == -1) {
        if (row.isEmpty) {
          selectedIndex = 0;
        } else {
          break;
        }
      }
      final item = remaining.removeAt(selectedIndex);
      usedWidth += (row.isEmpty ? 0.0 : spacing) + item.width;
      row.add(item);
    }
    rows.add(row);
  }
  return rows;
}

/// 用 TextPainter 量文本宽度。
/// ⚠ painter 未调用 dispose()（Flutter 3.16+ 建议，debug 会提示泄漏，R22）。
double _measureTextWidth(String text, TextStyle? style, TextScaler textScaler) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    maxLines: 1,
    textDirection: TextDirection.ltr,
    textScaler: textScaler,
  )..layout();
  return painter.width;
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

/// 可多选的项目 chip（记录表单选保养项目用；enabled=false 展示
/// "已停用但历史上被选过"的项目）。
class ChoiceChipButton extends StatelessWidget {
  const ChoiceChipButton({
    required this.label,
    required this.selected,
    required this.onTap,
    this.enabled = true,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        constraints: const BoxConstraints(minHeight: 36),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? tokens.primarySoft : tokens.surface2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? tokens.primary.withValues(alpha: 0.3)
                : tokens.line,
          ),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: selected ? tokens.primary : tokens.ink,
          ),
        ),
      ),
    );
  }
}

/// 页面级加载占位（目前仅提醒页使用；记录/我的页各自手写 loading 分支）。
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

/// 页面级错误占位（目前仅提醒页使用）。
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
