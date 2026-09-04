// fuel 域 widget 测试（共享夹具见 test/helpers/widget_app.dart）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lunio/domain/entities/fuel_price.dart';
import 'package:lunio/domain/entities/fuel_prediction.dart';
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
    // 预估下次油价块：假源默认无调价预告，显示占位文案。
    expect(find.text('预估下次油价'), findsOneWidget);
    expect(find.text('暂无调价预测'), findsOneWidget);
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
    // 调价后价格列：50% 档 27.5 × 7.67 = 210.93；当前价列不受影响。
    expect(find.text('¥209.28'), findsOneWidget);
    expect(find.text('¥210.93'), findsOneWidget);
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
    // 选广东：关 sheet、写省份偏好，油价自动刷新为广东价。
    await tester.tap(find.text('广东'));
    await tester.pumpAndSettle();
    expect(find.text('选择省份'), findsNothing);
    expect(await repository.getPreferenceValue('fuelProvince'), '广东');
    expect(find.text('广东'), findsOneWidget);
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
}
