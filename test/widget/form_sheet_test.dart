// 表单 sheet 运行时（showLunioFormSheet / FormSheetHandle，ADR 0016）
// 的模块级 widget 测试。
//
// 不走完整 App 夹具（pumpApp）：运行时只依赖 MaterialApp 环境（导航、
// Overlay、主题），每条用例经页面上一颗按钮触发用例自带的入口闭包，
// 验证装载失败/守卫拦截/提交成败/关场去重/结果透传/头部切换这些运行时
// 契约。各页面表单本身的行为由 widget/records、fuel 等域测试覆盖。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lunio/core/theme/lunio_theme.dart';
import 'package:lunio/features/shell/shared/form_sheet.dart';

void main() {
  /// 夹具：页面上一颗"open"按钮（触发用例注入的入口闭包）+ 页面标记
  /// 文本。页面标记兼作"底层页面还在"的观察点（关场过度会把 home 也
  /// pop 掉，标记消失）。
  Future<void> pumpHost(
    WidgetTester tester, {
    required Future<void> Function(BuildContext context) onOpen,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildLunioTheme(),
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('页面标记'),
                Builder(
                  builder: (context) => TextButton(
                    onPressed: () => onOpen(context),
                    child: const Text('open'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// 打开 sheet 的按钮点击 + 等动画收尾。
  Future<void> openSheet(WidgetTester tester) async {
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  /// 提交成功的成功文案 toast 有 1.6s 定时器，用例结束前泵过去，
  /// 避免报 pending timer。
  Future<void> drainToastTimer(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 1700));
  }

  testWidgets('load 失败：friendlyError toast 且 sheet 不出现', (tester) async {
    await pumpHost(
      tester,
      onOpen: (context) => showLunioFormSheet<void>(
        context: context,
        title: '测试表单',
        load: (handle) async => throw Exception('boom'),
        builder: (sheetContext, handle) => const Text('表单内容'),
        successMessage: '已保存',
      ),
    );
    await openSheet(tester);

    expect(find.text('表单内容'), findsNothing);
    expect(find.text('操作失败，请稍后重试'), findsOneWidget);
    await drainToastTimer(tester);
  });

  testWidgets('guard 拦截：info toast 且 sheet 不出现', (tester) async {
    await pumpHost(
      tester,
      onOpen: (context) => showLunioFormSheet<void>(
        context: context,
        title: '测试表单',
        guard: () => '请先新增车辆',
        builder: (sheetContext, handle) => const Text('表单内容'),
        successMessage: '已保存',
      ),
    );
    await openSheet(tester);

    expect(find.text('表单内容'), findsNothing);
    expect(find.text('请先新增车辆'), findsOneWidget);
    await drainToastTimer(tester);
  });

  testWidgets('提交失败：行内错误且 sheet 留场', (tester) async {
    await pumpHost(
      tester,
      onOpen: (context) => showLunioFormSheet<void>(
        context: context,
        title: '测试表单',
        // 错误行渲染归表单侧（ADR 0016 共识：module 只写 errorText），
        // 这里照真实表单的接法渲染把手上的错误文案。
        builder: (sheetContext, handle) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (handle.errorText != null) Text('错误：${handle.errorText}'),
            TextButton(
              onPressed: () => handle.submit(() async => throw Exception('boom')),
              child: const Text('save'),
            ),
          ],
        ),
        successMessage: '已保存',
      ),
    );
    await openSheet(tester);

    await tester.tap(find.text('save'));
    await tester.pumpAndSettle();

    expect(find.text('错误：操作失败，请稍后重试'), findsOneWidget);
    expect(find.text('测试表单'), findsOneWidget);
  });

  testWidgets('提交成功：关 sheet 并显示成功 toast', (tester) async {
    await pumpHost(
      tester,
      onOpen: (context) => showLunioFormSheet<void>(
        context: context,
        title: '测试表单',
        builder: (sheetContext, handle) => TextButton(
          onPressed: () => handle.submit(() async {}),
          child: const Text('save'),
        ),
        successMessage: '已保存',
      ),
    );
    await openSheet(tester);

    await tester.tap(find.text('save'));
    await tester.pumpAndSettle();

    expect(find.text('测试表单'), findsNothing);
    expect(find.text('已保存'), findsOneWidget);
    expect(find.text('页面标记'), findsOneWidget);
    await drainToastTimer(tester);
  });

  testWidgets('提交成功透传 resultOnSubmit 给入口 Future', (tester) async {
    bool? entryResult;
    await pumpHost(tester, onOpen: (context) async {
      entryResult = await showLunioFormSheet<bool>(
        context: context,
        title: '测试表单',
        builder: (sheetContext, handle) => TextButton(
          onPressed: () => handle.submit(() async {}),
          child: const Text('save'),
        ),
        resultOnSubmit: true,
        successMessage: '已保存',
      );
    });
    await openSheet(tester);

    await tester.tap(find.text('save'));
    await tester.pumpAndSettle();

    expect(entryResult, isTrue);
    expect(find.text('测试表单'), findsNothing);
    await drainToastTimer(tester);
  });

  testWidgets('barrierDismissible 固定 false：点遮罩不关 sheet', (tester) async {
    await pumpHost(
      tester,
      onOpen: (context) => showLunioFormSheet<void>(
        context: context,
        title: '测试表单',
        builder: (sheetContext, handle) => const Text('表单内容'),
        successMessage: '已保存',
      ),
    );
    await openSheet(tester);

    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    expect(find.text('测试表单'), findsOneWidget);
  });

  testWidgets('setFrame / setSubtitle 换头部', (tester) async {
    FormSheetHandle<void>? captured;
    await pumpHost(tester, onOpen: (context) {
      return showLunioFormSheet<void>(
        context: context,
        title: '添加车辆',
        builder: (sheetContext, handle) {
          captured = handle;
          return TextButton(
            onPressed: () => handle.setFrame(
              title: '保养项目',
              subtitle: '以下保养项目只做参考',
            ),
            child: const Text('switch'),
          );
        },
        successMessage: '已保存',
      );
    });
    await openSheet(tester);

    await tester.tap(find.text('switch'));
    await tester.pump();

    expect(find.text('保养项目'), findsOneWidget);
    expect(find.text('以下保养项目只做参考'), findsOneWidget);

    // 换回第一步：subtitle 传 null 表示清掉副标题。
    captured!.setFrame(title: '添加车辆', subtitle: null);
    await tester.pump();

    expect(find.text('添加车辆'), findsOneWidget);
    expect(find.text('以下保养项目只做参考'), findsNothing);

    // 装载后补副标题（setSubtitle 只动副标题）。
    captured!.setSubtitle('大众 速腾');
    await tester.pump();

    expect(find.text('大众 速腾'), findsOneWidget);
    expect(find.text('添加车辆'), findsOneWidget);
  });

  testWidgets('close 带 toast：非提交出口', (tester) async {
    FormSheetHandle<void>? captured;
    await pumpHost(tester, onOpen: (context) {
      return showLunioFormSheet<void>(
        context: context,
        title: '测试表单',
        builder: (sheetContext, handle) {
          captured = handle;
          return TextButton(
            onPressed: () => handle.close(toast: '加油记录已删除'),
            child: const Text('exit'),
          );
        },
        successMessage: '已保存',
      );
    });
    await openSheet(tester);

    captured!.close(toast: '加油记录已删除');
    await tester.pumpAndSettle();

    expect(find.text('测试表单'), findsNothing);
    expect(find.text('加油记录已删除'), findsOneWidget);
    await drainToastTimer(tester);
  });

  testWidgets('pop 过一次后再来的 submit/close 一律忽略', (tester) async {
    FormSheetHandle<void>? captured;
    await pumpHost(tester, onOpen: (context) {
      return showLunioFormSheet<void>(
        context: context,
        title: '测试表单',
        builder: (sheetContext, handle) {
          captured = handle;
          return TextButton(
            onPressed: () => handle.close(),
            child: const Text('exit'),
          );
        },
        successMessage: '已保存',
      );
    });
    await openSheet(tester);

    captured!.close();
    await tester.pumpAndSettle();
    expect(find.text('测试表单'), findsNothing);

    // 已关场：再 submit/close 都不应触发第二次 pop（否则会把 home 也
    // 关掉，"页面标记"随之消失）。
    await captured!.submit(() async {});
    captured!.close();
    await tester.pumpAndSettle();

    expect(find.text('页面标记'), findsOneWidget);
    expect(find.text('已保存'), findsNothing);
  });

  testWidgets('saving 期间的重复 submit 被忽略', (tester) async {
    final blocker = Completer<void>();
    var secondActionRan = false;
    FormSheetHandle<void>? captured;
    await pumpHost(tester, onOpen: (context) {
      return showLunioFormSheet<void>(
        context: context,
        title: '测试表单',
        builder: (sheetContext, handle) {
          captured = handle;
          return TextButton(
            onPressed: () => handle.submit(() => blocker.future),
            child: const Text('save'),
          );
        },
        successMessage: '已保存',
      );
    });
    await openSheet(tester);

    // 第一次提交挂起（Completer 未完成），第二次 submit 应被忽略。
    await tester.tap(find.text('save'));
    await tester.pump();
    await captured!.submit(() async => secondActionRan = true);
    expect(secondActionRan, isFalse);

    blocker.complete();
    await tester.pumpAndSettle();
    expect(find.text('测试表单'), findsNothing);
    await drainToastTimer(tester);
  });
}
