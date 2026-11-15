// 扫描选择 sheet（票 07）：诊断页"无记忆/直连失败"落到附近的 BLE 设备
// 列表，用户点选后回页面建链（story 5/6）。不过滤设备名（story 5：
// 全部显示防误伤），信号强度降序，行内"连接中…"状态反馈（story 6）。
//
// sheet 是纯视图 + 受控状态：扫描数据源经 obdScannerProvider 注入
//（测试换假扫描器），点选/关闭经回调与句柄协议回传页面——连接编排归
// 页面（会话工厂/记忆写/错误分类都在页面），sheet 不碰会话与偏好。
//
// ≈ Java 的模态选择对话框（JList + OK/Cancel）：行点击 = 选中事件，
// 句柄 = 对话框引用，页面持有句柄回填结果。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/lunio_tokens.dart';
import '../../../core/widgets/lunio_components.dart';
import '../shared/shell_shared.dart';
import 'ble_obd_transport.dart';
import 'obd_runtime.dart';

/// 扫描中提示文案（页面状态条与 sheet 顶部提示共用一份，文案单一出
/// 口惯例）。
const obdScanningHint = '正在扫描附近的蓝牙设备…';

/// sheet 句柄：页面 → sheet 的命令通道（连接失败回填行态 + 恢复扫描、
/// 连接成功关 sheet）。mount 后才有内容，未挂载时命令静默丢弃（迟到
/// 命令无害）。
class BleScanSheetHandle {
  _BleScanSheetState? _state;

  /// 连接失败回填：行回可点态、顶部提示失败文案、恢复扫描。
  void reportPickFailed(BleObdScanEntry entry, String copy) {
    _state?.reportPickFailed(entry, copy);
  }

  /// 关闭 sheet（连接成功，story 6"已选中"的收尾动作）。
  void close() {
    _state?.close();
  }

  /// sheet pop 完成（showLunioModalSheet future 完成）时解除挂接。
  void _detach() {
    _state = null;
  }
}

/// 打开扫描选择 sheet（同步返回句柄；onClosed 在 sheet 以任何方式关闭
/// 后回调——取消/下滑/句柄 close 都会触发，页面按当前相位决定是否回
/// idle）。
BleScanSheetHandle showBleScanSheet(
  BuildContext context, {
  required void Function(BleObdScanEntry) onDevicePicked,
  required void Function(BleObdTransportException) onGateFailed,
  required void Function() onClosed,
}) {
  final handle = BleScanSheetHandle();
  // 统一 sheet 出口（ADR 0016 骨架；选择器 barrierDismissible 默认
  // true：点遮罩/下滑关闭 = 取消，onClosed 回调里扫描中相位回 idle、
  // 连接中相位取消在途连接）。
  showLunioModalSheet<void>(
    context: context,
    builder: (_) => PrototypeSheetFrame(
      title: '选择适配器',
      bottomInset: MediaQuery.of(context).viewInsets.bottom,
      child: _BleScanSheet(
        handle: handle,
        onDevicePicked: onDevicePicked,
        onGateFailed: onGateFailed,
      ),
    ),
  ).whenComplete(() {
    handle._detach();
    onClosed();
  });
  return handle;
}

/// 扫描选择 sheet 主组件（ConsumerStatefulWidget：经 ref 读扫描器
/// provider）。
class _BleScanSheet extends ConsumerStatefulWidget {
  const _BleScanSheet({
    required this.handle,
    required this.onDevicePicked,
    required this.onGateFailed,
  });

  final BleScanSheetHandle handle;
  final void Function(BleObdScanEntry) onDevicePicked;

  /// 扫描启动遇门禁类失败（权限拒绝/蓝牙未开/不支持）：页面关 sheet、
  /// 状态条渲染文案，不把空列表当正常扫描结果展示。
  final void Function(BleObdTransportException) onGateFailed;

  @override
    ConsumerState<_BleScanSheet> createState() => _BleScanSheetState();
}

/// sheet 受控状态：订阅扫描结果流刷新列表，点选置连接中行态，失败回
/// 填与恢复扫描经句柄进。
class _BleScanSheetState extends ConsumerState<_BleScanSheet> {
  late final ObdScanner _scanner;
  StreamSubscription<List<BleObdScanEntry>>? _resultsSub;
  List<BleObdScanEntry> _entries = const [];
  String? _connectingId;
  String? _hint;

  @override
  void initState() {
    super.initState();
    widget.handle._state = this;
    _scanner = ref.read(obdScannerProvider);
    _resultsSub = _scanner.results.listen(
      _onResults,
      onError: (Object e) {
        _setHint(e);
      },
    );
    unawaited(_startScan());
  }

  /// 启动扫描；适配器门禁失败分两路：门禁类（权限/开关/不支持）回传
  /// 页面关 sheet、状态条渲染文案（story 8）；其余失败挂顶部提示。
  Future<void> _startScan() async {
    if (!mounted) {
      return;
    }
    try {
      await _scanner.start();
    } catch (e) {
      if (!mounted) {
        return;
      }
      if (e is BleObdTransportException && e.kind.isGateError) {
        widget.onGateFailed(e);
        return;
      }
      _setHint(e);
    }
  }

  /// 异常 → 顶部提示文案（BLE 可辨识异常用其状态条同款文案，其余归
  /// 通用扫描失败）。
  void _setHint(Object e) {
    if (!mounted) {
      return;
    }
    setState(() {
      _hint = e is BleObdTransportException
          ? e.statusCopy
          : '扫描失败，请重试';
    });
  }

  /// 扫描结果到达：整表刷新（扫描器已按信号强度降序）。
  void _onResults(List<BleObdScanEntry> entries) {
    if (!mounted) {
      return;
    }
    setState(() {
      _entries = entries;
    });
  }

  /// 行点选：置连接中行态 + 停扫 + 回传页面建链（story 6 连接中反馈）。
  void _onPick(BleObdScanEntry entry) {
    if (_connectingId != null) {
      return;
    }
    setState(() {
      _connectingId = entry.id;
    });
    unawaited(_scanner.stop());
    widget.onDevicePicked(entry);
  }

  /// 句柄命令：连接失败回填（页面调用）——行回可点态、顶部提示失败
  /// 文案、恢复扫描（重新 start，新设备继续进表）。
  void reportPickFailed(BleObdScanEntry entry, String copy) {
    if (!mounted) {
      return;
    }
    setState(() {
      _connectingId = null;
      _hint = copy;
    });
    unawaited(_startScan());
  }

  /// 句柄命令：关闭 sheet（连接成功收尾）。
  void close() {
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
  }

  /// 释放：退订结果流 + 停扫（下滑/取消/点选后 pop 都会走到；scanner
  /// stop 幂等）。
  @override
  void dispose() {
    unawaited(_scanner.stop());
    unawaited(_resultsSub?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    // 列表限高（车型选择 sheet 先例），长列表内部滚动不顶翻弹层。
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHintRow(context, tokens),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.48,
          ),
          child: _entries.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      '附近暂无蓝牙设备，请确认适配器已插车',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: tokens.subtle),
                    ),
                  ),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: _entries.length,
                  itemBuilder: (context, index) {
                    final entry = _entries[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _ScanDeviceRow(
                        entry: entry,
                        connecting: _connectingId == entry.id,
                        onPick: _connectingId == null
                            ? () => _onPick(entry)
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
  }

  /// 顶部提示行：失败/门禁文案优先，否则"正在扫描"默认文案（含小号
  /// 进度指示）。
  Widget _buildHintRow(BuildContext context, LunioTokens tokens) {
    final hint = _hint;
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
/// 状态文本，story 6；name 为空显"未命名设备"）。
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
    final name = entry.name.isEmpty ? '未命名设备' : entry.name;
    final row = Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: Theme.of(context).textTheme.titleSmall),
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
