// records 域 widget 测试（自原 widget_test.dart 按页面域拆分，
// 共享夹具见 test/helpers/widget_app.dart）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lunio/core/date/app_date_context.dart';

import '../helpers/widget_app.dart';

void main() {
  testWidgets('records page switches between cycle and item modes', (
    tester,
  ) async {
    await pumpApp(tester);
    await createDefaultCar(tester);
    await createDefaultRecord(tester);

    await tester.tap(find.text('记录'));
    await tester.pumpAndSettle();
    expect(find.text('2026-05-19'), findsOneWidget);
    expect(find.text('13,000 km'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsNWidgets(2));

    await tester.tap(find.text('机油').first);
    await tester.pumpAndSettle();
    expect(find.text('2026-05-19'), findsOneWidget);
    expect(find.text('13,000 km'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsNWidgets(2));

    await tester.tap(find.text('按项目'));
    await tester.pumpAndSettle();
    expect(find.textContaining('2026-05-19 · 13,000 km'), findsOneWidget);
    expect(find.textContaining('¥428.00'), findsNothing);
  });


  testWidgets('record form shows car and can add maintenance item', (
    tester,
  ) async {
    final database = await pumpApp(tester);
    await createDefaultCar(tester);
    await tester.tap(find.text('提醒'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, '新增保养记录'));
    await tester.pumpAndSettle();

    expect(find.text('奥迪 奥迪A3'), findsWidgets);
    expect(
      tester.widget<TextField>(find.byType(TextField).at(0)).controller?.text,
      '0',
    );
    expect(
      tester.widget<TextField>(find.byType(TextField).at(1)).controller?.text,
      '0',
    );

    await tester.tap(find.byType(TextField).at(0));
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField).at(0)).controller?.text,
      '',
    );
    tester.testTextInput.hide();
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, '新增').hitTestable().last);
    await tester.pumpAndSettle();
    expect(find.text('新增保养项目'), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(3), '玻璃水');
    await tester.enterText(find.byType(TextField).at(4), '3000');
    await tester.enterText(find.byType(TextField).at(5), '6');
    tester.testTextInput.hide();
    await tester.drag(
      find.byType(SingleChildScrollView).last,
      const Offset(0, -420),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存项目'));
    await tester.pumpAndSettle();

    expect(
      await database.select(database.maintenanceItems).get(),
      hasLength(11),
    );
    expect(find.text('玻璃水', skipOffstage: false), findsOneWidget);
  });


  testWidgets('date picker switches between day month and year grids', (
    tester,
  ) async {
    await pumpApp(tester);
    await createDefaultCar(tester);
    await enableDeveloperMode(tester);

    await tester.tap(find.widgetWithText(TextButton, '设置').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2026年5月19日'));
    await tester.pumpAndSettle();

    expect(find.text('一'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '5月'));
    await tester.pumpAndSettle();
    expect(find.text('12月'), findsOneWidget);
    expect(find.text('一'), findsNothing);

    await tester.tap(find.text('8月'));
    await tester.pumpAndSettle();
    expect(find.text('一'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, '2026年'));
    await tester.pumpAndSettle();
    expect(find.text('2016-2027年'), findsOneWidget);
    expect(find.text('2024年'), findsOneWidget);
    expect(find.text('一'), findsNothing);

    await tester.tap(find.text('2024年'));
    await tester.pumpAndSettle();
    expect(find.text('12月'), findsOneWidget);

    await tester.tap(find.text('2月'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextButton, '2024年'), findsOneWidget);
    expect(find.widgetWithText(TextButton, '2月'), findsOneWidget);
    expect(find.text('一'), findsOneWidget);
  });


  testWidgets('date picker clamps day when switching to shorter month', (
    tester,
  ) async {
    await pumpApp(
      tester,
      dateContext: AppDateContext(readSystemNow: () => DateTime(2026, 1, 31)),
    );
    await createDefaultCar(tester);
    await enableDeveloperMode(tester);

    await tester.tap(find.widgetWithText(TextButton, '设置').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2026年1月31日'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, '1月'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2月'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    expect(find.text('2026年2月28日'), findsOneWidget);
  });


  testWidgets('records page can create a maintenance record', (tester) async {
    final database = await pumpApp(tester);
    await createDefaultCar(tester);
    await createDefaultRecord(tester);

    expect(
      await database.select(database.maintenanceRecords).get(),
      hasLength(1),
    );
    expect(
      await database.select(database.maintenanceRecordItems).get(),
      hasLength(1),
    );
    expect(
      (await database.select(database.cars).get()).single.currentMileageKm,
      13000,
    );
  });


  testWidgets('editing zero cost clears formatted zero on tap', (tester) async {
    await pumpApp(tester);
    await createDefaultCar(tester);
    await tester.tap(find.text('提醒'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '新增保养记录'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '12000');
    await tester.tap(find.text('机油').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存记录'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('记录'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '编辑').last);
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextField>(find.byType(TextField).at(1)).controller?.text,
      '0.00',
    );
    await tester.tap(find.byType(TextField).at(1));
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField).at(1)).controller?.text,
      '',
    );
  });


  testWidgets('item mode edit opens record sheet and delete removes item row', (
    tester,
  ) async {
    final database = await pumpApp(tester);
    await createDefaultCar(tester);
    await createDefaultRecord(tester);

    await tester.tap(find.text('记录'));
    await tester.pumpAndSettle();
    expect(find.text('同车同日仅保留一条记录'), findsNothing);
    await tester.tap(find.text('按项目'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, '编辑').last);
    await tester.pumpAndSettle();
    expect(find.text('编辑保养记录'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, '删除').last);
    await tester.pumpAndSettle();
    expect(find.text('删除保养项目'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    expect(await database.select(database.maintenanceRecords).get(), isEmpty);
    expect(
      await database.select(database.maintenanceRecordItems).get(),
      isEmpty,
    );
  });
}
