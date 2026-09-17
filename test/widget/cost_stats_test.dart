// cost_stats 域 widget 测试（共享夹具见 test/helpers/widget_app.dart）：
// 统计页渲染（汇总/按年/项目占比/走势/默认当前车作用域）、车辆切换 chips、
// 空态（无记录/无车）、记录页汇总行入口、我的页入口、返回键。
// 播种必须在 pumpApp 之前：装配后直写库不会触发 provider 失效。
import 'package:flutter_test/flutter_test.dart';

import 'package:lunio/core/date/local_date.dart';
import 'package:lunio/data/database/app_database.dart';
import 'package:lunio/domain/entities/car.dart';
import 'package:lunio/domain/entities/maintenance_record.dart';
import 'package:lunio/domain/entities/sync_metadata.dart';

import '../helpers/widget_app.dart';

final _sync = SyncMetadata(
  status: SyncStatus.synced,
  updatedAt: DateTime(2026, 5, 19),
);

/// 播种两辆车 + 三条记录：
///   车A（本田 思域，应用车辆）：2026-05-01 ¥280（机油项目费用 ¥230）、
///     2025-03-01 ¥100（机油项目费用 ¥100）
///   车B（丰田 卡罗拉）：2026-04-01 ¥52（机油项目费用 ¥52）
/// 生效今天 = 2026-05-19（pumpApp 固定）。默认作用域 = 车A：
/// 总 ¥380.00、今年 ¥280.00；全部：总 ¥432.00、今年 ¥332.00。
Future<AppDatabase> seedTwoCarsWithRecords() async {
  final database = AppDatabase.inMemory();
  addTearDown(database.close);
  final bundle = testRepository(database);
  await bundle.ensureBootstrapData();
  final carA = await createCarWithDefaultItems(
    database,
    Car(
      brand: '本田',
      model: '思域（燃油版）',
      currentMileageKm: 12000,
      roadDate: const LocalDate(2020, 1, 1),
      sync: _sync,
    ),
  );
  final carB = await createCarWithDefaultItems(
    database,
    Car(
      brand: '丰田',
      model: '卡罗拉',
      currentMileageKm: 20000,
      roadDate: const LocalDate(2021, 6, 1),
      sync: _sync,
    ),
  );
  final oilA =
      (await bundle.listMaintenanceItemsForCar(carA))
          .firstWhere((item) => item.name == '机油')
          .id!;
  final oilB =
      (await bundle.listMaintenanceItemsForCar(carB))
          .firstWhere((item) => item.name == '机油')
          .id!;
  await bundle.repository.saveMaintenanceRecord(
    MaintenanceRecord(
      carId: carA,
      date: const LocalDate(2026, 5, 1),
      itemIds: [oilA],
      itemCosts: [
        RecordItemCost(
          itemId: oilA,
          materialCents: 15000,
          laborCents: 8000,
          costCents: 23000,
        ),
      ],
      costCents: 28000,
      mileageKm: 12000,
      sync: _sync,
    ),
  );
  await bundle.repository.saveMaintenanceRecord(
    MaintenanceRecord(
      carId: carA,
      date: const LocalDate(2025, 3, 1),
      itemIds: [oilA],
      itemCosts: [
        RecordItemCost(
          itemId: oilA,
          materialCents: 4000,
          laborCents: 6000,
          costCents: 10000,
        ),
      ],
      costCents: 10000,
      mileageKm: 11000,
      sync: _sync,
    ),
  );
  await bundle.repository.saveMaintenanceRecord(
    MaintenanceRecord(
      carId: carB,
      date: const LocalDate(2026, 4, 1),
      itemIds: [oilB],
      itemCosts: [
        RecordItemCost(
          itemId: oilB,
          materialCents: 2000,
          laborCents: 3200,
          costCents: 5200,
        ),
      ],
      costCents: 5200,
      mileageKm: 20000,
      sync: _sync,
    ),
  );
  await bundle.setAppliedCarId(carA);
  return database;
}

/// 播种一辆车、无任何记录（空态/无汇总行用例）。
Future<AppDatabase> seedCarWithoutRecords() async {
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
      sync: _sync,
    ),
  );
  await bundle.setAppliedCarId(carId);
  return database;
}

/// 经深链通道打开统计页（go 语义落页，用于渲染/切换类断言；注意它
/// 不是 push——返回键用例必须走真实入口），并等数据与转场动画就绪。
Future<void> openCostStatsPage(WidgetTester tester) async {
  await pushRouteViaNavigationChannel('/cost-stats');
  await pumpUntilFound(tester, find.text('总花费'));
  await tester.pumpAndSettle();
}

void main() {
  group('花费统计页', () {
    testWidgets('默认当前车作用域：汇总/按年/项目占比/走势渲染', (tester) async {
      final database = await seedTwoCarsWithRecords();
      await pumpApp(tester, database: database);
      await openCostStatsPage(tester);

      // 汇总卡：默认作用域 = 应用车辆（车A），不含车B。
      expect(find.text('总花费'), findsOneWidget);
      expect(find.text('¥380.00'), findsOneWidget);
      expect(find.text('¥280.00'), findsWidgets); // 今年花费 + 2026 年横条。
      expect(find.text('¥52.00'), findsNothing);
      // 按年花费：两个年份横条。
      expect(find.text('按年花费'), findsOneWidget);
      expect(find.text('2025年'), findsOneWidget);
      expect(find.text('2026年'), findsOneWidget);
      // 项目占比：项目名经清单解析（机油），未知项目不出现。
      expect(find.text('项目占比'), findsOneWidget);
      expect(find.text('机油'), findsOneWidget);
      expect(find.text('未知项目'), findsNothing);
      // 近 12 个月走势 + 峰值（默认作用域峰值 = 280）。
      expect(find.text('近 12 个月走势'), findsOneWidget);
      expect(find.text('峰值 ¥280.00'), findsOneWidget);
      // 车辆 chips：应用车辆与"全部"两枚（车B 也有，共三枚）。
      expect(find.text('本田 思域（燃油版）'), findsOneWidget);
      expect(find.text('丰田 卡罗拉'), findsOneWidget);
      expect(find.text('全部'), findsOneWidget);
    });

    testWidgets('车辆切换：全部合并两车、切回单车只看该车', (tester) async {
      final database = await seedTwoCarsWithRecords();
      await pumpApp(tester, database: database);
      await openCostStatsPage(tester);

      // 切"全部"：两车合并（280+100+52 = 432）。
      await tester.tap(find.text('全部'));
      await pumpUntilFound(tester, find.text('¥432.00'));
      expect(find.text('¥380.00'), findsNothing);

      // 切车B：只看卡罗拉的记录。
      await tester.tap(find.text('丰田 卡罗拉'));
      await pumpUntilFound(tester, find.text('¥52.00'));
      expect(find.text('¥380.00'), findsNothing);
      expect(find.text('¥432.00'), findsNothing);
      // 项目占比只剩车B的机油费用。
      expect(find.text('峰值 ¥52.00'), findsOneWidget);
    });

    testWidgets('有车无记录：空态卡 + chips 仍在', (tester) async {
      final database = await seedCarWithoutRecords();
      await pumpApp(tester, database: database);
      await pushRouteViaNavigationChannel('/cost-stats');
      await pumpUntilFound(
        tester,
        find.text('暂无保养记录，记一笔保养后这里会生成花费统计。'),
      );
      await tester.pumpAndSettle();
      expect(find.text('总花费'), findsNothing);
      expect(find.text('本田 思域（燃油版）'), findsOneWidget);
      expect(find.text('全部'), findsOneWidget);
    });

    testWidgets('无车：提示先新增车辆', (tester) async {
      final database = AppDatabase.inMemory();
      addTearDown(database.close);
      final bundle = testRepository(database);
      await bundle.ensureBootstrapData();
      await pumpApp(tester, database: database);
      await pushRouteViaNavigationChannel('/cost-stats');
      await pumpUntilFound(tester, find.text('请先新增车辆'));
      // 无车不给车辆 chips。
      expect(find.text('全部'), findsNothing);
    });

    testWidgets('返回键回到来源页（走真实入口 push，深链是 go 语义无栈可弹）',
        (tester) async {
      final database = await seedTwoCarsWithRecords();
      await pumpApp(tester, database: database);
      await tester.tap(find.text('我的'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('查看'));
      await pumpUntilFound(tester, find.text('总花费'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
      expect(find.text('总花费'), findsNothing);
      // 回到我的页：花费统计设置行还在。
      expect(find.text('花费统计'), findsOneWidget);
    });
  });

  group('记录页汇总行入口', () {
    testWidgets('有记录时显示今年花费行，点按进统计页', (tester) async {
      final database = await seedTwoCarsWithRecords();
      await pumpApp(tester, database: database);
      await tester.tap(find.text('记录'));
      await tester.pumpAndSettle();
      expect(find.text('今年花费'), findsOneWidget);
      expect(find.text('¥280.00'), findsWidgets); // 汇总行 + 2026 记录卡。

      await tester.tap(find.text('花费统计'));
      await pumpUntilFound(tester, find.text('总花费'));
      expect(find.text('按年花费'), findsOneWidget);
    });

    testWidgets('无记录时不显示汇总行', (tester) async {
      final database = await seedCarWithoutRecords();
      await pumpApp(tester, database: database);
      await tester.tap(find.text('记录'));
      await tester.pumpAndSettle();
      expect(find.text('今年花费'), findsNothing);
      expect(find.text('花费统计'), findsNothing);
    });
  });

  group('我的页入口', () {
    testWidgets('花费统计设置行进统计页', (tester) async {
      final database = await seedTwoCarsWithRecords();
      await pumpApp(tester, database: database);
      await tester.tap(find.text('我的'));
      await tester.pumpAndSettle();
      expect(find.text('花费统计'), findsOneWidget);

      await tester.tap(find.text('查看'));
      await pumpUntilFound(tester, find.text('总花费'));
      expect(find.text('按年花费'), findsOneWidget);
    });
  });
}
