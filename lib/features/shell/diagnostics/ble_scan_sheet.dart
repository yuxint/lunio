// 扫描选择 sheet（票 07）：诊断页「无记忆/直连失败」落到附近的 BLE 设备
// 列表，用户点选后回 controller 建链。
//
// 2026-11-15 起是纯渲染器（GLOSSARY「诊断连接编排」）：扫描器启动/停止、
// 结果订阅、连接中行态、失败回填与恢复扫描全部归
// diagnostics_connection_controller.dart；本文件只按 controller 的
// state.scan 渲染列表与提示，点选回调 controller.pickDevice。列表过滤
//（空名设备不进）与首见定序在扫描器数据源（mergeScanEntries），sheet
// 只渲染收到的清单。
//
// ≈ Java 的模态选择对话框（JList + Cancel）：数据来自后端状态对象，
// 行点击 = 选中事件，对话框本身不做业务判断。
import 'package:flutter/material.dart';

import '../../../core/theme/lunio_tokens.dart';
import '../../../core/widgets/lunio_components.dart';
import '../shared/shell_shared.dart';
import 'ble_scan_entries.dart' show BleObdScanEntry;
import 'diagnostics_connection_controller.dart';

/// 扫描中提示文案（页面状态条与 sheet 顶部提示共用一份，文案单一出
/// 口惯例）。
const obdScanningHint = '正在扫描附近的蓝牙设备…';

/// sheet 句柄：页面 → sheet 的命令通道（controller 主动关闭 sheet）。
/// mount 前收到的 close 请求记下来，首帧后补发（扫描启动即门禁失败的
/// 路径：controller 在 sheet 挂载前就要关掉它）；未挂载时命令静默丢弃
/// 的旧语义由「补发」替代（迟到命令仍无害）。
class BleScanSheetHandle {
  _BleScanSheetState? _state;
  bool _closePending = false;

  /// 关闭 sheet（连接成功/门禁失败收尾）。
  void close() {
    final state = _state;
    if (state == null) {
      _closePending = true;
      return;
    }
    state.close();
  }

  /// sheet 首帧挂载：补发未送达的 close（延到帧后 pop，避免 build 期
  /// 导航）。
  void _attach(_BleScanSheetState state) {
    _state = state;
    if (!_closePending) {
      return;
    }
    _closePending = false;
    WidgetsBinding.instance.addPostFrameCallback((_) => state.close());
  }

  /// sheet pop 完成时解除挂接。
  void _detach() {
    _state = null;
    _closePending = false;
  }
}

/// 打开扫描选择 sheet（同步返回句柄；onClosed 在 sheet 以任何方式关闭
/// 后回调——取消/下滑/句柄 close 都会触发，页面转告 controller 收尾）。
BleScanSheetHandle showBleScanSheet(
  BuildContext context, {
  required DiagnosticsConnectionController controller,
  required VoidCallback onClosed,
}) {
  final handle = BleScanSheetHandle();
  // 统一 sheet 出口（ADR 0016 骨架；选择器 barrierDismissible 默认
  // true：点遮罩/下滑关闭 = 取消）。
  showLunioModalSheet<void>(
    context: context,
    builder: (_) => PrototypeSheetFrame(
      title: '选择适配器',
      bottomInset: MediaQuery.of(context).viewInsets.bottom,
      child: _BleScanSheet(handle: handle, controller: controller),
    ),
  ).whenComplete(() {
    handle._detach();
    onClosed();
  });
  return handle;
}

/// 扫描选择 sheet 主体：只按 controller state.scan 渲染（句柄挂接需要
/// State 生命周期）。
class _BleScanSheet extends StatefulWidget {
  const _BleScanSheet({required this.handle, required this.controller});

  final BleScanSheetHandle handle;
  final DiagnosticsConnectionController controller;

  @override
  State<_BleScanSheet> createState() => _BleScanSheetState();
}

class _BleScanSheetState extends State<_BleScanSheet> {
  @override
  void initState() {
    super.initState();
    widget.handle._attach(this);
  }

  /// 句柄命令：关闭 sheet（controller 主动关闭：点选成功/门禁失败）。
  void close() {
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final tokens = Theme.of(context).extension<LunioTokens>()!;
        final scan = widget.controller.state.scan;
        // 列表限高（车型选择 sheet 先例），长列表内部滚动不顶翻弹层。
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHintRow(context, tokens, scan.hint),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.48,
              ),
              // 列表显式零内边距：ListView 默认拿系统安全区插值（状态栏高
              // 度）当自己的 padding，弹层贴屏底却把屏顶 inset 垫进列表顶
              //（2026-11-15 真机留白根因，widget 测试几何断言守卫）。
              child: scan.entries.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      // 不用 Center：Center 撑满约束最大高度（列表限高 48%
                      // 屏高），文案被推到中部、上下全成空白（留白根因之二）。
                      child: Text(
                        '附近暂无蓝牙设备，请确认适配器已插车',
                        textAlign: TextAlign.center,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: tokens.subtle),
                      ),
                    )
                  : ListView.builder(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      itemCount: scan.entries.length,
                      itemBuilder: (context, index) {
                        final entry = scan.entries[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _ScanDeviceRow(
                            entry: entry,
                            connecting: scan.connectingId == entry.id,
                            onPick: scan.connectingId == null
                                ? () => widget.controller.pickDevice(entry)
                                : null,
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 8),
            LunioSecondaryButton(
              label: '关闭',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        );
      },
    );
  }

  /// 顶部提示行：失败/门禁文案优先，否则"正在扫描"默认文案（含小号
  /// 进度指示）。
  Widget _buildHintRow(
    BuildContext context,
    LunioTokens tokens,
    String? hint,
  ) {
    if (hint != null) {
      return Text(
        hint,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: tokens.muted,
            ),
      );
    }
    return Row(
      children: [
        const SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 8),
        Text(
          obdScanningHint,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: tokens.muted,
              ),
        ),
      ],
    );
  }
}

/// 扫描设备行（LunioTappableCard 整卡可点；连接中行态右侧"连接中…"
/// 状态文本）。空名设备在扫描器合并函数就被过滤，行内名称恒非空。
class _ScanDeviceRow extends StatelessWidget {
  const _ScanDeviceRow({
    required this.entry,
    required this.connecting,
    this.onPick,
  });

  final BleObdScanEntry entry;
  final bool connecting;
  final VoidCallback? onPick;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    final row = Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(entry.name, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 2),
              Text(
                '信号强度 ${entry.rssi}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: tokens.muted,
                    ),
              ),
            ],
          ),
        ),
        if (connecting)
          Text(
            '连接中…',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: tokens.primary,
                ),
          ),
      ],
    );
    if (onPick == null) {
      return LunioCard(child: row);
    }
    return LunioTappableCard(onTap: onPick!, child: row);
  }
}
