// cost_stats 域 widget 测试（共享夹具见 test/helpers/widget_app.dart）：
// 统计页渲染（汇总/指标/项目占比条形列表/年度走势/默认应用车辆作用域 +
// 副标题车辆名）、空态（无记录/无车）、守恒（其他段吸收无归属费用）、
// 优惠展示、单年车走势隐藏、记录页汇总行入口、我的页入口、返回键。
// 播种必须在 pumpApp 之前：装配后直写库不会触发 provider 失效。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lunio/app/providers.dart';
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
///   车A（本田 思域，应用车辆）：2026-05-01 ¥280（机油项目费用 ¥230，
///     总费用超出项目合计 ¥50 → 其他段）、2025-03-01 ¥100（机油 ¥100）
///   车B（丰田 卡罗拉）：2026-04-01 ¥52（机油项目费用 ¥52）
/// 生效今天 = 2026-05-19（pumpApp 固定）。默认作用域 = 车A：
/// 总 ¥380.00、今年 ¥280.00、占比卡 = 机油 ¥330 + 其他 ¥50（守恒）；
/// 月均 = 38000 ÷ 15 个月（2025-03 → 2026-05）= ¥25.33。
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

/// 播种一辆车 + 一条带优惠的记录（单年数据）：机油计费 230
/// （材料 150 + 工时 80），总费用 180 → 记录级优惠 50
///（生效今天 = 2026-05-19）。
Future<AppDatabase> seedCarWithDiscountRecord() async {
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
  final oilId =
      (await bundle.listMaintenanceItemsForCar(carId))
          .firstWhere((item) => item.name == '机油')
          .id!;
  await bundle.repository.saveMaintenanceRecord(
    MaintenanceRecord(
      carId: carId,
      date: const LocalDate(2026, 5, 1),
      itemIds: [oilId],
      itemCosts: [
        RecordItemCost(
          itemId: oilId,
          materialCents: 15000,
          laborCents: 8000,
          costCents: 23000,
        ),
      ],
      costCents: 18000,
      mileageKm: 12000,
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
  await pumpUntilFound(tester, find.text('总费用'));
  await tester.pumpAndSettle();
}

void main() {
  group('费用统计页', () {
    testWidgets('默认应用车辆作用域：汇总/指标/项目占比/年度走势渲染', (tester) async {
      final database = await seedTwoCarsWithRecords();
      await pumpApp(tester, database: database);
      await openCostStatsPage(tester);

      // 汇总卡：作用域固定 = 应用车辆（车A），不含车B。总费用在汇总卡
      // 与占比卡头部各一处（守恒锚点），金额同串。
      expect(find.text('总费用'), findsNWidgets(2));
      expect(find.text('¥380.00'), findsNWidgets(2));
      expect(find.text('今年费用'), findsOneWidget);
      expect(find.text('¥280.00'), findsOneWidget);
      expect(find.text('¥52.00'), findsNothing);
      // 汇总指标行：2 条记录、均价 19000、月均 = 38000 ÷ 15 个月 =
      // 2533（全程摊薄，2025-03 → 2026-05）、上次 18 天前。
      expect(find.text('保养次数'), findsOneWidget);
      expect(find.text('2 次'), findsOneWidget);
      expect(find.text('今年 1 次'), findsOneWidget);
      expect(find.text('¥190.00'), findsOneWidget);
      expect(find.text('¥25.33'), findsOneWidget);
      expect(find.text('18 天前'), findsOneWidget);
      // 项目占比条形列表：机油实付 330（230+100，无优惠）+ 其他段 50
      //（记录总费用超出项目合计的差额），守恒 330 + 50 = 380。
      expect(find.text('项目占比'), findsOneWidget);
      expect(find.text('机油'), findsOneWidget);
      expect(find.text('¥330.00'), findsOneWidget);
      expect(find.text('其他'), findsOneWidget);
      expect(find.text('¥50.00'), findsOneWidget);
      expect(find.text('累计优惠'), findsNothing);
      expect(find.text('未知项目'), findsNothing);
      // 年度走势卡：两个年份 → 展示；画布真的有宽度（零宽 bug 回归锚）。
      expect(find.text('费用走势'), findsOneWidget);
      expect(find.text('2025'), findsOneWidget);
      expect(find.text('2026'), findsOneWidget);
      final trendPaint = tester.getSize(
        find.byKey(const ValueKey('cost-trend-paint')),
      );
      expect(trendPaint.width, greaterThan(200));
      // 条形统一起点 + 同一比例尺（Table 三列全表定宽）：机油行与"其他"
      // 行的条形左边缘相同，宽度比 = 实付比（330 : 50）。轨道若随行内
      // 内容宽窄变化（旧行式布局），比例会失真、此处即红。
      final oilBar = tester.getRect(
        find.byKey(const ValueKey('cost-bar-机油')),
      );
      final otherBar = tester.getRect(
        find.byKey(const ValueKey('cost-bar-其他')),
      );
      expect(oilBar.left, otherBar.left);
      expect(oilBar.width / otherBar.width, closeTo(33000 / 5000, 0.05));
      // 作用域固定当前应用车辆：副标题展示车辆名，无"全部"/切车 chips
      //（2026-09-20 拍板：统计页不提供多车维度）。
      expect(find.text('当前车辆：本田 思域（燃油版）'), findsOneWidget);
      expect(find.text('丰田 卡罗拉'), findsNothing);
      expect(find.text('全部'), findsNothing);
    });

    testWidgets('单年车：走势卡整卡不展示', (tester) async {
      final database = await seedCarWithDiscountRecord();
      await pumpApp(tester, database: database);
      await openCostStatsPage(tester);

      // 只有一年数据（2026）：没有走势可看，整卡隐藏（2026-09-21 拍板）。
      expect(find.text('费用走势'), findsNothing);
      expect(find.text('2026'), findsNothing);
    });

    testWidgets('点项目行打开项目档案 sheet', (tester) async {
      final database = await seedTwoCarsWithRecords();
      await pumpApp(tester, database: database);
      await openCostStatsPage(tester);

      await tester.tap(find.text('机油'));
      await pumpUntilFound(tester, find.text('逐次明细'));
      // 档案头：累计实付 330（23000 + 10000，无优惠）。
      expect(find.text('累计实付 ¥330.00'), findsOneWidget);
      expect(find.text('2 次'), findsNWidgets(2)); // 指标卡 + 档案各一处。
      expect(find.text('¥165.00'), findsOneWidget); // 单次均价 33000/2。
      // 逐次两行（日期倒序）。
      expect(find.text('2026-05-01'), findsOneWidget);
      expect(find.text('2025-03-01'), findsOneWidget);
      // 点遮罩关闭。
      await tester.tapAt(const Offset(20, 120));
      await tester.pumpAndSettle();
      expect(find.text('逐次明细'), findsNothing);
    });

    testWidgets('优惠展示：头部总费用 + 累计优惠、项目行省额', (tester) async {
      final database = await seedCarWithDiscountRecord();
      await pumpApp(tester, database: database);
      await openCostStatsPage(tester);

      // 占比卡头部：总费用 180（= 项目实付合计，无其他段）+ 累计优惠。
      expect(find.text('总费用'), findsNWidgets(2));
      expect(find.text('累计优惠 ¥50.00'), findsOneWidget);
      // 项目行：机油实付 180 + 省额小字。
      expect(find.text('机油'), findsOneWidget);
      expect(find.text('省 ¥50.00'), findsOneWidget);
      // 实付 180 与多处同串不计数：汇总卡两处 + 占比卡头部 + 项目行
      // + 指标行单次均价/月均（单月单条记录，两者都 = 总费用）= 6。
      expect(find.text('¥180.00'), findsNWidgets(6));
      // 有优惠记录：计费 230 − 优惠 50 = 实付 180 = 总费用，无缺口、
      // 无其他段。
      expect(find.text('其他'), findsNothing);
    });

    testWidgets('有车无记录：空态卡 + 副标题仍在', (tester) async {
      final database = await seedCarWithoutRecords();
      await pumpApp(tester, database: database);
      await pushRouteViaNavigationChannel('/cost-stats');
      await pumpUntilFound(
        tester,
        find.text('暂无保养记录，记一笔保养后这里会生成费用统计。'),
      );
      await tester.pumpAndSettle();
      expect(find.text('总费用'), findsNothing);
      expect(find.textContaining('当前车辆：'), findsOneWidget);
      expect(find.text('全部'), findsNothing);
    });

    testWidgets('无车：提示先新增车辆', (tester) async {
      final database = AppDatabase.inMemory();
      addTearDown(database.close);
      final bundle = testRepository(database);
      await bundle.ensureBootstrapData();
      await pumpApp(tester, database: database);
      await pushRouteViaNavigationChannel('/cost-stats');
      await pumpUntilFound(tester, find.text('请先新增车辆'));
      // 无车没有副标题车辆名，也没有任何作用域切换。
      expect(find.textContaining('当前车辆'), findsNothing);
      expect(find.text('全部'), findsNothing);
    });

    testWidgets('返回键回到来源页（走真实入口 push，深链是 go 语义无栈可弹）',
        (tester) async {
      final database = await seedTwoCarsWithRecords();
      await pumpApp(tester, database: database);
      await tester.tap(find.text('我的'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('查看'));
      await pumpUntilFound(tester, find.text('总费用'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
      expect(find.text('总费用'), findsNothing);
      // 回到我的页：费用统计设置行还在。
      expect(find.text('费用统计'), findsOneWidget);
    });

    testWidgets('车辆清单加载失败：错误页兜底且保留返回键', (tester) async {
      final database = await seedTwoCarsWithRecords();
      await pumpApp(
        tester,
        database: database,
        extraOverrides: [
          // 车辆清单 provider 直接抛错（应用车辆由它派生，一起失败）：
          // 统计页必须给出错误页而不是停在整页 loading（错误分支曾经
          // 不可达，carsProvider 失败时页面永久加载）。
          carsProvider.overrideWith(
            (ref) async => throw Exception('db down'),
          ),
        ],
      );
      await pushRouteViaNavigationChannel('/cost-stats');
      await pumpUntilFound(tester, find.textContaining('加载失败'));
      await tester.pumpAndSettle();
      expect(find.textContaining('加载失败'), findsOneWidget);
      // 错误分支也要有页内返回键（pushed 子页无底部导航可退）。
      expect(find.byTooltip('返回'), findsOneWidget);
    });
  });

  group('记录页汇总行入口', () {
    testWidgets('有记录时显示今年费用行，点按进统计页', (tester) async {
      final database = await seedTwoCarsWithRecords();
      await pumpApp(tester, database: database);
      await tester.tap(find.text('记录'));
      await tester.pumpAndSettle();
      expect(find.text('今年费用'), findsOneWidget);
      expect(find.text('¥280.00'), findsWidgets); // 汇总行 + 2026 记录卡。

      await tester.tap(find.text('费用统计'));
      await pumpUntilFound(tester, find.text('总费用'));
      expect(find.text('项目占比'), findsOneWidget);
    });

    testWidgets('无记录时不显示汇总行', (tester) async {
      final database = await seedCarWithoutRecords();
      await pumpApp(tester, database: database);
      await tester.tap(find.text('记录'));
      await tester.pumpAndSettle();
      expect(find.text('今年费用'), findsNothing);
      expect(find.text('费用统计'), findsNothing);
    });
  });

  group('我的页入口', () {
    testWidgets('费用统计设置行进统计页', (tester) async {
      final database = await seedTwoCarsWithRecords();
      await pumpApp(tester, database: database);
      await tester.tap(find.text('我的'));
      await tester.pumpAndSettle();
      expect(find.text('费用统计'), findsOneWidget);

      await tester.tap(find.text('查看'));
      await pumpUntilFound(tester, find.text('总费用'));
      expect(find.text('项目占比'), findsOneWidget);
    });
  });
}
