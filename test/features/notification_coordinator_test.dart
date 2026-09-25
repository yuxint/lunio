// 通知协调器的单元测试：权限真值协议、通知清扫模板、停车倒计时通知尾巴。
//
// LunioNotificationCoordinator 的依赖（容器 Ref、Repository、通知服务）
// 全部可替换：这里用内存数据库 + override 后的 ProviderContainer 驱动
// 真实装配，通知插件用 mock 方法通道（与 test/widget 共享夹具同一手法），锁死：
//  - reconcileSystemEnabled：真值回写只在不一致时发生，查询失败回退偏好值；
//  - requestPermission：记"已请求过"，被拒回写"系统通知关闭"；
//  - run* 清扫模板：写库前后各升一次代数、写库期间置中间态旗（旗在
//    finally 里先升代数再关闭），删库失败不清扫（异常上抛）且旗仍复位；
//  - onParkingCountdownSaved：开关关直接返回，授权且代数未变才调度。
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:lunio/app/providers.dart';
import 'package:lunio/core/notifications/lunio_notification_service.dart';
import 'package:lunio/core/platform/native_live_activities.dart';
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
  late _FakeLiveActivities liveActivities;

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
    liveActivities = _FakeLiveActivities();
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        // 服务逐用例新建，替代原 resetForTest 的单例状态重置。
        lunioNotificationServiceProvider.overrideWithValue(
          LunioNotificationService(),
        ),
        // 实时活动桥换成假实现：记录调用、可编排系统侧状态快照。
        nativeLiveActivitiesProvider.overrideWithValue(liveActivities),
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
      // 写库前 +1、写库完成后再 +1：后一次把"写库进行中才启动的同步任务"
      // 也作废（中间态守卫，2026-09-24）。
      expect(
        container.read(notificationSyncGenerationProvider),
        generationBefore + 2,
      );
      expect(
        notificationCalls.map((call) => call.method),
        contains('cancel'),
      );
    });

    test('run* 模板写库期间置中间态旗，结束关旗（三个模板统一）', () async {
      mockAndroidNotifications();
      final templates =
          <String, Future<void> Function(Future<void> Function())>{
        'runCarDeletion': coordinator.runCarDeletion,
        'runBackupRestore': coordinator.runBackupRestore,
        'runAllDataClear': coordinator.runAllDataClear,
      };
      for (final entry in templates.entries) {
        final generationBefore =
            container.read(notificationSyncGenerationProvider);
        expect(coordinator.isDataResetInFlight, isFalse, reason: entry.key);

        var flagDuringWrite = false;
        await entry.value(() async {
          flagDuringWrite = coordinator.isDataResetInFlight;
        });

        expect(flagDuringWrite, isTrue,
            reason: '${entry.key} 写库期间旗必须为真');
        expect(coordinator.isDataResetInFlight, isFalse,
            reason: '${entry.key} 结束后旗必须复位');
        expect(
          container.read(notificationSyncGenerationProvider),
          generationBefore + 2,
          reason: '$entry.key 写库前后各升一次代数',
        );
      }
    });

    test('run* 模板写库失败：异常上抛、旗仍复位、代数仍升两次', () async {
      mockAndroidNotifications();
      final generationBefore = container.read(notificationSyncGenerationProvider);

      await expectLater(
        coordinator.runBackupRestore(() async {
          expect(coordinator.isDataResetInFlight, isTrue);
          throw StateError('恢复失败');
        }),
        throwsStateError,
      );
      expect(coordinator.isDataResetInFlight, isFalse);
      // 失败回滚 = 数据未变，通知不取消；但写库期间启动的同步任务照样要
      // 作废（对回滚后的数据重算一轮，无害），所以两次 bump 都执行。
      expect(
        container.read(notificationSyncGenerationProvider),
        generationBefore + 2,
      );
      expect(
        notificationCalls.map((call) => call.method),
        isNot(contains('cancel')),
      );
    });

    test('runCarDeletion skips the sweep when the deletion fails', () async {
      mockAndroidNotifications();
      final generationBefore =
          container.read(notificationSyncGenerationProvider);

      await expectLater(
        coordinator.runCarDeletion(() async {
          expect(coordinator.isDataResetInFlight, isTrue);
          throw StateError('删库失败');
        }),
        throwsStateError,
      );
      expect(coordinator.isDataResetInFlight, isFalse);
      // 失败回滚同样双 bump（对回滚后数据重算一轮，无害）——与
      // runBackupRestore 失败用例同一契约，三个模板对称。
      expect(
        container.read(notificationSyncGenerationProvider),
        generationBefore + 2,
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
      // 8000/8900 系已取消，9001~9004（停车）逐个断言不在取消名单里。
      expect(parkingIds, contains(8000));
      for (final id in [9001, 9002, 9003, 9004]) {
        expect(parkingIds, isNot(contains(id)), reason: '停车通知 $id 不应被取消');
      }
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
      expect(cancelledIds, containsAll([9002, 9003, 9004]));
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
      expect(cancelledIds, containsAll([9001, 9002, 9003, 9004]));
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

  group('parking live activity (ADR 0012)', () {
    // 到点时刻必须相对当前时间（写死日期一过用例就退化，同上组）。
    ParkingCountdown futureCountdown() => ParkingCountdown(
          startedAt: DateTime.now(),
          durationSeconds: 1800,
        );

    ParkingCountdown expiredCountdown() => ParkingCountdown(
          startedAt: DateTime.now().subtract(const Duration(minutes: 40)),
          durationSeconds: 1800,
        );

    test('save starts the live activity even with system notifications off',
        () async {
      mockAndroidNotifications(notificationsEnabled: false);
      await preferences.writeRaw('systemNotificationsEnabled', 'false');
      final countdown = futureCountdown();

      await coordinator.onParkingCountdownSaved(countdown);

      // 实时活动与通知开关无关（独立系统能力）：开关关着也要上卡，
      // 且上卡区间必须是保存的倒计时（送错时间戳 = 卡片走时不准）。
      expect(liveActivities.calls, contains('start'));
      expect(liveActivities.startedAtArg, countdown.startedAt);
      expect(liveActivities.endsAtArg, countdown.endsAt);
      expect(
        notificationCalls.map((call) => call.method),
        isNot(contains('zonedSchedule')),
      );
    });

    test('save skips the live activity when endsAt has already passed',
        () async {
      mockAndroidNotifications();

      await coordinator.onParkingCountdownSaved(expiredCountdown());

      expect(liveActivities.calls, isNot(contains('start')));
    });

    test('clear stops the live activity regardless of the toggle', () async {
      mockAndroidNotifications(notificationsEnabled: false);
      await preferences.writeRaw('systemNotificationsEnabled', 'false');

      await coordinator.onParkingCountdownCleared();

      expect(liveActivities.calls, contains('stop'));
    });

    test('clearAllData stops the live activity', () async {
      mockAndroidNotifications();

      await coordinator.runAllDataClear(() async {});

      expect(liveActivities.calls, contains('stop'));
    });

    test('clearAllData keeps the live activity when the clear fails',
        () async {
      mockAndroidNotifications();
      final generationBefore =
          container.read(notificationSyncGenerationProvider);

      await expectLater(
        coordinator.runAllDataClear(() async {
          expect(coordinator.isDataResetInFlight, isTrue);
          throw StateError('清库失败');
        }),
        throwsStateError,
      );
      expect(coordinator.isDataResetInFlight, isFalse);
      // 失败回滚同样双 bump（三个模板对称，同 runBackupRestore 失败用例）。
      expect(
        container.read(notificationSyncGenerationProvider),
        generationBefore + 2,
      );

      // 清库失败 = 数据未变：活动不撤、通知不取消（与 runCarDeletion
      // 失败路径同一模板语义）。
      expect(liveActivities.calls, isEmpty);
      expect(
        notificationCalls.map((call) => call.method),
        isNot(contains('cancel')),
      );
    });

    test('car deletion and backup restore never touch the live activity',
        () async {
      mockAndroidNotifications();

      await coordinator.runCarDeletion(() async {});
      await coordinator.runBackupRestore(() async {});

      expect(liveActivities.calls, isEmpty);
    });

    test('reconcile: clears a leftover activity when no countdown exists',
        () async {
      liveActivities.snapshot = const LiveActivitySnapshot(
        running: true,
        expired: false,
      );
      await preferences.clearParkingCountdown();

      await coordinator.reconcileParkingLiveActivity();

      expect(liveActivities.calls, ['status', 'stop']);
    });

    test('reconcile: does nothing when nothing runs and no countdown exists',
        () async {
      liveActivities.snapshot = const LiveActivitySnapshot(
        running: false,
        expired: false,
      );

      await preferences.clearParkingCountdown();

      await coordinator.reconcileParkingLiveActivity();

      expect(liveActivities.calls, ['status']);
    });

    test('reconcile: restarts a lost activity while time remains', () async {
      liveActivities.snapshot = const LiveActivitySnapshot(
        running: false,
        expired: false,
      );
      final countdown = futureCountdown();
      await preferences.saveParkingCountdown(countdown);

      await coordinator.reconcileParkingLiveActivity();

      expect(liveActivities.calls, ['status', 'start']);
      expect(liveActivities.endsAtArg, countdown.endsAt);
    });

    test('reconcile: does not resurrect an already expired countdown',
        () async {
      liveActivities.snapshot = const LiveActivitySnapshot(
        running: false,
        expired: false,
      );
      await preferences.saveParkingCountdown(expiredCountdown());

      await coordinator.reconcileParkingLiveActivity();

      expect(liveActivities.calls, ['status']);
    });

    test('reconcile: flips a running activity to expired past endsAt',
        () async {
      final countdown = expiredCountdown();
      liveActivities.snapshot = LiveActivitySnapshot(
        running: true,
        expired: false,
        endsAt: countdown.endsAt,
      );
      await preferences.saveParkingCountdown(countdown);

      await coordinator.reconcileParkingLiveActivity();

      expect(liveActivities.calls, ['status', 'markExpired']);
    });

    test('reconcile: leaves a live activity in expired form untouched',
        () async {
      final countdown = expiredCountdown();
      liveActivities.snapshot = LiveActivitySnapshot(
        running: true,
        expired: true,
        endsAt: countdown.endsAt,
      );
      await preferences.saveParkingCountdown(countdown);

      await coordinator.reconcileParkingLiveActivity();

      expect(liveActivities.calls, ['status']);
    });

    test('reconcile: rebuilds when the activity endsAt drifted from the pref',
        () async {
      final countdown = futureCountdown();
      liveActivities.snapshot = LiveActivitySnapshot(
        running: true,
        expired: false,
        endsAt: countdown.endsAt.add(const Duration(minutes: 5)),
      );
      await preferences.saveParkingCountdown(countdown);

      await coordinator.reconcileParkingLiveActivity();

      expect(liveActivities.calls, ['status', 'start']);
      expect(liveActivities.endsAtArg, countdown.endsAt);
    });

    test('reconcile: aborts when the sync generation changed mid-flight',
        () async {
      final countdown = futureCountdown();
      liveActivities.snapshot = const LiveActivitySnapshot(
        running: false,
        expired: false,
      );
      await preferences.saveParkingCountdown(countdown);
      liveActivities.onStatus = () {
        container.read(notificationSyncGenerationProvider.notifier).bump();
      };

      await coordinator.reconcileParkingLiveActivity();

      expect(liveActivities.calls, ['status']);
    });

    test('markParkingLiveActivityExpired flips the activity to expired',
        () async {
      await coordinator.markParkingLiveActivityExpired();

      expect(liveActivities.calls, ['markExpired']);
    });
  });
}

/// 实时活动假桥：记录调用、编排 status 返回值。[onStatus] 在每次 status
/// 查询时触发（用于模拟查询期间恢复备份/清空数据的代数竞态）。
class _FakeLiveActivities extends NativeLiveActivities {
  final List<String> calls = <String>[];
  LiveActivitySnapshot? snapshot;
  DateTime? startedAtArg;
  DateTime? endsAtArg;
  void Function()? onStatus;

  @override
  Future<bool> start({
    required DateTime startedAt,
    required DateTime endsAt,
  }) async {
    calls.add('start');
    startedAtArg = startedAt;
    endsAtArg = endsAt;
    return true;
  }

  @override
  Future<bool> markExpired() async {
    calls.add('markExpired');
    return true;
  }

  @override
  Future<bool> stop() async {
    calls.add('stop');
    return true;
  }

  @override
  Future<LiveActivitySnapshot?> status() async {
    calls.add('status');
    onStatus?.call();
    return snapshot;
  }
}
