// fuel 域 widget 测试（共享夹具见 test/helpers/widget_app.dart）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lunio/domain/entities/fuel_price.dart';
import 'package:lunio/domain/entities/fuel_prediction.dart';
import 'package:lunio/domain/entities/fuel_record.dart';
import 'package:lunio/core/theme/lunio_tokens.dart';
import 'package:lunio/features/shell/fuel/fuel_records_card.dart';
import 'package:lunio/features/shell/shared/shared_widgets.dart';

import 'package:lunio/core/date/local_date.dart';
import 'package:lunio/data/database/app_database.dart';
import 'package:lunio/domain/entities/car.dart';
import 'package:lunio/domain/entities/maintenance_item.dart';
import 'package:lunio/domain/entities/sync_metadata.dart';
import '../helpers/widget_app.dart';

void main() {
  testWidgets('fuel prediction developer switch toggles fuel tab instantly', (
    tester,
  ) async {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    final repository = testRepository(database);
    await repository.ensureBootstrapData();
    await repository.setPreferenceValue('developerModeEnabled', 'true');
    await pumpApp(tester, database: database);

    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();

    // 开发者模式打开后出现"加油预测"开关行；默认关闭，底部没有加油 tab。
    expect(find.text('加油预测'), findsOneWidget);
    expect(find.byType(Switch), findsOneWidget);
    expect(find.text('加油'), findsNothing);

    // 打开开关：底部导航实时出现加油 tab（无需重启 App）。
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.text('加油'), findsOneWidget);

    // 再次关闭：加油 tab 消失，数据入口同步隐藏。
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.text('加油'), findsNothing);
  });


  testWidgets('fuel page shows fill cost tiers with capacity and mock price', (
    tester,
  ) async {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    final repository = testRepository(database);
    final sync = SyncMetadata(
      status: SyncStatus.synced,
      updatedAt: DateTime(2026),
    );
    await repository.ensureBootstrapData();
    await repository.setPreferenceValue('developerModeEnabled', 'true');
    await repository.setPreferenceValue('fuelPredictionEnabled', 'true');
    await repository.setPreferenceValue('fuelProvince', '湖北');
    final carId = await repository.createCarWithMaintenanceItems(
      Car(
        brand: '本田',
        model: '22款思域',
        currentMileageKm: 10000,
        roadDate: const LocalDate(2023, 8, 12),
        tankCapacityLiters: 55,
        sync: sync,
      ),
      [
        MaintenanceItem(
          carsId: 0,
          name: '机油',
          enabled: true,
          remindByMileage: true,
          remindByTime: false,
          mileageIntervalKm: 5000,
          timeIntervalMonths: null,
          notOverdueUpperLimit: 100,
          overdueUpperLimit: 125,
          sortOrder: 0,
          sync: sync,
        ),
      ],
    );
    await repository.setAppliedCarId(carId);
    await repository.saveFuelPrediction(
      FuelPrediction(carId: carId, fuelPercent: 50),
    );
    await pumpApp(tester, database: database);

    await tester.tap(find.text('加油'));
    await tester.pumpAndSettle();

    // 页面骨架：没有独立设置区/剩余油量区，省份与油品是油价卡副标题的
    // 两个可点段。
    expect(find.text('当前油价'), findsOneWidget);
    expect(find.text('剩余油量'), findsNothing);
    expect(find.text('加油设置'), findsNothing);
    expect(find.text('湖北'), findsOneWidget);
    expect(find.text('92#'), findsOneWidget);
    // 油价来自测试假源，但界面不标注数据来源。
    expect(find.textContaining('示例数据'), findsNothing);
    // 预估下次油价块：假源默认无调价预告，显示占位文案，无涨跌箭头。
    expect(find.text('预估下次油价'), findsOneWidget);
    expect(find.text('暂无调价预测'), findsOneWidget);
    expect(find.byIcon(Icons.trending_up), findsNothing);
    expect(find.byIcon(Icons.trending_down), findsNothing);
    // 档位列表：表头四列；已存的 50% 定位在第一行，窗口内往下可见
    // 48/46/44/42。
    expect(find.text('当前油量'), findsOneWidget);
    expect(find.text('可加油量'), findsOneWidget);
    expect(find.text('加满价格'), findsOneWidget);
    expect(find.text('调价后价格'), findsOneWidget);
    expect(find.text('50%'), findsOneWidget);
    expect(find.textContaining('（当前）'), findsNothing);
    expect(find.text('48%'), findsOneWidget);
    expect(find.text('46%'), findsOneWidget);
    expect(find.text('44%'), findsOneWidget);
    expect(find.text('42%'), findsOneWidget);
    // 50% 档：55 升 × 50% = 27.5 升（当前油量与可加油量相同，各一列）；
    // 湖北 92# 假源价 7.61，27.5 × 7.61 = 209.28 元。
    expect(find.text('27.5 升'), findsNWidgets(2));
    expect(find.text('¥209.28'), findsOneWidget);
    // 无调价预告时"调价后价格"列显示占位符（可见 5 档各一个）。
    expect(find.text('—'), findsNWidgets(5));
  });


  testWidgets('fuel page shows predicted price from adjustment forecast', (
    tester,
  ) async {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    final repository = testRepository(database);
    final sync = SyncMetadata(
      status: SyncStatus.synced,
      updatedAt: DateTime(2026),
    );
    await repository.ensureBootstrapData();
    await repository.setPreferenceValue('developerModeEnabled', 'true');
    await repository.setPreferenceValue('fuelPredictionEnabled', 'true');
    await repository.setPreferenceValue('fuelProvince', '湖北');
    final carId = await repository.createCarWithMaintenanceItems(
      Car(
        brand: '本田',
        model: '22款思域',
        currentMileageKm: 10000,
        roadDate: const LocalDate(2023, 8, 12),
        tankCapacityLiters: 55,
        sync: sync,
      ),
      [
        MaintenanceItem(
          carsId: 0,
          name: '机油',
          enabled: true,
          remindByMileage: true,
          remindByTime: false,
          mileageIntervalKm: 5000,
          timeIntervalMonths: null,
          notOverdueUpperLimit: 100,
          overdueUpperLimit: 125,
          sortOrder: 0,
          sync: sync,
        ),
      ],
    );
    await repository.setAppliedCarId(carId);
    await repository.saveFuelPrediction(
      FuelPrediction(carId: carId, fuelPercent: 50),
    );
    // 调价预告：9月11日上调 0.05~0.06 → 中值 0.055，预估价 7.67。
    await pumpApp(
      tester,
      database: database,
      fuelForecast: const FuelAdjustmentForecast(
        month: 9,
        day: 11,
        trend: FuelPriceTrend.up,
        minChangePerLiter: 0.05,
        maxChangePerLiter: 0.06,
      ),
    );

    await tester.tap(find.text('加油'));
    await tester.pumpAndSettle();

    // 预估下次油价块：预估价 + 调价日期，样式与当前油价行一致。
    expect(find.text('7.67 元/升'), findsOneWidget);
    expect(find.text('9月11日调价'), findsOneWidget);
    // 涨跌箭头：预告上调 → 红色上行箭头（红涨绿跌），且无下行箭头。
    expect(find.byIcon(Icons.trending_up), findsOneWidget);
    expect(find.byIcon(Icons.trending_down), findsNothing);
    final tokens = Theme.of(
      tester.element(find.text('预估下次油价')),
    ).extension<LunioTokens>()!;
    expect(
      tester.widget<Icon>(find.byIcon(Icons.trending_up)).color,
      tokens.danger,
    );
    // 调价后价格列：50% 档 27.5 × 7.67 = 210.93；当前价列不受影响。
    expect(find.text('¥209.28'), findsOneWidget);
    expect(find.text('¥210.93'), findsOneWidget);
  });

  testWidgets('fuel page hides expired forecast and shows placeholders', (
    tester,
  ) async {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    final repository = testRepository(database);
    final sync = SyncMetadata(
      status: SyncStatus.synced,
      updatedAt: DateTime(2026),
    );
    await repository.ensureBootstrapData();
    await repository.setPreferenceValue('developerModeEnabled', 'true');
    await repository.setPreferenceValue('fuelPredictionEnabled', 'true');
    final carId = await repository.createCarWithMaintenanceItems(
      Car(
        brand: '本田',
        model: '22款思域',
        currentMileageKm: 10000,
        roadDate: const LocalDate(2023, 8, 12),
        tankCapacityLiters: 55,
        sync: sync,
      ),
      [
        MaintenanceItem(
          carsId: 0,
          name: '机油',
          enabled: true,
          remindByMileage: true,
          remindByTime: false,
          mileageIntervalKm: 5000,
          timeIntervalMonths: null,
          notOverdueUpperLimit: 100,
          overdueUpperLimit: 125,
          sortOrder: 0,
          sync: sync,
        ),
      ],
    );
    await repository.setAppliedCarId(carId);
    // 过期预告：调价日 5月18日 早于固定"今天"2026-05-19（次日即过期）。
    await pumpApp(
      tester,
      database: database,
      fuelForecast: const FuelAdjustmentForecast(
        month: 5,
        day: 18,
        trend: FuelPriceTrend.up,
        minChangePerLiter: 0.05,
        maxChangePerLiter: 0.06,
      ),
    );

    await tester.tap(find.text('加油'));
    await tester.pumpAndSettle();

    // 过期预告按无预告处理：预估块占位、无箭头、调价后价格列全"—"。
    expect(find.text('暂无调价预测'), findsOneWidget);
    expect(find.byIcon(Icons.trending_up), findsNothing);
    expect(find.byIcon(Icons.trending_down), findsNothing);
    expect(find.text('5月18日调价'), findsNothing);
    expect(find.text('—'), findsNWidgets(5));
    // 油价主体不受预告过期影响，当前价照常展示。
    expect(find.text('7.61 元/升'), findsOneWidget);
  });

  testWidgets('fuel forecast down trend shows green falling arrow', (
    tester,
  ) async {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    final repository = testRepository(database);
    await repository.ensureBootstrapData();
    await repository.setPreferenceValue('developerModeEnabled', 'true');
    await repository.setPreferenceValue('fuelPredictionEnabled', 'true');
    final carId = await createCarWithDefaultItems(
      database,
      Car(
        brand: '本田',
        model: '22款思域',
        currentMileageKm: 10000,
        roadDate: const LocalDate(2023, 8, 12),
        sync: SyncMetadata(status: SyncStatus.synced, updatedAt: DateTime(2026)),
      ),
    );
    await repository.setAppliedCarId(carId);
    // 调价预告：9月11日下调 → 绿色下行箭头（红涨绿跌）。
    await pumpApp(
      tester,
      database: database,
      fuelForecast: const FuelAdjustmentForecast(
        month: 9,
        day: 11,
        trend: FuelPriceTrend.down,
        minChangePerLiter: 0.05,
        maxChangePerLiter: 0.06,
      ),
    );

    await tester.tap(find.text('加油'));
    await tester.pumpAndSettle();

    expect(find.text('预估下次油价'), findsOneWidget);
    expect(find.byIcon(Icons.trending_down), findsOneWidget);
    expect(find.byIcon(Icons.trending_up), findsNothing);
    final tokens = Theme.of(
      tester.element(find.text('预估下次油价')),
    ).extension<LunioTokens>()!;
    expect(
      tester.widget<Icon>(find.byIcon(Icons.trending_down)).color,
      tokens.success,
    );
  });


  testWidgets('fuel page persists baseline tier after scrolling tier list', (
    tester,
  ) async {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    final repository = testRepository(database);
    final sync = SyncMetadata(
      status: SyncStatus.synced,
      updatedAt: DateTime(2026),
    );
    await repository.ensureBootstrapData();
    await repository.setPreferenceValue('developerModeEnabled', 'true');
    await repository.setPreferenceValue('fuelPredictionEnabled', 'true');
    final carId = await repository.createCarWithMaintenanceItems(
      Car(
        brand: '本田',
        model: '22款思域',
        currentMileageKm: 10000,
        roadDate: const LocalDate(2023, 8, 12),
        tankCapacityLiters: 55,
        sync: sync,
      ),
      [
        MaintenanceItem(
          carsId: 0,
          name: '机油',
          enabled: true,
          remindByMileage: true,
          remindByTime: false,
          mileageIntervalKm: 5000,
          timeIntervalMonths: null,
          notOverdueUpperLimit: 100,
          overdueUpperLimit: 125,
          sortOrder: 0,
          sync: sync,
        ),
      ],
    );
    await repository.setAppliedCarId(carId);
    // 没保存过的车：默认按 50% 定位，不落库。
    await pumpApp(tester, database: database);

    await tester.tap(find.text('加油'));
    await tester.pumpAndSettle();

    expect(
      await repository.getFuelPredictionForCar(carId),
      isNull,
      reason: '进入页面不写库',
    );

    // 向上拖三行左右：吸附物理按拖动末速度投射惯性停点再取整行档位
    // （132px 匀速拖动的末速度会多走约一档，落点确定可复现），
    // 停稳后自动把该档位写库。
    await tester.timedDrag(find.text('50%'), const Offset(0, -132), const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    final saved = await repository.getFuelPredictionForCar(carId);
    expect(saved?.fuelPercent, 42);
    expect(find.text('42%'), findsOneWidget);
  });


  testWidgets('fuel page reset icon scrolls baseline back to 50%', (
    tester,
  ) async {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    final repository = testRepository(database);
    final sync = SyncMetadata(
      status: SyncStatus.synced,
      updatedAt: DateTime(2026),
    );
    await repository.ensureBootstrapData();
    await repository.setPreferenceValue('developerModeEnabled', 'true');
    await repository.setPreferenceValue('fuelPredictionEnabled', 'true');
    final carId = await repository.createCarWithMaintenanceItems(
      Car(
        brand: '本田',
        model: '22款思域',
        currentMileageKm: 10000,
        roadDate: const LocalDate(2023, 8, 12),
        tankCapacityLiters: 55,
        sync: sync,
      ),
      [
        MaintenanceItem(
          carsId: 0,
          name: '机油',
          enabled: true,
          remindByMileage: true,
          remindByTime: false,
          mileageIntervalKm: 5000,
          timeIntervalMonths: null,
          notOverdueUpperLimit: 100,
          overdueUpperLimit: 125,
          sortOrder: 0,
          sync: sync,
        ),
      ],
    );
    await repository.setAppliedCarId(carId);
    await repository.saveFuelPrediction(
      FuelPrediction(carId: carId, fuelPercent: 50),
    );
    await pumpApp(tester, database: database);

    await tester.tap(find.text('加油'));
    await tester.pumpAndSettle();

    // 滚走基准档后点返回图标：滚回 50% 在第一行并写库。
    await tester.timedDrag(find.text('50%'), const Offset(0, -132), const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('回到 50%'));
    await tester.pumpAndSettle();

    expect(find.text('50%'), findsOneWidget);
    expect(
      (await repository.getFuelPredictionForCar(carId))?.fuelPercent,
      50,
    );
  });


  testWidgets('fuel page opens province and grade picker sheets from price card', (
    tester,
  ) async {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    final repository = testRepository(database);
    final sync = SyncMetadata(
      status: SyncStatus.synced,
      updatedAt: DateTime(2026),
    );
    await repository.ensureBootstrapData();
    await repository.setPreferenceValue('developerModeEnabled', 'true');
    await repository.setPreferenceValue('fuelPredictionEnabled', 'true');
    await repository.setPreferenceValue('fuelProvince', '湖北');
    final carId = await repository.createCarWithMaintenanceItems(
      Car(
        brand: '本田',
        model: '22款思域',
        currentMileageKm: 10000,
        roadDate: const LocalDate(2023, 8, 12),
        tankCapacityLiters: 55,
        sync: sync,
      ),
      [
        MaintenanceItem(
          carsId: 0,
          name: '机油',
          enabled: true,
          remindByMileage: true,
          remindByTime: false,
          mileageIntervalKm: 5000,
          timeIntervalMonths: null,
          notOverdueUpperLimit: 100,
          overdueUpperLimit: 125,
          sortOrder: 0,
          sync: sync,
        ),
      ],
    );
    await repository.setAppliedCarId(carId);
    await pumpApp(tester, database: database);

    await tester.tap(find.text('加油'));
    await tester.pumpAndSettle();

    // 点副标题油品段 → 弹出油品选择 sheet（4 个胶囊一行单选，贴内容收缩）。
    await tester.tap(find.text('92#'));
    await tester.pumpAndSettle();
    expect(find.text('选择油品'), findsOneWidget);
    // 油品只有 4 项：sheet 用一行胶囊贴内容收缩，不出现下方空白
    // （用户反馈过列表版留白，这里守住总高度上限）。
    expect(
      tester.getRect(find.byType(PrototypeSheetFrame)).height,
      lessThan(200),
    );
    // 选 95#：关 sheet、写偏好、副标题跟着变。
    await tester.tap(find.text('95#'));
    await tester.pumpAndSettle();
    expect(find.text('选择油品'), findsNothing);
    expect(await repository.getPreferenceValue('fuelGrade'), '95');
    expect(find.text('95#'), findsOneWidget);

    // 点副标题省份段 → 弹出省份选择 sheet（限高滚动）。
    await tester.tap(find.text('湖北'));
    await tester.pumpAndSettle();
    expect(find.text('选择省份'), findsOneWidget);
    // 选广东：关 sheet、写省份偏好。缓存是单省价表（ADR 0011），换省后
    // 省份不匹配按"暂无数据"展示，不自动拉取。
    await tester.tap(find.text('广东'));
    await tester.pumpAndSettle();
    expect(find.text('选择省份'), findsNothing);
    expect(await repository.getPreferenceValue('fuelProvince'), '广东');
    expect(find.text('广东'), findsOneWidget);
    expect(find.text('— 元/升'), findsOneWidget);
    expect(find.text('暂无数据'), findsOneWidget);

    // 手动点"刷新"：按当前省份拉取。此前油品已切到 95#，出广东 95# 价。
    await tester.tap(find.text('刷新'));
    await tester.pumpAndSettle();
    expect(find.text('8.17 元/升'), findsOneWidget);
    expect(find.text('暂无数据'), findsNothing);
  });


  testWidgets('fuel page guides to fill tank capacity before costing', (
    tester,
  ) async {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    final repository = testRepository(database);
    final sync = SyncMetadata(
      status: SyncStatus.synced,
      updatedAt: DateTime(2026),
    );
    await repository.ensureBootstrapData();
    await repository.setPreferenceValue('developerModeEnabled', 'true');
    await repository.setPreferenceValue('fuelPredictionEnabled', 'true');
    final carId = await repository.createCarWithMaintenanceItems(
      Car(
        brand: '本田',
        model: '22款思域',
        currentMileageKm: 10000,
        roadDate: const LocalDate(2023, 8, 12),
        sync: sync,
      ),
      [
        MaintenanceItem(
          carsId: 0,
          name: '机油',
          enabled: true,
          remindByMileage: true,
          remindByTime: false,
          mileageIntervalKm: 5000,
          timeIntervalMonths: null,
          notOverdueUpperLimit: 100,
          overdueUpperLimit: 125,
          sortOrder: 0,
          sync: sync,
        ),
      ],
    );
    await repository.setAppliedCarId(carId);
    await pumpApp(tester, database: database);

    await tester.tap(find.text('加油'));
    await tester.pumpAndSettle();

    // 未填容积：空态引导出现（容积入口在车辆管理），不显示金额。
    expect(find.textContaining('填写油箱容积'), findsOneWidget);
    expect(find.textContaining('¥'), findsNothing);
  });

  testWidgets('fuel price row merges manual edit and reset into one button', (
    tester,
  ) async {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    final repository = testRepository(database);
    final sync = SyncMetadata(
      status: SyncStatus.synced,
      updatedAt: DateTime(2026),
    );
    await repository.ensureBootstrapData();
    await repository.setPreferenceValue('developerModeEnabled', 'true');
    await repository.setPreferenceValue('fuelPredictionEnabled', 'true');
    final carId = await createCarWithDefaultItems(
      database,
      Car(
        brand: '本田',
        model: '22款思域',
        currentMileageKm: 10000,
        roadDate: const LocalDate(2023, 8, 12),
        sync: sync,
      ),
    );
    await repository.setAppliedCarId(carId);
    await pumpApp(tester, database: database);

    await tester.tap(find.text('加油'));
    await tester.pumpAndSettle();

    // 数据源价状态：右侧按钮显示"手填"（进编辑），无"重置"。
    expect(find.text('7.61 元/升'), findsOneWidget);
    expect(find.text('手填'), findsOneWidget);
    expect(find.text('重置'), findsNothing);

    // 点价格文字不进编辑（入口已收掉），只有"手填"按钮能打开 sheet。
    await tester.tap(find.text('7.61 元/升'));
    await tester.pumpAndSettle();
    expect(find.text('编辑油价'), findsNothing);

    // 点"手填" → 编辑油价 sheet → 存一个手填价。
    await tester.tap(find.text('手填'));
    await tester.pumpAndSettle();
    expect(find.text('编辑油价'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '7.88');
    await tester.tap(find.widgetWithText(FilledButton, '保存手填价'));
    await tester.pumpAndSettle();

    // 手填价状态：手填价生效，按钮切成"重置"，"手填"消失。
    expect(find.text('7.88 元/升'), findsOneWidget);
    expect(find.text('重置'), findsOneWidget);
    expect(find.text('手填'), findsNothing);

    // 点"重置" → 恢复数据源价，按钮切回"手填"。
    await tester.tap(find.text('重置'));
    await tester.pumpAndSettle();
    expect(find.text('7.61 元/升'), findsOneWidget);
    expect(find.text('手填'), findsOneWidget);
    expect(find.text('重置'), findsNothing);
  });

  // ---- 加油记录卡（ADR 0014，票 05）----

  /// 建车 + 打开开发者/加油开关 + 装配 App 后直泵加油记录卡。
  /// 入口挂载点已在加油页注释隐藏（雏形先不对用户可见），测试绕过
  /// 页面直接泵卡组件（pumpApp 的 child 参数）。
  /// 加油记录的播种必须在装配前完成（[buildRecords] 回调拿到 carId 后
  /// 同步写库，provider 首读才能看到），与夹具"播种在装配前"约定一致。
  Future<({TestRepositories repository, int carId})> pumpRecordsCard(
    WidgetTester tester,
    List<FuelRecord> Function(int carId) buildRecords,
  ) async {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    final repository = testRepository(database);
    final sync = SyncMetadata(
      status: SyncStatus.synced,
      updatedAt: DateTime(2026),
    );
    await repository.ensureBootstrapData();
    await repository.setPreferenceValue('developerModeEnabled', 'true');
    await repository.setPreferenceValue('fuelPredictionEnabled', 'true');
    final carId = await repository.createCarWithMaintenanceItems(
      Car(
        brand: '本田',
        model: '22款思域',
        currentMileageKm: 10000,
        roadDate: const LocalDate(2023, 8, 12),
        tankCapacityLiters: 55,
        sync: sync,
      ),
      [
        MaintenanceItem(
          carsId: 0,
          name: '机油',
          enabled: true,
          remindByMileage: true,
          remindByTime: false,
          mileageIntervalKm: 5000,
          timeIntervalMonths: null,
          notOverdueUpperLimit: 100,
          overdueUpperLimit: 125,
          sortOrder: 0,
          sync: sync,
        ),
      ],
    );
    await repository.setAppliedCarId(carId);
    for (final record in buildRecords(carId)) {
      await repository.fuelRepository.saveFuelRecord(record);
    }
    await pumpApp(tester, database: database, child: const FuelRecordsCard());
    await tester.pumpAndSettle();
    return (repository: repository, carId: carId);
  }

  /// 加油记录播种造数（金额/升数给常用默认值，fullTank 默认加满）。
  FuelRecord fuelSeed(
    int carId, {
    required String date,
    required int mileageKm,
    double volumeLiters = 40,
    int totalCostCents = 30000,
    bool fullTank = true,
  }) {
    return FuelRecord(
      carId: carId,
      date: LocalDate.parse(date),
      mileageKm: mileageKm,
      volumeLiters: volumeLiters,
      totalCostCents: totalCostCents,
      fullTank: fullTank,
    );
  }

  testWidgets('fuel records card shows empty state and saves via form', (
    tester,
  ) async {
    final fixture = await pumpRecordsCard(tester, (carId) => []);

    // 入口已注释隐藏、测试直泵卡组件，页面标题断言不再适用。
    // 空态一行文案占位（不隐藏入口）。
    expect(find.text('还没有加油记录，点「记一笔」开始记录'), findsOneWidget);

    // 记一笔：表单 sheet，填里程/金额/升数三格（日期默认生效今天）。
    await tester.tap(find.text('记一笔'));
    await tester.pumpAndSettle();
    expect(find.text('记一笔加油'), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(0), '12300');
    await tester.enterText(find.byType(TextField).at(1), '300');
    await tester.pump();
    // 单价 = 金额 ÷ 升数，只读展示：升数未填时给占位。
    expect(find.text('—'), findsWidgets);
    await tester.enterText(find.byType(TextField).at(2), '40');
    await tester.pump();
    expect(find.text('7.50 元/升'), findsOneWidget);
    // 加满开关默认开。
    final fullTankSwitch = tester.widget<Switch>(
      find.byType(Switch).first,
    );
    expect(fullTankSwitch.value, isTrue);

    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    // 行出现（默认日期 2026-05-19 · 12,300 km / ¥300.00）；
    // 只有一条满箱不闭合 → 无摘要行。
    expect(find.textContaining('2026-05-19 · 12,300 km'), findsOneWidget);
    expect(find.text('¥300.00'), findsOneWidget);
    expect(find.textContaining('平均油耗'), findsNothing);
    final records = await fixture.repository
        .listFuelRecordsForCar(fixture.carId);
    expect(records, hasLength(1));
    expect(records.first.date, const LocalDate(2026, 5, 19));
    expect(records.first.mileageKm, 12300);
    expect(records.first.totalCostCents, 30000);
    expect(records.first.volumeLiters, 40);
    expect(records.first.fullTank, isTrue);
  });

  testWidgets('fuel record row opens edit sheet prefilled and saves changes', (
    tester,
  ) async {
    final fixture = await pumpRecordsCard(
      tester,
      (carId) => [
        fuelSeed(carId, date: '2026-05-10', mileageKm: 12000),
      ],
    );

    // 行点按进编辑，五项字段预填（单价 = 300 ÷ 40 = 7.50 一并展示）。
    await tester.tap(find.textContaining('2026-05-10 · 12,000 km'));
    await tester.pumpAndSettle();
    expect(find.text('编辑加油记录'), findsOneWidget);
    expect(find.widgetWithText(TextField, '12000'), findsOneWidget);
    expect(find.widgetWithText(TextField, '300.00'), findsOneWidget);
    expect(find.widgetWithText(TextField, '40.0'), findsOneWidget);
    expect(find.text('7.50 元/升'), findsOneWidget);

    // 改里程保存：行与库都更新。
    await tester.enterText(find.byType(TextField).at(0), '12100');
    await tester.tap(find.widgetWithText(FilledButton, '保存修改'));
    await tester.pumpAndSettle();
    expect(find.textContaining('2026-05-10 · 12,100 km'), findsOneWidget);
    final records = await fixture.repository
        .listFuelRecordsForCar(fixture.carId);
    expect(records.single.mileageKm, 12100);
  });

  testWidgets('fuel record delete asks confirmation and removes the row', (
    tester,
  ) async {
    final fixture = await pumpRecordsCard(
      tester,
      (carId) => [
        fuelSeed(carId, date: '2026-05-10', mileageKm: 12000),
      ],
    );

    await tester.tap(find.textContaining('2026-05-10 · 12,000 km'));
    await tester.pumpAndSettle();
    // 编辑态里的"删除"按钮 → 确认框（调用方弹），确认后行与库都清掉。
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(find.text('删除加油记录'), findsOneWidget);
    // 编辑 sheet 的删除按钮与确认框确认按钮同名，取最后一个（弹窗内）。
    await tester.tap(find.text('删除').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('2026-05-10'), findsNothing);
    expect(find.text('还没有加油记录，点「记一笔」开始记录'), findsOneWidget);
    expect(
      await fixture.repository.listFuelRecordsForCar(fixture.carId),
      isEmpty,
    );
  });

  testWidgets('fuel records list collapses to latest five with expand-all', (
    tester,
  ) async {
    await pumpRecordsCard(
      tester,
      (carId) => [
        for (var day = 1; day <= 6; day++)
          fuelSeed(carId, date: '2026-05-0$day', mileageKm: 10000 + day * 100),
      ],
    );

    // 默认收起：只显示最近 5 条（05-02 ~ 05-06），最早的 05-01 折叠。
    expect(find.textContaining('2026-05-01'), findsNothing);
    expect(find.textContaining('2026-05-02'), findsOneWidget);
    expect(find.text('展开全部'), findsOneWidget);

    await tester.tap(find.text('展开全部'));
    await tester.pumpAndSettle();
    expect(find.textContaining('2026-05-01'), findsOneWidget);
    expect(find.text('收起'), findsOneWidget);

    await tester.tap(find.text('收起'));
    await tester.pumpAndSettle();
    expect(find.textContaining('2026-05-01'), findsNothing);
  });

  testWidgets(
    'fuel records card shows average summary and per-row segment consumption',
    (tester) async {
      await pumpRecordsCard(
        tester,
        (carId) => [
          // 首条满箱：只做锚点（行内无本段油耗）。
          fuelSeed(
            carId,
            date: '2026-05-01',
            mileageKm: 10000,
            volumeLiters: 20,
            totalCostCents: 15000,
          ),
          // 中间部分加油：计入段升数/金额，不闭合段。
          fuelSeed(
            carId,
            date: '2026-05-05',
            mileageKm: 10200,
            volumeLiters: 10,
            totalCostCents: 8000,
            fullTank: false,
          ),
          // 闭合条：段 = 40 升 / 500 km → 8.0 L/100km；每公里 0.66 元。
          fuelSeed(
            carId,
            date: '2026-05-10',
            mileageKm: 10500,
            volumeLiters: 30,
            totalCostCents: 25000,
          ),
        ],
      );

      // 摘要行 = 全部有效段聚合（此例只有一段）：8.0 L/100km · ¥0.66。
      expect(
        find.text('平均油耗 8.0 L/100km · 每公里 ¥0.66'),
        findsOneWidget,
      );
      // 行内本段油耗只挂在闭合行上（05-10），全局唯一。
      expect(find.text('8.0 L/100km'), findsOneWidget);
    },
  );
}
