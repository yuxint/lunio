// app_shell 域 widget 测试（自原 widget_test.dart 按页面域拆分，
// 共享夹具见 test/helpers/widget_app.dart）。
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lunio/core/theme/lunio_theme.dart';
import 'package:lunio/features/shell/shared/modal_feedback.dart';
import 'package:lunio/features/shell/shared/shared_widgets.dart';

import '../helpers/widget_app.dart';

void main() {
  testWidgets('app shell exposes three main entries', (tester) async {
    await pumpApp(tester);

    expect(find.text('保养提醒'), findsWidgets);
    expect(find.text('还没有车辆'), findsOneWidget);
    expect(find.text('提醒'), findsOneWidget);
    expect(find.text('记录'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);
  });


  testWidgets('bottom navigation clears Android three-button inset', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      const systemNavigationHeight = 48.0;
      mockNativeSystemUi(
        navigationMode: 0,
        navigationBarHeight: systemNavigationHeight,
      );

      await pumpApp(tester);

      expect(
        bottomNavigationShellPadding(tester).bottom,
        12 + systemNavigationHeight,
      );
      final screenHeight =
          tester.view.physicalSize.height / tester.view.devicePixelRatio;
      final systemNavigationTop = screenHeight - systemNavigationHeight;

      expect(
        tester.getBottomLeft(find.text('我的')).dy,
        lessThanOrEqualTo(systemNavigationTop),
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });


  testWidgets('bottom navigation stays put for Android gesture navigation', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      mockNativeSystemUi(navigationMode: 2, navigationBarHeight: 24);
      await pumpApp(tester);

      expect(bottomNavigationShellPadding(tester).bottom, 12);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });


  testWidgets('bottom navigation stays put for iOS bottom safe area', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    var invokedNativeSystemUi = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(nativeSystemUiChannel, (call) async {
          invokedNativeSystemUi = true;
          return null;
        });
    try {
      await pumpApp(tester);

      expect(bottomNavigationShellPadding(tester).bottom, 12);
      expect(invokedNativeSystemUi, isFalse);
    } finally {
      debugDefaultTargetPlatformOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(nativeSystemUiChannel, null);
    }
  });


  testWidgets('bottom navigation switches primary tabs', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('记录'));
    await pumpUntilFound(tester, find.text('保养记录'));
    expect(find.text('保养记录'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);

    await tester.tap(find.text('我的'));
    await pumpUntilFound(tester, find.text('个人中心'));
    expect(find.text('个人中心'), findsOneWidget);
    // LunioPage 现为 CustomScrollView + SliverPadding（R25），页面级
    // padding 断言改查 SliverPadding。
    final profilePadding = tester.widget<SliverPadding>(
      find.byType(SliverPadding).first,
    );
    expect(profilePadding.padding, const EdgeInsets.fromLTRB(18, 2, 18, 72));
  });


  testWidgets('theme switch stays on profile without success feedback', (
    tester,
  ) async {
    await pumpApp(tester);

    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('深色'));
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('个人中心'), findsOneWidget);
    expect(find.text('主题已切换'), findsNothing);
  });


  testWidgets('theme switch ignores the current option', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('跟随系统'));
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('个人中心'), findsOneWidget);
    expect(find.text('主题已切换'), findsNothing);
  });


  testWidgets('destructive confirm dialog uses red confirm action', (
    tester,
  ) async {
    await pumpApp(tester);
    await createDefaultCar(tester);

    await tester.tap(find.widgetWithText(TextButton, '删除').first);
    await tester.pumpAndSettle();

    expect(find.byType(BackdropFilter), findsOneWidget);
    final deleteButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '删除'),
    );
    final background = deleteButton.style?.backgroundColor?.resolve({});
    expect(background, const Color(0xffef4444));

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('删除车辆'), findsNothing);
  });


  testWidgets('sheet 骨架按底部安全区抬高内容，键盘不叠加预留', (tester) async {
    Widget wrapSheet({double safeBottom = 0, double keyboardInset = 0}) =>
        MaterialApp(
          theme: buildLunioTheme(),
          // 真实弹窗链路里外层是松约束（sheet 贴内容收缩），这里用 Center
          // 复现：否则紧约束下滚动容器撑满全屏，量不到高度差。
          home: Center(
            child: Builder(
              builder: (context) => MediaQuery(
                // 模拟全面屏底部安全区（Home 横条/屏幕圆角），iPhone 常见约 34。
                data: MediaQuery.of(
                  context,
                ).copyWith(padding: EdgeInsets.only(bottom: safeBottom)),
                child: PrototypeSheetFrame(
                  title: '选择油品',
                  bottomInset: keyboardInset,
                  child: const SizedBox(height: 40),
                ),
              ),
            ),
          ),
        );
    double frameHeight() =>
        tester.getRect(find.byType(PrototypeSheetFrame)).height;

    // 基准：无安全区、无键盘。
    await tester.pumpWidget(wrapSheet());
    final baseHeight = frameHeight();

    // 有安全区：总高度比基准多 34，内容被抬离屏幕圆角区。
    await tester.pumpWidget(wrapSheet(safeBottom: 34));
    expect(frameHeight(), baseHeight + 34);

    // 键盘高度(300)高于安全区时取较大值，只多 300 而不是 334（不叠加）。
    await tester.pumpWidget(wrapSheet(safeBottom: 34, keyboardInset: 300));
    expect(frameHeight(), baseHeight + 300);
  });


  testWidgets('底部 sheet 下拉整块跟手，松手过阈值关闭', (tester) async {
    Widget buildHost(WidgetBuilder sheetBuilder) => MaterialApp(
      theme: buildLunioTheme(),
      home: Scaffold(
        body: Center(
          child: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showLunioModalSheet<void>(
                context: context,
                builder: sheetBuilder,
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpWidget(
      buildHost(
        (context) => PrototypeSheetFrame(
          title: '测试弹窗',
          child: const SizedBox(height: 40),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.text('测试弹窗'), findsOneWidget);

    // 在标题处下拉 180px（分步发指针事件，滚动识别器需要帧间隔才认领
    // 手势；内容无滚动余地，出界距离直接变成 sheet 下移量），松手后远超
    // 关闭阈值（矮 sheet 阈值按 80px 下限计）。
    final titleCenter = tester.getCenter(find.text('测试弹窗'));
    final gesture = await tester.startGesture(titleCenter);
    await gesture.moveBy(const Offset(0, 60));
    await tester.pump();
    await gesture.moveBy(const Offset(0, 120));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('测试弹窗'), findsNothing);
  });


  testWidgets('点弹窗内非输入框区域收起键盘但不关弹窗', (tester) async {
    final focusNode = FocusNode();
    Widget buildHost() => MaterialApp(
      theme: buildLunioTheme(),
      home: Scaffold(
        body: Center(
          child: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showLunioModalSheet<void>(
                context: context,
                builder: (context) => PrototypeSheetFrame(
                  title: '输入弹窗',
                  child: TextField(focusNode: focusNode),
                ),
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpWidget(buildHost());
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(focusNode.hasFocus, isTrue);

    // 点标题（非输入框）：键盘收起，弹窗保持打开。
    await tester.tap(find.text('输入弹窗'));
    await tester.pump();
    expect(focusNode.hasFocus, isFalse);
    expect(find.text('输入弹窗'), findsOneWidget);
  });


  testWidgets('内容超一屏的 sheet：向上拖正常滚动，顶部下拉拖关', (tester) async {
    Widget buildHost() => MaterialApp(
      theme: buildLunioTheme(),
      home: Scaffold(
        body: Center(
          child: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showLunioModalSheet<void>(
                context: context,
                builder: (context) => PrototypeSheetFrame(
                  title: '长内容弹窗',
                  child: Container(color: Colors.teal, height: 1200),
                ),
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpWidget(buildHost());
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    // 内容超一屏：内部滚动容器可滚，向上拖应正常滚内容（标题上移），
    // 而不是把 sheet 拖走。
    final titleCenter = tester.getCenter(find.text('长内容弹窗'));
    final scrollGesture = await tester.startGesture(titleCenter);
    await scrollGesture.moveBy(const Offset(0, -60));
    await tester.pump();
    await scrollGesture.moveBy(const Offset(0, -120));
    await tester.pump();
    await scrollGesture.up();
    await tester.pumpAndSettle();
    expect(find.text('长内容弹窗'), findsOneWidget);
    final scrolledDy = tester.getTopLeft(find.text('长内容弹窗')).dy;
    expect(scrolledDy, lessThan(titleCenter.dy - 100));

    // 滚回顶部后下拉：内部出界滚动转成 sheet 跟手，松手过阈值关闭。
    final backGesture = await tester.startGesture(titleCenter);
    await backGesture.moveBy(const Offset(0, 60));
    await tester.pump();
    await backGesture.moveBy(const Offset(0, 300));
    await tester.pump();
    await backGesture.up();
    await tester.pumpAndSettle();
    expect(find.text('长内容弹窗'), findsNothing);
  });
}
