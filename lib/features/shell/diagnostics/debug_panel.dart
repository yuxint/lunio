// 诊断调试终端（ADR 0023）：自由 AT/PID 命令 + 一键检测脚本 + 原始
// 响应日志。进入调试模式暂停自动轮询，退出恢复默认 29-bit 头并重启
// 轮询；日志可复制交回分析。
//
// 一键检测是健康快照（2026-11-16 精简，ADR 0023 修订节）：快照集 ∩ 本车
// 位图 + DTC + 私有 DID 三段只读。私有 DID 本轮仍不进正常轮询；2026-11-16 定案
// ——内置水温已切标准 PID 0167、227029 为表显刻度交叉验证不接产品卡片
//（ADR 0021 修订节、ADR 0022 修订节）。
// ignore_for_file: use_key_in_widget_constructors, library_private_types_in_public_api

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/lunio_tokens.dart';
import '../../../core/widgets/lunio_components.dart';
import '../shared/shell_shared.dart';
import 'elm327_parser.dart' show normalizeObdCommand;
import 'elm327_session.dart';
import 'obd_verification_run.dart';

/// 调试面板：折叠展开 + 调试模式开关 + 自由终端 + 一键检测 + 日志。
class DiagnosticsDebugPanel extends StatefulWidget {
  const DiagnosticsDebugPanel({
    required this.session,
    required this.connected,
    required this.carLabel,
    this.onVerificationLog,
    this.onOpenSessionLogs,
  });

  /// 当前会话（null = 未建链/已释放）。
  final Elm327Session? session;

  /// 是否已连接（未连接时所有命令控件禁用）。
  final bool connected;

  /// 日志头部的车辆标识。
  /// 车辆标签（一键检测日志头用）。
  final String carLabel;

  /// 一键检测整段日志回调（2026-11-18 拍板：追加进当次会话日志文件）。
  final void Function(String log)? onVerificationLog;

  /// 打开会话日志列表 sheet（调试终端「会话日志」入口行）。
  final VoidCallback? onOpenSessionLogs;

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

  /// 一键检测：run 协议归 `obd_verification_run.dart`（发什么 / 顺序 /
  /// 日志格式 / 默认头恢复），本 widget 只清空日志、把日志块追加进
  /// `_log` 并持有 busy 生命周期。执行器 adapter 把会话异常翻译成
  /// run module 的结果分类：超时=继续，其余会话失败=中止。
  Future<void> _runVerification() async {
    final session = widget.session;
    if (session == null || !_debugMode || _busy) {
      return;
    }
    setState(() {
      _busy = true;
      _log = '';
    });
    try {
      final result = await runObdVerification(
        carLabel: widget.carLabel,
        onLog: (block) {
          if (!mounted) {
            return;
          }
          setState(() {
            _log = '$_log$block';
          });
        },
        send: (command) async {
          try {
            return ObdCommandFrame(await session.sendRawCommand(command));
          } on Elm327TimeoutException catch (error) {
            return ObdCommandTimeout(error);
          } on Elm327SessionException catch (error) {
            return ObdCommandFailure(error);
          }
        },
      );
      // 整段日志落会话文件（2026-11-18 共识 7；无 sink 时静默）。
      widget.onVerificationLog?.call(result.log);
    } finally {
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
          // 会话日志入口（2026-11-18 拍板）：展开区顶部，任何连接状态
          // 可看（历史会话文件与连接状态无关）。
          if (_expanded && widget.onOpenSessionLogs != null) ...[
            const SizedBox(height: 8),
            LunioTappableCard(
              onTap: () => widget.onOpenSessionLogs?.call(),
              child: Row(
                children: [
                  Icon(Icons.history, size: 18, color: tokens.muted),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '会话日志',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                  const Icon(Icons.chevron_right,
                      size: 18, color: Colors.white24),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
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
                  label: '一键检测',
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