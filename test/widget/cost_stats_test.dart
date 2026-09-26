// cost_stats 域 widget 测试（共享夹具见 test/helpers/widget_app.dart）：
// 统计页渲染（汇总/指标/项目占比堆叠条与明细行/保养费用坐标系柱状图/
// 默认应用车辆作用域 + 副标题车辆名）、空态（无记录/无车）、守恒（其
// 他段吸收无归属费用）、优惠展示与三列对齐、单条记录保养费用卡隐藏、
// 加油卡坐标系月度柱、记录页汇总行入口、我的页入口、返回键。
// 播种必须在 pumpApp 之前：装配后直写库不会触发 provider 失效。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lunio/app/providers.dart';
import 'package:lunio/core/date/local_date.dart';
import 'package:lunio/data/database/app_database.dart';
import 'package:lunio/domain/entities/car.dart';
import 'package:lunio/domain/entities/fuel_price.dart';
import 'package:lunio/domain/entities/fuel_record.dart';
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

/// 播种一辆车 + 同年（2026）两条记录：2026-05-01 优惠记录（同
/// [seedCarWithDiscountRecord]）+ 2026-03-01 ¥100 简洁记录。单年双条，
/// 用于锁定"走势卡按记录条数判断、不按年份"（2026-09-23 拍板）。
Future<AppDatabase> seedCarWithTwoRecordsSameYear() async {
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
  await bundle.repository.saveMaintenanceRecord(
    MaintenanceRecord(
      carId: carId,
      date: const LocalDate(2026, 3, 1),
      // 简洁模式形态：挂项目但费用全空（校验要求 itemIds 非空）。
      itemIds: [oilId],
      itemCosts: const [],
      costCents: 10000,
      mileageKm: 11000,
      sync: _sync,
    ),
  );
  await bundle.setAppliedCarId(carId);
  return database;
}

/// 播种一辆车 + 两个项目各一条记录（有省/无省混合，2026-09-24 占比卡
/// 三列对齐用）：R1 机油计费 ¥100 = 总费用 ¥100（无省）；R2 机滤计费
/// ¥100、总费用 ¥80（省 ¥20 全归机滤）。占比行 = 机油 ¥100（56%）、
/// 机滤 ¥80（44%），总费用 ¥180。
Future<AppDatabase> seedCarWithMixedSaveRows() async {
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
  final items = await bundle.listMaintenanceItemsForCar(carId);
  final oilId = items.firstWhere((item) => item.name == '机油').id!;
  final filterId = items.firstWhere((item) => item.name == '机滤').id!;
  await bundle.repository.saveMaintenanceRecord(
    MaintenanceRecord(
      carId: carId,
      date: const LocalDate(2026, 5, 1),
      itemIds: [oilId],
      itemCosts: [
        RecordItemCost(
          itemId: oilId,
          materialCents: null,
          laborCents: null,
          costCents: 10000,
        ),
      ],
      costCents: 10000,
      mileageKm: 12000,
      sync: _sync,
    ),
  );
  await bundle.repository.saveMaintenanceRecord(
    MaintenanceRecord(
      carId: carId,
      date: const LocalDate(2026, 9, 1),
      itemIds: [filterId],
      itemCosts: [
        RecordItemCost(
          itemId: filterId,
          materialCents: null,
          laborCents: null,
          costCents: 10000,
        ),
      ],
      costCents: 8000,
      mileageKm: 12500,
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
      expect(find.text('今年保养'), findsOneWidget);
      // 无加油记录：汇总卡不显示"今年加油"栏，页面也无加油费用卡。
      expect(find.text('今年加油'), findsNothing);
      expect(find.text('加油费用'), findsNothing);
      // ¥280.00 两处：汇总卡"今年保养" + 走势卡 2026 柱顶（金额全格式）。
      expect(find.text('¥280.00'), findsNWidgets(2));
      expect(find.text('¥52.00'), findsNothing);
      // 汇总指标行：2 条记录、均价 19000、月均 = 38000 ÷ 15 个月 =
      // 2533（全程摊薄，2025-03 → 2026-05）、上次 18 天前。
      expect(find.text('保养次数'), findsOneWidget);
      expect(find.text('2 次'), findsOneWidget);
      expect(find.text('今年 1 次'), findsOneWidget);
      expect(find.text('¥190.00'), findsOneWidget);
      expect(find.text('¥25.33'), findsOneWidget);
      expect(find.text('18 天前'), findsOneWidget);
      // 项目占比（2026-09-24 C 方案）：机油实付 330（230+100，无优惠）
      // + 其他段 50（记录总费用超出项目合计的差额），守恒 330 + 50 = 380。
      expect(find.text('项目占比'), findsOneWidget);
      expect(find.text('机油'), findsOneWidget);
      expect(find.text('¥330.00'), findsOneWidget);
      expect(find.text('其他'), findsOneWidget);
      expect(find.text('¥50.00'), findsOneWidget);
      expect(find.text('累计优惠'), findsNothing);
      expect(find.text('未知项目'), findsNothing);
      // 保养费用卡（2026-09-24 改版）：2 条记录 → 展示；两年放得下、
      // 等分铺满无滚动条，柱顶标金额；柱高同一把尺（按峰刻度归一，比
      // 例 = 两年费用比）；纵轴三条刻度（峰值 ¥280 → 半峰步进 ¥200、
      // 峰 ¥400）。
      expect(find.text('保养费用'), findsOneWidget);
      expect(find.text('2025'), findsOneWidget);
      expect(find.text('2026'), findsOneWidget);
      expect(find.text('¥100.00'), findsOneWidget); // 2025 柱顶。
      expect(find.text('¥400'), findsOneWidget); // 纵轴峰刻度。
      final bar2025 = tester.getRect(
        find.byKey(const ValueKey('cost-year-bar-2025')),
      );
      final bar2026 = tester.getRect(
        find.byKey(const ValueKey('cost-year-bar-2026')),
      );
      expect(bar2025.width, 16.0); // 柱宽与月度柱统一（第五轮）。
      expect(bar2026.left - bar2025.left, greaterThan(150)); // 铺满等分。
      expect(bar2026.height / bar2025.height, closeTo(28000 / 10000, 0.1));
      // 两年放得下：不出现滚动条（滚动条只在超一屏时出现，第五轮）。
      expect(find.byType(Scrollbar), findsNothing);
      // 堆叠条（2026-09-24 C 方案）：分段宽度比 = 实付比（330 : 50）。
      final oilSeg = tester.getRect(
        find.byKey(const ValueKey('cost-seg-机油')),
      );
      final otherSeg = tester.getRect(
        find.byKey(const ValueKey('cost-seg-其他')),
      );
      expect(oilSeg.width / otherSeg.width, closeTo(33000 / 5000, 0.05));
      // 明细行三列竖向对齐（2026-09-24 用户点名）：百分比列与实付列的
      // 右边缘跨行相等（其他行无省额、留空不影响对齐）。
      expect(tester.getRect(find.text('87%')).right,
          tester.getRect(find.text('13%')).right);
      expect(tester.getRect(find.text('¥330.00')).right,
          tester.getRect(find.text('¥50.00')).right);
      // 作用域固定当前应用车辆：副标题展示车辆名，无"全部"/切车 chips
      //（2026-09-20 拍板：统计页不提供多车维度）。
      expect(find.text('当前车辆：本田 思域（燃油版）'), findsOneWidget);
      expect(find.text('丰田 卡罗拉'), findsNothing);
      expect(find.text('全部'), findsNothing);
    });

    testWidgets('单条记录：走势卡整卡不展示', (tester) async {
      final database = await seedCarWithDiscountRecord();
      await pumpApp(tester, database: database);
      await openCostStatsPage(tester);

      // 只有 1 条记录：没有对比，整卡隐藏（2026-09-23 拍板，替换原
      // "单年车"规则——判断口径改为记录条数）。
      expect(find.text('保养费用'), findsNothing);
      expect(find.text('2026'), findsNothing);
    });

    testWidgets('单年车两条记录：走势卡展示（按记录数不按年份判断）',
        (tester) async {
      final database = await seedCarWithTwoRecordsSameYear();
      await pumpApp(tester, database: database);
      await openCostStatsPage(tester);

      // 两条记录都在 2026：旧"单年车隐藏"规则会藏掉，新规则（≥2 条
      // 记录）展示单根年度柱。
      expect(find.text('保养费用'), findsOneWidget);
      expect(find.text('2026'), findsOneWidget);
      expect(find.byKey(const ValueKey('cost-year-bar-2026')), findsOneWidget);
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
      // 头部一行（2026-09-24 第五轮）：累计优惠与占比卡的"总费用"标签
      // 同一行（.at(1) = 占比卡那处，第一处在汇总卡）。
      expect(
        tester.getRect(find.text('累计优惠 ¥50.00')).top,
        tester.getRect(find.text('总费用').at(1)).top,
      );
      // 项目行：机油实付 180 + 省额小字 + 占比 100%（唯一项目）。
      expect(find.text('机油'), findsOneWidget);
      expect(find.text('省 ¥50.00'), findsOneWidget);
      expect(find.text('100%'), findsOneWidget);
      // 实付 180 与多处同串不计数：汇总卡两处 + 占比卡头部 + 项目行
      // + 指标行单次均价/月均（单月单条记录，两者都 = 总费用）= 6。
      expect(find.text('¥180.00'), findsNWidgets(6));
      // 有优惠记录：计费 230 − 优惠 50 = 实付 180 = 总费用，无缺口、
      // 无其他段。
      expect(find.text('其他'), findsNothing);
    });

    testWidgets('占比明细行跨行对齐：有省与无省混合（2026-09-24 用户点名）',
        (tester) async {
      final database = await seedCarWithMixedSaveRows();
      await pumpApp(tester, database: database);
      await openCostStatsPage(tester);

      // 两行：机油（无省、实付 ¥100、56%）与机滤（省 ¥20、实付 ¥80、
      // 44%）。无省行的省槽留空，不能把百分比列/实付列挤歪——三列右
      // 边缘跨行必须相等。
      expect(find.text('省 ¥20.00'), findsOneWidget);
      expect(tester.getRect(find.text('56%')).right,
          tester.getRect(find.text('44%')).right);
      final oilAmt = tester.getRect(
        find.descendant(
          of: find.byKey(const ValueKey('cost-amt-机油')),
          matching: find.text('¥100.00'),
        ),
      );
      final filterAmt = tester.getRect(
        find.descendant(
          of: find.byKey(const ValueKey('cost-amt-机滤')),
          matching: find.text('¥80.00'),
        ),
      );
      expect(oilAmt.right, filterAmt.right);
    });

    testWidgets('有车无记录：空态卡 + 副标题仍在', (tester) async {
      final database = await seedCarWithoutRecords();
      await pumpApp(tester, database: database);
      await pushRouteViaNavigationChannel('/cost-stats');
      await pumpUntilFound(
        tester,
        find.text('暂无保养/加油记录，记一笔后这里会生成费用统计。'),
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
    testWidgets('有记录时显示今年保养/今年加油汇总行，点按进统计页', (tester) async {
      final database = await seedTwoCarsWithRecords();
      await pumpApp(tester, database: database);
      await tester.tap(find.text('记录'));
      await tester.pumpAndSettle();
      expect(find.text('今年保养'), findsOneWidget);
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
      expect(find.text('今年保养'), findsNothing);
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

  group('加油费用卡（ADR 0015）', () {
    /// 播种一辆车（无保养记录）+ 两条加油记录：2026-09 实付 270、
    /// 2024-03 应付 300（跨两年，验证全历史月度柱铺满补 0 与实付优先
    /// 口径；生效今天固定 2026-05-19）。
    Future<AppDatabase> seedCarWithFuelRecords() async {
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
      await bundle.fuelRepository.saveFuelRecord(
        FuelRecord(
          carId: carId,
          date: const LocalDate(2026, 9, 1),
          grade: FuelGrade.gasoline92,
          unitPriceCents: 815,
          payableCents: 30000,
          actualCents: 27000,
          sync: _sync,
        ),
      );
      await bundle.fuelRepository.saveFuelRecord(
        FuelRecord(
          carId: carId,
          date: const LocalDate(2024, 3, 15),
          grade: FuelGrade.gasoline95,
          unitPriceCents: 855,
          payableCents: 30000,
          sync: _sync,
        ),
      );
      await bundle.setAppliedCarId(carId);
      return database;
    }

    testWidgets('只有加油记录：全历史月度柱初始停最右，保养区降轻提示', (
      tester,
    ) async {
      final database = await seedCarWithFuelRecords();
      await pumpApp(tester, database: database);
      await tester.tap(find.text('记录'));
      await tester.pumpAndSettle();
      // 记录页头部：只有加油记录 → 只显示"今年加油 ¥270.00"，
      // "今年保养"段隐藏（不留 ¥0.00 占位，2026-09-22 二轮反馈）。
      expect(find.text('今年保养'), findsNothing);
      expect(find.text('今年加油'), findsOneWidget);
      expect(find.text('¥270.00'), findsOneWidget);

      await tester.tap(find.text('费用统计'));
      await pumpUntilFound(tester, find.text('加油费用'));
      await tester.pumpAndSettle();
      // 加油卡（2026-09-24 第五轮头部一行）：总额 = 270 + 300 =
      // ¥570.00 + 月均（"N 笔"删除；2024-03 → 生效今天 2026-05 共 27
      // 个自然月，57000 ÷ 27 = 2111）；月度柱 = 全历史连续时间轴
      // （2024-03 → 2026-09，轴标签「26.9」式；加油记录晚于生效今天
      // 2026-05-19，属播种数据，序列防御性顺延）。
      expect(find.text('总费用'), findsOneWidget);
      expect(find.text('¥570.00'), findsOneWidget);
      expect(find.text('2 笔'), findsNothing); // 第五轮：笔数删除。
      expect(find.text('月均 ¥21.11'), findsOneWidget);
      expect(find.text('24.3'), findsOneWidget);
      expect(find.text('26.9'), findsOneWidget);
      // 柱顶金额：有花费月才标（¥300.00 = 2024-03 应付；¥270.00 =
      // 2026-09 实付，记录页同串故用 AtLeast）；补 0 月不标 → 全页无
      // ¥0.00。
      expect(find.text('¥300.00'), findsOneWidget);
      expect(find.text('¥270.00'), findsAtLeastNWidgets(1));
      expect(find.text('¥0.00'), findsNothing);
      // 坐标系纵轴（2026-09-24）：峰值月 ¥300 → 半峰步进 ¥200、峰 ¥400。
      expect(find.text('¥400'), findsOneWidget);
      expect(find.text('¥200'), findsOneWidget);
      // 年度行已删：卡内无任何按年统计的文案。
      expect(find.text('2026年'), findsNothing);
      expect(find.text('2025年'), findsNothing);
      expect(find.text('2024年'), findsNothing);
      // 初始停最右（2026-09-23 拍板）：首月「24.3」被滚出视口左侧，
      // 最近月「26.9」落在测试窗口（800 宽）内；31 个月 × 64 列宽超一
      // 屏 → 底部出现滚动条（第五轮；2026-09-26 起滑动时才显示拇指）。
      expect(tester.getRect(find.text('24.3')).right, lessThan(0));
      expect(tester.getRect(find.text('26.9')).right, lessThan(800));
      expect(find.byType(Scrollbar), findsOneWidget);
      expect(
        tester.widget<Scrollbar>(find.byType(Scrollbar)).thumbVisibility,
        isNot(true),
      );
      // 保养汇总卡不存在：无"今年保养"文字；保养区只有一行轻提示。
      expect(find.text('今年保养'), findsNothing);
      expect(
        find.text('暂无保养记录，记一笔保养后这里会生成保养费用统计。'),
        findsOneWidget,
      );
    });

    /// 播种一辆车：一条保养记录（2026-05-01 机油 ¥100）+ 一条加油记录
    /// （2026-09-01 应付 300 实付 270）——验证汇总卡三栏与加油卡并存。
    Future<AppDatabase> seedCarWithMaintenanceAndFuel() async {
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
      final oilId = (await bundle.listMaintenanceItemsForCar(carId))
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
              materialCents: null,
              laborCents: null,
              costCents: 10000,
            ),
          ],
          costCents: 10000,
          mileageKm: 12000,
          sync: _sync,
        ),
      );
      await bundle.fuelRepository.saveFuelRecord(
        FuelRecord(
          carId: carId,
          date: const LocalDate(2026, 9, 1),
          grade: FuelGrade.gasoline92,
          unitPriceCents: 815,
          payableCents: 30000,
          actualCents: 27000,
          sync: _sync,
        ),
      );
      await bundle.setAppliedCarId(carId);
      return database;
    }

    testWidgets('保养与加油并存：汇总卡三栏，加油费用卡在页面最后', (
      tester,
    ) async {
      final database = await seedCarWithMaintenanceAndFuel();
      await pumpApp(tester, database: database);
      await tester.tap(find.text('记录'));
      await tester.pumpAndSettle();
      // 记录页头部两段都在：今年保养 ¥100.00 + 今年加油 ¥270.00
      // （¥100.00 另一处是保养记录卡上的总费用，共两处）。
      expect(find.text('今年保养'), findsOneWidget);
      expect(find.text('¥100.00'), findsNWidgets(2));
      expect(find.text('今年加油'), findsOneWidget);
      expect(find.text('¥270.00'), findsOneWidget);

      await tester.tap(find.text('费用统计'));
      await pumpUntilFound(tester, find.text('加油费用'));
      await tester.pumpAndSettle();
      // 汇总卡三栏：总费用 | 今年保养 | 今年加油。push 后来源页是否仍
      // 可寻址随路由树时序浮动，跨页文字一律用 AtLeast 断言（"总费用"
      // 在汇总卡 + 占比卡锚点 + 加油卡标签至少三处）。
      expect(find.text('今年保养'), findsAtLeastNWidgets(1));
      expect(find.text('今年加油'), findsAtLeastNWidgets(1));
      expect(find.text('总费用'), findsAtLeastNWidgets(3));
      // 保养与加油各卡并存：走势卡（只有 1 条保养记录不显示，2026-09-23
      // 新规则）与加油卡。加油月均：唯一记录晚于生效今天（2026-09 >
      // 2026-05）→ 按 1 个月摊 = ¥270.00（第五轮口径）。
      expect(find.text('保养费用'), findsNothing);
      expect(find.text('加油费用'), findsOneWidget);
      expect(find.text('月均 ¥270.00'), findsOneWidget);
      expect(find.text('¥570.00'), findsNothing); // 加油总额只有一笔 270。
    });
  });
}
