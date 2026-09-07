// records 域 widget 测试（共享夹具见 test/helpers/widget_app.dart）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lunio/core/date/app_date_context.dart';
import 'package:lunio/core/date/local_date.dart';
import 'package:lunio/data/database/app_database.dart';
import 'package:lunio/domain/entities/car.dart';
import 'package:lunio/domain/entities/maintenance_record.dart';
import 'package:lunio/domain/entities/sync_metadata.dart';

import '../helpers/widget_app.dart';

/// 预播种一辆默认项目车 + 一条带项目费用的记录（默认机油 230 = 材料 150 +
/// 工时 80，总费用 280 与合计不一致，模拟总费用优惠场景；可通过参数改
/// 项目费用/总费用，造项目级不一致——如 200 ≠ 150+80 的项目优惠价）。
/// 必须在 pumpApp 之前建库播种：App 装配后再经仓库直接写库不会触发
/// provider 失效，页面会拿到旧的空缓存。
Future<AppDatabase> seedCostedRecord({
  int itemCostCents = 23000,
  int totalCostCents = 28000,
}) async {
  final database = AppDatabase.inMemory();
  addTearDown(database.close);
  final bundle = testRepository(database);
  await bundle.ensureBootstrapData();
  final carId = await createCarWithDefaultItems(
    database,
    Car(
      brand: '本田',
      model: '思域（燃油版）',
      currentMileageKm: 12000,
      roadDate: const LocalDate(2020, 1, 1),
      sync: SyncMetadata(
        status: SyncStatus.pendingCreate,
        updatedAt: DateTime(2026, 5, 19),
      ),
    ),
  );
  final items = await bundle.listMaintenanceItemsForCar(carId);
  final oilId = items.firstWhere((item) => item.name == '机油').id!;
  await bundle.repository.saveMaintenanceRecord(
    MaintenanceRecord(
      carId: carId,
      date: const LocalDate(2026, 5, 19),
      itemIds: [oilId],
      itemCosts: [
        RecordItemCost(
          itemId: oilId,
          materialCents: 15000,
          laborCents: 8000,
          costCents: itemCostCents,
        ),
      ],
      costCents: totalCostCents,
      mileageKm: 12000,
      sync: SyncMetadata(
        status: SyncStatus.synced,
        updatedAt: DateTime(2026, 5, 19),
      ),
    ),
  );
  await bundle.setAppliedCarId(carId);
  return database;
}

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

  testWidgets('detail mode auto fills item cost and total then persists', (
    tester,
  ) async {
    final database = await pumpApp(tester);
    await createDefaultCar(tester);
    await tester.tap(find.text('提醒'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '新增保养记录'));
    await tester.pumpAndSettle();

    // 默认简洁模式：没有按项目费用输入。
    expect(find.text('材料费'), findsNothing);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await tester.tap(find.text('机油').first);
    await tester.pumpAndSettle();

    // 详细模式表单字段顺序：里程/费用/备注 + 该项目的材料/工时/项目费用。
    await tester.enterText(find.byType(TextField).at(0), '12000');
    await tester.enterText(find.byType(TextField).at(3), '150');
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(4), '80');
    await tester.pumpAndSettle();

    // 自动算链：项目费用 = 材料 + 工时；总费用跟随合计。
    expect(
      tester.widget<TextField>(find.byType(TextField).at(5)).controller!.text,
      '230.00',
    );
    expect(
      tester.widget<TextField>(find.byType(TextField).at(1)).controller!.text,
      '230.00',
    );

    // 手改项目费用为 200（≠ 材料+工时 230）：红字 + 该行黄色警告角标，
    // 总费用自动跟随 200，无不一致提示。纯提示，保存不拦截。
    await tester.enterText(find.byType(TextField).at(5), '200');
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.warning_amber_rounded), findsNWidgets(2));
    expect(
      tester.widget<TextField>(find.byType(TextField).at(5)).style?.color,
      const Color(0xffef4444),
    );
    expect(
      tester.widget<TextField>(find.byType(TextField).at(1)).controller!.text,
      '200.00',
    );

    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存记录'));
    await tester.pumpAndSettle();

    final costRow = (await database
        .select(database.maintenanceRecordItems)
        .get()).single;
    expect(costRow.materialCostCents, 15000);
    expect(costRow.laborCostCents, 8000);
    expect(costRow.costCents, 20000);
    expect(
      (await database.select(database.maintenanceRecords).get())
          .single
          .costCents,
      20000,
    );
  });

  testWidgets('editing costed record opens detail mode prefilled', (
    tester,
  ) async {
    final database = await seedCostedRecord();
    await pumpApp(tester, database: database);

    await tester.tap(find.text('记录'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '编辑').first);
    await tester.pumpAndSettle();

    // 编辑带项目费用的记录自动进详细模式，历史费用（含不一致的总费用）
    // 原样回显：总费用 280 ≠ 项目费用合计 230 → 总费用红字 + 警告角标。
    expect(find.text('材料费'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField).at(3)).controller!.text,
      '150.00',
    );
    expect(
      tester.widget<TextField>(find.byType(TextField).at(4)).controller!.text,
      '80.00',
    );
    expect(
      tester.widget<TextField>(find.byType(TextField).at(5)).controller!.text,
      '230.00',
    );
    expect(
      tester.widget<TextField>(find.byType(TextField).at(1)).controller!.text,
      '280.00',
    );
    // 只提示总费用（280 ≠ 合计 230）：总费用框尾警告角标；项目费用本身
    // 一致（230 = 150 + 80）不再加标。
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField).at(1)).style?.color,
      const Color(0xffef4444),
    );
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    // 整卡点击 → 按周期详情弹窗：整条记录 + 全部项目费用，取存储值展示。
    // （页面标题与弹窗标题同为"保养记录"，共两处。）
    await tester.tap(find.text('2026-05-19'));
    await tester.pumpAndSettle();
    expect(find.text('保养记录'), findsNWidgets(2));
    expect(find.textContaining('整条记录总费用'), findsOneWidget);
    expect(find.text('总费用'), findsOneWidget);
    // 卡片上的总费用与弹窗指标格各一份（sheet 打开时卡片仍在树下）。
    expect(find.text('¥280.00'), findsNWidgets(2));
    expect(find.text('项目费用'), findsOneWidget);
    expect(find.text('¥230.00'), findsOneWidget);
    expect(find.textContaining('材料 ¥150.00 / 工时 ¥80.00'), findsOneWidget);
    // 总费用与合计不一致 → 弹窗里也有黄色警告角标。
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
  });

  testWidgets('item mode card tap opens single item detail sheet', (
    tester,
  ) async {
    final database = await seedCostedRecord();
    await pumpApp(tester, database: database);

    await tester.tap(find.text('记录'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('按项目'));
    await tester.pumpAndSettle();
    // 行卡标题是"机油"，点标题触发整行 onTap → 只看该项目的详情弹窗。
    await tester.tap(find.text('机油').last);
    await tester.pumpAndSettle();

    expect(find.text('机油'), findsWidgets);
    expect(find.text('项目费用'), findsOneWidget);
    expect(find.text('¥230.00'), findsOneWidget);
    expect(find.text('总费用'), findsOneWidget);
    expect(find.text('¥280.00'), findsOneWidget);
    expect(find.textContaining('材料 ¥150.00 / 工时 ¥80.00'), findsOneWidget);
    // 单项目费用本身一致（230 = 150 + 80），无警告角标。
    expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
  });

  testWidgets(
    'editing mismatched item cost keeps stored value when changing material',
    (tester) async {
      final database = await seedCostedRecord(
        itemCostCents: 20000,
        totalCostCents: 20000,
      );
      await pumpApp(tester, database: database);

      await tester.tap(find.text('记录'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, '编辑').first);
      await tester.pumpAndSettle();

      // 存量项目费用 200 ≠ 材料+工时 230（优惠价）：打开即视为手改，
      // 红字 + 行头/框尾两个警告角标提示（与新建手改不一致价同样式）。
      expect(
        tester.widget<TextField>(find.byType(TextField).at(5)).controller!.text,
        '200.00',
      );
      expect(find.byIcon(Icons.warning_amber_rounded), findsNWidgets(2));
      expect(
        tester.widget<TextField>(find.byType(TextField).at(5)).style?.color,
        const Color(0xffef4444),
      );

      // 改材料费触发自动算链：优惠价 200 不被覆盖为材料+工时 240。
      await tester.enterText(find.byType(TextField).at(3), '160');
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(
          find.byType(TextField).at(5),
        ).controller!.text,
        '200.00',
      );
      // 总费用跟随新合计 200（合计取项目费用字段本身的权威值，不含材料/
      // 工时推导；存量总费用 200 == 合计 200，未被视为手改，保持自动跟随）。
      expect(
        tester.widget<TextField>(
          find.byType(TextField).at(1),
        ).controller!.text,
        '200.00',
      );

      // 保存后落库的是权威值：项目费用 200 原样保留，未被算链冲掉。
      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存记录'));
      await tester.pumpAndSettle();

      final costRow = (await database
          .select(database.maintenanceRecordItems)
          .get()).single;
      expect(costRow.materialCostCents, 16000);
      expect(costRow.laborCostCents, 8000);
      expect(costRow.costCents, 20000);
      expect(
        (await database.select(database.maintenanceRecords).get())
            .single
            .costCents,
        20000,
      );
    },
  );
}
