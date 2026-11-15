// 诊断调试终端（ADR 0023）：自由 AT/PID 命令 + 一键验证脚本 + 原始
// 响应日志。进入调试模式暂停自动轮询，退出恢复默认 29-bit 头并重启
// 轮询；日志可复制交回分析。
//
// 本轮私有 DID 只在这里验证，不进正常轮询：验证通过后再决定把内置
// 水温换成命中命令、或把 227029 加为实测总油量检测点。
// ignore_for_file: use_key_in_widget_constructors, library_private_types_in_public_api

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/lunio_tokens.dart';
import '../../../core/widgets/lunio_components.dart';
import '../shared/shell_shared.dart';
import 'elm327_parser.dart' show normalizeObdCommand;
import 'elm327_session.dart';

/// 一键验证命令序列（ADR 0023）：标准能力/读数 + 本田私有 DID。
/// `227029` 是 CIVIC_FLV（DA60，16 位 ÷100 升）；`22202C` 是
/// ECT 1–4（DA01，16 位有符号 ÷10 ℃）；`22267A` 是原始水温。
const List<String> obdVerificationCommands = [
  'ATI',
  'ATDPN',
  '0100',
  '0120',
  '0140',
  '0160',
  '0105',
  '012F',
  '0142',
  '010C',
  'ATRV',
  'ATSH DA 60 F1',
  '227029',
  'ATSH DA 10 F1',
  '222623',
  '222678',
  '22267A',
  '2223E2',
  '2223E3',
  'ATSH DA 01 F1',
  '22202C',
  'ATSH DB 33 F1',
];

/// 调试面板：折叠展开 + 调试模式开关 + 自由终端 + 一键采集 + 日志。
class DiagnosticsDebugPanel extends StatefulWidget {
  const DiagnosticsDebugPanel({
    required this.session,
    required this.connected,
    required this.carLabel,
  });

  /// 当前会话（null = 未建链/已释放）。
  final Elm327Session? session;

  /// 是否已连接（未连接时所有命令控件禁用）。
  final bool connected;

  /// 日志头部的车辆标识。
  final String carLabel;

  @override
  State<DiagnosticsDebugPanel> createState() => _DiagnosticsDebugPanelState();
}

class _DiagnosticsDebugPanelState extends State<DiagnosticsDebugPanel> {
  final _commandController = TextEditingController();
  bool _expanded = false;
  bool _debugMode = false;
  bool _busy = false;
  String _log = '';

  @override
  void didUpdateWidget(covariant DiagnosticsDebugPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session ||
        (!widget.connected && _debugMode)) {
      _debugMode = false;
      _busy = false;
    }
  }

  @override
  void dispose() {
    _commandController.dispose();
    super.dispose();
  }

  Future<void> _setDebugMode(bool value) async {
    final session = widget.session;
    if (session == null) {
      return;
    }
    if (value) {
      setState(() => _busy = true);
      await session.pausePolling();
      if (!mounted) {
        return;
      }
      setState(() {
        _debugMode = true;
        _busy = false;
      });
      return;
    }
    setState(() => _busy = true);
    try {
      // 退出调试恢复 29-bit 功能寻址头，再重启自动轮询。
      await session.sendRawCommand('ATSH DB 33 F1');
    } catch (_) {
      // 适配器已断/恢复命令失败：轮询恢复后由正常链路错误处理。
    }
    session.resumePolling();
    if (!mounted) {
      return;
    }
    setState(() {
      _debugMode = false;
      _busy = false;
    });
  }

  Future<void> _send() async {
    final session = widget.session;
    final command = _commandController.text.trim();
    if (session == null || command.isEmpty || !_debugMode || _busy) {
      return;
    }
    setState(() => _busy = true);
    _append('> ${normalizeObdCommand(command)}');
    try {
      final frame = await session.sendRawCommand(command);
      _append(frame);
    } catch (error) {
      _append('ERROR: $error');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _runVerification() async {
    final session = widget.session;
    if (session == null || !_debugMode || _busy) {
      return;
    }
    setState(() {
      _busy = true;
      _log = 'Lunio OBD 验证日志\n'
          '车辆：${widget.carLabel}\n'
          '开始：${DateTime.now().toIso8601String()}\n'
          '说明：按顺序发送标准能力/读数 + 本田私有 DID；ATSH 变更后\n'
          '由末尾 ATSH DB 33 F1 恢复。\n\n';
    });
    try {
      for (final command in obdVerificationCommands) {
        if (!mounted) {
          break;
        }
        _append('> ${normalizeObdCommand(command)}');
        try {
          final frame = await session.sendRawCommand(command);
          _append(frame);
        } catch (error) {
          _append('ERROR: $error');
        }
      }
    } finally {
      try {
        await session.sendRawCommand('ATSH DB 33 F1');
      } catch (_) {}
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _append(String text) {
    final normalized = text
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .trimRight();
    final stamp = DateTime.now().toIso8601String();
    if (!mounted) {
      return;
    }
    setState(() {
      _log = '$_log[$stamp] $normalized\n';
    });
  }

  Future<void> _copyLog() async {
    await Clipboard.setData(ClipboardData(text: _log));
    if (mounted) {
      showStatusOverlay(
        context,
        '日志已复制',
        StatusOverlayTone.success,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    final enabled = widget.connected && widget.session != null;
    return LunioCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.terminal, size: 18, color: tokens.muted),
              const SizedBox(width: 6),
              Text('调试', style: Theme.of(context).textTheme.titleSmall),
              const Spacer(),
              TextButton(
                onPressed: () => setState(() => _expanded = !_expanded),
                child: Text(_expanded ? '收起' : '展开'),
              ),
            ],
          ),
          if (_expanded) ...[
            const SizedBox(height: 8),
            const LunioInlineMessage(
              message: 'ATSH/ATSP/ATCRA/ATD/ATZ 会改变适配器状态；mode 04 '
                  '会清故障码。进入调试会暂停自动轮询，退出会恢复默认头'
                  '并重启轮询。',
              tone: LunioStatusTone.warning,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '调试模式（暂停自动轮询）',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                Switch(
                  value: _debugMode,
                  onChanged: enabled && !_busy
                      ? (value) => unawaited(_setDebugMode(value))
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _commandController,
                    enabled: enabled && _debugMode && !_busy,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: '原始命令',
                      hintText: '如 0105、ATSH DA 60 F1、227029',
                      isDense: true,
                    ),
                    onSubmitted: (_) => unawaited(_send()),
                  ),
                ),
                const SizedBox(width: 8),
                SmallActionButton(
                  label: '发送',
                  primary: true,
                  onPressed: enabled && _debugMode && !_busy
                      ? () => unawaited(_send())
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                SmallActionButton(
                  label: '一键采集验证日志',
                  primary: true,
                  onPressed: enabled && _debugMode && !_busy
                      ? () => unawaited(_runVerification())
                      : null,
                ),
                SmallActionButton(
                  label: '复制日志',
                  secondary: true,
                  onPressed: _log.isEmpty ? null : () => unawaited(_copyLog()),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 220),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: tokens.surface2,
                borderRadius: BorderRadius.circular(tokens.radiusMedium),
                border: Border.all(color: tokens.line),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  _log.isEmpty ? '暂无日志' : _log,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                      ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}