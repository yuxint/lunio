// 弹层与瞬时反馈工具（≈ 前端项目的 Modal/Toast 封装）。
//
// 提供四类原语，全部页面统一走这里：
//  - showLunioModalSheet：底部 sheet（全屏路由式对话框 + 毛玻璃底 + 淡入）
//  - showLunioDialog / showConfirmDialog / showMessageDialog：居中对话框
//    （确认框返回 bool?，点取消 false、点确认 true、点遮罩关闭 null）
//  - showStatusOverlay：页面内容区轻量 toast（Overlay 实现，1.6s 自动消失；
//    这是产品约定的瞬时成功反馈，替代系统 SnackBar）
//  - dismissTransientUi：切 tab 时统一收起键盘/toast/snackbar
//
// 实现：自绘 showGeneralDialog + BackdropFilter 毛玻璃（不是系统
// showModalBottomSheet），保证三端观感一致。
// ignore_for_file: use_key_in_widget_constructors, library_private_types_in_public_api

import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../core/theme/lunio_tokens.dart';
import '../../../core/widgets/lunio_components.dart';

/// 底部 sheet：全屏对话框 + 底部对齐内容。
/// 不再内建白底表面（§5.3.2 收敛后全项目唯一骨架是 PrototypeSheetFrame），
/// 调用方在 builder 里用 PrototypeSheetFrame 自带表面与标题。
Future<T?> showLunioModalSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierColor: Colors.transparent,
    barrierDismissible: false,
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (context, animation, secondaryAnimation) {
      final child = Material(
        type: MaterialType.transparency,
        child: builder(context),
      );
      return _LunioModalBackdrop(
        alignment: Alignment.bottomCenter,
        barrierDismissible: barrierDismissible,
        useSafeArea: false,
        child: FractionallySizedBox(widthFactor: 1, child: child),
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(opacity: animation, child: child);
    },
  );
}

/// 居中对话框：缩放+淡入动画。
Future<T?> showLunioDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierColor: Colors.transparent,
    barrierDismissible: false,
    transitionDuration: const Duration(milliseconds: 160),
    pageBuilder: (context, animation, secondaryAnimation) {
      return _LunioModalBackdrop(
        alignment: Alignment.center,
        barrierDismissible: barrierDismissible,
        useSafeArea: true,
        child: builder(context),
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final scale = Tween<double>(
        begin: 0.98,
        end: 1,
      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));
      return FadeTransition(
        opacity: animation,
        child: ScaleTransition(scale: scale, child: child),
      );
    },
  );
}

/// 毛玻璃背景层：模糊 scrim + 点击空白处关闭（barrierDismissible 时）。
/// useSafeArea 决定是否避开刘海/状态栏（居中对话框要避开，sheet 不用）。
class _LunioModalBackdrop extends StatelessWidget {
  const _LunioModalBackdrop({
    required this.alignment,
    required this.barrierDismissible,
    required this.useSafeArea,
    required this.child,
  });

  final AlignmentGeometry alignment;
  final bool barrierDismissible;
  final bool useSafeArea;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scrimOpacity = isDark ? 0.30 : 0.18;
    return SizedBox.expand(
      child: Stack(
        children: [
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
              child: ColoredBox(
                color: Colors.black.withValues(alpha: scrimOpacity),
              ),
            ),
          ),
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: barrierDismissible
                  ? () => Navigator.of(context).maybePop()
                  : null,
            ),
          ),
          if (useSafeArea)
            SafeArea(
              child: _LunioModalContent(alignment: alignment, child: child),
            )
          else
            _LunioModalContent(alignment: alignment, child: child),
        ],
      ),
    );
  }
}

/// 内容对齐容器：空 GestureDetector 挡住点击事件，
/// 防止点内容区触发底层的"点击空白关闭"。
class _LunioModalContent extends StatelessWidget {
  const _LunioModalContent({required this.alignment, required this.child});

  final AlignmentGeometry alignment;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: GestureDetector(onTap: () {}, child: child),
    );
  }
}

/// 通用确认框：取消/确认双按钮，destructive=true 时确认键为危险红。
/// 返回 true（确认）/false（取消）/null（点遮罩关闭）。
/// 删除记录、删车、清空数据、恢复备份等危险操作都用它。
Future<bool?> showConfirmDialog({
  required BuildContext context,
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = true,
}) {
  return showLunioDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (context) {
      final tokens = Theme.of(context).extension<LunioTokens>()!;
      final confirmColor = destructive ? tokens.danger : tokens.primary;
      return Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        backgroundColor: Colors.transparent,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: tokens.surface,
            borderRadius: BorderRadius.circular(tokens.radiusLarge),
            border: Border.all(color: tokens.line),
            boxShadow: [
              BoxShadow(
                color: tokens.ink.withValues(alpha: 0.16),
                blurRadius: 36,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(message, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: LunioSecondaryButton(
                      label: '取消',
                      onPressed: () => Navigator.of(context).pop(false),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                        backgroundColor: confirmColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            tokens.radiusMedium,
                          ),
                        ),
                      ),
                      onPressed: () => Navigator.of(context).pop(true),
                      child: Text(confirmLabel),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// 单键信息对话框（带语义色图标），如备份恢复冲突提示。
Future<void> showMessageDialog({
  required BuildContext context,
  required String title,
  required String message,
  required StatusOverlayTone tone,
}) {
  return showLunioDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (context) {
      final tokens = Theme.of(context).extension<LunioTokens>()!;
      final toneColor = statusToneColor(tokens, tone);
      return Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        backgroundColor: Colors.transparent,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: tokens.surface,
            borderRadius: BorderRadius.circular(tokens.radiusLarge),
            border: Border.all(color: tokens.line),
            boxShadow: [
              BoxShadow(
                color: tokens.ink.withValues(alpha: 0.16),
                blurRadius: 36,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(statusToneIcon(tone), color: toneColor, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(message, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                    backgroundColor: toneColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(tokens.radiusMedium),
                    ),
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('确认'),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// 收起所有瞬时 UI（键盘焦点、状态 toast、SnackBar）。
/// 底部导航切 tab 时调用，避免残留弹层盖住新页面。
void dismissTransientUi(BuildContext context) {
  FocusManager.instance.primaryFocus?.unfocus();
  hideStatusOverlay();
  ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
}

/// toast 语义色枚举。
enum StatusOverlayTone { success, error, info }

/// 当前显示的 toast（全局单例：新 toast 会先顶掉旧的）。
OverlayEntry? _statusOverlayEntry;

/// 立即隐藏 toast。
void hideStatusOverlay() {
  _statusOverlayEntry?.remove();
  _statusOverlayEntry = null;
}

/// 在页面内容区中央显示轻量 toast（1.6 秒自动消失，点击不拦截）。
/// 成功/失败反馈统一走它，不要用系统 SnackBar。
void showStatusOverlay(
  BuildContext context,
  String message,
  StatusOverlayTone tone,
) {
  final tokens = Theme.of(context).extension<LunioTokens>()!;
  final overlay = Overlay.maybeOf(context);
  if (overlay == null) {
    return;
  }
  hideStatusOverlay();
  final entry = OverlayEntry(
    builder: (context) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: _StatusOverlay(
            message: message,
            tokens: tokens,
            tone: tone,
            onDismiss: hideStatusOverlay,
          ),
        ),
      );
    },
  );
  _statusOverlayEntry = entry;
  overlay.insert(entry);
}

/// toast 卡片本体（1.6s 定时器触发 onDismiss 移除 Overlay）。
class _StatusOverlay extends StatefulWidget {
  const _StatusOverlay({
    required this.message,
    required this.tokens,
    required this.tone,
    required this.onDismiss,
  });

  final String message;
  final LunioTokens tokens;
  final StatusOverlayTone tone;
  final VoidCallback onDismiss;

  @override
  State<_StatusOverlay> createState() => _StatusOverlayState();
}

class _StatusOverlayState extends State<_StatusOverlay> {
  Timer? timer;

  @override
  void initState() {
    super.initState();
    timer = Timer(const Duration(milliseconds: 1600), widget.onDismiss);
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = widget.tokens;
    final toneColor = statusToneColor(tokens, widget.tone);
    return Material(
      color: Colors.transparent,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tokens.surface,
          borderRadius: BorderRadius.circular(tokens.radiusMedium),
          border: Border.all(color: tokens.line),
          boxShadow: [
            BoxShadow(
              color: tokens.ink.withValues(alpha: 0.16),
              blurRadius: 28,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(statusToneIcon(widget.tone), color: toneColor, size: 20),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  widget.message,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: tokens.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// toast 语义色映射。
Color statusToneColor(LunioTokens tokens, StatusOverlayTone tone) {
  return switch (tone) {
    StatusOverlayTone.success => tokens.success,
    StatusOverlayTone.error => tokens.danger,
    StatusOverlayTone.info => tokens.primary,
  };
}

/// toast 图标映射。
IconData statusToneIcon(StatusOverlayTone tone) {
  return switch (tone) {
    StatusOverlayTone.success => Icons.check_circle_outline,
    StatusOverlayTone.error => Icons.error_outline,
    StatusOverlayTone.info => Icons.info_outline,
  };
}
