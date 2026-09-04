// vehicles 域 widget 测试（自原 widget_test.dart 按页面域拆分，
// 共享夹具见 test/helpers/widget_app.dart）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lunio/core/date/app_date_context.dart';
import 'package:lunio/features/shell/profile/vehicles.dart' show PickerOption;

import '../helpers/widget_app.dart';

void main() {
  testWidgets('profile can create a car and set it as applied car', (
    tester,
  ) async {
    final database = await pumpApp(tester, inAppNotificationsEnabled: true);

    await createDefaultCar(tester);

    expect(find.text('保养提醒'), findsNothing);
    expect(find.text('奥迪 奥迪A3'), findsWidgets);
    expect(find.text('当前'), findsOneWidget);
    expect(find.textContaining('0km'), findsOneWidget);
    expect(find.textContaining('车龄'), findsNothing);
    expect(find.textContaining('上路'), findsNothing);
    expect(find.text('当前车辆保养项目'), findsNothing);
    expect(await database.select(database.cars).get(), hasLength(1));
    // 燃油模板 10 项（默认预选动力 = 目录第一项奥迪A3 的推荐值燃油）。
    expect(
      await database.select(database.maintenanceItems).get(),
      hasLength(10),
    );
  });


  testWidgets('add car first step does not persist data', (tester) async {
    final database = await pumpApp(tester);

    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('新增车辆'));
    await tester.pumpAndSettle();
    expect(find.text('添加车辆'), findsOneWidget);
    expect(find.textContaining('同一品牌车型'), findsNothing);
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();

    expect(find.text('上一步'), findsOneWidget);
    expect(find.text('保养项目'), findsOneWidget);
    expect(find.text('以下保养项目只做参考，具体以官方保养手册为准'), findsOneWidget);
    expect(find.textContaining('同一品牌车型'), findsNothing);
    expect(await database.select(database.cars).get(), isEmpty);
    expect(await database.select(database.maintenanceItems).get(), isEmpty);
  });


  testWidgets('add car form opens vehicle model picker', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('新增车辆'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('奥迪 奥迪A3'));
    await tester.pumpAndSettle();

    expect(find.text('选择车型'), findsOneWidget);
    expect(find.text('搜索品牌或车型'), findsOneWidget);
    expect(find.text('奥迪'), findsWidgets);
  });


  testWidgets('add car wizard keeps selected model after going back', (
    tester,
  ) async {
    await pumpApp(tester);

    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('新增车辆'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('奥迪 奥迪A3'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '轩逸');
    await tester.pumpAndSettle();
    // 搜索框里的输入（EditableText）与列表行同名，精确点 PickerOption 行。
    await tester.tap(find.widgetWithText(PickerOption, '轩逸'));
    await tester.pumpAndSettle();
    expect(find.text('日产 轩逸'), findsOneWidget);

    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('上一步'));
    await tester.pumpAndSettle();

    expect(find.text('日产 轩逸'), findsOneWidget);
    expect(find.text('奥迪 奥迪A3'), findsNothing);
  });


  testWidgets(
    'add car wizard supports custom model input for catalog gaps',
    (tester) async {
      await pumpApp(tester);

      await tester.tap(find.text('我的'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('新增车辆'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('奥迪 奥迪A3'));
      await tester.pumpAndSettle();
      // 目录外的老车（懂车帝已下架）走自定义输入兜底（ADR 0003）。
      await tester.enterText(find.byType(TextField).last, '不存在的车系');
      await tester.pumpAndSettle();
      expect(find.text('没有匹配车型'), findsOneWidget);
      await tester.tap(find.text('＋ 自定义输入…'));
      await tester.pumpAndSettle();
      // 自定义车型弹窗走 showLunioDialog seam（ADR 同族卡片，外层是
      // Dialog），dialog 里只有品牌/车型两个输入框，从 Dialog 范围内定位。
      final dialogFields = find.descendant(
        of: find.byType(Dialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(dialogFields.at(0), '雪佛兰');
      await tester.enterText(dialogFields.at(1), '科鲁泽');
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();

      expect(find.text('雪佛兰 科鲁泽'), findsOneWidget);
      // 自定义车型没有目录推荐值，动力类型预选燃油。
      expect(
        tester
            .widgetList<Text>(find.byType(Text))
            .map((text) => text.data)
            .whereType<String>(),
        contains('燃油'),
      );
    },
  );


  testWidgets('add car wizard reloads items after powertrain changes', (
    tester,
  ) async {
    await pumpApp(tester);

    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('新增车辆'));
    await tester.pumpAndSettle();

    // 默认预选燃油：机油/汽油滤芯都在。
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    expect(find.text('机油'), findsOneWidget);
    expect(find.text('汽油滤芯'), findsOneWidget);

    // 回第一步换成纯电：模板应整组换成纯电那套（没有机油）。
    await tester.tap(find.text('上一步'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('纯电'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();

    expect(find.text('机油'), findsNothing);
    expect(find.text('减速器油'), findsOneWidget);
  });


  testWidgets('profile can edit car mileage', (tester) async {
    final database = await pumpApp(tester);

    await createDefaultCar(tester);

    await tester.ensureVisible(find.widgetWithText(TextButton, '编辑').last);
    await tester.tap(find.widgetWithText(TextButton, '编辑').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '60000');
    await tester.tap(find.text('保存车辆'));
    await tester.pumpAndSettle();

    expect(find.textContaining('60,000km'), findsOneWidget);
    expect(
      (await database.select(database.cars).get()).single.currentMileageKm,
      60000,
    );
  });


  testWidgets('add car item step can remove a loaded default item', (
    tester,
  ) async {
    final database = await pumpApp(tester);

    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('新增车辆'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();

    // 燃油模板 10 项。
    expect(find.byTooltip('删除'), findsNWidgets(10));
    await tester.tap(find.byTooltip('删除').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存车辆'));
    await tester.pumpAndSettle();

    expect(
      await database.select(database.maintenanceItems).get(),
      hasLength(9),
    );
  });


  testWidgets('add car item step custom item form starts without intervals', (
    tester,
  ) async {
    await pumpApp(tester);

    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('新增车辆'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '新增'));
    await tester.pumpAndSettle();

    expect(find.text('新增保养项目'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField).at(1)).controller?.text,
      '',
    );
    expect(
      tester.widget<TextField>(find.byType(TextField).at(2)).controller?.text,
      '',
    );
  });


  testWidgets('add car item step can restore removed default item draft', (
    tester,
  ) async {
    final database = await pumpApp(tester);

    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('新增车辆'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('删除').first);
    await tester.pumpAndSettle();
    expect(find.text('机油'), findsNothing);

    await tester.tap(find.widgetWithText(TextButton, '恢复').last);
    await tester.pumpAndSettle();
    expect(find.text('恢复默认项目'), findsOneWidget);
    expect(find.text('已存在'), findsNWidgets(9));
    await tester.tap(find.widgetWithText(FilledButton, '恢复'));
    await tester.pumpAndSettle();
    expect(find.text('机油'), findsOneWidget);

    await tester.tap(find.text('保存车辆'));
    await tester.pumpAndSettle();

    expect(
      await database.select(database.maintenanceItems).get(),
      hasLength(10),
    );
  });


  testWidgets('add car date picker today uses effective app date', (
    tester,
  ) async {
    await pumpApp(
      tester,
      dateContext: AppDateContext(readSystemNow: () => DateTime(2026, 1, 31)),
    );

    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('新增车辆'));
    await tester.pumpAndSettle();

    expect(find.text('2026年1月31日'), findsOneWidget);
    await tester.tap(find.text('2026年1月31日'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '1月'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2月'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(find.text('2026年2月28日'), findsOneWidget);

    await tester.tap(find.text('2026年2月28日'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '今天'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    expect(find.text('2026年1月31日'), findsOneWidget);
  });
}
