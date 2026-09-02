// 弹层与瞬时反馈工具（≈ 前端项目的 Modal/Toast 封装）。
//
// 提供四类原语，全部页面统一走这里：
//  - showLunioModalSheet：底部 sheet（全屏路由式对话框 + 毛玻璃底 + 淡入；
//    支持下滑关闭：内容在滚动顶部时下拉，整块 sheet 跟手，松手过阈值/有
//    速度即关闭）
//  - showLunioDialog / showConfirmDialog / showMessageDialog：居中对话框
//    （确认框返回 bool?，点取消 false、点确认 true、点遮罩关闭 null）
//  - showStatusOverlay：页面内容区轻量 toast（Overlay 实现，1.6s 自动消失；
//    这是产品约定的瞬时成功反馈，替代系统 SnackBar）
//  - dismissTransientUi：切 tab 时统一收起键盘/toast/snackbar
//
// 弹窗内点击非输入框区域统一收起键盘（不关弹窗）；点弹窗外遮罩区仍是
// 直接关闭整个弹窗（无未保存确认，产品决策）。
//
// 实现：自绘 showGeneralDialog + BackdropFilter 毛玻璃（不是系统
// showModalBottomSheet），保证三端观感一致。
// ignore_for_file: use_key_in_widget_constructors, library_private_types_in_public_api

import 'dart:async';
import 'dart:math' as math;
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
        child: FractionallySizedBox(
          widthFactor: 1,
          child: _SheetDragDismiss(
            dismissible: barrierDismissible,
            child: child,
          ),
        ),
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

/// 内容对齐容器：GestureDetector 挡住点击事件，
/// 防止点内容区触发底层的"点击空白关闭"；
/// 同时把点在非输入框上的点击用来收起键盘（键盘不自动收的产品决策，
/// 由这里统一兜住，数字键盘/全键盘行为一致）。
class _LunioModalContent extends StatelessWidget {
  const _LunioModalContent({required this.alignment, required this.child});

  final AlignmentGeometry alignment;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: GestureDetector(
        // 输入框、按钮等自身会吃掉点击，走不到这里；能走到这里的
        // 都是"点空白"，收键盘即可（不关弹窗）。
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: child,
      ),
    );
  }
}

/// 底部 sheet 的下滑关闭手势层。
///
/// 实现（Java 类比：两种事件源，谁先抢到事件谁处理，互不重复）：
///  1. 内容可滚时（表单内容超过一屏）：内部滚动容器（PrototypeSheetFrame
///     的 SingleChildScrollView）的手势识别器在竞技场里先赢，拖动交给它；
///     当内容已滚到顶部仍继续下拉，内部产生"出界滚动"
///     （OverscrollNotification，overscroll < 0），监听通知把出界距离累加成
///     sheet 的下移量，sheet 跟手；已拖出后上推（overscroll > 0）则往回收。
///  2. 内容收缩不满一屏时（多数短表单）：Flutter 对 min=max=0 的滚动容器
///     不装拖拽识别器（canDrag=false，出界通知也不会有），此时外层自己的
///     onVerticalDrag 手势是竞技场里唯一的纵向拖拽成员，必然胜出，同样把
///     手指位移累加到 sheet 下移量上。
/// 松手（两条通道各自的手势结束点）时：下移量超过 1/4 sheet 高度、或下滑
/// 速度够快 → pop 关闭；否则动画弹回原位。
class _SheetDragDismiss extends StatefulWidget {
  const _SheetDragDismiss({required this.dismissible, required this.child});

  /// 与 showLunioModalSheet 的 barrierDismissible 同源：遮罩点击不可关时，
  /// 下滑也不可关，两类"关闭"语义保持一致。
  final bool dismissible;
  final Widget child;

  @override
  State<_SheetDragDismiss> createState() => _SheetDragDismissState();
}

class _SheetDragDismissState extends State<_SheetDragDismiss>
    with SingleTickerProviderStateMixin {
  /// 当前 sheet 被拖下来的距离（0 = 原位）。
  double _dragOffset = 0;

  /// 拖了但没过阈值时，把 sheet 弹回原位的动画。
  AnimationController? _resetController;

  /// 判定"拖够远了"的最小距离下限：sheet 很矮时按 80px 计，
  /// 避免轻碰就关。
  static const double _minDismissDistance = 80;

  /// 判定"有意关闭"的最小下滑速度（逻辑像素/秒）。
  static const double _dismissVelocity = 700;

  @override
  void dispose() {
    _resetController?.dispose();
    super.dispose();
  }

  // ---- 通道 1：内容可滚时的出界滚动通知 ----

  bool _onNotification(ScrollNotification notification) {
    if (!widget.dismissible) {
      return false;
    }
    // 只关心纵向滚动；横向滚动（如未来可能的一行多胶囊横滑）的出界
    // 方向符号与纵向无关，不能拿来拖 sheet。
    if (notification.metrics.axis != Axis.vertical) {
      return false;
    }
    if (notification is OverscrollNotification) {
      _applyDragDelta(-notification.overscroll);
    } else if (notification is ScrollEndNotification && _dragOffset > 0) {
      _onDragSettled(notification.dragDetails?.velocity.pixelsPerSecond.dy ?? 0);
    }
    return false;
  }

  // ---- 通道 2：内容收缩时的外层拖拽手势 ----
  // 内容不可滚时内部没有识别器，这里独占手势；内容可滚时内部识别器
  // 先注册进竞技场会赢，这里的回调根本不会触发，因此两条通道互斥。

  void _onManualDragUpdate(DragUpdateDetails details) {
    if (_dragOffset == 0 && details.delta.dy <= 0) {
      // 原位时向上拖没有"关弹窗"语义，直接忽略。
      return;
    }
    _applyDragDelta(details.delta.dy);
  }

  void _onManualDragEnd(DragEndDetails details) {
    if (_dragOffset <= 0) {
      return;
    }
    _onDragSettled(details.velocity.pixelsPerSecond.dy);
  }

  // ---- 两条通道共用的下移量计算与关闭判定 ----

  /// 把手指位移累加到 sheet 下移量上（delta > 0 = 向下拖）。
  void _applyDragDelta(double delta) {
    // 回弹动画进行中又拖动：先停动画，避免动画监听和手势同时改下移量。
    _resetController?.stop();
    if (_dragOffset == 0 && delta > 0) {
      // 第一次拖动时顺手收键盘，避免键盘高度变化和拖动叠加造成跳动。
      FocusManager.instance.primaryFocus?.unfocus();
    }
    setState(() {
      _dragOffset = math.max(0, math.min(_dragOffset + delta, _maxDrag()));
    });
  }

  /// 拖动停止（通知通道：ScrollEnd；手势通道：onDragEnd）时判定关闭或弹回。
  void _onDragSettled(double downwardVelocity) {
    if (_dragOffset > _dismissThreshold() ||
        downwardVelocity > _dismissVelocity) {
      Navigator.of(context).maybePop();
    } else {
      _animateBack();
    }
  }

  /// 关闭阈值：sheet 高度的 1/4（不低于 [_minDismissDistance]）。
  double _dismissThreshold() {
    final height = context.size?.height ?? 0;
    return math.max(height * 0.25, _minDismissDistance);
  }

  /// 拖动距离上限：按屏幕高度的 70% 算而不是 sheet 自身高度——
  /// 矮 sheet（贴内容收缩）若按自身高度限制，会被卡在关闭阈值以内，
  /// 拖了也关不掉。
  double _maxDrag() {
    final screenHeight = MediaQuery.sizeOf(context).height;
    return screenHeight * 0.7;
  }

  /// 未达关闭条件时，180ms 内把 sheet 弹回原位（与弹窗淡入时长一致）。
  void _animateBack() {
    _resetController?.dispose();
    final controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
      value: _dragOffset,
    );
    _resetController = controller;
    // 从当前拖动距离补间回 0。
    final animation = Tween<double>(
      begin: _dragOffset,
      end: 0,
    ).animate(CurvedAnimation(parent: controller, curve: Curves.easeOutCubic));
    controller.addListener(() {
      if (mounted) {
        setState(() => _dragOffset = animation.value);
      }
    });
    controller.forward();
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: _onNotification,
      child: GestureDetector(
        // 只声明纵向拖拽回调，不抢占点击；dismissible=false 时传 null，
        // 识别器不注册，手势层完全透明。
        onVerticalDragUpdate: widget.dismissible ? _onManualDragUpdate : null,
        onVerticalDragEnd: widget.dismissible ? _onManualDragEnd : null,
        child: Transform.translate(
          offset: Offset(0, _dragOffset),
          child: widget.child,
        ),
      ),
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
