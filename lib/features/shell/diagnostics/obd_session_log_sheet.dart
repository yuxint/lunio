// OBD 会话日志列表 sheet（2026-11-18 拍板）：调试终端的「会话日志」
// 入口行打开；列表 = 会话文件（连接建立时刻命名）+ 读数条数 + 导出/
// 删除；入口在调试终端（共识 6），导出走原生文件保存桥（复用备份
// 导出的 exportJsonFile 通道，内容与文件名不受 JSON 限制）。
import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/platform/native_files.dart';
import '../../../core/theme/lunio_tokens.dart';
import '../../../core/widgets/lunio_components.dart';
import '../shared/shell_shared.dart';
import 'obd_session_log.dart';

/// 打开会话日志列表 sheet：load = 目录列表（form_sheet 装载管道，装载
/// 失败 toast、sheet 不出现）。
Future<void> showObdSessionLogSheet(BuildContext context) async {
  await showLunioFormSheet<void, List<ObdSessionLogEntry>>(
    context: context,
    title: '会话日志',
    load: (handle) =>
        ObdSessionLogStore.production().then((s) => s.list()),
    builder: (context, handle, entries) {
      if (entries.isEmpty) {
        return const LunioEmptyCard('暂无会话日志');
      }
      return Column(
        children: [
          for (final entry in entries) ...[
            _SessionLogTile(entry: entry),
            const SizedBox(height: 10),
          ],
          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      );
    },
  );
}

/// 单个会话日志文件条目：名称 + 条数/大小 + 导出/删除。
class _SessionLogTile extends StatelessWidget {
  const _SessionLogTile({required this.entry});

  final ObdSessionLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    final started = entry.startedAt;
    String two(int v) => v.toString().padLeft(2, '0');
    final label = '${started.year}-${two(started.month)}-${two(started.day)} '
        '${two(started.hour)}:${two(started.minute)}:${two(started.second)}';
    return LunioCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(
                  '${entry.lineCount} 条记录 · '
                  '${(entry.bytes / 1024).toStringAsFixed(1)} KB',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: tokens.muted,
                      ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '导出',
            onPressed: () => unawaited(_export(context)),
            icon: const Icon(Icons.ios_share, size: 20),
            color: tokens.primary,
          ),
          IconButton(
            tooltip: '删除',
            onPressed: () => unawaited(_delete(context)),
            icon: const Icon(Icons.delete_outline, size: 20),
            color: tokens.danger,
          ),
        ],
      ),
      // LunioCard 无 onTap 参数——这里不需要整卡点击，两按钮即动作。
    );
  }

  /// 导出：读全文 → 原生保存桥（用户选位置）；取消/失败不提示。
  Future<void> _export(BuildContext context) async {
    final content = await ObdSessionLogStore.production()
        .then((s) => s.readContent(entry.fileName));
    if (!context.mounted) {
      return;
    }
    final ok = await NativeFiles.exportJsonFile(
      filename: entry.fileName,
      content: content,
    );
    if (context.mounted && ok) {
      showStatusOverlay(context, '会话日志已导出', StatusOverlayTone.success);
    }
  }

  /// 删除：确认框 → 删文件 → toast；sheet 列表不自动刷新（form_sheet
  /// 装载语义：重新打开 sheet 才重载——成本可接受，避免 builder 重入
  /// 复杂度）。
  Future<void> _delete(BuildContext context) async {
    final confirmed = await showConfirmDialog(
      context: context,
      title: '删除会话日志',
      message: '删除 ${entry.fileName} 的本次连接记录？',
      confirmLabel: '删除',
    );
    if (confirmed != true) {
      return;
    }
    final store = await ObdSessionLogStore.production();
    await store.delete(entry.fileName);
    if (context.mounted) {
      showStatusOverlay(context, '已删除', StatusOverlayTone.success);
    }
  }
}
