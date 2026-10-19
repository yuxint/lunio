// 自绘日期选择器（showSimpleDatePicker / SimpleDatePicker）的模块级
// widget 直测。
//
// 四个表单入口（保养记录、加油记录、加车向导、手动日期）共用这一个
// 日期 interface，但控制器单测全部用注入的假选择器绕开它，选择器本体
// 此前只能靠表单级 widget 测试间接碾过——范围钳制错一天、翻页越界、
// 上限今天可点这类日期边界 bug 只能等表单测试偶然撞上。本文件跨
// showSimpleDatePicker 完整 interface 驱动（不直泵 State）：每条用例
// 经宿主按钮真弹 sheet，黑盒断言选值返回、取消/遮罩返回 null、年/月
// 翻页、firstDate/lastDate 钳制与"今天"快捷键这些边界契约。
//
// 不走完整 App 夹具（pumpApp）：选择器只依赖 MaterialApp 环境
// （导航、Overlay、LunioTokens 主题），接法同 form_sheet_test；today
// 一律显式传入固定值——DateTime.now() 在 testWidgets 里不可假
// （FakeAsync 只拦定时器/微任务，不拦墙钟），不传会随真实日期漂移。
// 不覆盖：入口的 today 默认分支（同因墙钟不可假，四个生产入口也只有
// 手动日期设置走默认值）；下滑手势关闭（与点遮罩同属 barrierDismissible
// 契约，点遮罩已覆盖）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lunio/core/date/local_date.dart';
import 'package:lunio/core/theme/lunio_theme.dart';
import 'package:lunio/features/shell/shared/date_picker.dart';

void main() {
  /// 宿主：页面上一颗"open"按钮触发用例注入的入口闭包（form_sheet_test
  /// 同款模式）。视口放大到 800×1200（pumpApp 同款手法）：sheet 高度
  /// 上限是屏高 72%，默认 600 高的测试视口会把日历下缘滚出 sheet 的
  /// 滚动视口、tap 落空。
  Future<void> pumpHost(
    WidgetTester tester, {
    required void Function(BuildContext context) onOpen,
  }) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildLunioTheme(),
        home: Scaffold(
          body: Center(
            child: Builder(
              builder: (context) => TextButton(
                onPressed: () => onOpen(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// 打开选择器并等 sheet 弹出动画收尾。
  Future<void> openPicker(WidgetTester tester) async {
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  /// 点"确定"收场并等关场动画结束，返回入口 Future 供调用方 await 断言。
  Future<LocalDate?> confirmPicker(
    WidgetTester tester,
    Future<LocalDate?>? picked,
  ) async {
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    return picked;
  }

  testWidgets('初始定位：落在初始日期的年月页，直接确定返回原值', (tester) async {
    Future<LocalDate?>? picked;
    await pumpHost(tester, onOpen: (context) {
      picked = showSimpleDatePicker(
        context,
        initialDate: LocalDate(2026, 5, 19),
        firstDate: LocalDate(2026, 1, 1),
        lastDate: LocalDate(2026, 12, 31),
        today: LocalDate(2026, 5, 19),
      );
    });
    await openPicker(tester);

    // sheet 标题 + 头部定位在初始日期的年月。
    expect(find.text('选择日期'), findsOneWidget);
    expect(find.widgetWithText(TextButton, '2026年'), findsOneWidget);
    expect(find.widgetWithText(TextButton, '5月'), findsOneWidget);
    // 周一开头的星期列头 + 5 月 31 天的日历格（含初始日 19）。
    for (final label in ['一', '二', '三', '四', '五', '六', '日']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('19'), findsOneWidget);
    expect(find.text('31'), findsOneWidget);

    expect(await confirmPicker(tester, picked), LocalDate(2026, 5, 19));
  });

  testWidgets('点选新日期后确定：返回所选日期', (tester) async {
    Future<LocalDate?>? picked;
    await pumpHost(tester, onOpen: (context) {
      picked = showSimpleDatePicker(
        context,
        initialDate: LocalDate(2026, 5, 19),
        firstDate: LocalDate(2026, 1, 1),
        lastDate: LocalDate(2026, 12, 31),
        today: LocalDate(2026, 5, 19),
      );
    });
    await openPicker(tester);

    await tester.tap(find.text('15'));
    await tester.pump();
    expect(await confirmPicker(tester, picked), LocalDate(2026, 5, 15));
  });

  testWidgets('取消：入口 Future 以 null 完成', (tester) async {
    Future<LocalDate?>? picked;
    await pumpHost(tester, onOpen: (context) {
      picked = showSimpleDatePicker(
        context,
        initialDate: LocalDate(2026, 5, 19),
        firstDate: LocalDate(2026, 1, 1),
        lastDate: LocalDate(2026, 12, 31),
        today: LocalDate(2026, 5, 19),
      );
    });
    await openPicker(tester);

    // 先改选再取消：改选不应随取消泄漏出去。
    await tester.tap(find.text('10'));
    await tester.pump();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(await picked, isNull);
    expect(find.text('选择日期'), findsNothing);
  });

  testWidgets('点遮罩：选择器 sheet 默认可关，入口 Future 以 null 完成', (
    tester,
  ) async {
    Future<LocalDate?>? picked;
    await pumpHost(tester, onOpen: (context) {
      picked = showSimpleDatePicker(
        context,
        initialDate: LocalDate(2026, 5, 19),
        firstDate: LocalDate(2026, 1, 1),
        lastDate: LocalDate(2026, 12, 31),
        today: LocalDate(2026, 5, 19),
      );
    });
    await openPicker(tester);

    // sheet 底部对齐，左上角必在遮罩区。
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    expect(await picked, isNull);
    expect(find.text('选择日期'), findsNothing);
  });

  testWidgets('上限今天：未来格子点了无效、下月翻页到界、今天按钮在', (
    tester,
  ) async {
    Future<LocalDate?>? picked;
    await pumpHost(tester, onOpen: (context) {
      picked = showSimpleDatePicker(
        context,
        initialDate: LocalDate(2026, 5, 19),
        firstDate: LocalDate(2026, 5, 1),
        lastDate: LocalDate(2026, 5, 19),
        today: LocalDate(2026, 5, 19),
      );
    });
    await openPicker(tester);

    // 范围只有 5-01 ~ 5-19：20 及以后置灰，点了不改选。
    await tester.tap(find.text('20'));
    await tester.pump();
    // 5 月已是上限页：下个月翻页到界不动。
    await tester.tap(find.byTooltip('下个月'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextButton, '5月'), findsOneWidget);
    // today 在范围内 → "今天"快捷键显示。
    expect(find.text('今天'), findsOneWidget);

    expect(await confirmPicker(tester, picked), LocalDate(2026, 5, 19));
  });

  testWidgets('firstDate 钳制：月初之前格子点了无效、上月翻页到界', (
    tester,
  ) async {
    Future<LocalDate?>? picked;
    await pumpHost(tester, onOpen: (context) {
      picked = showSimpleDatePicker(
        context,
        initialDate: LocalDate(2026, 5, 19),
        firstDate: LocalDate(2026, 5, 10),
        lastDate: LocalDate(2026, 5, 31),
        today: LocalDate(2026, 5, 19),
      );
    });
    await openPicker(tester);

    // 范围只有 5-10 ~ 5-31：9 及之前置灰，点了不改选。
    await tester.tap(find.text('5'));
    await tester.pump();
    // 5 月已是下限页：上个月翻页到界不动。
    await tester.tap(find.byTooltip('上个月'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextButton, '5月'), findsOneWidget);

    expect(await confirmPicker(tester, picked), LocalDate(2026, 5, 19));
  });

  testWidgets('日模式翻页：跨月进位且选中日钳到目标月天数（1.31 → 2.28）', (
    tester,
  ) async {
    Future<LocalDate?>? picked;
    await pumpHost(tester, onOpen: (context) {
      picked = showSimpleDatePicker(
        context,
        initialDate: LocalDate(2026, 1, 31),
        firstDate: LocalDate(2025, 6, 1),
        lastDate: LocalDate(2026, 12, 31),
        today: LocalDate(2026, 5, 19),
      );
    });
    await openPicker(tester);

    await tester.tap(find.byTooltip('下个月'));
    await tester.pumpAndSettle();

    // 2026 年 2 月非闰年只有 28 天：没有 29 格，选中日从 31 钳到 28。
    expect(find.widgetWithText(TextButton, '2月'), findsOneWidget);
    expect(find.text('29'), findsNothing);
    expect(find.text('28'), findsOneWidget);
    expect(await confirmPicker(tester, picked), LocalDate(2026, 2, 28));
  });

  testWidgets('日模式翻页跨年：12 月翻到次年 1 月', (tester) async {
    Future<LocalDate?>? picked;
    await pumpHost(tester, onOpen: (context) {
      picked = showSimpleDatePicker(
        context,
        initialDate: LocalDate(2025, 12, 15),
        firstDate: LocalDate(2024, 1, 1),
        lastDate: LocalDate(2027, 12, 31),
        today: LocalDate(2026, 5, 19),
      );
    });
    await openPicker(tester);

    await tester.tap(find.byTooltip('下个月'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextButton, '2026年'), findsOneWidget);
    expect(find.widgetWithText(TextButton, '1月'), findsOneWidget);
    expect(await confirmPicker(tester, picked), LocalDate(2026, 1, 15));
  });

  testWidgets('月模式：标题点入、禁用月点了无效、选月回日模式', (tester) async {
    Future<LocalDate?>? picked;
    await pumpHost(tester, onOpen: (context) {
      picked = showSimpleDatePicker(
        context,
        initialDate: LocalDate(2026, 5, 19),
        firstDate: LocalDate(2026, 3, 10),
        lastDate: LocalDate(2026, 8, 20),
        today: LocalDate(2026, 5, 19),
      );
    });
    await openPicker(tester);

    // 点头部月份标题 → 12 个月网格。
    await tester.tap(find.widgetWithText(TextButton, '5月'));
    await tester.pumpAndSettle();
    expect(find.text('3月'), findsOneWidget);
    // 月网格下没有日历的星期列头（还在月模式）。
    expect(find.text('一'), findsNothing);

    // 2 月整月早于 firstDate（3-10）→ 置灰：点了不切模式。
    await tester.tap(find.text('2月'));
    await tester.pump();
    expect(find.text('9月'), findsOneWidget);
    expect(find.text('一'), findsNothing);

    // 选 7 月 → 回日模式，落在 7 月页。
    await tester.tap(find.text('7月'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextButton, '7月'), findsOneWidget);
    expect(find.text('一'), findsOneWidget);
    expect(find.text('31'), findsOneWidget);
    expect(await confirmPicker(tester, picked), LocalDate(2026, 7, 19));
  });

  testWidgets('月模式翻年：浏览年搬动选中日期（确认弹出的是当前浏览页）', (
    tester,
  ) async {
    Future<LocalDate?>? picked;
    await pumpHost(tester, onOpen: (context) {
      picked = showSimpleDatePicker(
        context,
        initialDate: LocalDate(2026, 5, 19),
        firstDate: LocalDate(2020, 1, 1),
        lastDate: LocalDate(2038, 12, 31),
        today: LocalDate(2026, 5, 19),
      );
    });
    await openPicker(tester);

    await tester.tap(find.widgetWithText(TextButton, '5月'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('上一年'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextButton, '2025年'), findsOneWidget);

    await tester.tap(find.text('3月'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextButton, '3月'), findsOneWidget);
    expect(await confirmPicker(tester, picked), LocalDate(2025, 3, 19));
  });

  testWidgets('年模式：12 年一页、翻页到界、禁用年无效、选年回落月模式', (
    tester,
  ) async {
    Future<LocalDate?>? picked;
    await pumpHost(tester, onOpen: (context) {
      picked = showSimpleDatePicker(
        context,
        initialDate: LocalDate(2026, 5, 19),
        firstDate: LocalDate(2020, 1, 1),
        lastDate: LocalDate(2038, 12, 31),
        today: LocalDate(2026, 5, 19),
      );
    });
    await openPicker(tester);

    // 点头部年份标题 → 12 年一页的年份网格（2026 落在 2016-2027 页）。
    await tester.tap(find.widgetWithText(TextButton, '2026年'));
    await tester.pumpAndSettle();
    expect(find.text('2016-2027年'), findsOneWidget);

    // 该页首年 2016 不晚于 firstDate（2020）→ 上一组翻页到界不动。
    await tester.tap(find.byTooltip('上一组年份'));
    await tester.pumpAndSettle();
    expect(find.text('2016-2027年'), findsOneWidget);

    // 2018 < 2020 置灰：点了不离开年份网格。
    await tester.tap(find.text('2018年'));
    await tester.pump();
    expect(find.text('2020年'), findsOneWidget);

    // 翻下一组 → 2028-2039 页，选 2030 年回落月模式。
    await tester.tap(find.byTooltip('下一组年份'));
    await tester.pumpAndSettle();
    expect(find.text('2028-2039年'), findsOneWidget);
    await tester.tap(find.text('2030年'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextButton, '2030年'), findsOneWidget);
    expect(find.text('6月'), findsOneWidget);

    // 再选 3 月 → 日模式。
    await tester.tap(find.text('3月'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextButton, '3月'), findsOneWidget);
    expect(await confirmPicker(tester, picked), LocalDate(2030, 3, 19));
  });

  testWidgets('今天快捷键：today 在范围内 → 一键选中今天并跳页', (tester) async {
    Future<LocalDate?>? picked;
    await pumpHost(tester, onOpen: (context) {
      picked = showSimpleDatePicker(
        context,
        initialDate: LocalDate(2026, 2, 10),
        firstDate: LocalDate(2026, 1, 1),
        lastDate: LocalDate(2026, 12, 31),
        today: LocalDate(2026, 5, 19),
      );
    });
    await openPicker(tester);

    expect(find.text('今天'), findsOneWidget);
    await tester.tap(find.text('今天'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextButton, '5月'), findsOneWidget);
    expect(await confirmPicker(tester, picked), LocalDate(2026, 5, 19));
  });

  testWidgets('今天快捷键：today 超出范围 → 按钮不显示', (tester) async {
    Future<LocalDate?>? picked;
    await pumpHost(tester, onOpen: (context) {
      picked = showSimpleDatePicker(
        context,
        initialDate: LocalDate(2026, 2, 10),
        firstDate: LocalDate(2026, 1, 1),
        lastDate: LocalDate(2026, 3, 31),
        today: LocalDate(2026, 5, 19),
      );
    });
    await openPicker(tester);

    expect(find.text('今天'), findsNothing);
    expect(await confirmPicker(tester, picked), LocalDate(2026, 2, 10));
  });
}
