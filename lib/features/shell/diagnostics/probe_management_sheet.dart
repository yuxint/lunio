// 检测点管理 sheet（照保养项目交互，ADR 0021 修订节、ADR 0023）：
// 顶部车辆 pill + 新增；卡片 = 名称 + 刷新规则/解析类型 + 编辑/启停/
// 删除；内置卡片带"内置"标签、无删除按钮；自定义可增改删。
//
// 页面只保留实时读数列表（见 diagnostics_page.dart），配置入口在这里；
// 表单仍走 probe_form.dart 的 showProbeFormSheet。
// ignore_for_file: use_key_in_widget_constructors
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/theme/lunio_tokens.dart';
import '../../../core/widgets/lunio_components.dart';
import '../../../domain/entities/car.dart';
import '../../../domain/entities/diagnostics_probe.dart';
import '../shared/shell_shared.dart';
import 'probe_form.dart';

/// 打开某辆车的检测点管理 sheet。
void showProbeManagementSheet(BuildContext context, {required Car car}) {
  showLunioModalSheet<void>(
    context: context,
    builder: (context) => PrototypeSheetFrame(
      title: '检测点管理',
      child: ProbeManagementSheetContent(car: car),
    ),
  );
}

/// 管理 sheet 主体：列表数据走 [diagnosticsProbesProvider] family，
/// 写库后动作层逐出 family、本组件自动重算。
class ProbeManagementSheetContent extends ConsumerStatefulWidget {
  const ProbeManagementSheetContent({required this.car});

  final Car car;

  @override
  ConsumerState<ProbeManagementSheetContent> createState() =>
      _ProbeManagementSheetContentState();
}

class _ProbeManagementSheetContentState
    extends ConsumerState<ProbeManagementSheetContent> {
  final scrollController = ScrollController();

  @override
  void dispose() {
    scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final carId = widget.car.id;
    if (carId == null) {
      return const LunioInlineMessage(message: '请先保存车辆');
    }
    final probesAsync = ref.watch(diagnosticsProbesProvider(carId));
    final maxListHeight = MediaQuery.sizeOf(context).height * 0.54;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: ItemPills(
                labels: ['${widget.car.brand} ${widget.car.model}'],
              ),
            ),
            const SizedBox(width: 12),
            SmallActionButton(
              label: '新增',
              primary: true,
              onPressed: () =>
                  showProbeFormSheet(context, ref, carId: carId),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const _EcuAutoSyncRow(),
        const SizedBox(height: 12),
        if (!probesAsync.hasValue && probesAsync.isLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 28),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (!probesAsync.hasValue && probesAsync.hasError)
          Text('加载失败：${friendlyError(probesAsync.error!)}')
        else ...[
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxListHeight),
            child: SingleChildScrollView(
              controller: scrollController,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var index = 0;
                      index < probesAsync.requireValue.length;
                      index++) ...[
                    _ProbeManagementCard(
                      probe: probesAsync.requireValue[index],
                      onEdit: () => showProbeFormSheet(
                        context,
                        ref,
                        carId: carId,
                        probe: probesAsync.requireValue[index],
                      ),
                      onToggle: () => unawaited(
                        _toggleProbe(
                          context,
                          ref,
                          probesAsync.requireValue[index],
                        ),
                      ),
                      onDelete: probesAsync.requireValue[index].isBuiltIn
                          ? null
                          : () => _deleteProbe(
                                context,
                                ref,
                                probesAsync.requireValue[index],
                              ),
                    ),
                    if (index != probesAsync.requireValue.length - 1)
                      const SizedBox(height: 10),
                  ],
                ],
              ),
            ),
          ),
          if (probesAsync.hasError) ...[
            const SizedBox(height: 10),
            LunioInlineMessage(
              message: '刷新失败：${friendlyError(probesAsync.error!)}',
              tone: LunioStatusTone.danger,
            ),
          ],
        ],
      ],
    );
  }

  /// 启停检测点：动作层异常穿透，这里 toast 兜底（与 [_deleteProbe]
  /// 同一接缝口径）。
  Future<void> _toggleProbe(
    BuildContext context,
    WidgetRef ref,
    DiagnosticsProbe probe,
  ) async {
    try {
      await setDiagnosticsProbeEnabled(ref, probe, !probe.enabled);
    } catch (error) {
      if (context.mounted) {
        showStatusOverlay(
          context,
          friendlyError(error),
          StatusOverlayTone.error,
        );
      }
    }
  }

  /// 删除自定义检测点：确认框 → 动作层删除+失效 → 失败 toast。
  Future<void> _deleteProbe(
    BuildContext context,
    WidgetRef ref,
    DiagnosticsProbe probe,
  ) async {
    final confirmed = await showConfirmDialog(
      context: context,
      title: '删除检测点',
      message: '确定删除 ${probe.name}？',
      confirmLabel: '删除',
    );
    if (confirmed != true) {
      return;
    }
    try {
      await removeDiagnosticsProbe(ref, probe);
    } catch (error) {
      if (context.mounted) {
        showStatusOverlay(
          context,
          friendlyError(error),
          StatusOverlayTone.error,
        );
      }
    }
  }
}

/// 「ECU 自动同步」开关行（ADR 0026 + ADR 0030）：开 = 任何连接状态下
/// 读到数据就静默写入——更大 ECU 里程写入车辆里程（ADR 0026），
/// 门限放行的油量写入加油页剩余油量（ADR 0030，当前应用车）。
/// 开关读写走动作层 setObdOdometerAutoSync（偏好纪元 bump，键不变）。
class _EcuAutoSyncRow extends ConsumerWidget {
  const _EcuAutoSyncRow();

  /// 写偏好失败 toast 兜底（动作层异常穿透，调用点翻译；与本文件
  /// 行开关的 `_toggleProbe` 同一接缝口径）。
  Future<void> _setAutoSync(
    BuildContext context,
    WidgetRef ref,
    bool value,
  ) async {
    try {
      await setObdOdometerAutoSync(ref, value);
    } catch (error) {
      if (context.mounted) {
        showStatusOverlay(
          context,
          friendlyError(error),
          StatusOverlayTone.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    final enabled = ref.watch(obdOdometerAutoSyncProvider).value ?? false;
    return LunioCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'ECU 自动同步',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  '连接诊断时自动更新车辆里程与加油页剩余油量',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: tokens.muted,
                      ),
                ),
              ],
            ),
          ),
          Switch(
            value: enabled,
            onChanged: (value) =>
                unawaited(_setAutoSync(context, ref, value)),
          ),
        ],
      ),
    );
  }
}

/// 检测点管理卡：名称 + 内置标签 + 刷新规则/解析类型 + 三个动作。
class _ProbeManagementCard extends StatelessWidget {
  const _ProbeManagementCard({
    required this.probe,
    required this.onEdit,
    required this.onToggle,
    required this.onDelete,
  });

  final DiagnosticsProbe probe;
  final VoidCallback onEdit;
  final VoidCallback onToggle;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    final actions = Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        SmallActionButton(label: '编辑', onPressed: onEdit, secondary: true),
        const SizedBox(width: 8),
        SmallActionButton(
          label: probe.enabled ? '已启用' : '已禁用',
          onPressed: onToggle,
          primary: probe.enabled,
          muted: !probe.enabled,
        ),
        if (onDelete != null) ...[
          const SizedBox(width: 8),
          SmallActionButton(
            label: '删除',
            tooltip: '删除',
            onPressed: onDelete,
            danger: true,
          ),
        ],
      ],
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(tokens.radiusLarge),
        border: Border.all(color: tokens.line),
        boxShadow: [
          BoxShadow(
            color: tokens.ink.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        probe.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    if (probe.isBuiltIn) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: tokens.surface2,
                          borderRadius:
                              BorderRadius.circular(tokens.radiusSmall),
                        ),
                        child: Text(
                          '内置',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: tokens.muted),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  '每 ${probe.refreshIntervalSeconds} 秒刷新 · '
                  '${probe.parseType.label}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          actions,
        ],
      ),
    );
  }
}