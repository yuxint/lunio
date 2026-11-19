// OBD 会话日志列表 sheet（2026-11-18 拍板）：调试终端的「会话日志」
// 入口行打开；列表 = 会话文件（连接建立时刻命名）+ 读数条数 + 导出/
// 删除。只读+按钮动作 sheet → showLunioModalSheet 只读出口（点遮罩/
// 下滑/返回键三路可关，2026-11-19 拍板；此前误走编辑类出口且无关闭
// 按钮，用户没有任何关闭途径——深审发现的唯一违规）。
import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/platform/native_files.dart';
import '../../../core/theme/lunio_tokens.dart';
import '../../../core/widgets/lunio_components.dart';
import '../shared/shell_shared.dart';
import 'obd_session_log.dart';

/// 打开会话日志列表 sheet：装载失败 toast（与 form_sheet 装载语义同
/// 源：sheet 不出现、错误轻提示）。[currentRecordingFileName] = 当前
/// 正在记录的会话文件名（页面从 sink 取）：该条目显示「正在记录」并
/// 禁用删除（删除路径与 recorder 追加写并发会破坏文件与句柄）。
Future<void> showObdSessionLogSheet(
  BuildContext context, {
  String? currentRecordingFileName,
}) async {
  final List<ObdSessionLogEntry> entries;
  try {
    final store = await ObdSessionLogStore.production();
    entries = await store.list();
  } catch (_) {
    if (context.mounted) {
      showStatusOverlay(context, '装载失败', StatusOverlayTone.error);
      }
    return;
  }
  if (!context.mounted) {
    return;
  }
  await showLunioModalSheet<void>(
    context: context,
    builder: (sheetContext) => PrototypeSheetFrame(
      title: '会话日志',
      child: entries.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: LunioEmptyCard('暂无会话日志'),
            )
          : Column(
              children: [
                for (final entry in entries) ...[
                  _SessionLogTile(
                    entry: entry,
                    isCurrent: entry.fileName == currentRecordingFileName,
                  ),
                  const SizedBox(height: 10),
                ],
                SizedBox(height: MediaQuery.of(sheetContext).padding.bottom),
              ],
            ),
    ),
  );
}

/// 单个会话日志文件条目：名称 + 条数/大小 + 导出/删除。
class _SessionLogTile extends StatelessWidget {
  const _SessionLogTile({required this.entry, required this.isCurrent});

  final ObdSessionLogEntry entry;
  final bool isCurrent;

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
                  isCurrent
                      ? '${entry.lineCount} 条记录 · '
                          '${(entry.bytes / 1024).toStringAsFixed(1)} KB · 正在记录'
                      : '${entry.lineCount} 条记录 · '
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
            tooltip: isCurrent ? '正在记录，不可删除' : '删除',
            onPressed: isCurrent ? null : () => unawaited(_delete(context)),
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
