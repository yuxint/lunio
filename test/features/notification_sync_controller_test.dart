// NotificationSyncController 的单元测试：停车实时活动对账的触发与守卫
// 分支（ADR 0012）。
//
// 控制器收 WidgetRef（生产由主壳层 State 传入），这里用宿主 Consumer
// widget 在真实装配里构造并 start 它；容器经 UncontrolledProviderScope
// 外挂，播种与断言用同一个 container。数据容器与桥假件的手法同
// notification_coordinator_test.dart。锁死：
//  - 倒计时 provider 装载中跳过对账（fireImmediately 首拍 + 装载那一拍
//    合计恰好一轮，守卫被删会变成两轮）；
//  - 偏好 JSON 损坏转 null 数据：按"偏好无倒计时"对账，活动在跑撤掉；
//  - 装载出的倒计时原样传给协调器对账；
//  - dispose 后 sync 直接放弃；onAppResumed 再对一轮。
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunio/app/providers.dart';
import 'package:lunio/core/notifications/lunio_notification_service.dart';
import 'package:lunio/core/platform/native_live_activities.dart';
import 'package:lunio/data/database/app_database.dart';
import 'package:lunio/data/preferences/app_preferences.dart';
import 'package:lunio/domain/entities/parking_countdown.dart';
import 'package:lunio/features/shell/reminders/notification_sync_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const notificationsChannel = MethodChannel(
    'dexterous.com/flutter/local_notifications',
  );
  const timezoneChannel = MethodChannel('flutter_timezone');

  late AppDatabase database;
  late ProviderContainer container;
  late LunioPreferences preferences;
  late _FakeLiveActivities liveActivities;

  /// 注册 Android 平台实现 + mock 通知/时区通道。控制器装载后会跑通知
  /// 同步链（含权限协议），须有平台 mock 兜住；本文件只对实时活动调用
  /// 断言，通知通道调用一律不关心。测试默认平台即 Android，不再覆写
  /// debugDefaultTargetPlatformOverride（testWidgets 的 foundation 不变量
  /// 要求用例体内复位，tearDown 晚于校验）。
  void mockAndroidNotifications() {
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
          return switch (call.method) {
            'initialize' => true,
            'requestNotificationsPermission' => true,
            'areNotificationsEnabled' => true,
            'canScheduleExactNotifications' => true,
            'requestExactAlarmsPermission' => true,
            _ => null,
          };
        });
  }

  /// 挂载宿主 widget（真实构造并 start 控制器），返回控制器句柄。
  Future<NotificationSyncController> pumpHost(WidgetTester tester) async {
    final hostKey = GlobalKey<_ControllerHostState>();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: _ControllerHost(key: hostKey),
      ),
    );
    return hostKey.currentState!.controller;
  }

  setUp(() {
    database = AppDatabase.inMemory();
    liveActivities = _FakeLiveActivities();
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        lunioNotificationServiceProvider.overrideWithValue(
          LunioNotificationService(),
        ),
        nativeLiveActivitiesProvider.overrideWithValue(liveActivities),
      ],
    );
    preferences = container.read(lunioPreferencesProvider);
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

  group('parking live activity reconcile triggers (ADR 0012)', () {
    testWidgets('reconciles exactly once after the preference resolves',
        (tester) async {
      mockAndroidNotifications();

      await pumpHost(tester);
      await tester.pumpAndSettle();

      // 无倒计时：装载守卫正确时 fireImmediately 首拍跳过、装载那一拍
      // 补一轮——合计恰好一次 status；守卫被删会变两轮。
      expect(liveActivities.calls, ['status']);
    });

    testWidgets('stops a leftover activity when the pref JSON is corrupt',
        (tester) async {
      mockAndroidNotifications();
      // JSON 损坏经偏好门面转 null 数据（R14）：按"偏好无倒计时"对账，
      // 活动在跑 → 撤。
      await preferences.writeRaw('parkingCountdown', '{broken');
      liveActivities.snapshot = const LiveActivitySnapshot(
        running: true,
        expired: false,
      );

      await pumpHost(tester);
      await tester.pumpAndSettle();

      expect(liveActivities.calls, ['status', 'stop']);
    });

    testWidgets('passes the loaded countdown through to the coordinator',
        (tester) async {
      mockAndroidNotifications();
      // 到点时刻相对真实当前时间（写死日期一过用例就退化，同协调器测试）。
      final countdown = ParkingCountdown(
        startedAt: DateTime.now(),
        durationSeconds: 1800,
      );
      await preferences.saveParkingCountdown(countdown);
      liveActivities.snapshot = const LiveActivitySnapshot(
        running: false,
        expired: false,
      );

      await pumpHost(tester);
      await tester.pumpAndSettle();

      // 活动丢了 + 剩余为正 → 补启，参数是装载出的倒计时区间。
      expect(liveActivities.calls, ['status', 'start']);
      expect(liveActivities.startedAtArg, countdown.startedAt);
      expect(liveActivities.endsAtArg, countdown.endsAt);
    });

    testWidgets('reconciles again on app resumed', (tester) async {
      mockAndroidNotifications();
      final controller = await pumpHost(tester);
      await tester.pumpAndSettle();
      liveActivities.calls.clear();

      controller.onAppResumed();
      await tester.pumpAndSettle();

      expect(liveActivities.calls, ['status']);
    });

    testWidgets('sync is a no-op after dispose', (tester) async {
      mockAndroidNotifications();
      final controller = await pumpHost(tester);
      await tester.pumpAndSettle();
      liveActivities.calls.clear();

      // 宿主卸载 → 控制器 dispose，之后再调 sync 必须放弃。
      await tester.pumpWidget(const SizedBox.shrink());
      await controller.syncParkingLiveActivity();

      expect(liveActivities.calls, isEmpty);
    });
  });
}

/// 宿主 widget：真实构造 NotificationSyncController 并 start（生产由
/// AppShell 的 State 做），控制器随宿主卸载 dispose。
class _ControllerHost extends ConsumerStatefulWidget {
  const _ControllerHost({super.key});

  @override
  ConsumerState<_ControllerHost> createState() => _ControllerHostState();
}

class _ControllerHostState extends ConsumerState<_ControllerHost> {
  late final NotificationSyncController controller;

  @override
  void initState() {
    super.initState();
    controller = NotificationSyncController(
      ref: ref,
      shellContext: () => context,
      isAlive: () => mounted,
    )..start();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// 实时活动假桥：记录调用、编排 status 返回值（协调器测试同款最小集）。
class _FakeLiveActivities extends NativeLiveActivities {
  final List<String> calls = <String>[];
  LiveActivitySnapshot? snapshot;
  DateTime? startedAtArg;
  DateTime? endsAtArg;

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
    return snapshot;
  }
}
