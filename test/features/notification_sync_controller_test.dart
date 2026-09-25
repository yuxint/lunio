// NotificationSyncController 的单元测试：停车实时活动对账的触发与守卫
// 分支（ADR 0012）+ 破坏性写库中间态守卫（2026-09-24）。
//
// 控制器收 WidgetRef（生产由主壳层 State 传入），这里用宿主 Consumer
// widget 在真实装配里构造并 start 它；容器经 UncontrolledProviderScope
// 外挂，播种与断言用同一个 container。数据容器与桥假件的手法同
// notification_coordinator_test.dart。锁死：
//  - 倒计时 provider 装载中跳过对账（fireImmediately 首拍 + 装载那一拍
//    合计恰好一轮，守卫被删会变成两轮）；
//  - 偏好 JSON 损坏转 null 数据：按"偏好无倒计时"对账，活动在跑撤掉；
//  - 装载出的倒计时原样传给协调器对账；
//  - dispose 后 sync 直接放弃；onAppResumed 再对一轮；
//  - 中间态守卫：恢复写库进行中触发的同步被入口早退（不弹窗、不误判），
//    写库结束后由最终一轮正常补判；应用内检查执行中来了新请求置
//    pending，弹窗关闭后强制重跑补判（R3 同款，2026-09-24 补齐）；
//    展示前复查（2026-09-25 补用例）：保养弹窗开着时发起/结束恢复，
//    里程弹窗展示前被旗、代数两半各拦一轮。
//  说明：弹窗路径中间态守卫分两道——方法内旗检查（与 syncFromProviders
//  入口早退之间无 await，公开 API 单独不可达，靠评审保障）与展示前复查
//  （保养/里程两处展示调用各一道）。本文件锁定里程位点（已变异验证）：
//  删整道复查 → 两个用例都红；只删代数半 → "恢复已结束"用例红（旗假，
//  只剩代数半能拦）；只删旗半 → 两用例绿——可达路径上 bump 与置旗同步
//  发生、代数半总先拦住，旗半是纵深防御冗余。保养位点与里程位点同构
//  （同一表达式、同一旗与代数），只差"静默判定偏好读"的亚毫秒窗口，
//  公开 API 打不出确定性用例，靠同构 + 评审保障。
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunio/app/providers.dart';
import 'package:lunio/core/date/local_date.dart';
import 'package:lunio/core/notifications/lunio_notification_service.dart';
import 'package:lunio/core/platform/native_live_activities.dart';
import 'package:lunio/core/theme/lunio_theme.dart';
import 'package:lunio/data/database/app_database.dart';
import 'package:lunio/data/preferences/app_preferences.dart';
import 'package:lunio/data/repositories/built_in_catalog_repository.dart';
import 'package:lunio/domain/entities/car.dart';
import 'package:lunio/domain/entities/maintenance_item.dart';
import 'package:lunio/domain/entities/maintenance_record.dart';
import 'package:lunio/domain/entities/parking_countdown.dart';
import 'package:lunio/domain/entities/sync_metadata.dart';
import 'package:lunio/features/shell/reminders/notification_coordinator.dart';
import 'package:lunio/features/shell/reminders/notification_sync_controller.dart';

import '../helpers/built_in_catalog_loader.dart' show loadBuiltInVehicleCatalogForTest;
import '../helpers/widget_app.dart';

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
        // 目录仓库必须注入测试加载器（微任务即完成）：默认加载器走
        // rootBundle 资产通道，在本文件第二个及以后的假异步区里等不到
        // 通道回包，bootstrap→cars→appliedCar 整条链会挂死（与
        // widget_app.dart 的 pumpApp 同一手法，教训见其注释）。
        builtInCatalogRepositoryProvider.overrideWithValue(
          BuiltInCatalogRepository(
            database,
            loadBuiltInVehicleCatalog: () async =>
                loadBuiltInVehicleCatalogForTest(),
          ),
        ),
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

  group('data reset in-flight guards (2026-09-24 中间态守卫)', () {
    late TestRepositories repos;
    late int carId;

    /// 播种"初始无到期"基线：一辆车（上路 2020-01-01）+ 唯一项目"机油"
    /// 刚保养过（记录日期 = 今天，12 个月间隔 → 正常）。里程更新提醒因
    /// car.sync.updatedAt = 当下而不到期，不构成干扰弹窗；需要里程提醒
    /// 到期的用例传 [carSyncUpdatedAt] 把车辆同步时间戳拨老（单条记录
    /// 推断频率 = 每月，老时间戳必到期）。
    Future<void> seedBaseline({DateTime? carSyncUpdatedAt}) async {
      repos = testRepository(database);
      final sync = SyncMetadata(
        status: SyncStatus.synced,
        updatedAt: carSyncUpdatedAt ?? DateTime.now(),
      );
      carId = await repos.createCarWithMaintenanceItems(
        Car(
          brand: '本田',
          model: '思域',
          currentMileageKm: 100000,
          roadDate: const LocalDate(2020, 1, 1),
          sync: sync,
        ),
        [
          MaintenanceItem(
            carsId: 0,
            name: '机油',
            enabled: true,
            remindByMileage: false,
            remindByTime: true,
            timeIntervalMonths: 12,
            sortOrder: 0,
            sync: sync,
          ),
        ],
      );
      final items = await repos.listMaintenanceItemsForCar(carId);
      await repos.saveMaintenanceRecord(
        MaintenanceRecord(
          carId: carId,
          date: LocalDate.fromDateTime(DateTime.now()),
          itemIds: [items.first.id!],
          costCents: 0,
          mileageKm: 99000,
          sync: sync,
        ),
      );
    }

    /// 补插一个无记录的到期项：时间基线落到上路日期 2020-01-01，36 个月
    /// 间隔早已超期（danger），必产生到期提醒。
    Future<void> addOverdueItem(String name) async {
      await repos.saveMaintenanceItem(
        MaintenanceItem(
          carsId: carId,
          name: name,
          enabled: true,
          remindByMileage: false,
          remindByTime: true,
          timeIntervalMonths: 36,
          sortOrder: 9,
          sync: SyncMetadata(
            status: SyncStatus.synced,
            updatedAt: DateTime.now(),
          ),
        ),
      );
    }

    /// 轮询等"保养提醒"弹窗出现。弹窗前的真实异步链（provider 解析 →
    /// 静默判定偏好读 → 展示前守卫 → showDialog 入帧）跨多个事件循环代，
    /// pumpAndSettle 的"无帧即停"会提前退出；这里每泵一次都让事件循环
    /// 走一圈，100 次预算留足余量。
    Future<void> pumpUntilDialog(WidgetTester tester) async {
      for (var attempt = 0; attempt < 100; attempt++) {
        await tester.pump(const Duration(milliseconds: 50));
        if (find.text('保养提醒').evaluate().isNotEmpty) {
          return;
        }
      }
    }

    /// 失效 + 确定性重算：Riverpod 3 的失效重算是惰性的（读才触发，且
    /// 调度可能落在假时钟上），三步齐做才能确定性地让 listenManual 带着
    /// 新数据触发同步：推一帧（放行调度）→ 读 .future（强制重算完成）→
    /// 再推一帧（让重算引发的后续微任务落帧）。
    Future<void> refreshItems(WidgetTester tester) async {
      container.invalidate(maintenanceItemsForCarProvider);
      container.invalidate(appliedCarMaintenanceItemsProvider);
      await tester.pump();
      await container.read(appliedCarMaintenanceItemsProvider.future);
      await tester.pump();
    }

    testWidgets('恢复写库进行中的同步被入口早退，结束后最终一轮正常补判',
        timeout: const Timeout(Duration(seconds: 30)),
        (tester) async {
      mockAndroidNotifications();
      await seedBaseline();
      await pumpHost(tester);
      await tester.pumpAndSettle();
      expect(find.text('保养提醒'), findsNothing);

      final coordinator = container.read(notificationCoordinatorProvider);
      final release = Completer<void>();
      final restore = coordinator.runBackupRestore(() => release.future);
      await tester.pump();

      // 写库进行中数据变化（生产 = 恢复在逐行插入中间态；这里以补插到期
      // 项并失效重算代替）：provider 带着新到期项、中间态旗为真，此时
      // listenManual 的自动触发与手动触发都必须被入口早退，绝不弹窗。
      // 杀伤机制备注：单删入口守卫时，写库期间的这轮同步也不会当场弹窗
      // （方法内旗检查仍拦着），但应用内签名已被提前记为"含刹车油已
      // 消费"；假恢复不改数据，最终一轮被签名比对整体跳过、补判永不
      // 发生，用例在收尾断言处红。杀伤依赖"假恢复不改数据"这一构造。
      await addOverdueItem('刹车油');
      await refreshItems(tester);
      await tester.pumpAndSettle();
      expect(find.text('保养提醒'), findsNothing);

      release.complete();
      await restore;
      // 生产里恢复完成后动作层失效 provider 家族（invalidateVehicleProviders，
      // ADR 0007）触发最终一轮；测试里等价手动失效+强制重算。补判必须
      // 弹出到期项。
      await refreshItems(tester);
      await pumpUntilDialog(tester);
      expect(find.text('保养提醒'), findsOneWidget);
      expect(find.text('刹车油'), findsOneWidget);
    });

    testWidgets('弹窗开着时数据变化置 pending，关闭后强制重跑补上新到期项',
        timeout: const Timeout(Duration(seconds: 30)),
        (tester) async {
      mockAndroidNotifications();
      await seedBaseline();
      await addOverdueItem('刹车油');
      await pumpHost(tester);
      // 首轮同步需要数据 provider 完成解析，强制重算后等弹窗出现。
      await refreshItems(tester);
      await pumpUntilDialog(tester);
      // 首轮检查弹出含刹车油的到期弹窗，挂起等待用户动作。
      expect(find.text('保养提醒'), findsOneWidget);
      expect(find.text('刹车油'), findsOneWidget);

      // 弹窗开着时又来一个到期项：新一轮检查请求被置 pending（R3 同款，
      // 不丢弃）。pending 被删时这里直接把检查丢弃。
      await addOverdueItem('变速箱油');
      await refreshItems(tester);
      await tester.pumpAndSettle();

      // 系统返回键关闭（showLunioDialog 的遮罩不可点关，返回键走
      // maybePop 返回 null、无动作副作用）；finally 里的 pending 重跑
      // 必须用最新数据补判——新弹窗要同时含两个到期项。pending 被删时
      // 关闭后不再有任何弹窗，本用例红。
      await tester.binding.handlePopRoute();
      await pumpUntilDialog(tester);
      await tester.pumpAndSettle();
      expect(find.text('保养提醒'), findsOneWidget);
      expect(find.text('刹车油'), findsOneWidget);
      expect(find.text('变速箱油'), findsOneWidget);
    });

    testWidgets('保养弹窗开着时发起恢复：里程弹窗展示前被复查拦下（旗半）',
        timeout: const Timeout(Duration(seconds: 30)), (tester) async {
      mockAndroidNotifications();
      // 保养（无记录到期项）与里程（老同步时间戳）同时到期：首轮检查
      // 通过展示前复查，弹出保养弹窗并挂起等待用户动作。
      await seedBaseline(carSyncUpdatedAt: DateTime(2020, 1, 1));
      await addOverdueItem('刹车油');
      await pumpHost(tester);
      await refreshItems(tester);
      await pumpUntilDialog(tester);
      expect(find.text('保养提醒'), findsOneWidget);
      expect(find.text('更新当前里程'), findsNothing);

      final coordinator = container.read(notificationCoordinatorProvider);
      final release = Completer<void>();
      final restore = coordinator.runBackupRestore(() => release.future);
      await tester.pump();
      expect(coordinator.isDataResetInFlight, isTrue);

      // 返回键关闭保养弹窗（= null 动作、无副作用）。检查链恢复后走到
      // 里程弹窗展示前复查：写库仍在进行（旗真），showMileageReminder
      // 是旧快照算出来的，必须放弃。复查被删时这里会弹出里程弹窗，
      // 本用例红。
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('保养提醒'), findsNothing);
      expect(find.text('更新当前里程'), findsNothing);

      release.complete();
      await restore;
      await tester.pump();
      expect(coordinator.isDataResetInFlight, isFalse);
      expect(find.text('更新当前里程'), findsNothing);
    });

    testWidgets('保养弹窗开着时恢复已结束：里程弹窗展示前被复查拦下（代数半）',
        timeout: const Timeout(Duration(seconds: 30)), (tester) async {
      mockAndroidNotifications();
      await seedBaseline(carSyncUpdatedAt: DateTime(2020, 1, 1));
      await addOverdueItem('刹车油');
      await pumpHost(tester);
      await refreshItems(tester);
      await pumpUntilDialog(tester);
      expect(find.text('保养提醒'), findsOneWidget);

      // 恢复在保养弹窗挂起期间开始并结束：旗已关，但代数比检查开工时
      // 拍的快照多了 2，里程弹窗展示前复查靠代数半边拦下。删掉代数半
      // （或整道复查）时里程弹窗照样弹，本用例红。
      final coordinator = container.read(notificationCoordinatorProvider);
      await coordinator.runBackupRestore(() async {});
      await tester.pump();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('保养提醒'), findsNothing);
      expect(find.text('更新当前里程'), findsNothing);
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

  /// 弹窗需要 Navigator：shellContext 指向 MaterialApp 内部的 Builder
  /// 上下文（initState 先于 build，故经字段中转）。
  BuildContext? _dialogContext;

  @override
  void initState() {
    super.initState();
    controller = NotificationSyncController(
      ref: ref,
      shellContext: () => _dialogContext ?? context,
      isAlive: () => mounted,
    )..start();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // MaterialApp + Lunio 主题：弹窗（showLunioDialog → 对话框内容读
    // Theme extension LunioTokens）需要 Navigator 与主题两者齐备。
    return MaterialApp(
      theme: buildLunioTheme(),
      home: Scaffold(
        body: Builder(
          builder: (dialogContext) {
            _dialogContext = dialogContext;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }
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
