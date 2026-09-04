// maintenance_items 域 widget 测试（共享夹具见 test/helpers/widget_app.dart）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';


import 'package:lunio/domain/entities/maintenance_item.dart';
import 'package:lunio/domain/entities/sync_metadata.dart';
import '../helpers/widget_app.dart';

void main() {
  testWidgets('profile can add a custom maintenance item', (tester) async {
    final database = await pumpApp(tester);

    await createDefaultCar(tester);

    await tester.tap(find.widgetWithText(TextButton, '项目').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '新增').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '玻璃水');
    await tester.enterText(find.byType(TextField).at(1), '3000');
    await tester.enterText(find.byType(TextField).at(2), '6');
    tester.testTextInput.hide();
    await tester.drag(
      find.byType(SingleChildScrollView).last,
      const Offset(0, -420),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存项目'));
    await tester.pumpAndSettle();

    expect(find.text('玻璃水'), findsOneWidget);
    expect(
      await database.select(database.maintenanceItems).get(),
      hasLength(11),
    );
  });


  testWidgets('maintenance item sheet uses vehicle scoped compact copy', (
    tester,
  ) async {
    await pumpApp(tester);
    await createDefaultCar(tester);

    await tester.tap(find.widgetWithText(TextButton, '项目').first);
    await tester.pumpAndSettle();

    expect(find.text('保养项目'), findsOneWidget);
    expect(find.text('奥迪 奥迪A3'), findsWidgets);
    expect(find.textContaining('项目名称可变'), findsNothing);
    expect(find.textContaining('关闭后不出现在'), findsNothing);
    expect(find.text('提醒：5,000公里/6个月'), findsWidgets);
    // 燃油模板里空调滤芯、空气滤芯都是这个间隔，出现两行。
    expect(find.text('提醒：2万公里/1年'), findsNWidgets(2));
    expect(find.text('默认'), findsNothing);
    expect(find.text('自定义'), findsNothing);
    expect(find.text('点按编辑'), findsNothing);
    expect(find.byIcon(Icons.chevron_right), findsNothing);
    expect(find.byType(Switch), findsNothing);
    expect(find.widgetWithText(TextButton, '编辑'), findsWidgets);
    expect(find.widgetWithText(TextButton, '已启用'), findsWidgets);
    expect(find.widgetWithText(TextButton, '启用'), findsNothing);
    expect(find.widgetWithText(TextButton, '删除'), findsWidgets);

    await tester.tap(find.widgetWithText(TextButton, '已启用').first);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextButton, '已禁用'), findsOneWidget);
  });


  testWidgets(
    'maintenance item form uses unit suffixes and validates empty intervals',
    (tester) async {
      await pumpApp(tester);
      await createDefaultCar(tester);

      await tester.tap(find.widgetWithText(TextButton, '项目').first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, '新增').last);
      await tester.pumpAndSettle();

      expect(find.text('新增保养项目'), findsOneWidget);
      expect(find.text('项目名称'), findsOneWidget);
      expect(find.text('km'), findsOneWidget);
      expect(find.text('月'), findsOneWidget);
      expect(find.text('间隔 km'), findsNothing);
      expect(find.text('间隔 月'), findsNothing);
      expect(
        tester.widget<TextField>(find.byType(TextField).at(1)).controller?.text,
        '',
      );
      expect(
        tester.widget<TextField>(find.byType(TextField).at(2)).controller?.text,
        '',
      );

      await tester.enterText(find.byType(TextField).first, '玻璃水');
      tester.testTextInput.hide();
      await tester.tap(find.text('保存项目'));
      await tester.pumpAndSettle();

      expect(find.text('里程间隔必须填写正整数'), findsOneWidget);
    },
  );


  testWidgets('maintenance item row opens edit sheet and edits item name', (
    tester,
  ) async {
    final database = await pumpApp(tester);
    await createDefaultCar(tester);

    await tester.tap(find.widgetWithText(TextButton, '项目').first);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
    await tester.tap(find.text('机油'));
    await tester.pumpAndSettle();
    expect(find.text('编辑保养项目'), findsNothing);

    await tester.ensureVisible(find.widgetWithText(TextButton, '编辑').last);
    await tester.tap(find.widgetWithText(TextButton, '编辑').last);
    await tester.pumpAndSettle();
    expect(find.text('编辑保养项目'), findsOneWidget);
    expect(find.textContaining('默认项目名称保持稳定'), findsNothing);
    await tester.enterText(find.byType(TextField).first, '全合成机油');
    tester.testTextInput.hide();
    await tester.tap(find.text('保存项目'));
    await tester.pumpAndSettle();

    expect(find.text('全合成机油'), findsOneWidget);
    expect(
      (await database.select(database.maintenanceItems).get()).map(
        (item) => item.name,
      ),
      contains('全合成机油'),
    );
  });


  testWidgets('maintenance item sheet keeps scroll after editing an item', (
    tester,
  ) async {
    final database = await pumpApp(tester);
    await createDefaultCar(tester);
    final car = (await database.select(database.cars).get()).single;
    final repository = testRepository(database);
    final sync = SyncMetadata(
      status: SyncStatus.pendingCreate,
      updatedAt: DateTime(2026, 5, 19),
    );
    for (var index = 0; index < 24; index++) {
      await repository.saveMaintenanceItem(
        MaintenanceItem(
          carsId: car.id,
          name: '测试项目 ${index.toString().padLeft(2, '0')}',
          enabled: true,
          remindByMileage: true,
          remindByTime: false,
          mileageIntervalKm: 1000 + index,
          sortOrder: 1000 + index,
          sync: sync,
        ),
      );
    }

    await tester.tap(find.widgetWithText(TextButton, '项目').first);
    await tester.pumpAndSettle();
    final scrollView = find.byType(SingleChildScrollView).last;
    final scrollable = find.byType(Scrollable).last;
    await tester.scrollUntilVisible(
      find.text('测试项目 18'),
      220,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();
    final offsetBeforeEdit = tester
        .widget<SingleChildScrollView>(scrollView)
        .controller!
        .offset;
    expect(offsetBeforeEdit, greaterThan(0));

    await tester.tap(find.text('测试项目 18'));
    await tester.pumpAndSettle();
    expect(find.text('编辑保养项目'), findsNothing);

    await tester.scrollUntilVisible(
      find.widgetWithText(TextButton, '编辑').last,
      80,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '编辑').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '测试项目 18 改');
    tester.testTextInput.hide();
    await tester.tap(find.text('保存项目'));
    await tester.pumpAndSettle();

    final offsetAfterEdit = tester
        .widget<SingleChildScrollView>(scrollView)
        .controller!
        .offset;
    expect(offsetAfterEdit, greaterThan(0));
    expect(find.text('测试项目 18 改'), findsOneWidget);
  });
}
