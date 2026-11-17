// 提醒页 OBD 快速连接 UI（ADR 0027）：「连接OBD」胶囊按钮 + 油量水温
// 信息卡。两个组件只做渲染与转发：连接状态与读数来自 App 级连接控制器
// （obdConnectionControllerProvider，obd_runtime.dart），连接/断开/进诊
// 断页的决策在页面接线与控制器，不在本文件。
//
// 按钮四态（ADR 0027 拍板）：白=未连接（idle，与「更新里程」同款白胶
// 囊）；黄=连接中（connecting/scanning）；绿=已连接（connected）；红=
// 连接失败（disconnected）。黄/绿/红用语义 Soft 底 + 语义色字（与状态
// 徽章同一把色板），白态沿用英雄卡白 16% 底，视觉同源、色板单一来源。
//
// ≈ Java 的纯 View 组件：无状态、无副作用，事件经回调上抛。
import 'package:flutter/material.dart';

import '../../../core/format/clock.dart';
import '../../../core/theme/lunio_tokens.dart';
import '../../../core/widgets/lunio_components.dart';
import '../shared/shell_shared.dart';
import '../diagnostics/diagnostics_connection_controller.dart';

/// 「连接OBD」快速连接胶囊按钮（英雄卡顶行 [LunioHeroCard.secondaryAction]
/// 槽位）：颜色随连接相位，点击行为由调用方接线。
class ObdQuickConnectButton extends StatelessWidget {
  const ObdQuickConnectButton({
    super.key,
    required this.phase,
    required this.onTap,
  });

  /// App 级连接控制器的当前相位。
  final DiagnosticsConnectionPhase phase;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    // 白态 = 英雄卡「更新里程」同款白 16% 底 + 白字；其余三态用语义
    // Soft 底 + 语义色字（LunioStatusTonePalette 同一把色板）。
    final (Color background, Color foreground) = switch (phase) {
      DiagnosticsConnectionPhase.idle => (
        Colors.white.withValues(alpha: 0.16),
        Colors.white,
      ),
      DiagnosticsConnectionPhase.connecting ||
      DiagnosticsConnectionPhase.scanning => (
        tokens.warningSoft,
        tokens.warning,
      ),
      DiagnosticsConnectionPhase.connected => (
        tokens.successSoft,
        tokens.success,
      ),
      DiagnosticsConnectionPhase.disconnected => (
        tokens.dangerSoft,
        tokens.danger,
      ),
    };
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: foreground,
        backgroundColor: background,
        minimumSize: const Size(0, 32),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
        ),
      ),
      child: const Text('连接OBD'),
    );
  }
}

/// 油量水温信息卡（英雄卡下方，仅已连接显示）：油量 + 水温两条核心读数
/// + 刷新按钮 + 更新时间；点击整卡进诊断页。只显示实时读数（ADR 0027
/// 拍板「不回退最后读数」），无实时读数显「—」。
class ObdReadingsCard extends StatelessWidget {
  const ObdReadingsCard({
    super.key,
    required this.fuelDisplay,
    required this.coolantDisplay,
    required this.updatedAt,
    required this.onRefresh,
    required this.onOpen,
  });

  /// 油量展示值（如「45%」）；null = 无实时读数，显「—」。
  final String? fuelDisplay;

  /// 水温展示值（如「85°C」）；null = 无实时读数，显「—」。
  final String? coolantDisplay;

  /// 更新时间（两条读数较新者的读取时刻；null = 都没有 → 不显时间行）。
  final DateTime? updatedAt;

  final VoidCallback onRefresh;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    return LunioTappableCard(
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _ReadingBlock(label: '油量', value: fuelDisplay),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ReadingBlock(label: '水温', value: coolantDisplay),
              ),
              IconButton(
                tooltip: '立即刷新',
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh, size: 20),
                visualDensity: VisualDensity.compact,
                color: tokens.primary,
              ),
            ],
          ),
          if (updatedAt != null) ...[
            const SizedBox(height: 6),
            Text(
              '更新 ${formatReadingTime(updatedAt!, now: DateTime.now())}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: tokens.muted,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 单条读数块：标签 + 值（大字，w800；无值灰「—」）。
class _ReadingBlock extends StatelessWidget {
  const _ReadingBlock({required this.label, required this.value});

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 4),
        Text(
          value ?? '—',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: value == null ? tokens.subtle : tokens.ink,
              ),
        ),
      ],
    );
  }
}
