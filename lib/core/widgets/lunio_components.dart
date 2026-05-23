import 'package:flutter/material.dart';

import '../theme/lunio_tokens.dart';

class LunioPage extends StatelessWidget {
  const LunioPage({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    required this.children,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 112),
      children: [
        LunioTopBar(title: title, subtitle: subtitle, trailing: trailing),
        const SizedBox(height: 16),
        ...children,
      ],
    );
  }
}

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

class LunioCard extends StatelessWidget {
  const LunioCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
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
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            tokens.primary,
            tokens.primaryStrong,
            const Color(0xff0f392c),
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
      child: Column(
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
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
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
                      borderRadius: BorderRadius.circular(tokens.radiusSmall),
                    ),
                  ),
                  child: Text(actionLabel!),
                ),
            ],
          ),
          const SizedBox(height: 22),
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
    );
  }
}

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
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
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
            const SizedBox(height: 7),
            Text(
              metric.value,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class LunioStatusBadge extends StatelessWidget {
  const LunioStatusBadge({super.key, required this.label, required this.tone});

  final String label;
  final LunioStatusTone tone;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    final (background, foreground) = switch (tone) {
      LunioStatusTone.normal => (tokens.primarySoft, tokens.primary),
      LunioStatusTone.warning => (tokens.warningSoft, tokens.warning),
      LunioStatusTone.danger => (tokens.dangerSoft, tokens.danger),
    };
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

enum LunioStatusTone { normal, warning, danger }

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
        borderRadius: BorderRadius.circular(tokens.radiusMedium),
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
                  onTap: () => onSelected(index),
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
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(tokens.radiusSmall),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 36,
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
