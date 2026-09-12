// app_shell 域 widget 测试（共享夹具见 test/helpers/widget_app.dart）。
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
    // LunioPage 是 CustomScrollView + SliverPadding 结构，页面级
    // padding 断言查 SliverPadding。
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


  testWidgets('长表单触顶时键盘弹出把 sheet 底边抬到键盘上方', (tester) async {
    // 固定逻辑分辨率，几何断言不受宿主默认窗口影响。
    tester.view.devicePixelRatio = 3.0;
    tester.view.physicalSize = const Size(1170, 2532);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const screenHeight = 844.0;
    // FakeViewPadding 单位是物理像素：900 物理 @ dpr 3 = 300 逻辑。
    const keyboardLogical = 300.0;
    const keyboardPhysical = 900.0;

    Widget buildHost() => MaterialApp(
      theme: buildLunioTheme(),
      home: Scaffold(
        body: Center(
          child: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showLunioModalSheet<void>(
                context: context,
                builder: (sheetContext) => PrototypeSheetFrame(
                  title: '编辑保养记录',
                  // 真实接缝：与各表单 sheet 一致，从 sheet 自己的
                  // context 读键盘高度（dialog 路由内 viewInsets 可见）。
                  bottomInset: MediaQuery.of(sheetContext).viewInsets.bottom,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    // 20 × 80 = 1600 远超屏高，保证内容触顶。
                    children: [
                      for (var i = 0; i < 20; i++) const SizedBox(height: 80),
                    ],
                  ),
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

    // 无键盘：长表单触顶 = 整屏高（宿主无顶部安全区），底边贴屏幕底。
    // 注意 PrototypeSheetFrame 的渲染盒含外侧键盘预留，量不到表面底边；
    // sheet 表面（Container）与滚动视口等高，用视口矩形度量。
    final scrollRect = tester.getRect(find.byType(SingleChildScrollView));
    expect(scrollRect.bottom, screenHeight);
    expect(scrollRect.height, screenHeight);

    // 键盘弹出：sheet 底边 = 键盘顶边，高度同步收缩为可用高度，滚动
    // 视口完整落在键盘上方（回归锁定：此前键盘预留垫在滚动内容内部，
    // 触顶后视口下半截被键盘盖住，底部输入框点了也看不见）。
    tester.view.viewInsets = const FakeViewPadding(bottom: keyboardPhysical);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();

    final usableHeight = screenHeight - keyboardLogical;
    final liftedScrollRect = tester.getRect(find.byType(SingleChildScrollView));
    expect(liftedScrollRect.bottom, usableHeight);
    expect(liftedScrollRect.height, usableHeight);
  });


  testWidgets('无键盘时 sheet 贴住屏幕底边，键盘弹出才抬升', (tester) async {
    tester.view.devicePixelRatio = 3.0;
    tester.view.physicalSize = const Size(1170, 2532);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const screenHeight = 844.0;
    const safeBottom = 34.0;
    const keyboardLogical = 300.0;
    // FakeViewPadding 单位是物理像素：900 物理 @ dpr 3 = 300 逻辑。
    const keyboardPhysical = 900.0;

    Widget buildHost() => MaterialApp(
      theme: buildLunioTheme(),
      // 通过 MaterialApp.builder 注入底部安全区：路由子树（含弹层）
      // 从这里继承 MediaQuery，模拟全面屏 Home 横条。
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(padding: EdgeInsets.only(bottom: safeBottom)),
        child: child!,
      ),
      home: Scaffold(
        body: Center(
          child: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showLunioModalSheet<void>(
                context: context,
                builder: (sheetContext) => PrototypeSheetFrame(
                  title: '更新里程',
                  bottomInset: MediaQuery.of(sheetContext).viewInsets.bottom,
                  child: const SizedBox(height: 40),
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

    // 无键盘：sheet 贴住屏幕底边，不因安全区悬空（回归锁定：键盘抬升
    // 方案初版把安全区也垫到容器外侧，无键盘时底部空出一条 Home 横条
    // 高度的缝，用户报告）。
    expect(
      tester.getRect(find.byType(SingleChildScrollView)).bottom,
      screenHeight,
    );

    // 键盘弹出：底边抬到键盘顶边；安全区被键盘覆盖后不再重复垫。
    tester.view.viewInsets = const FakeViewPadding(bottom: keyboardPhysical);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();

    expect(
      tester.getRect(find.byType(SingleChildScrollView)).bottom,
      screenHeight - keyboardLogical,
    );
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

  testWidgets('编辑表单（barrierDismissible=false）遮罩/下滑/返回都关不掉', (
    tester,
  ) async {
    Widget buildHost() => MaterialApp(
      theme: buildLunioTheme(),
      home: Scaffold(
        body: Center(
          child: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showLunioModalSheet<void>(
                context: context,
                barrierDismissible: false,
                builder: (sheetContext) => PrototypeSheetFrame(
                  title: '锁定弹窗',
                  child: LunioFormActions(
                    confirmLabel: '确定',
                    onCancel: () => Navigator.of(sheetContext).pop(),
                    onConfirm: () {},
                  ),
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
    expect(find.text('锁定弹窗'), findsOneWidget);

    // 点弹窗外遮罩（sheet 外左上角）：不关。
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(find.text('锁定弹窗'), findsOneWidget);

    // 从标题处下拉拖拽：手势识别器未注册，sheet 不动也不关。
    final titleCenter = tester.getCenter(find.text('锁定弹窗'));
    final dragGesture = await tester.startGesture(titleCenter);
    await dragGesture.moveBy(const Offset(0, 200));
    await tester.pump();
    await dragGesture.up();
    await tester.pumpAndSettle();
    expect(find.text('锁定弹窗'), findsOneWidget);
    expect(tester.getCenter(find.text('锁定弹窗')), titleCenter);

    // maybePop（系统返回键的等价路径，PopScope canPop=false）：不关。
    await tester.state<NavigatorState>(
      find.byType(Navigator),
    ).maybePop();
    await tester.pumpAndSettle();
    expect(find.text('锁定弹窗'), findsOneWidget);

    // 点取消按钮：唯一出口。
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('锁定弹窗'), findsNothing);
  });
}
