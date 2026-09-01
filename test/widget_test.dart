import 'dart:async';

import 'package:flutter/cupertino.dart';
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
import 'package:lunio/core/date/local_date.dart';
import 'package:lunio/core/notifications/lunio_notification_service.dart';
import 'package:lunio/data/backup/backup_codec.dart';
import 'package:lunio/data/bootstrap/built_in_vehicle_catalog.dart';
import 'helpers/built_in_catalog_loader.dart' show loadBuiltInVehicleCatalogForTest;
import 'package:lunio/data/database/app_database.dart';
import 'package:lunio/data/repositories/lunio_repository.dart';
import 'package:lunio/domain/entities/car.dart';
import 'package:lunio/domain/entities/maintenance_item.dart';
import 'package:lunio/domain/entities/fuel_prediction.dart';
import 'package:lunio/domain/entities/maintenance_record.dart';
import 'package:lunio/domain/entities/notification_settings.dart';
import 'package:lunio/domain/entities/parking_countdown.dart';
import 'package:lunio/domain/entities/sync_metadata.dart';
import 'package:lunio/features/shell/profile/vehicles.dart' show PickerOption;
import 'package:lunio/features/shell/shared/formatters.dart' show maintenanceItemFromDefault;
import 'package:lunio/features/shell/shared/shared_widgets.dart' show PrototypeSheetFrame;

void main() {
  late BuiltInVehicleCatalog builtInCatalog;
  const nativeFilesChannel = MethodChannel('lunio/native_files');
  const nativeNotificationSettingsChannel = MethodChannel(
    'lunio/native_notification_settings',
  );
  const nativeSystemUiChannel = MethodChannel('lunio/native_system_ui');
  const notificationsChannel = MethodChannel(
    'dexterous.com/flutter/local_notifications',
  );
  const timezoneChannel = MethodChannel('flutter_timezone');

  void mockNativeFiles(Future<Object?> Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(nativeFilesChannel, handler);
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(nativeFilesChannel, null),
    );
  }

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

  setUpAll(() {
    builtInCatalog = loadBuiltInVehicleCatalogForTest();
  });

  LunioRepository testRepository(AppDatabase database) {
    return LunioRepository(
      database,
      loadBuiltInVehicleCatalog: () async => builtInCatalog,
    );
  }

  Future<void> pumpUntilFound(WidgetTester tester, Finder finder) async {
    for (var attempt = 0; attempt < 20; attempt++) {
      if (finder.evaluate().isNotEmpty) {
        return;
      }
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<AppDatabase> pumpApp(
    WidgetTester tester, {
    AppDateContext? dateContext,
    AppDatabase? database,
    bool systemNotificationsEnabled = false,
    bool inAppNotificationsEnabled = false,
  }) async {
    // 通知服务是进程级单例：重置初始化状态，避免上一个用例的
    // 初始化结果（可用/不可用）影响本用例的 mock 行为。
    LunioNotificationService.instance.resetForTest();
    final appDatabase = database ?? AppDatabase.inMemory();
    if (database == null) {
      addTearDown(appDatabase.close);
    }
    final repository = testRepository(appDatabase);
    await repository.ensureBootstrapData();
    await repository.setPreferenceValue(
      'systemNotificationsEnabled',
      systemNotificationsEnabled.toString(),
    );
    await repository.setPreferenceValue(
      'inAppNotificationsEnabled',
      inAppNotificationsEnabled.toString(),
    );
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(appDatabase),
          lunioRepositoryProvider.overrideWithValue(repository),
          appDateContextProvider.overrideWithValue(
            dateContext ??
                AppDateContext(readSystemNow: () => DateTime(2026, 5, 19)),
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

  /// 测试替身：等价已删除的 createCarWithDefaultItems（R26 清理）——
  /// 按车的动力类型查当前库里的模板 → 转车辆级项目实体 → 建车。
  /// 注意不主动 bootstrap：目录由调用方按需灌入。
  Future<int> createCarWithDefaultItems(
    LunioRepository repository,
    Car car,
  ) async {
    final defaults = await repository.listDefaultItemsForPowertrain(
      powertrainType: car.powertrainType,
    );
    return repository.createCarWithMaintenanceItems(
      car,
      [for (final item in defaults) maintenanceItemFromDefault(item, car.sync)],
    );
  }

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

  Future<void> enableDeveloperMode(WidgetTester tester) async {
    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    for (var index = 0; index < 5; index++) {
      await tester.tap(find.text('版本 1.0.0'));
      await tester.pumpAndSettle();
    }
    expect(find.text('手动日期'), findsOneWidget);
  }

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

  test(
    'notification settings default to system notifications enabled',
    () async {
      final database = AppDatabase.inMemory();
      addTearDown(database.close);
      final container = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWithValue(database)],
      );
      addTearDown(container.dispose);

      final settings = await container.read(
        notificationSettingsProvider.future,
      );

      expect(settings.systemNotificationsEnabled, isTrue);
      expect(settings.inAppNotificationsEnabled, isTrue);
      expect(settings.dueRepeatFrequency.value, 'weekly');
    },
  );

  testWidgets('app shell exposes three main entries', (tester) async {
    await pumpApp(tester);

    expect(find.text('保养提醒'), findsWidgets);
    expect(find.text('还没有车辆'), findsOneWidget);
    expect(find.text('提醒'), findsOneWidget);
    expect(find.text('记录'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);
  });

  testWidgets('bottom navigation clears Android three-button inset', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      const systemNavigationHeight = 48.0;
      mockNativeSystemUi(
        navigationMode: 0,
        navigationBarHeight: systemNavigationHeight,
      );

      await pumpApp(tester);

      expect(
        bottomNavigationShellPadding(tester).bottom,
        12 + systemNavigationHeight,
      );
      final screenHeight =
          tester.view.physicalSize.height / tester.view.devicePixelRatio;
      final systemNavigationTop = screenHeight - systemNavigationHeight;

      expect(
        tester.getBottomLeft(find.text('我的')).dy,
        lessThanOrEqualTo(systemNavigationTop),
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('bottom navigation stays put for Android gesture navigation', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      mockNativeSystemUi(navigationMode: 2, navigationBarHeight: 24);
      await pumpApp(tester);

      expect(bottomNavigationShellPadding(tester).bottom, 12);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('bottom navigation stays put for iOS bottom safe area', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    var invokedNativeSystemUi = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(nativeSystemUiChannel, (call) async {
          invokedNativeSystemUi = true;
          return null;
        });
    try {
      await pumpApp(tester);

      expect(bottomNavigationShellPadding(tester).bottom, 12);
      expect(invokedNativeSystemUi, isFalse);
    } finally {
      debugDefaultTargetPlatformOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(nativeSystemUiChannel, null);
    }
  });

  testWidgets('bottom navigation switches primary tabs', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('记录'));
    await pumpUntilFound(tester, find.text('保养记录'));
    expect(find.text('保养记录'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);

    await tester.tap(find.text('我的'));
    await pumpUntilFound(tester, find.text('个人中心'));
    expect(find.text('个人中心'), findsOneWidget);
    // LunioPage 现为 CustomScrollView + SliverPadding（R25），页面级
    // padding 断言改查 SliverPadding。
    final profilePadding = tester.widget<SliverPadding>(
      find.byType(SliverPadding).first,
    );
    expect(profilePadding.padding, const EdgeInsets.fromLTRB(18, 2, 18, 72));
  });

  testWidgets('theme switch stays on profile without success feedback', (
    tester,
  ) async {
    await pumpApp(tester);

    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('深色'));
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('个人中心'), findsOneWidget);
    expect(find.text('主题已切换'), findsNothing);
  });

  testWidgets('theme switch ignores the current option', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('跟随系统'));
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('个人中心'), findsOneWidget);
    expect(find.text('主题已切换'), findsNothing);
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

  testWidgets('reminder action row opens maintenance and parking sheets', (
    tester,
  ) async {
    await pumpApp(tester);
    await createDefaultCar(tester);
    await tester.tap(find.text('提醒'));
    await tester.pumpAndSettle();

    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.widgetWithText(FilledButton, '新增保养记录'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '停车倒计时'), findsOneWidget);
    final addRecordButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '新增保养记录'),
    );
    final parkingButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '停车倒计时'),
    );
    expect(parkingButton.style, addRecordButton.style);

    await tester.tap(find.widgetWithText(FilledButton, '新增保养记录'));
    await tester.pumpAndSettle();

    expect(find.text('新增保养记录'), findsWidgets);
    expect(find.text('下一步'), findsOneWidget);
    expect(find.text('保存记录'), findsNothing);
    expect(find.byType(BackdropFilter), findsOneWidget);
    final sheetFrame = find.byWidgetPredicate(
      (widget) => widget is FractionallySizedBox && widget.widthFactor == 1,
    );
    expect(
      tester.getRect(sheetFrame.last).bottom,
      tester.view.physicalSize.height / tester.view.devicePixelRatio,
    );

    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(find.text('下一步'), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, '停车倒计时'));
    await tester.pumpAndSettle();
    expect(find.text('停车计时'), findsOneWidget);
    expect(find.text('入场时间'), findsOneWidget);
    expect(find.text('0.5 小时'), findsOneWidget);
  });

  testWidgets('reminders without records show empty due overview', (
    tester,
  ) async {
    await pumpApp(tester);
    await createDefaultCar(tester);

    await tester.tap(find.text('提醒'));
    await tester.pumpAndSettle();

    expect(find.text('到期概览'), findsOneWidget);
    expect(find.text('暂无'), findsOneWidget);
    expect(find.text('暂无保养记录，记录首保后再生成保养提醒。'), findsOneWidget);
    expect(find.text('管理项目'), findsNothing);
    expect(find.text('按当前应用车辆计算里程与时间进度'), findsNothing);
  });

  testWidgets('reminders can start and end parking countdown', (tester) async {
    final database = await pumpApp(
      tester,
      dateContext: AppDateContext(
        readSystemNow: () => DateTime(2026, 6, 10, 10, 20),
      ),
    );
    await createDefaultCar(tester);

    await tester.tap(find.text('提醒'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '停车倒计时'));
    await tester.pumpAndSettle();

    expect(find.text('停车计时'), findsOneWidget);
    expect(find.text('入场时间'), findsOneWidget);
    expect(find.text('10:20:00'), findsOneWidget);
    expect(find.text('免费时长'), findsOneWidget);
    expect(find.text('0.5 小时'), findsOneWidget);
    await tester.tap(find.text('开始计时'));
    await tester.pumpAndSettle();

    expect(find.text('剩余充足'), findsNothing);
    expect(find.text('10:50:00 前离场'), findsOneWidget);
    expect(find.textContaining('还剩'), findsNothing);
    expect(await testRepository(database).getParkingCountdown(), isNotNull);

    await tester.tap(find.widgetWithText(TextButton, '结束'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FilledButton, '停车倒计时'), findsOneWidget);
    expect(await testRepository(database).getParkingCountdown(), isNull);
  });

  testWidgets('parking countdown sheet keeps actions above keyboard', (
    tester,
  ) async {
    await pumpApp(
      tester,
      dateContext: AppDateContext(
        readSystemNow: () => DateTime(2026, 6, 10, 10, 20),
      ),
    );
    await createDefaultCar(tester);
    await tester.tap(find.text('提醒'));
    await tester.pumpAndSettle();

    const keyboardHeight = 360.0;
    tester.view.viewInsets = const FakeViewPadding(bottom: keyboardHeight);
    addTearDown(tester.view.resetViewInsets);
    await tester.pump();

    await tester.tap(find.widgetWithText(FilledButton, '停车倒计时'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextField, '免费时长'));
    await tester.pumpAndSettle();

    final keyboardTop =
        tester.view.physicalSize.height / tester.view.devicePixelRatio -
        keyboardHeight;
    final startButtonBottom = tester
        .getBottomLeft(find.widgetWithText(FilledButton, '开始计时'))
        .dy;
    expect(startButtonBottom, lessThanOrEqualTo(keyboardTop));
  });

  testWidgets('parking countdown starts Android notification timer', (
    tester,
  ) async {
    final notificationCalls = <MethodCall>[];
    final cleanupNotifications = mockAndroidNotifications(notificationCalls);
    try {
      await pumpApp(
        tester,
        dateContext: AppDateContext(readSystemNow: () => DateTime.now()),
        systemNotificationsEnabled: true,
      );
      await createDefaultCar(tester);
      notificationCalls.clear();

      await tester.tap(find.text('提醒'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '停车倒计时'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('开始计时'));
      await tester.pumpAndSettle();

      expect(
        notificationCalls.map((call) => call.method),
        containsAll(<String>[
          'requestNotificationsPermission',
          'show',
          'zonedSchedule',
        ]),
      );
      final showCall = notificationCalls.singleWhere(
        (call) => call.method == 'show',
      );
      final showArguments = showCall.arguments as Map<Object?, Object?>;
      final showSpecifics =
          showArguments['platformSpecifics'] as Map<Object?, Object?>;
      expect(showSpecifics['channelId'], 'lunio_parking_ongoing');
      expect(showSpecifics['ongoing'], isTrue);
      expect(showSpecifics['chronometerCountDown'], isTrue);
    } finally {
      cleanupNotifications();
    }
  });

  testWidgets('parking countdown accepts custom minutes', (tester) async {
    final database = await pumpApp(
      tester,
      dateContext: AppDateContext(
        readSystemNow: () => DateTime(2026, 6, 10, 10, 20),
      ),
    );
    await createDefaultCar(tester);

    await tester.tap(find.text('提醒'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '停车倒计时'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, '免费时长'), '45');
    await tester.tap(find.text('开始计时'));
    await tester.pumpAndSettle();

    expect(find.text('11:05:00 前离场'), findsOneWidget);
    expect(find.textContaining('还剩'), findsNothing);
    final countdown = await testRepository(database).getParkingCountdown();
    expect(countdown?.durationSeconds, 2700);
  });

  testWidgets('parking countdown entry time uses scroll wheels', (
    tester,
  ) async {
    await pumpApp(
      tester,
      dateContext: AppDateContext(
        readSystemNow: () => DateTime(2026, 6, 10, 10, 20, 15),
      ),
    );
    await createDefaultCar(tester);

    await tester.tap(find.text('提醒'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '停车倒计时'));
    await tester.pumpAndSettle();

    final durationField = tester.widget<TextField>(
      find.widgetWithText(TextField, '免费时长'),
    );
    expect(durationField.keyboardType, TextInputType.text);
    expect(durationField.textInputAction, TextInputAction.done);
    expect(durationField.inputFormatters, hasLength(1));
    expect(
      durationField.inputFormatters!.single,
      isA<FilteringTextInputFormatter>(),
    );

    await tester.tap(find.text('10:20:15'));
    await tester.pumpAndSettle();

    expect(find.text('选择入场时间'), findsOneWidget);
    expect(find.byType(CupertinoPicker), findsNWidgets(3));
    expect(find.text('时'), findsOneWidget);
    expect(find.text('分'), findsOneWidget);
    expect(find.text('秒'), findsOneWidget);
  });

  testWidgets('reminders show expired parking countdown', (tester) async {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    await testRepository(database).saveParkingCountdown(
      ParkingCountdown(
        startedAt: DateTime(2026, 6, 10, 10, 20, 15),
        durationSeconds: 1800,
      ),
    );

    await pumpApp(
      tester,
      database: database,
      dateContext: AppDateContext(
        readSystemNow: () => DateTime(2026, 6, 10, 11, 2, 15),
      ),
    );

    expect(find.text('已超时'), findsNothing);
    expect(find.text('停车时长'), findsOneWidget);
    expect(find.text('42:00'), findsOneWidget);
    expect(find.text('+12:00'), findsNothing);
    expect(find.textContaining('已超 '), findsNothing);
    expect(find.text('10:50:15 已到点'), findsOneWidget);
  });

  testWidgets('parking countdown button is disabled while countdown runs', (
    tester,
  ) async {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    await testRepository(database).saveParkingCountdown(
      ParkingCountdown(
        startedAt: DateTime(2026, 6, 10, 10, 20),
        durationSeconds: 1800,
      ),
    );
    await pumpApp(
      tester,
      database: database,
      dateContext: AppDateContext(
        readSystemNow: () => DateTime(2026, 6, 10, 10, 20),
      ),
    );
    await createDefaultCar(tester);

    await tester.tap(find.text('提醒'));
    await tester.pumpAndSettle();

    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '停车倒计时'),
    );
    expect(button.onPressed, isNull);

    await tester.tap(find.widgetWithText(FilledButton, '停车倒计时'));
    await tester.pumpAndSettle();
    expect(find.text('停车计时'), findsNothing);
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

  testWidgets('profile can create a car and set it as applied car', (
    tester,
  ) async {
    final database = await pumpApp(tester, inAppNotificationsEnabled: true);

    await createDefaultCar(tester);

    expect(find.text('保养提醒'), findsNothing);
    expect(find.text('奥迪 奥迪A3'), findsWidgets);
    expect(find.text('当前'), findsOneWidget);
    expect(find.textContaining('0km'), findsOneWidget);
    expect(find.textContaining('车龄'), findsNothing);
    expect(find.textContaining('上路'), findsNothing);
    expect(find.text('当前车辆保养项目'), findsNothing);
    expect(await database.select(database.cars).get(), hasLength(1));
    // 燃油模板 10 项（默认预选动力 = 目录第一项奥迪A3 的推荐值燃油）。
    expect(
      await database.select(database.maintenanceItems).get(),
      hasLength(10),
    );
  });

  testWidgets('in-app reminders wait for the first maintenance record', (
    tester,
  ) async {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    final repository = testRepository(database);
    await repository.ensureBootstrapData();
    final sync = SyncMetadata(
      status: SyncStatus.pendingCreate,
      updatedAt: DateTime(2026, 5, 19),
    );
    final carId = await createCarWithDefaultItems(repository, 
      Car(
        brand: '本田',
        model: '思域（燃油版）',
        currentMileageKm: 0,
        roadDate: const LocalDate(2020, 1, 1),
        sync: sync,
      ),
    );
    await repository.setAppliedCarId(carId);
    await repository.setPreferenceValue('inAppNotificationsEnabled', 'true');

    await pumpApp(tester, database: database, inAppNotificationsEnabled: true);
    await tester.pumpAndSettle();
    await tester.tap(find.text('提醒'));
    await tester.pumpAndSettle();

    expect(find.text('暂无保养记录，记录首保后再生成保养提醒。'), findsOneWidget);
    expect(find.text('15 天内不再提醒'), findsNothing);
  });

  testWidgets('profile backup exports json through native file saver', (
    tester,
  ) async {
    final calls = <MethodCall>[];
    mockNativeFiles((call) async {
      calls.add(call);
      return true;
    });
    await pumpApp(tester);

    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    expect(find.text('备份数据'), findsOneWidget);
    expect(find.text('JSON 备份'), findsNothing);

    await tester.tap(find.text('备份数据'));
    await tester.pumpAndSettle();
    expect(calls, isEmpty);

    await tester.tap(find.widgetWithText(TextButton, '导出').first);
    await tester.pump(const Duration(milliseconds: 250));

    expect(calls.single.method, 'exportJsonFile');
    final arguments = calls.single.arguments as Map<Object?, Object?>;
    expect(
      arguments['filename'],
      matches(RegExp(r'^lunio-backup-\d{8}-\d{6}\.json$')),
    );
    expect(arguments['content'], isA<String>());
    expect(find.text('备份完成'), findsOneWidget);
    expect(find.text('数据备份'), findsNothing);
    expect(find.text('备份 JSON'), findsNothing);
  });

  testWidgets('profile backup cancel does not show success feedback', (
    tester,
  ) async {
    mockNativeFiles((call) async {
      if (call.method == 'exportJsonFile') {
        return false;
      }
      return null;
    });
    await pumpApp(tester);

    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '导出').first);
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('备份完成'), findsNothing);
  });

  testWidgets('profile restore confirms before picking a file', (tester) async {
    // 恢复成功后会显式取消系统通知；未 mock 的通道在测试里永不回包，
    // 会让流程挂起，所以这里要挂上通知/时区 mock。
    final notificationCalls = <MethodCall>[];
    final cleanupNotifications = mockAndroidNotifications(notificationCalls);
    mockNativeFiles((call) async {
      if (call.method == 'pickJsonFile') {
        return const BackupCodec().encode(
          const BackupPayload(schemaVersion: 1),
        );
      }
      return null;
    });
    try {
      final database = await pumpApp(tester);
      await createDefaultCar(tester);

      // 行标题现在是"恢复数据"（不可点的纯文本），点它不会打开确认弹窗；
      // 弹窗标题也是"恢复数据"，所以用弹窗副标题区分弹窗是否出现。
      await tester.tap(find.text('恢复数据').first);
      await tester.pumpAndSettle();
      expect(find.textContaining('恢复会先清空本地'), findsNothing);

      await tester.tap(find.widgetWithText(TextButton, '恢复').first);
      await tester.pumpAndSettle();
      expect(find.textContaining('恢复会先清空本地'), findsOneWidget);
      // 恢复语义文案：明示只清业务数据、偏好保留（R2 口径）。
      expect(find.textContaining('偏好设置会保留'), findsOneWidget);

      await tester.tap(find.text('恢复').last);
      await tester.pump(const Duration(milliseconds: 250));

      expect(await database.select(database.cars).get(), isEmpty);
      expect(find.text('恢复完成'), findsOneWidget);
      expect(find.text('数据恢复'), findsNothing);
      expect(find.text('备份 JSON'), findsNothing);
    } finally {
      cleanupNotifications();
    }
  });

  testWidgets('profile restore confirm cancel keeps current data', (
    tester,
  ) async {
    var pickCallCount = 0;
    mockNativeFiles((call) async {
      if (call.method == 'pickJsonFile') {
        pickCallCount++;
      }
      return null;
    });
    final database = await pumpApp(tester);
    await createDefaultCar(tester);

    await tester.tap(find.widgetWithText(TextButton, '恢复').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(pickCallCount, 0);
    expect(await database.select(database.cars).get(), hasLength(1));
  });

  testWidgets('profile restore file cancel keeps current data', (tester) async {
    var pickCallCount = 0;
    mockNativeFiles((call) async {
      if (call.method == 'pickJsonFile') {
        pickCallCount++;
      }
      return null;
    });
    final database = await pumpApp(tester);
    await createDefaultCar(tester);

    await tester.tap(find.widgetWithText(TextButton, '恢复').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('恢复').last);
    await tester.pumpAndSettle();

    expect(pickCallCount, 1);
    expect(await database.select(database.cars).get(), hasLength(1));
  });

  testWidgets('profile restore backup conflict shows one-button dialog', (
    tester,
  ) async {
    final sync = SyncMetadata(
      status: SyncStatus.synced,
      updatedAt: DateTime(2026),
    );
    final database = await pumpApp(tester);
    await createDefaultCar(tester);
    final existingCar = (await database.select(database.cars).get()).single;
    mockNativeFiles((call) async {
      if (call.method == 'pickJsonFile') {
        return const BackupCodec().encode(
          BackupPayload(
            schemaVersion: 1,
            cars: [
              Car(
                id: 99,
                brand: '本田',
                model: '思域（燃油版）',
                currentMileageKm: 12000,
                roadDate: LocalDate.parse(existingCar.roadDate),
                sync: sync,
              ),
              Car(
                id: 100,
                brand: '本田',
                model: '思域（燃油版）',
                currentMileageKm: 13000,
                roadDate: LocalDate.parse(existingCar.roadDate),
                sync: sync,
              ),
            ],
          ),
        );
      }
      return null;
    });

    await tester.tap(find.widgetWithText(TextButton, '恢复').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('恢复').last);
    await tester.pumpAndSettle();

    expect(await database.select(database.cars).get(), hasLength(1));
    expect(find.text('恢复失败'), findsOneWidget);
    expect(find.text('确认'), findsOneWidget);
    expect(find.text('取消'), findsNothing);
  });

  testWidgets(
    'clearing data cancels parking and reminder notifications and keeps catalog',
    (tester) async {
      final notificationCalls = <MethodCall>[];
      final cleanupNotifications = mockAndroidNotifications(notificationCalls);
      try {
        final database = await pumpApp(
          tester,
          dateContext: AppDateContext(readSystemNow: () => DateTime.now()),
          systemNotificationsEnabled: true,
        );
        await createDefaultCar(tester);

        // 先启动停车倒计时，制造 9001/9002 系统通知。
        await tester.tap(find.text('提醒'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, '停车倒计时'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('开始计时'));
        await tester.pumpAndSettle();
        expect(
          notificationCalls.map((call) => call.method),
          containsAll(<String>['show', 'zonedSchedule']),
        );
        notificationCalls.clear();

        await tester.tap(find.text('我的'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(TextButton, '清空'));
        await tester.pumpAndSettle();
        // 清空确认文案明示目录表保留。
        expect(find.textContaining('默认车辆模型与默认保养项目目录会保留'), findsOneWidget);
        await tester.tap(find.widgetWithText(FilledButton, '清空'));
        await tester.pumpAndSettle();

        final cancelledIds = notificationCalls
            .where((call) => call.method == 'cancel')
            .map((call) => (call.arguments as Map<Object?, Object?>)['id'])
            .whereType<int>()
            .toSet();
        expect(cancelledIds, containsAll([9001, 9002]));
        // R10 收紧：取消只发 16 个在用 id，不再整段扫 8000~8999。
        expect(
          cancelledIds.where((id) => id >= 8000 && id < 9000),
          <int>{
            for (var index = 0; index < 8; index++) 8000 + index,
            for (var index = 0; index < 8; index++) 8900 + index,
          },
        );
        expect(find.text('已清空数据'), findsOneWidget);
        expect(await database.select(database.cars).get(), isEmpty);
        expect(
          await database.select(database.maintenanceItems).get(),
          isEmpty,
        );
        // 注意：appPreferences 不恒为空——清空后同步引擎按首启语义
        // 重新初始化通知权限，会立刻写回 systemNotificationPermission*
        // 两个 key。这里只断言业务偏好确实被清掉。
        expect(
          await testRepository(database).getParkingCountdown(),
          isNull,
        );
        expect(
          await testRepository(database).getPreferenceValue('themeMode'),
          isNull,
        );
        // 默认目录表保留（清空语义）。
        expect(
          await database.select(database.vehicleDefaultMaintenanceItems).get(),
          isNotEmpty,
        );
        expect(await database.select(database.vehicleModels).get(), isNotEmpty);
      } finally {
        cleanupNotifications();
      }
    },
  );

  testWidgets('deleting the last car cancels reminder notifications', (
    tester,
  ) async {
    final notificationCalls = <MethodCall>[];
    final cleanupNotifications = mockAndroidNotifications(notificationCalls);
    try {
      final database = await pumpApp(
        tester,
        dateContext: AppDateContext(readSystemNow: () => DateTime.now()),
        systemNotificationsEnabled: true,
      );
      await createDefaultCar(tester);

      // 车辆创建触发的首轮调度结束后清空调用记录，只看删除动作的取消。
      await tester.pump(const Duration(milliseconds: 300));
      notificationCalls.clear();

      await tester.tap(find.widgetWithText(TextButton, '删除').first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await tester.pumpAndSettle();

      // R1：同步控制器在无车时短路不走重排，删除动作必须显式取消
      // 8000/8900 系旧调度，否则最后一辆车删完后通知残留。
      final cancelledIds = notificationCalls
          .where((call) => call.method == 'cancel')
          .map((call) => (call.arguments as Map<Object?, Object?>)['id'])
          .whereType<int>()
          .toSet();
      expect(
        cancelledIds,
        containsAll(<int>[
          for (var index = 0; index < 8; index++) 8000 + index,
          for (var index = 0; index < 8; index++) 8900 + index,
        ]),
      );
      expect(await database.select(database.cars).get(), isEmpty);
    } finally {
      cleanupNotifications();
    }
  });

  testWidgets('notification sync queues a pending reschedule instead of '
      'dropping it', (tester) async {
    final notificationCalls = <MethodCall>[];
    final cleanupNotifications = mockAndroidNotifications(notificationCalls);
    try {
      final database = await pumpApp(
        tester,
        systemNotificationsEnabled: true,
      );
      await createDefaultCar(tester);

      // 首轮调度稳定结束后清空调用记录，只看本用例触发的重排。
      await tester.pump(const Duration(milliseconds: 300));
      notificationCalls.clear();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(MaterialApp)),
      );
      final repository = testRepository(database);
      final car = (await repository.listCars()).first;
      final items = await repository.listMaintenanceItemsForCar(car.id!);

      // 闸门：第一轮重排的第一个 cancel 挂起不返回，制造"重排仍在
      // 进行中"的时间窗口（R3 竞态的复现条件）。
      final gate = Completer<void>();
      var gateUsed = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(notificationsChannel, (call) async {
            if (call.method == 'cancel' && !gateUsed) {
              gateUsed = true;
              notificationCalls.add(call);
              await gate.future;
              return null;
            }
            notificationCalls.add(call);
            return switch (call.method) {
              'initialize' => true,
              'requestNotificationsPermission' => true,
              'areNotificationsEnabled' => true,
              'canScheduleExactNotifications' => true,
              'requestExactAlarmsPermission' => true,
              _ => null,
            };
          });

      // 变更 1：保存一条记录（数据签名变化）→ 第一轮重排启动并卡在闸门。
      await repository.saveMaintenanceRecord(
        MaintenanceRecord(
          carId: car.id!,
          date: const LocalDate(2026, 5, 19),
          itemIds: [items.first.id!],
          costCents: 10000,
          mileageKm: 13000,
          sync: car.sync,
        ),
      );
      container.invalidate(appliedCarRecordsProvider);
      for (var i = 0; i < 30 && notificationCalls.isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(
        notificationCalls.map((call) => call.method),
        contains('cancel'),
      );

      // 变更 2（第一轮仍未结束）：再保存一条不同日期的记录 → 新签名
      // 只能排队等待，不允许被丢弃（R3）。
      await repository.saveMaintenanceRecord(
        MaintenanceRecord(
          carId: car.id!,
          date: const LocalDate(2026, 5, 18),
          itemIds: [items.first.id!],
          costCents: 20000,
          mileageKm: 13100,
          sync: car.sync,
        ),
      );
      container.invalidate(appliedCarRecordsProvider);
      await tester.pump(const Duration(milliseconds: 100));

      // 打开闸门 → 第一轮收尾 → finally 里按 pending 用最新数据重跑一轮。
      gate.complete();
      await tester.pumpAndSettle();

      // R10 后每轮重排精确取消 16 个在用 id：两轮都发生 → cancel 恰好
      // 32 次；若第二轮被丢弃则只有 16 次。
      final cancelCount = notificationCalls
          .where((call) => call.method == 'cancel')
          .length;
      expect(cancelCount, 32);
      expect(
        await repository.listMaintenanceRecordsForCar(car.id!),
        hasLength(2),
      );
    } finally {
      cleanupNotifications();
    }
  });

  testWidgets('add car first step does not persist data', (tester) async {
    final database = await pumpApp(tester);

    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('新增车辆'));
    await tester.pumpAndSettle();
    expect(find.text('添加车辆'), findsOneWidget);
    expect(find.textContaining('同一品牌车型'), findsNothing);
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();

    expect(find.text('上一步'), findsOneWidget);
    expect(find.text('保养项目'), findsOneWidget);
    expect(find.text('以下保养项目只做参考，具体以官方保养手册为准'), findsOneWidget);
    expect(find.textContaining('同一品牌车型'), findsNothing);
    expect(await database.select(database.cars).get(), isEmpty);
    expect(await database.select(database.maintenanceItems).get(), isEmpty);
  });

  testWidgets('add car form opens vehicle model picker', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('新增车辆'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('奥迪 奥迪A3'));
    await tester.pumpAndSettle();

    expect(find.text('选择车型'), findsOneWidget);
    expect(find.text('搜索品牌或车型'), findsOneWidget);
    expect(find.text('奥迪'), findsWidgets);
  });

  testWidgets('add car wizard keeps selected model after going back', (
    tester,
  ) async {
    await pumpApp(tester);

    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('新增车辆'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('奥迪 奥迪A3'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '轩逸');
    await tester.pumpAndSettle();
    // 搜索框里的输入（EditableText）与列表行同名，精确点 PickerOption 行。
    await tester.tap(find.widgetWithText(PickerOption, '轩逸'));
    await tester.pumpAndSettle();
    expect(find.text('日产 轩逸'), findsOneWidget);

    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('上一步'));
    await tester.pumpAndSettle();

    expect(find.text('日产 轩逸'), findsOneWidget);
    expect(find.text('奥迪 奥迪A3'), findsNothing);
  });

  testWidgets(
    'add car wizard supports custom model input for catalog gaps',
    (tester) async {
      await pumpApp(tester);

      await tester.tap(find.text('我的'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('新增车辆'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('奥迪 奥迪A3'));
      await tester.pumpAndSettle();
      // 目录外的老车（懂车帝已下架）走自定义输入兜底（ADR 0003）。
      await tester.enterText(find.byType(TextField).last, '不存在的车系');
      await tester.pumpAndSettle();
      expect(find.text('没有匹配车型'), findsOneWidget);
      await tester.tap(find.text('＋ 自定义输入…'));
      await tester.pumpAndSettle();
      // dialog 里只有品牌/车型两个输入框，从 AlertDialog 范围内定位。
      final dialogFields = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(dialogFields.at(0), '雪佛兰');
      await tester.enterText(dialogFields.at(1), '科鲁泽');
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();

      expect(find.text('雪佛兰 科鲁泽'), findsOneWidget);
      // 自定义车型没有目录推荐值，动力类型预选燃油。
      expect(
        tester
            .widgetList<Text>(find.byType(Text))
            .map((text) => text.data)
            .whereType<String>(),
        contains('燃油'),
      );
    },
  );

  testWidgets('add car wizard reloads items after powertrain changes', (
    tester,
  ) async {
    await pumpApp(tester);

    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('新增车辆'));
    await tester.pumpAndSettle();

    // 默认预选燃油：机油/汽油滤芯都在。
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    expect(find.text('机油'), findsOneWidget);
    expect(find.text('汽油滤芯'), findsOneWidget);

    // 回第一步换成纯电：模板应整组换成纯电那套（没有机油）。
    await tester.tap(find.text('上一步'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('纯电'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();

    expect(find.text('机油'), findsNothing);
    expect(find.text('减速器油'), findsOneWidget);
  });

  testWidgets('profile can edit car mileage', (tester) async {
    final database = await pumpApp(tester);

    await createDefaultCar(tester);

    await tester.ensureVisible(find.widgetWithText(TextButton, '编辑').last);
    await tester.tap(find.widgetWithText(TextButton, '编辑').last);
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

  testWidgets('add car item step can remove a loaded default item', (
    tester,
  ) async {
    final database = await pumpApp(tester);

    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('新增车辆'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();

    // 燃油模板 10 项。
    expect(find.byTooltip('删除'), findsNWidgets(10));
    await tester.tap(find.byTooltip('删除').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存车辆'));
    await tester.pumpAndSettle();

    expect(
      await database.select(database.maintenanceItems).get(),
      hasLength(9),
    );
  });

  testWidgets('add car item step custom item form starts without intervals', (
    tester,
  ) async {
    await pumpApp(tester);

    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('新增车辆'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '新增'));
    await tester.pumpAndSettle();

    expect(find.text('新增保养项目'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField).at(1)).controller?.text,
      '',
    );
    expect(
      tester.widget<TextField>(find.byType(TextField).at(2)).controller?.text,
      '',
    );
  });

  testWidgets('add car item step can restore removed default item draft', (
    tester,
  ) async {
    final database = await pumpApp(tester);

    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('新增车辆'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('删除').first);
    await tester.pumpAndSettle();
    expect(find.text('机油'), findsNothing);

    await tester.tap(find.widgetWithText(TextButton, '恢复').last);
    await tester.pumpAndSettle();
    expect(find.text('恢复默认项目'), findsOneWidget);
    expect(find.text('已存在'), findsNWidgets(9));
    await tester.tap(find.widgetWithText(FilledButton, '恢复'));
    await tester.pumpAndSettle();
    expect(find.text('机油'), findsOneWidget);

    await tester.tap(find.text('保存车辆'));
    await tester.pumpAndSettle();

    expect(
      await database.select(database.maintenanceItems).get(),
      hasLength(10),
    );
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

  testWidgets('add car date picker today uses effective app date', (
    tester,
  ) async {
    await pumpApp(
      tester,
      dateContext: AppDateContext(readSystemNow: () => DateTime(2026, 1, 31)),
    );

    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('新增车辆'));
    await tester.pumpAndSettle();

    expect(find.text('2026年1月31日'), findsOneWidget);
    await tester.tap(find.text('2026年1月31日'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '1月'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2月'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(find.text('2026年2月28日'), findsOneWidget);

    await tester.tap(find.text('2026年2月28日'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '今天'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    expect(find.text('2026年1月31日'), findsOneWidget);
  });

  testWidgets('destructive confirm dialog uses red confirm action', (
    tester,
  ) async {
    await pumpApp(tester);
    await createDefaultCar(tester);

    await tester.tap(find.widgetWithText(TextButton, '删除').first);
    await tester.pumpAndSettle();

    expect(find.byType(BackdropFilter), findsOneWidget);
    final deleteButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '删除'),
    );
    final background = deleteButton.style?.backgroundColor?.resolve({});
    expect(background, const Color(0xffef4444));

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('删除车辆'), findsNothing);
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

    expect(find.text('保养提醒'), findsWidgets);
    expect(find.text('机油'), findsOneWidget);
    expect(find.text('0%'), findsWidgets);
    expect(find.text('里程：距离下次约 5,000 公里'), findsOneWidget);
  });

  testWidgets('reminders use manual date for time progress', (tester) async {
    final database = await pumpApp(
      tester,
      dateContext: AppDateContext(readSystemNow: () => DateTime(2026, 5, 19)),
    );
    await createDefaultCar(tester);
    await createDefaultRecord(tester);

    await pumpApp(
      tester,
      database: database,
      dateContext: AppDateContext(
        readSystemNow: () => DateTime(2026, 5, 19),
        manualDate: const LocalDate(2027, 5, 19),
      ),
    );
    await tester.tap(find.text('提醒'));
    await tester.pumpAndSettle();

    expect(find.text('超期'), findsWidgets);
    expect(find.textContaining('已超期'), findsNothing);
    expect(find.text('时间：已超 6个月'), findsWidgets);

    await tester.tap(find.text('机油').first);
    await tester.pumpAndSettle();
    expect(find.text('上次保养日期'), findsOneWidget);
    expect(find.text('2026-05-19'), findsOneWidget);
    expect(find.text('上次保养里程'), findsOneWidget);
    expect(find.text('13,000 km'), findsOneWidget);
  });

  testWidgets('profile can enable manual date preference', (tester) async {
    final database = await pumpApp(tester);
    await createDefaultCar(tester);
    await enableDeveloperMode(tester);

    await tester.tap(find.widgetWithText(TextButton, '设置').last);
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

  testWidgets('profile hides manual date behind developer mode', (
    tester,
  ) async {
    final database = await pumpApp(tester);
    await createDefaultCar(tester);

    expect(find.text('版本 1.0.0'), findsOneWidget);
    expect(find.text('手动日期'), findsNothing);

    await enableDeveloperMode(tester);
    await tester.tap(find.widgetWithText(TextButton, '设置').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存日期'));
    await tester.pumpAndSettle();

    for (var index = 0; index < 5; index++) {
      await tester.tap(find.text('版本 1.0.0 · 开发者模式'));
      await tester.pumpAndSettle();
    }

    expect(find.text('手动日期'), findsNothing);
    expect(
      await testRepository(database).getPreferenceValue('manualDateEnabled'),
      'false',
    );
    expect(
      await testRepository(database).getPreferenceValue('manualDate'),
      isNull,
    );
  });

  testWidgets('profile can save maintenance notification settings', (
    tester,
  ) async {
    final notificationCalls = <MethodCall>[];
    final cleanupNotifications = mockAndroidNotifications(notificationCalls);
    try {
      final database = await pumpApp(tester, inAppNotificationsEnabled: true);
      await createDefaultCar(tester);

      await tester.tap(find.text('通知提醒'));
      await tester.pumpAndSettle();
      expect(find.text('手机系统通知、应用内通知'), findsOneWidget);
      expect(find.textContaining('到期后：每周'), findsNothing);
      expect(find.text('到期后提醒次数'), findsNothing);

      await tester.tap(find.widgetWithText(TextButton, '设置').first);
      await tester.pumpAndSettle();
      expect(find.text('手机系统通知'), findsOneWidget);
      expect(find.text('应用内通知'), findsOneWidget);
      expect(find.text('到期后提醒次数'), findsOneWidget);
      expect(find.text('每周'), findsOneWidget);
      expect(find.text('每 2 周'), findsOneWidget);
      expect(find.text('每月'), findsOneWidget);
      expect(find.text('每天'), findsNothing);
      expect(find.text('系统 App 通知'), findsNothing);
      expect(find.text('打开 App 弹窗通知'), findsNothing);
      expect(find.text('到期提醒'), findsNothing);
      expect(find.text('提前提醒'), findsNothing);
      expect(find.text('超期提醒'), findsNothing);
      expect(find.text('达到后的提醒次数'), findsNothing);

      await tester.tap(find.text('每 2 周'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存设置'));
      await tester.pumpAndSettle();

      final repository = testRepository(database);
      expect(
        await repository.getPreferenceValue('inAppNotificationsEnabled'),
        'true',
      );
      expect(
        await repository.getPreferenceValue('maintenanceDueRepeat'),
        'everyTwoWeeks',
      );
      expect(find.text('手机系统通知、应用内通知'), findsOneWidget);
      expect(find.textContaining('到期后：每 2 周'), findsNothing);
      expect(find.text('通知设置已保存'), findsNothing);
      expect(
        await repository.getPreferenceValue('maintenanceEarlyEnabled'),
        isNull,
      );
      expect(
        await repository.getPreferenceValue(
          'maintenanceNotificationEarlyPercent',
        ),
        isNull,
      );
      expect(
        await repository.getPreferenceValue('maintenanceOverdueEnabled'),
        isNull,
      );
    } finally {
      cleanupNotifications();
    }
  });

  testWidgets(
    'notification settings refresh system permission status on open',
    (tester) async {
      final notificationCalls = <MethodCall>[];
      final cleanupNotifications = mockAndroidNotifications(
        notificationCalls,
        notificationsEnabled: false,
      );
      try {
        final database = AppDatabase.inMemory();
        addTearDown(database.close);
        final repository = testRepository(database);
        await repository.setPreferenceValue(
          'systemNotificationPermissionRequested',
          'true',
        );

        await pumpApp(
          tester,
          database: database,
          systemNotificationsEnabled: true,
        );

        await tester.tap(find.text('我的'));
        await tester.pumpAndSettle();
        notificationCalls.clear();
        await tester.tap(find.widgetWithText(TextButton, '设置').first);
        await tester.pumpAndSettle();

        expect(
          notificationCalls.map((call) => call.method),
          contains('areNotificationsEnabled'),
        );
        expect(
          await repository.getPreferenceValue('systemNotificationsEnabled'),
          'false',
        );
      } finally {
        cleanupNotifications();
      }
    },
  );

  testWidgets('notification settings opens system notification settings', (
    tester,
  ) async {
    final notificationCalls = <MethodCall>[];
    final cleanupNotifications = mockAndroidNotifications(notificationCalls);
    var openSettingsCount = 0;
    mockNativeNotificationSettings((call) async {
      if (call.method == 'openNotificationSettings') {
        openSettingsCount++;
        return true;
      }
      return null;
    });
    try {
      await pumpApp(tester, inAppNotificationsEnabled: true);
      await tester.tap(find.text('我的'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, '设置').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('系统设置'));
      await tester.pumpAndSettle();

      expect(openSettingsCount, 1);
    } finally {
      cleanupNotifications();
    }
  });

  testWidgets(
    'in-app reminder can snooze maintenance item and mileage update',
    (tester) async {
      final database = AppDatabase.inMemory();
      addTearDown(database.close);
      final repository = testRepository(database);
      await repository.ensureBootstrapData();
      final sync = SyncMetadata(
        status: SyncStatus.pendingCreate,
        updatedAt: DateTime(2026, 4, 1),
      );
      final carId = await createCarWithDefaultItems(repository, 
        Car(
          brand: '本田',
          model: '思域（燃油版）',
          currentMileageKm: 0,
          roadDate: const LocalDate(2026, 5, 19),
          sync: sync,
        ),
      );
      await repository.setAppliedCarId(carId);
      final car = (await repository.listCars()).single;
      final item = (await repository.listMaintenanceItemsForCar(
        car.id!,
      )).firstWhere((item) => item.remindByTime);
      await repository.saveMaintenanceRecord(
        MaintenanceRecord(
          carId: car.id!,
          date: const LocalDate(2025, 5, 19),
          itemIds: [item.id!],
          costCents: 0,
          mileageKm: 0,
          sync: sync,
        ),
      );
      await repository.setPreferenceValue('inAppNotificationsEnabled', 'true');

      await pumpApp(
        tester,
        database: database,
        inAppNotificationsEnabled: true,
      );
      await tester.pumpAndSettle();

      expect(find.text('保养提醒'), findsWidgets);
      expect(find.text(item.name), findsWidgets);
      expect(find.textContaining('已超'), findsWidgets);
      expect(find.textContaining('时间到期已超'), findsNothing);
      expect(find.textContaining('里程已超'), findsNothing);
      expect(find.text('更新当前里程'), findsNothing);
      expect(find.text('15 天内不再提醒'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, '15 天内不再提醒'));
      await tester.pumpAndSettle();
      expect(
        await repository.getPreferenceValue(
          'maintenanceReminderSnoozedUntil:${item.id}',
        ),
        '2026-06-03',
      );

      expect(find.text('更新当前里程'), findsOneWidget);
      expect(
        find.descendant(of: find.byType(Dialog), matching: find.text('保养提醒')),
        findsNothing,
      );
      await tester.tap(find.widgetWithText(FilledButton, '15 天内不再提醒'));
      await tester.pumpAndSettle();
      expect(
        await repository.getPreferenceValue(
          'mileageUpdateSnoozedUntil:${car.id}',
        ),
        '2026-06-03',
      );
    },
  );

  testWidgets('mileage update reminder waits for car updated_at cadence', (
    tester,
  ) async {
    final database = AppDatabase.inMemory();
    addTearDown(database.close);
    final repository = testRepository(database);
    await repository.ensureBootstrapData();
    final sync = SyncMetadata(
      status: SyncStatus.pendingCreate,
      updatedAt: DateTime(2026, 5),
    );
    final carId = await createCarWithDefaultItems(repository, 
      Car(
        brand: '本田',
        model: '思域（燃油版）',
        currentMileageKm: 0,
        roadDate: const LocalDate(2026, 5, 19),
        sync: sync,
      ),
    );
    await repository.setAppliedCarId(carId);
    final car = (await repository.listCars()).single;
    final item = (await repository.listMaintenanceItemsForCar(
      car.id!,
    )).firstWhere((item) => item.remindByTime);
    await repository.saveMaintenanceRecord(
      MaintenanceRecord(
        carId: car.id!,
        date: const LocalDate(2025, 5, 19),
        itemIds: [item.id!],
        costCents: 0,
        mileageKm: 0,
        sync: sync,
      ),
    );
    await repository.setPreferenceValue('inAppNotificationsEnabled', 'true');

    await pumpApp(tester, database: database, inAppNotificationsEnabled: true);
    await tester.pumpAndSettle();

    expect(find.text('保养提醒'), findsWidgets);
    await tester.tap(find.widgetWithText(FilledButton, '15 天内不再提醒'));
    await tester.pumpAndSettle();

    expect(find.text('更新当前里程'), findsNothing);
  });

  testWidgets(
    'in-app reminder acknowledgement suppresses reminders for the day',
    (tester) async {
      final notificationCalls = <MethodCall>[];
      final cleanupNotifications = mockAndroidNotifications(notificationCalls);
      final database = AppDatabase.inMemory();
      addTearDown(database.close);
      final repository = testRepository(database);
      await repository.ensureBootstrapData();
      final sync = SyncMetadata(
        status: SyncStatus.pendingCreate,
        updatedAt: DateTime(2026, 4, 1),
      );
      final carId = await createCarWithDefaultItems(repository, 
        Car(
          brand: '本田',
          model: '思域（燃油版）',
          currentMileageKm: 0,
          roadDate: const LocalDate(2026, 5, 19),
          sync: sync,
        ),
      );
      await repository.setAppliedCarId(carId);
      final car = (await repository.listCars()).single;
      final item = (await repository.listMaintenanceItemsForCar(
        car.id!,
      )).firstWhere((item) => item.remindByTime);
      await repository.saveMaintenanceRecord(
        MaintenanceRecord(
          carId: car.id!,
          date: const LocalDate(2025, 5, 19),
          itemIds: [item.id!],
          costCents: 0,
          mileageKm: 0,
          sync: sync,
        ),
      );
      await repository.setPreferenceValue('inAppNotificationsEnabled', 'true');

      await pumpApp(
        tester,
        database: database,
        systemNotificationsEnabled: true,
        inAppNotificationsEnabled: true,
      );
      await tester.pumpAndSettle();

      expect(find.text('保养提醒'), findsWidgets);
      notificationCalls.clear();
      await tester.tap(find.widgetWithText(FilledButton, '知道了'));
      await tester.pumpAndSettle();
      expect(
        await repository.getPreferenceValue(
          'maintenanceInAppReminderAcknowledgedOn:${item.id}',
        ),
        '2026-05-19',
      );
      expect(find.text('更新当前里程'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '知道了'));
      await tester.pumpAndSettle();
      expect(
        await repository.getPreferenceValue(
          'mileageUpdateInAppAcknowledgedOn:${car.id}',
        ),
        '2026-05-19',
      );
      expect(
        notificationCalls
            .where((call) => call.method == 'zonedSchedule')
            .map((call) => call.arguments as Map<Object?, Object?>)
            .map((arguments) => arguments['title']),
        contains('保养提醒'),
      );

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(find.widgetWithText(FilledButton, '知道了'), findsNothing);
      expect(find.text('更新当前里程'), findsNothing);

      await pumpApp(
        tester,
        database: database,
        inAppNotificationsEnabled: true,
      );
      await tester.pumpAndSettle();

      expect(find.widgetWithText(FilledButton, '知道了'), findsNothing);
      expect(find.text('更新当前里程'), findsNothing);
      cleanupNotifications();
    },
  );

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
    // 油价来自示例数据源，但界面不再标注"示例数据"（文案已精简）。
    expect(find.textContaining('示例数据'), findsNothing);
    // 档位列表：已存的 50% 定位在第一行，窗口内往下可见 48/46/44/42。
    expect(find.text('50%'), findsOneWidget);
    expect(find.textContaining('（当前）'), findsNothing);
    expect(find.text('48%'), findsOneWidget);
    expect(find.text('46%'), findsOneWidget);
    expect(find.text('44%'), findsOneWidget);
    expect(find.text('42%'), findsOneWidget);
    // 50% 档：55 升 × (100-50)/100 = 27.5 升；
    // 湖北 92# 示例价 7.45 + 16×0.01 = 7.61，27.5 × 7.61 = 209.28 元。
    expect(find.textContaining('需 27.5 升'), findsOneWidget);
    expect(find.text('¥209.28'), findsOneWidget);
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

    // 向上拖三行左右：滚动停稳后吸附物理把第一行对齐到整行档位，
    // 并自动把该档位写库（timedDrag 匀速拖动，落点可复现）。
    await tester.timedDrag(find.text('50%'), const Offset(0, -132), const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    final saved = await repository.getFuelPredictionForCar(carId);
    expect(saved?.fuelPercent, 46);
    expect(find.text('46%'), findsOneWidget);
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
