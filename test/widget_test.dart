import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:lunio/app/providers.dart';
import 'package:lunio/app/lunio_app.dart';
import 'package:lunio/core/date/app_date_context.dart';
import 'package:lunio/core/date/local_date.dart';
import 'package:lunio/data/backup/backup_codec.dart';
import 'package:lunio/data/database/app_database.dart';
import 'package:lunio/data/repositories/lunio_repository.dart';
import 'package:lunio/domain/entities/car.dart';
import 'package:lunio/domain/entities/maintenance_item.dart';
import 'package:lunio/domain/entities/sync_metadata.dart';

void main() {
  const nativeFilesChannel = MethodChannel('lunio/native_files');

  void mockNativeFiles(Future<Object?> Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(nativeFilesChannel, handler);
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(nativeFilesChannel, null),
    );
  }

  Future<AppDatabase> pumpApp(
    WidgetTester tester, {
    AppDateContext? dateContext,
    AppDatabase? database,
  }) async {
    final appDatabase = database ?? AppDatabase.inMemory();
    if (database == null) {
      addTearDown(appDatabase.close);
    }
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(appDatabase),
          appDateContextProvider.overrideWithValue(
            dateContext ??
                AppDateContext(readSystemNow: () => DateTime(2026, 5, 19)),
          ),
        ],
        child: const LunioApp(),
      ),
    );
    await tester.pumpAndSettle();
    return appDatabase;
  }

  Future<void> createDefaultCar(WidgetTester tester) async {
    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('新增车辆'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('下一步'));
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
    await tester.tap(find.text('下一步'));
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

  testWidgets('record form shows car and can add maintenance item', (
    tester,
  ) async {
    final database = await pumpApp(tester);
    await createDefaultCar(tester);
    await tester.tap(find.text('提醒'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('新增保养记录'));
    await tester.pumpAndSettle();

    expect(find.text('东风本田 思域'), findsWidgets);
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
      hasLength(15),
    );
    expect(find.text('玻璃水', skipOffstage: false), findsOneWidget);
  });

  testWidgets('profile can create a car and set it as applied car', (
    tester,
  ) async {
    final database = await pumpApp(tester);

    await createDefaultCar(tester);

    expect(find.text('东风本田 思域'), findsWidgets);
    expect(find.text('当前'), findsOneWidget);
    expect(find.textContaining('0km'), findsOneWidget);
    expect(find.textContaining('车龄'), findsNothing);
    expect(find.textContaining('上路'), findsNothing);
    expect(find.text('当前车辆保养项目'), findsNothing);
    expect(await database.select(database.cars).get(), hasLength(1));
    expect(
      await database.select(database.maintenanceItems).get(),
      hasLength(14),
    );
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
    expect(find.text('备份'), findsOneWidget);
    expect(find.text('JSON 备份'), findsNothing);

    await tester.tap(find.text('导出').first);
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
    await tester.tap(find.text('导出').first);
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('备份完成'), findsNothing);
  });

  testWidgets('profile restore confirms before picking a file', (tester) async {
    mockNativeFiles((call) async {
      if (call.method == 'pickJsonFile') {
        return const BackupCodec().encode(
          const BackupPayload(schemaVersion: 2),
        );
      }
      return null;
    });
    final database = await pumpApp(tester);
    await createDefaultCar(tester);

    await tester.tap(find.text('恢复').first);
    await tester.pumpAndSettle();
    expect(find.text('恢复数据'), findsOneWidget);

    await tester.tap(find.text('恢复').last);
    await tester.pump(const Duration(milliseconds: 250));

    expect(await database.select(database.cars).get(), isEmpty);
    expect(find.text('恢复完成'), findsOneWidget);
    expect(find.text('数据恢复'), findsNothing);
    expect(find.text('备份 JSON'), findsNothing);
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

    await tester.tap(find.text('恢复').first);
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

    await tester.tap(find.text('恢复').first);
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
            schemaVersion: 2,
            cars: [
              Car(
                id: 99,
                brand: '东风本田',
                model: '思域',
                currentMileageKm: 12000,
                roadDate: LocalDate.parse(existingCar.roadDate),
                sync: sync,
              ),
              Car(
                id: 100,
                brand: '东风本田',
                model: '思域',
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

    await tester.tap(find.text('恢复').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('恢复').last);
    await tester.pumpAndSettle();

    expect(await database.select(database.cars).get(), hasLength(1));
    expect(find.text('恢复失败'), findsOneWidget);
    expect(find.text('确认'), findsOneWidget);
    expect(find.text('取消'), findsNothing);
  });

  testWidgets('add car first step does not persist data', (tester) async {
    final database = await pumpApp(tester);

    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('新增车辆'));
    await tester.pumpAndSettle();
    expect(find.textContaining('同一品牌车型'), findsNothing);
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();

    expect(find.text('上一步'), findsOneWidget);
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
    await tester.tap(find.text('东风本田 思域'));
    await tester.pumpAndSettle();

    expect(find.text('选择车型'), findsOneWidget);
    expect(find.text('搜索品牌或车型'), findsOneWidget);
    expect(find.text('东风本田'), findsWidgets);
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
      hasLength(15),
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
    await tester.tap(find.text('汽油发动机清洁剂（燃油宝）'));
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
    final repository = LunioRepository(database);
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

    expect(find.byTooltip('删除'), findsNWidgets(14));
    await tester.tap(find.byTooltip('删除').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存车辆'));
    await tester.pumpAndSettle();

    expect(
      await database.select(database.maintenanceItems).get(),
      hasLength(13),
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
    expect(find.text('汽油发动机清洁剂（燃油宝）'), findsNothing);

    await tester.tap(find.widgetWithText(TextButton, '恢复'));
    await tester.pumpAndSettle();
    expect(find.text('恢复默认项目'), findsOneWidget);
    expect(find.text('已存在'), findsNWidgets(13));
    await tester.tap(find.widgetWithText(FilledButton, '恢复'));
    await tester.pumpAndSettle();
    expect(find.text('汽油发动机清洁剂（燃油宝）'), findsOneWidget);

    await tester.tap(find.text('保存车辆'));
    await tester.pumpAndSettle();

    expect(
      await database.select(database.maintenanceItems).get(),
      hasLength(14),
    );
  });

  testWidgets('date picker switches between day month and year grids', (
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

    await tester.tap(find.text('手动日期'));
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
    await tester.tap(find.byTooltip('新增保养记录'));
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

    expect(find.text('保养提醒'), findsOneWidget);
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
