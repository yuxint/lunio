// reminders 域 widget 测试（共享夹具见 test/helpers/widget_app.dart）。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:lunio/app/providers.dart';
import 'package:lunio/core/date/app_date_context.dart';

import 'package:lunio/core/date/local_date.dart';
import 'package:lunio/data/database/app_database.dart';
import 'package:lunio/domain/entities/car.dart';
import 'package:lunio/domain/entities/maintenance_record.dart';
import 'package:lunio/domain/entities/sync_metadata.dart';
import '../helpers/widget_app.dart';

void main() {
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
    final carId = await createCarWithDefaultItems(database, 
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
      final carId = await createCarWithDefaultItems(database, 
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
    final carId = await createCarWithDefaultItems(database, 
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
      try {
        final database = AppDatabase.inMemory();
        addTearDown(database.close);
        final repository = testRepository(database);
        await repository.ensureBootstrapData();
        final sync = SyncMetadata(
          status: SyncStatus.pendingCreate,
          updatedAt: DateTime(2026, 4, 1),
        );
        final carId = await createCarWithDefaultItems(
          database,
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
      } finally {
        cleanupNotifications();
      }
    },
  );
}
