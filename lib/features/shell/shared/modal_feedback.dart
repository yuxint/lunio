// ignore_for_file: use_key_in_widget_constructors, library_private_types_in_public_api

import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../core/theme/lunio_tokens.dart';
import '../../../core/widgets/lunio_components.dart';

Future<T?> showLunioModalSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  bool showDragHandle = false,
  Color? backgroundColor,
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
          child: backgroundColor == Colors.transparent
              ? child
              : _LunioDefaultSheetSurface(
                  showDragHandle: showDragHandle,
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

class _LunioDefaultSheetSurface extends StatelessWidget {
  const _LunioDefaultSheetSurface({
    required this.showDragHandle,
    required this.child,
  });

  final bool showDragHandle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    return Container(
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(tokens.radiusXl),
        ),
        boxShadow: [
          BoxShadow(
            color: tokens.ink.withValues(alpha: 0.18),
            blurRadius: 54,
            offset: const Offset(0, -20),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showDragHandle) ...[
            const SizedBox(height: 8),
            Container(
              width: 48,
              height: 5,
              decoration: BoxDecoration(
                color: tokens.line,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 8),
          ],
          child,
        ],
      ),
    );
  }
}

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

void dismissTransientUi(BuildContext context) {
  FocusManager.instance.primaryFocus?.unfocus();
  hideStatusOverlay();
  ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
}

enum StatusOverlayTone { success, error, info }

OverlayEntry? _statusOverlayEntry;

void hideStatusOverlay() {
  _statusOverlayEntry?.remove();
  _statusOverlayEntry = null;
}

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

Color statusToneColor(LunioTokens tokens, StatusOverlayTone tone) {
  return switch (tone) {
    StatusOverlayTone.success => tokens.success,
    StatusOverlayTone.error => tokens.danger,
    StatusOverlayTone.info => tokens.primary,
  };
}

IconData statusToneIcon(StatusOverlayTone tone) {
  return switch (tone) {
    StatusOverlayTone.success => Icons.check_circle_outline,
    StatusOverlayTone.error => Icons.error_outline,
    StatusOverlayTone.info => Icons.info_outline,
  };
}
