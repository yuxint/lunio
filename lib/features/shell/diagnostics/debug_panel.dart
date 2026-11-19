// 诊断调试终端（ADR 0023）：自由 AT/PID 命令 + 一键检测脚本 + 原始
// 响应日志。2026-11-19 拍板改懒暂停：无显式调试开关，发原始命令前暂
// 停自动轮询、命令返回即恢复；一键检测整段结束才恢复（避免轮询插队
// 打断序列）。日志可复制/清空。
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
  bool _busy = false;
  String _log = '';

  @override
  void didUpdateWidget(covariant DiagnosticsDebugPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session) {
      _busy = false;
      _log = '';
    }
  }

  @override
  void dispose() {
    _commandController.dispose();
    super.dispose();
  }

  /// 原始命令（2026-11-19 拍板懒暂停）：先暂停自动轮询（等在途请求收
  /// 尾），命令返回/失败即恢复——单条命令独占链路 1-2 秒，轮询让路。
  Future<void> _send() async {
    final session = widget.session;
    final command = _commandController.text.trim();
    if (session == null || command.isEmpty || _busy) {
      return;
    }
    setState(() => _busy = true);
    _append('> ${normalizeObdCommand(command)}');
    await session.pausePolling();
    try {
      final frame = await session.sendRawCommand(command);
      _append(frame);
    } catch (error) {
      _append('ERROR: $error');
    } finally {
      session.resumePolling();
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  /// 一键检测：run 协议归 `obd_verification_run.dart`（发什么 / 顺序 /
  /// 日志格式 / 默认头恢复），本 widget 只清空日志、把日志块追加进
  /// `_log` 并持有 busy 生命周期。执行器 adapter 把会话异常翻译成
  /// run module 的结果分类：超时=继续，其余会话失败=中止。
  /// 一键检测（2026-11-19 拍板）：先暂停自动轮询，**整段结束才恢复**
  /// （27 条连续序列，按条恢复会被轮询插队打断）；完成写日志尾行 +
  /// toast（完成态可感知），整段日志落会话文件。
  Future<void> _runVerification() async {
    final session = widget.session;
    if (session == null || _busy) {
      return;
    }
    setState(() {
      _busy = true;
      _log = '';
    });
    await session.pausePolling();
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
      _append('—— 一键检测完成 ——');
      if (mounted) {
        showStatusOverlay(context, '一键检测完成', StatusOverlayTone.success);
      }
      // 整段日志落会话文件（2026-11-18 共识 7；无 sink 时静默）。
      widget.onVerificationLog?.call(result.log);
    } finally {
      session.resumePolling();
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
                  Icon(Icons.chevron_right, size: 18, color: tokens.line),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (_expanded) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _commandController,
                    enabled: enabled && !_busy,
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
                  onPressed: enabled && !_busy
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
                  onPressed: enabled && !_busy
                      ? () => unawaited(_runVerification())
                      : null,
                ),
                SmallActionButton(
                  label: '复制日志',
                  secondary: true,
                  onPressed: _log.isEmpty ? null : () => unawaited(_copyLog()),
                ),
                SmallActionButton(
                  label: '清空',
                  secondary: true,
                  onPressed: _log.isEmpty ? null : () => setState(() => _log = ''),
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