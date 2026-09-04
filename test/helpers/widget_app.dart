// widget 测试共享夹具（≈ Java 测试里的 AbstractIntegrationTest 基类 +
// 测试工厂）：pumpApp、仓库装配门面、通知/原生通道 mock、常用造数函数。
//
// 约定：
//  - pumpApp 负责装配：内存数据库 + 测试目录（built_in_catalog_loader）
//    + 固定"今天" + 假油价源 + 每用例全新通知服务实例；
//  - TestRepositories 是给用例体播种/断言用的装配门面（把拆分后的各
//    域模块捆在一个对象上），生产代码不要用；
//  - 所有通道 mock 都自带 addTearDown 清理（mockNative* 系列）或返回
//    清理闭包（mockAndroidNotifications，需与平台覆写成对调用）。
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:lunio/app/app_router.dart';
import 'package:lunio/app/providers.dart';
import 'package:lunio/app/lunio_app.dart';
import 'package:lunio/core/date/app_date_context.dart';
import 'package:lunio/core/notifications/lunio_notification_service.dart';
import 'package:lunio/data/database/app_database.dart';
import 'package:lunio/data/preferences/app_preferences.dart';
import 'package:lunio/data/repositories/built_in_catalog_repository.dart';
import 'package:lunio/data/repositories/fuel_repository.dart';
import 'package:lunio/data/repositories/lunio_repository.dart';
import 'package:lunio/domain/entities/car.dart';
import 'package:lunio/domain/entities/maintenance_item.dart';
import 'package:lunio/domain/entities/maintenance_record.dart';
import 'package:lunio/domain/entities/fuel_prediction.dart';
import 'package:lunio/domain/entities/parking_countdown.dart';
import 'package:lunio/domain/entities/fuel_price.dart';
import 'package:lunio/features/shell/shared/formatters.dart' show maintenanceItemFromDefault;

import 'built_in_catalog_loader.dart' show loadBuiltInVehicleCatalogForTest;

/// 油价源测试替身：固定全国价表（湖北 92# = 7.61，与 55 升 50% 档
/// 组合出 ¥209.28 便于断言），可选带调价预告。替换真源避免测试触网。
class _FakeFuelPriceSource implements FuelPriceSource {
  _FakeFuelPriceSource({this.forecast});

  final FuelAdjustmentForecast? forecast;

  @override
  Future<FuelPriceData> fetchPrices() async {
    return FuelPriceData(
      fetchedAt: DateTime(2026, 5, 19),
      pricesByProvince: {
        '湖北': {
          FuelGrade.gasoline92: 7.61,
          FuelGrade.gasoline95: 8.15,
          FuelGrade.gasoline98: 9.15,
          FuelGrade.diesel0: 7.20,
        },
        '广东': {FuelGrade.gasoline92: 7.63},
      },
      forecast: forecast,
    );
  }
}

const nativeFilesChannel = MethodChannel('lunio/native_files');
const nativeNotificationSettingsChannel = MethodChannel(
  'lunio/native_notification_settings',
);
const nativeSystemUiChannel = MethodChannel('lunio/native_system_ui');
const notificationsChannel = MethodChannel(
  'dexterous.com/flutter/local_notifications',
);
const timezoneChannel = MethodChannel('flutter_timezone');

/// mock 原生文件桥（备份导出/导入的系统保存/选择框）。
void mockNativeFiles(Future<Object?> Function(MethodCall call) handler) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(nativeFilesChannel, handler);
  addTearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(nativeFilesChannel, null),
  );
}

/// mock 原生通知设置跳转桥。
void mockNativeNotificationSettings(
  Future<Object?> Function(MethodCall call) handler,
) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(nativeNotificationSettingsChannel, handler);
  addTearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(nativeNotificationSettingsChannel, null),
  );
}

/// mock 原生系统 UI 桥（导航栏模式与高度）。
void mockNativeSystemUi({
  required int navigationMode,
  required double navigationBarHeight,
}) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(nativeSystemUiChannel, (call) async {
        if (call.method == 'getSystemNavigationInfo') {
          return {
            'navigationMode': navigationMode,
            'navigationBarHeight': navigationBarHeight,
          };
        }
        return null;
      });
  addTearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(nativeSystemUiChannel, null),
  );
}

/// 底部导航壳层内边距探针（导航栏 inset 相关用例断言用）。
EdgeInsets bottomNavigationShellPadding(WidgetTester tester) {
  final paddingFinder = find.byWidgetPredicate((widget) {
    if (widget is! Padding || widget.padding is! EdgeInsets) {
      return false;
    }
    final padding = widget.padding as EdgeInsets;
    return padding.left == 14 && padding.top == 0 && padding.right == 14;
  });
  expect(paddingFinder, findsOneWidget);
  return tester.widget<Padding>(paddingFinder).padding as EdgeInsets;
}

/// mock Android 通知平台 + 时区通道。返回清理闭包——调用方必须在用例
/// 结束前调用（平台覆写的不变量检查要求用例体内复位），通常写成：
/// `final cleanup = mockAndroidNotifications(calls); ... cleanup();`
VoidCallback mockAndroidNotifications(
  List<MethodCall> calls, {
  bool notificationsEnabled = true,
}) {
  debugDefaultTargetPlatformOverride = TargetPlatform.android;
  AndroidFlutterLocalNotificationsPlugin.registerWith();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(timezoneChannel, (call) async {
        if (call.method == 'getLocalTimezone') {
          return 'Asia/Shanghai';
        }
        return null;
      });
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(notificationsChannel, (call) async {
        calls.add(call);
        return switch (call.method) {
          'initialize' => true,
          'requestNotificationsPermission' => true,
          'areNotificationsEnabled' => notificationsEnabled,
          'canScheduleExactNotifications' => true,
          'requestExactAlarmsPermission' => true,
          _ => null,
        };
      });
  return () {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notificationsChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(timezoneChannel, null);
  };
}

/// 测试专用仓库装配门面：把拆分后的各域模块捆在一个对象上，让用例体
/// 用一份引用完成播种与断言（≈ 测试夹具里的 ServiceLocator）。生产代码
/// 不要用——那是测试专用的一揽子引用，不是模块边界。
class TestRepositories {
  TestRepositories(this.database)
      : preferences = LunioPreferences(database),
        // 目录加载器必须注入测试版（纯 async 闭包，微任务即完成）：默认
        // 加载器走 rootBundle 资产通道，在第二个用例的假异步区里等不到
        // 通道回包会把用例挂到 10 分钟超时。注入的加载器读的也是同一份
        // assets/data/catalog/ 真实分片（见 built_in_catalog_loader.dart）。
        catalogRepository = BuiltInCatalogRepository(
          database,
          loadBuiltInVehicleCatalog: () async => loadBuiltInVehicleCatalogForTest(),
        ),
        fuelRepository = FuelRepository(database, LunioPreferences(database)) {
    repository = LunioRepository(
      database,
      preferences: preferences,
      fuel: fuelRepository,
    );
  }

  final AppDatabase database;
  final LunioPreferences preferences;
  final BuiltInCatalogRepository catalogRepository;
  final FuelRepository fuelRepository;
  late final LunioRepository repository;

  // ---- 各域转发（用例体经门面播种/断言，不直接关心模块归属）----

  /// 转发目录仓库：灌入内置车型目录与默认模板（按 catalogId 幂等对账，
  /// 写 vehicle_models / vehicle_default_maintenance_items 两表）。
  Future<void> ensureBootstrapData() => catalogRepository.ensureBootstrapData();

  /// 转发偏好门面原语读：按 key 读原始字符串值（断言偏好状态用）。
  Future<String?> getPreferenceValue(String key) => preferences.readRaw(key);

  /// 转发偏好门面原语写：按 key 写原始字符串值（null 删键）。
  Future<void> setPreferenceValue(String key, String? value) =>
      preferences.writeRaw(key, value);

  /// 转发偏好门面：写当前应用车辆 id（null 清空；只写偏好，不失效 provider）。
  Future<void> setAppliedCarId(int? carId) =>
      preferences.setAppliedCarId(carId);

  /// 转发偏好门面：读停车倒计时偏好（JSON 解码，未设置返回 null）。
  Future<ParkingCountdown?> getParkingCountdown() =>
      preferences.getParkingCountdown();

  /// 转发偏好门面：写停车倒计时偏好（JSON 编码）。
  Future<void> saveParkingCountdown(ParkingCountdown countdown) =>
      preferences.saveParkingCountdown(countdown);

  /// 转发加油仓库：读某车的加油预测设置行（无则 null）。
  Future<FuelPrediction?> getFuelPredictionForCar(int carId) =>
      fuelRepository.getFuelPredictionForCar(carId);

  /// 转发加油仓库：写某车的加油预测设置行（写 fuel_predictions 表）。
  Future<void> saveFuelPrediction(FuelPrediction prediction) =>
      fuelRepository.saveFuelPrediction(prediction);

  /// 转发主仓库：单事务建车带项目（写 cars + maintenance_items，
  /// 无应用车辆时把新车设为当前）。
  Future<int> createCarWithMaintenanceItems(
    Car car,
    List<MaintenanceItem> items,
  ) => repository.createCarWithMaintenanceItems(car, items);

  /// 转发主仓库：列全部车辆。
  Future<List<Car>> listCars() => repository.listCars();

  /// 转发主仓库：列某车的保养项目。
  Future<List<MaintenanceItem>> listMaintenanceItemsForCar(int carId) =>
      repository.listMaintenanceItemsForCar(carId);

  /// 转发主仓库：列某车的保养记录。
  Future<List<MaintenanceRecord>> listMaintenanceRecordsForCar(int carId) =>
      repository.listMaintenanceRecordsForCar(carId);

  /// 转发主仓库：保存单条保养记录（写 records 表）。
  Future<int> saveMaintenanceRecord(MaintenanceRecord record) =>
      repository.saveMaintenanceRecord(record);

  /// 转发主仓库：保存单条保养项目（写 maintenance_items 表）。
  Future<int> saveMaintenanceItem(MaintenanceItem item) =>
      repository.saveMaintenanceItem(item);
}

/// 用例体播种/断言入口：按数据库装配一份 TestRepositories。
TestRepositories testRepository(AppDatabase database) => TestRepositories(database);

/// 按车的动力类型查当前库里的默认模板 → 转车辆级项目实体 → 建车（单事务）。
/// 注意不主动 bootstrap：目录由调用方（一般经 pumpApp）按需灌入。
Future<int> createCarWithDefaultItems(
  AppDatabase database,
  Car car,
) async {
  final bundle = TestRepositories(database);
  final defaults = await bundle.catalogRepository.listDefaultItemsForPowertrain(
    powertrainType: car.powertrainType,
  );
  return bundle.repository.createCarWithMaintenanceItems(
    car,
    [for (final item in defaults) maintenanceItemFromDefault(item, car.sync)],
  );
}

/// 轮询等待某个 finder 出现（异步数据加载场景，pumpAndSettle 不适用时）。
Future<void> pumpUntilFound(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 20; attempt++) {
    if (finder.evaluate().isNotEmpty) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// 装配完整 App：内存数据库 + 测试目录 + 固定"今天"（2026-05-19）+
/// 假油价源 + 全新通知服务实例（用例间不共享通知服务状态）。
/// 返回数据库供用例体播种/断言。
Future<AppDatabase> pumpApp(
  WidgetTester tester, {
  AppDateContext? dateContext,
  AppDatabase? database,
  bool systemNotificationsEnabled = false,
  bool inAppNotificationsEnabled = false,
  FuelAdjustmentForecast? fuelForecast,
}) async {
  final appDatabase = database ?? AppDatabase.inMemory();
  if (database == null) {
    addTearDown(appDatabase.close);
  }
  final preferences = LunioPreferences(appDatabase);
  final catalogRepository = BuiltInCatalogRepository(
    appDatabase,
    loadBuiltInVehicleCatalog: () async => loadBuiltInVehicleCatalogForTest(),
  );
  await catalogRepository.ensureBootstrapData();
  await preferences.setSystemNotificationsEnabled(systemNotificationsEnabled);
  await preferences.setInAppNotificationsEnabled(inAppNotificationsEnabled);
  tester.view.physicalSize = const Size(800, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(appDatabase),
        builtInCatalogRepositoryProvider.overrideWithValue(catalogRepository),
        lunioRepositoryProvider.overrideWithValue(
          LunioRepository(
            appDatabase,
            preferences: preferences,
            fuel: FuelRepository(appDatabase, preferences),
          ),
        ),
        lunioNotificationServiceProvider.overrideWithValue(
          LunioNotificationService(),
        ),
        appDateContextProvider.overrideWithValue(
          dateContext ??
              AppDateContext(readSystemNow: () => DateTime(2026, 5, 19)),
        ),
        // 油价真源会发网络请求，统一替换为固定假源。
        fuelPriceSourceProvider.overrideWithValue(
          _FakeFuelPriceSource(forecast: fuelForecast),
        ),
      ],
      child: LunioApp(routerConfig: buildAppRouter()),
    ),
  );
  for (var frame = 0; frame < 10; frame++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  return appDatabase;
}

/// UI 造数：经"我的"页向导建一辆默认车并设为应用车辆。
Future<void> createDefaultCar(WidgetTester tester) async {
  await tester.tap(find.text('我的'));
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('新增车辆'));
  await pumpUntilFound(tester, find.text('下一步'));
  if (find.text('下一步').evaluate().isEmpty) {
    final visibleTexts = tester
        .widgetList<Text>(find.byType(Text))
        .map((text) => text.data)
        .whereType<String>()
        .toSet()
        .toList();
    fail('新增车辆下一步未出现，当前文本: $visibleTexts');
  }
  await tester.tap(find.text('下一步'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('保存车辆'));
  await tester.pumpAndSettle();
}

/// UI 造数：连点版本号 5 次打开开发者模式。
Future<void> enableDeveloperMode(WidgetTester tester) async {
  await tester.tap(find.text('我的'));
  await tester.pumpAndSettle();
  for (var index = 0; index < 5; index++) {
    await tester.tap(find.text('版本 1.0.0'));
    await tester.pumpAndSettle();
  }
  expect(find.text('手动日期'), findsOneWidget);
}

/// UI 造数：经提醒页表单建一条默认保养记录（13000km / ¥428 / 机油）。
Future<void> createDefaultRecord(WidgetTester tester) async {
  await tester.tap(find.text('提醒'));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(FilledButton, '新增保养记录'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField).at(0), '13000');
  await tester.enterText(find.byType(TextField).at(1), '428.00');
  await tester.tap(find.text('机油').last);
  await tester.pumpAndSettle();
  await tester.tap(find.text('下一步'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('保存记录'));
  await tester.pumpAndSettle();
}
