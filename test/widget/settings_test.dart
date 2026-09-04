// settings 域 widget 测试（共享夹具见 test/helpers/widget_app.dart）。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:lunio/app/providers.dart';
import 'package:lunio/data/backup/backup_codec.dart';

import 'package:lunio/core/date/local_date.dart';
import 'package:lunio/data/database/app_database.dart';
import 'package:lunio/domain/entities/car.dart';
import 'package:lunio/domain/entities/notification_settings.dart';
import 'package:lunio/domain/entities/sync_metadata.dart';
import '../helpers/widget_app.dart';

void main() {
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

      // 行标题"恢复数据"是不可点的纯文本，点它不会打开确认弹窗；
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
}
