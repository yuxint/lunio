import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:lunio/app/providers.dart';
import 'package:lunio/app/lunio_app.dart';
import 'package:lunio/core/date/app_date_context.dart';
import 'package:lunio/core/date/local_date.dart';
import 'package:lunio/data/database/app_database.dart';

void main() {
  Future<AppDatabase> pumpApp(
    WidgetTester tester, {
    AppDateContext? dateContext,
  }) async {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          appDateContextProvider.overrideWithValue(
            dateContext ??
                AppDateContext(readSystemNow: () => DateTime(2026, 5, 19)),
          ),
        ],
        child: const LunioApp(),
      ),
    );
    await tester.pumpAndSettle();
    return database;
  }

  Future<void> createDefaultCar(WidgetTester tester) async {
    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('新增车辆'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存车辆'));
    await tester.pumpAndSettle();
  }

  Future<void> createDefaultRecord(WidgetTester tester) async {
    await tester.tap(find.text('提醒'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('新增保养记录'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '13000');
    await tester.enterText(find.byType(TextField).at(1), '428.00');
    await tester.tap(find.text('机油').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存记录'));
    await tester.pumpAndSettle();
  }

  testWidgets('app shell exposes three main entries', (tester) async {
    await pumpApp(tester);

    expect(find.text('保养提醒'), findsOneWidget);
    expect(find.text('还没有车辆'), findsOneWidget);
    expect(find.text('提醒'), findsOneWidget);
    expect(find.text('记录'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);
  });

  testWidgets('bottom navigation switches primary tabs', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('记录'));
    await tester.pumpAndSettle();
    expect(find.text('保养记录'), findsOneWidget);

    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    expect(find.text('个人中心'), findsOneWidget);
  });

  testWidgets('theme switch stays on profile and shows toast', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('深色'));
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('个人中心'), findsOneWidget);
    expect(find.text('主题已切换'), findsOneWidget);
  });

  testWidgets('records page switches between cycle and item modes', (
    tester,
  ) async {
    await pumpApp(tester);
    await createDefaultCar(tester);
    await createDefaultRecord(tester);

    await tester.tap(find.text('记录'));
    await tester.pumpAndSettle();
    expect(find.text('2026-05-19'), findsOneWidget);

    await tester.tap(find.text('按项目'));
    await tester.pumpAndSettle();
    expect(find.textContaining('¥428.00'), findsOneWidget);
  });

  testWidgets('floating add action opens placeholder bottom sheet', (
    tester,
  ) async {
    await pumpApp(tester);
    await createDefaultCar(tester);
    await tester.tap(find.text('提醒'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('新增保养记录'));
    await tester.pumpAndSettle();

    expect(find.text('新增保养记录'), findsWidgets);
    expect(find.text('保存记录'), findsOneWidget);
  });

  testWidgets('profile can create a car and set it as applied car', (
    tester,
  ) async {
    final database = await pumpApp(tester);

    await createDefaultCar(tester);

    expect(find.text('东风本田 思域'), findsWidgets);
    expect(find.text('当前'), findsOneWidget);
    expect(find.textContaining('10,000km'), findsOneWidget);
    expect(find.textContaining('车龄'), findsOneWidget);
    expect(find.textContaining('上路'), findsNothing);
    expect(find.text('当前车辆保养项目'), findsNothing);
    expect(await database.select(database.cars).get(), hasLength(1));
    expect(
      await database.select(database.maintenanceItems).get(),
      hasLength(3),
    );
  });

  testWidgets('add car form opens vehicle model picker', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('新增车辆'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('东风本田 思域'));
    await tester.pumpAndSettle();

    expect(find.text('选择车型'), findsOneWidget);
    expect(find.text('搜索品牌或车型'), findsOneWidget);
    expect(find.text('东风本田'), findsWidgets);
  });

  testWidgets('profile can edit car mileage', (tester) async {
    final database = await pumpApp(tester);

    await createDefaultCar(tester);

    await tester.tap(find.widgetWithText(TextButton, '编辑').first);
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

  testWidgets('profile can add a custom maintenance item', (tester) async {
    final database = await pumpApp(tester);

    await createDefaultCar(tester);

    await tester.tap(find.widgetWithText(TextButton, '项目').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('新增项目'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '玻璃水');
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
      hasLength(4),
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
    expect(find.text('东风本田 思域'), findsWidgets);
    expect(find.textContaining('项目名称可变'), findsNothing);
    expect(find.textContaining('关闭后不出现在'), findsNothing);
    expect(find.text('提醒：5,000公里/6个月'), findsWidgets);
    expect(find.text('提醒：2万公里/1年'), findsOneWidget);
    expect(find.byTooltip('编辑'), findsNothing);
  });

  testWidgets('maintenance item row opens edit sheet', (tester) async {
    await pumpApp(tester);
    await createDefaultCar(tester);

    await tester.tap(find.widgetWithText(TextButton, '项目').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('机油').first);
    await tester.pumpAndSettle();

    expect(find.text('编辑保养项目'), findsOneWidget);
    expect(find.textContaining('默认项目名称保持稳定'), findsNothing);
  });

  testWidgets('date picker swaps calendar and year month selector', (
    tester,
  ) async {
    await pumpApp(tester);
    await createDefaultCar(tester);

    await tester.tap(find.text('手动日期'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2026年5月19日'));
    await tester.pumpAndSettle();

    expect(find.text('一'), findsOneWidget);
    await tester.tap(find.text('2026年5月'));
    await tester.pumpAndSettle();
    expect(find.text('2026'), findsOneWidget);
    expect(find.text('5月'), findsOneWidget);
    expect(find.text('一'), findsNothing);

    await tester.tap(find.text('5月'));
    await tester.pumpAndSettle();
    expect(find.text('一'), findsOneWidget);
  });

  testWidgets('destructive confirm dialog uses red confirm action', (
    tester,
  ) async {
    await pumpApp(tester);
    await createDefaultCar(tester);

    await tester.tap(find.widgetWithText(TextButton, '删除').first);
    await tester.pumpAndSettle();

    final deleteButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '删除'),
    );
    final background = deleteButton.style?.backgroundColor?.resolve({});
    expect(background, const Color(0xffef4444));
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

  testWidgets('reminders use current car records and thresholds', (
    tester,
  ) async {
    await pumpApp(
      tester,
      dateContext: AppDateContext(
        readSystemNow: () => DateTime(2026, 5, 23),
        manualDate: const LocalDate(2026, 5, 23),
      ),
    );
    await createDefaultCar(tester);
    await createDefaultRecord(tester);

    await tester.tap(find.text('提醒'));
    await tester.pumpAndSettle();

    expect(find.text('保养提醒'), findsOneWidget);
    expect(find.text('机油'), findsOneWidget);
    expect(find.text('0%'), findsWidgets);
    expect(find.textContaining('上次 2026-05-23'), findsOneWidget);
  });

  testWidgets('profile can enable manual date preference', (tester) async {
    final database = await pumpApp(tester);
    await createDefaultCar(tester);

    await tester.tap(find.text('手动日期'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存日期'));
    await tester.pumpAndSettle();

    final preferences = await database.select(database.appPreferences).get();
    expect(
      preferences.map((preference) => '${preference.key}:${preference.value}'),
      containsAll(['manualDateEnabled:true', 'manualDate:2026-05-19']),
    );
  });
}
