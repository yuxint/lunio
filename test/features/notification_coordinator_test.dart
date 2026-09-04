// 通知协调器的单元测试：权限真值协议、通知清扫模板、停车倒计时通知尾巴。
//
// LunioNotificationCoordinator 的依赖（容器 Ref、Repository、通知服务）
// 全部可替换：这里用内存数据库 + override 后的 ProviderContainer 驱动
// 真实装配，通知插件用 mock 方法通道（与 widget_test 同一手法），锁死：
//  - reconcileSystemEnabled：真值回写只在不一致时发生，查询失败回退偏好值；
//  - requestPermission：记"已请求过"，被拒回写"系统通知关闭"；
//  - run* 清扫模板：先升代数再删库再清扫，删库失败不清扫（异常上抛）；
//  - onParkingCountdownSaved：开关关直接返回，授权且代数未变才调度。
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:lunio/app/providers.dart';
import 'package:lunio/core/notifications/lunio_notification_service.dart';
import 'package:lunio/data/database/app_database.dart';
import 'package:lunio/data/preferences/app_preferences.dart';
import 'package:lunio/domain/entities/notification_settings.dart';
import 'package:lunio/domain/entities/parking_countdown.dart';
import 'package:lunio/features/shell/reminders/notification_coordinator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const notificationsChannel = MethodChannel(
    'dexterous.com/flutter/local_notifications',
  );
  const timezoneChannel = MethodChannel('flutter_timezone');

  late AppDatabase database;
  late ProviderContainer container;
  late LunioPreferences preferences;
  late LunioNotificationCoordinator coordinator;
  late List<MethodCall> notificationCalls;

  /// 注册 Android 平台实现 + mock 通知/时区通道。[onCall] 在每次通道调用
  /// 后触发（用于在权限请求期间 bump 同步代数等竞态模拟）。
  void mockAndroidNotifications({
    bool notificationsEnabled = true,
    bool permissionGranted = true,
    void Function(MethodCall call)? onCall,
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
          notificationCalls.add(call);
          onCall?.call(call);
          return switch (call.method) {
            'initialize' => true,
            'requestNotificationsPermission' => permissionGranted,
            'areNotificationsEnabled' => notificationsEnabled,
            'canScheduleExactNotifications' => true,
            'requestExactAlarmsPermission' => true,
            _ => null,
          };
        });
  }

  /// 让"查询系统通知开关"抛异常（模拟平台查询失败）。
  void mockSystemQueryFailure() {
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
          notificationCalls.add(call);
          if (call.method == 'areNotificationsEnabled') {
            throw PlatformException(code: 'mock', message: '查询失败');
          }
          return switch (call.method) {
            'initialize' => true,
            _ => null,
          };
        });
  }

  setUp(() {
    // 通知服务是进程级单例：重置初始化状态，避免上一个用例的初始化结果
    //（可用/不可用）影响本用例的 mock 行为。
    database = AppDatabase.inMemory();
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        // 服务逐用例新建，替代原 resetForTest 的单例状态重置。
        lunioNotificationServiceProvider.overrideWithValue(
          LunioNotificationService(),
        ),
      ],
    );
    preferences = container.read(lunioPreferencesProvider);
    coordinator = container.read(notificationCoordinatorProvider);
    notificationCalls = <MethodCall>[];
  });

  tearDown(() async {
    container.dispose();
    await database.close();
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notificationsChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(timezoneChannel, null);
  });

  group('reconcileSystemEnabled', () {
    test('writes the system truth back and refreshes the settings provider',
        () async {
      mockAndroidNotifications(notificationsEnabled: false);
      // 偏好当前值为开（默认），系统真实状态为关。
      final before = await container.read(notificationSettingsProvider.future);
      expect(before.systemNotificationsEnabled, isTrue);

      final result = await coordinator.reconcileSystemEnabled();

      expect(result, isFalse);
      expect(
        await preferences.readRaw('systemNotificationsEnabled'),
        'false',
      );
      // 偏好缓存已被失效：设置 provider 重算后反映系统真实状态。
      final after = await container.read(notificationSettingsProvider.future);
      expect(after.systemNotificationsEnabled, isFalse);
    });

    test('does not write when the preference already matches the system',
        () async {
      mockAndroidNotifications(notificationsEnabled: false);
      await preferences.writeRaw('systemNotificationsEnabled', 'false');

      final result = await coordinator.reconcileSystemEnabled();

      expect(result, isFalse);
      // 偏好与系统真值一致：不发生回写，值保持不变。
      expect(
        await preferences.readRaw('systemNotificationsEnabled'),
        'false',
      );
    });

    test('falls back to the preference value when the system query fails',
        () async {
      mockSystemQueryFailure();
      await preferences.writeRaw('systemNotificationsEnabled', 'true');

      final result = await coordinator.reconcileSystemEnabled();

      expect(result, isTrue);
      // 查询失败不写偏好。
      expect(
        await preferences.readRaw('systemNotificationsEnabled'),
        'true',
      );
    });
  });

  group('requestPermission', () {
    test('records the request and keeps the enabled preference untouched on grant',
        () async {
      mockAndroidNotifications(permissionGranted: true);

      final granted = await coordinator.requestPermission();

      expect(granted, isTrue);
      expect(
        await preferences.readRaw(
          'systemNotificationPermissionRequested',
        ),
        'true',
      );
      expect(
        await preferences.readRaw('systemNotificationsEnabled'),
        isNull,
      );
    });

    test('writes the enabled preference off and refreshes on denial', () async {
      mockAndroidNotifications(permissionGranted: false);
      await container.read(notificationSettingsProvider.future);

      final granted = await coordinator.requestPermission();

      expect(granted, isFalse);
      expect(
        await preferences.readRaw(
          'systemNotificationPermissionRequested',
        ),
        'true',
      );
      expect(
        await preferences.readRaw('systemNotificationsEnabled'),
        'false',
      );
      final settings = await container.read(notificationSettingsProvider.future);
      expect(settings.systemNotificationsEnabled, isFalse);
    });
  });

  group('ensureInitialSystemNotificationPermission', () {
    test('requests the permission on first run and reports that it did',
        () async {
      mockAndroidNotifications(permissionGranted: true);

      final requestedNow = await coordinator
          .ensureInitialSystemNotificationPermission();

      expect(requestedNow, isTrue);
      expect(
        notificationCalls.map((call) => call.method),
        contains('requestNotificationsPermission'),
      );
    });

    test('only reconciles on later runs without asking again', () async {
      mockAndroidNotifications(notificationsEnabled: false);
      await preferences.writeRaw(
        'systemNotificationPermissionRequested',
        'true',
      );

      final requestedNow = await coordinator
          .ensureInitialSystemNotificationPermission();

      expect(requestedNow, isFalse);
      expect(
        notificationCalls.map((call) => call.method),
        isNot(contains('requestNotificationsPermission')),
      );
      // reconcile 已把偏好对齐系统真值。
      expect(
        await preferences.readRaw('systemNotificationsEnabled'),
        'false',
      );
    });
  });

  group('ensureSystemNotificationsSchedulable', () {
    test('returns true without asking when the system allows notifications',
        () async {
      mockAndroidNotifications(notificationsEnabled: true);

      final schedulable = await coordinator
          .ensureSystemNotificationsSchedulable();

      expect(schedulable, isTrue);
      expect(
        notificationCalls.map((call) => call.method),
        isNot(contains('requestNotificationsPermission')),
      );
    });

    test('asks once and proceeds when granted', () async {
      mockAndroidNotifications(notificationsEnabled: false);

      final schedulable = await coordinator
          .ensureSystemNotificationsSchedulable();

      expect(schedulable, isTrue);
      expect(
        notificationCalls.map((call) => call.method),
        contains('requestNotificationsPermission'),
      );
      expect(
        await preferences.readRaw(
          'systemNotificationPermissionRequested',
        ),
        'true',
      );
    });

    test('writes the preference off and cancels scheduling when denied',
        () async {
      mockAndroidNotifications(
        notificationsEnabled: false,
        permissionGranted: false,
      );

      final schedulable = await coordinator
          .ensureSystemNotificationsSchedulable();

      expect(schedulable, isFalse);
      expect(
        await preferences.readRaw('systemNotificationsEnabled'),
        'false',
      );
      expect(
        notificationCalls.map((call) => call.method),
        contains('cancel'),
      );
    });

    test('reconciles to off and cancels when previously requested but still off',
        () async {
      mockAndroidNotifications(notificationsEnabled: false);
      await preferences.writeRaw(
        'systemNotificationPermissionRequested',
        'true',
      );

      final schedulable = await coordinator
          .ensureSystemNotificationsSchedulable();

      expect(schedulable, isFalse);
      expect(
        notificationCalls.map((call) => call.method),
        isNot(contains('requestNotificationsPermission')),
      );
      expect(
        await preferences.readRaw('systemNotificationsEnabled'),
        'false',
      );
      expect(
        notificationCalls.map((call) => call.method),
        contains('cancel'),
      );
    });
  });

  group('saveNotificationSettings', () {
    test('writes the three keys and refreshes the settings provider', () async {
      mockAndroidNotifications();
      await container.read(notificationSettingsProvider.future);

      await coordinator.saveNotificationSettings(
        const LunioNotificationSettings(
          systemNotificationsEnabled: false,
          inAppNotificationsEnabled: false,
          dueRepeatFrequency: ReminderRepeatFrequency.monthly,
        ),
      );

      final values = await preferences.readRawAll([
        'systemNotificationsEnabled',
        'inAppNotificationsEnabled',
        'maintenanceDueRepeat',
      ]);
      expect(values['systemNotificationsEnabled'], 'false');
      expect(values['inAppNotificationsEnabled'], 'false');
      expect(values['maintenanceDueRepeat'], 'monthly');
      final settings = await container.read(notificationSettingsProvider.future);
      expect(settings.dueRepeatFrequency, ReminderRepeatFrequency.monthly);
    });
  });

  group('notification sweep templates', () {
    test('runCarDeletion bumps the generation, deletes, then cancels reminders',
        () async {
      mockAndroidNotifications();
      var deleted = false;
      final generationBefore = container.read(notificationSyncGenerationProvider);

      await coordinator.runCarDeletion(() async {
        deleted = true;
      });

      expect(deleted, isTrue);
      expect(
        container.read(notificationSyncGenerationProvider),
        generationBefore + 1,
      );
      expect(
        notificationCalls.map((call) => call.method),
        contains('cancel'),
      );
    });

    test('runCarDeletion skips the sweep when the deletion fails', () async {
      mockAndroidNotifications();

      await expectLater(
        coordinator.runCarDeletion(() async {
          throw StateError('删库失败');
        }),
        throwsStateError,
      );
      expect(
        notificationCalls.map((call) => call.method),
        isNot(contains('cancel')),
      );
    });

    test('runBackupRestore cancels reminder notifications but keeps parking',
        () async {
      mockAndroidNotifications();
      final parkingIds = <Object?>[];

      await coordinator.runBackupRestore(() async {});

      for (final call in notificationCalls.where(
        (call) => call.method == 'cancel',
      )) {
        parkingIds.add(call.arguments['id']);
      }
      // 8000/8900 系已取消，9001/9002（停车）不在取消名单里。
      expect(parkingIds, contains(8000));
      expect(parkingIds, isNot(contains(9001)));
      expect(parkingIds, isNot(contains(9002)));
    });

    test('runAllDataClear cancels parking first, then reminder notifications',
        () async {
      mockAndroidNotifications();
      final cancelledIds = <Object?>[];

      await coordinator.runAllDataClear(() async {});

      for (final call in notificationCalls.where(
        (call) => call.method == 'cancel',
      )) {
        cancelledIds.add(call.arguments['id']);
      }
      expect(cancelledIds.indexOf(9001), lessThan(cancelledIds.indexOf(8000)));
      expect(cancelledIds, contains(9002));
    });
  });

  group('onParkingCountdownSaved', () {
    // 倒计时的到点时刻必须是未来：通知服务遇到"到点时刻已过"会直接跳过
    // 调度（lunio_notification_service.dart 的 scheduleParkingCountdownNotification），
    // 写死日期一旦过了就全部用例退化/挂掉，所以用相对当前时间的时刻。
    ParkingCountdown countdown() => ParkingCountdown(
          startedAt: DateTime.now(),
          durationSeconds: 1800,
        );

    test('returns early without asking when system notifications are off',
        () async {
      mockAndroidNotifications(notificationsEnabled: false);
      await preferences.writeRaw('systemNotificationsEnabled', 'false');

      await coordinator.onParkingCountdownSaved(countdown());

      expect(
        notificationCalls.map((call) => call.method),
        isNot(contains('requestNotificationsPermission')),
      );
      expect(
        notificationCalls.map((call) => call.method),
        isNot(contains('zonedSchedule')),
      );
    });

    test('requests the permission, then schedules the due alert', () async {
      mockAndroidNotifications();

      await coordinator.onParkingCountdownSaved(countdown());

      // canScheduleExactNotifications 为 true 时服务跳过精确闹钟请求，
      // 直接带 exact 调度。
      expect(
        notificationCalls.map((call) => call.method),
        containsAllInOrder([
          'requestNotificationsPermission',
          'canScheduleExactNotifications',
          'zonedSchedule',
        ]),
      );
    });

    test('writes the preference off and skips scheduling when denied', () async {
      mockAndroidNotifications(permissionGranted: false);

      await coordinator.onParkingCountdownSaved(countdown());

      expect(
        await preferences.readRaw('systemNotificationsEnabled'),
        'false',
      );
      expect(
        notificationCalls.map((call) => call.method),
        isNot(contains('zonedSchedule')),
      );
    });

    test('skips scheduling when the sync generation changed mid-flight',
        () async {
      mockAndroidNotifications(
        onCall: (call) {
          // 模拟权限请求对话框期间发生恢复备份/清空数据（代数 bump，R8）。
          if (call.method == 'requestNotificationsPermission') {
            container
                .read(notificationSyncGenerationProvider.notifier)
                .bump();
          }
        },
      );

      await coordinator.onParkingCountdownSaved(countdown());

      expect(
        notificationCalls.map((call) => call.method),
        isNot(contains('zonedSchedule')),
      );
    });
  });

  group('onParkingCountdownCleared', () {
    test('cancels the parking notifications while system notifications are on',
        () async {
      mockAndroidNotifications();

      await coordinator.onParkingCountdownCleared();

      final cancelledIds = notificationCalls
          .where((call) => call.method == 'cancel')
          .map((call) => call.arguments['id']);
      expect(cancelledIds, containsAll([9001, 9002]));
    });

    test('does not cancel anything while system notifications are off',
        () async {
      mockAndroidNotifications(notificationsEnabled: false);
      await preferences.writeRaw('systemNotificationsEnabled', 'false');

      await coordinator.onParkingCountdownCleared();

      expect(
        notificationCalls.map((call) => call.method),
        isNot(contains('cancel')),
      );
    });
  });
}
