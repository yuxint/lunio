// 主壳层：三个 tab（提醒/记录/我的）共用的页面骨架。
//
// 职责（≈ 主页面 Controller + 布局）：
//  1. 挂载当前 tab 页面 + 自绘悬浮底部导航栏（go_router 路由切换）；
//  2. 生命周期监听（WidgetsBindingObserver ≈ Android Activity 的
//     onResume/onPause 回调）：前台恢复时重查应用内提醒、刷新导航 inset；
//  3. Android 三键导航栏 inset 适配（三键模式下补导航栏高度）；
//  4. ★ 通知同步引擎：build 里 watch 全部相关 provider → 拼数据签名 →
//     签名变化才触发"重排系统通知 / 弹应用内提醒"（详见方法注释）。
//
// ConsumerStatefulWidget = "有状态 + 能用 Riverpod 容器"的组件。
// State 的字段（下划线开头）≈ Controller 的私有成员变量。
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/date/local_date.dart';
import '../../core/notifications/lunio_notification_service.dart';
import '../../core/platform/native_system_ui.dart';
import '../../core/theme/lunio_tokens.dart';
import '../../domain/entities/car.dart';
import '../../domain/entities/maintenance_item.dart';
import '../../domain/entities/maintenance_record.dart';
import '../../domain/entities/notification_settings.dart';
import '../../domain/entities/parking_countdown.dart';
import 'profile/profile_page.dart';
import 'records/records_page.dart';
import 'reminders/reminder_page.dart';
import 'shared/shell_shared.dart';

/// 主壳层组件。selectedIndex 来自路由（0/1/2 对应三个入口）。
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.selectedIndex});

  final int selectedIndex;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell>
    with WidgetsBindingObserver {
  // ---- 通知同步的状态（签名比对机制的核心字段）----
  // 思路：把"当前应该有的通知状态"压成一个签名字符串存起来；
  // 每次 build 重算签名，与旧值不同才做真正的调度/弹窗工作。
  // 这样"任何数据变化 → provider 刷新 → build → 签名 diff → 同步"。

  /// 上次系统通知调度的签名（null = 从未同步过，首帧必触发）。
  String? _systemNotificationSignature;

  /// 上次应用内提醒弹窗的签名。
  String? _inAppNotificationSignature;

  /// 系统通知重排是否在执行中（防并发重入；⚠ 正在执行时的新签名会被
  /// 直接丢弃——"丢更新"竞态，见审查报告 R3）。
  bool _syncingSystemNotifications = false;

  /// 应用内提醒检查是否在执行中。
  bool _checkingInAppNotifications = false;

  /// 首启权限检查是否在执行中（防重入）。
  bool _checkingInitialSystemPermission = false;

  // ---- Android 三键导航 inset 适配 ----
  double _androidThreeButtonNavigationInset = 0.0;

  /// 异步刷新的请求序号：只接受最新一次请求的结果
  /// （requestId + mounted 双检查防竞态，写法正确）。
  int _systemNavigationRequestId = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshAndroidSystemNavigationInset();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// 回到前台：清空应用内提醒签名（强制下次 build 重新检查弹窗，
  /// 实现"用户处理完提醒离开再回来，若又到期会再次提醒"），
  /// 并刷新导航 inset（用户可能在系统设置里切了导航方式）。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _inAppNotificationSignature = null;
      _refreshAndroidSystemNavigationInset();
      if (mounted) {
        setState(() {});
      }
    }
  }

  @override
  void didChangeMetrics() {
    _refreshAndroidSystemNavigationInset();
  }

  /// 每帧 build：
  ///  1. watch 全部业务 provider（数据一变这里就重建）；
  ///  2. 调 _syncReminderNotifications 做签名比对（副作用挂到
  ///     postFrameCallback，避免 build 期间做 I/O ——但"在 build 里
  ///     触发副作用"本身就是反模式，见审查报告 R12）；
  ///  3. 渲染当前 tab 页 + 底部导航。
  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    final notificationSettings = ref.watch(notificationSettingsProvider);
    final appliedCar = ref.watch(appliedCarProvider);
    final items = ref.watch(appliedCarMaintenanceItemsProvider);
    final records = ref.watch(appliedCarRecordsProvider);
    final today = ref.watch(effectiveTodayProvider);
    final parkingCountdown = ref.watch(parkingCountdownProvider);
    _syncReminderNotifications(
      settingsValue: notificationSettings,
      carValue: appliedCar,
      itemsValue: items,
      recordsValue: records,
      todayValue: today,
      parkingCountdownValue: parkingCountdown,
    );
    final pages = [
      const ReminderPreviewPage(),
      const RecordsPreviewPage(),
      const ProfilePreviewPage(),
    ];

    return Scaffold(
      backgroundColor: tokens.background,
      body: SafeArea(child: pages[widget.selectedIndex]),
      bottomNavigationBar: Padding(
        padding: EdgeInsets.fromLTRB(
          14,
          0,
          14,
          12 + _androidThreeButtonNavigationInset,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: tokens.surface.withValues(alpha: 0.88),
            borderRadius: BorderRadius.circular(tokens.radiusXl),
            border: Border.all(color: tokens.line.withValues(alpha: 0.9)),
            boxShadow: [
              BoxShadow(
                color: tokens.ink.withValues(alpha: 0.16),
                blurRadius: 46,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                _BottomNavItem(
                  icon: Icons.home_repair_service_outlined,
                  selectedIcon: Icons.home_repair_service,
                  label: '提醒',
                  selected: widget.selectedIndex == 0,
                  onTap: () {
                    dismissTransientUi(context);
                    context.go('/reminders');
                  },
                ),
                const SizedBox(width: 6),
                _BottomNavItem(
                  icon: Icons.format_list_bulleted_outlined,
                  selectedIcon: Icons.format_list_bulleted,
                  label: '记录',
                  selected: widget.selectedIndex == 1,
                  onTap: () {
                    dismissTransientUi(context);
                    context.go('/records');
                  },
                ),
                const SizedBox(width: 6),
                _BottomNavItem(
                  icon: Icons.person_outline,
                  selectedIcon: Icons.person,
                  label: '我的',
                  selected: widget.selectedIndex == 2,
                  onTap: () {
                    dismissTransientUi(context);
                    context.go('/me');
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 查询 Android 导航模式并更新 inset（异步，带 requestId 防乱序）。
  /// 三键导航 → inset = 导航栏高度；手势导航 → 0。
  Future<void> _refreshAndroidSystemNavigationInset() async {
    final requestId = ++_systemNavigationRequestId;
    if (defaultTargetPlatform != TargetPlatform.android) {
      _updateAndroidSystemNavigationInset(0.0, requestId);
      return;
    }

    final info = await NativeSystemUi.getSystemNavigationInfo();
    if (!mounted || requestId != _systemNavigationRequestId) {
      return;
    }
    final nextInset = info?.usesThreeButtonNavigation == true
        ? info!.navigationBarHeight
        : 0.0;
    _updateAndroidSystemNavigationInset(nextInset, requestId);
  }

  void _updateAndroidSystemNavigationInset(double nextInset, int requestId) {
    if (!mounted || requestId != _systemNavigationRequestId) {
      return;
    }
    if (_androidThreeButtonNavigationInset == nextInset) {
      return;
    }
    setState(() => _androidThreeButtonNavigationInset = nextInset);
  }

  /// ★ 通知同步入口（每次 build 调用）。
  ///
  /// 流程：
  ///  1. 从 6 个 AsyncValue 里解包数据（loading 中的当 null，
  ///     settings 未就绪直接返回）；
  ///  2. 系统通知开关开着时，postFrame 触发首启权限检查；
  ///  3. 数据就绪后拼"系统通知签名" = 提醒频率 + 停车倒计时摘要 +
  ///     全量数据签名（reminderNotificationDataSignature，拼大字符串，
  ///     长列表下每帧 O(n)）；签名变化 → 先记录新签名（⚠ 记录在调度
  ///     完成之前，是丢更新竞态的一半成因）→ postFrame 调度；
  ///  4. "应用内签名"同理，变化 → postFrame 弹应用内提醒。
  ///
  /// car/items/records/today 任一还在加载就不做同步——所以刚装 App
  /// 或恢复备份后，等 provider 全部就绪那一帧才触发首次通知同步。
  void _syncReminderNotifications({
    required AsyncValue<LunioNotificationSettings> settingsValue,
    required AsyncValue<Car?> carValue,
    required AsyncValue<List<MaintenanceItem>> itemsValue,
    required AsyncValue<List<MaintenanceRecord>> recordsValue,
    required AsyncValue<LocalDate> todayValue,
    required AsyncValue<ParkingCountdown?> parkingCountdownValue,
  }) {
    final settings = settingsValue.maybeWhen(
      data: (value) => value,
      orElse: () => null,
    );
    final car = carValue.maybeWhen(data: (value) => value, orElse: () => null);
    final items = itemsValue.maybeWhen(
      data: (value) => value,
      orElse: () => null,
    );
    final records = recordsValue.maybeWhen(
      data: (value) => value,
      orElse: () => null,
    );
    final today = todayValue.maybeWhen(
      data: (value) => value,
      orElse: () => null,
    );
    final parkingCountdown = parkingCountdownValue.maybeWhen(
      data: (value) => value,
      orElse: () => null,
    );
    if (settings == null) {
      return;
    }
    if (settings.systemNotificationsEnabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _ensureInitialSystemNotificationPermission();
      });
    }
    if (car == null || items == null || records == null || today == null) {
      return;
    }
    final dataSignature = reminderNotificationDataSignature(
      car: car,
      items: items,
      records: records,
      today: today,
    );
    final systemSignature = settings.systemNotificationsEnabled
        ? '${settings.dueRepeatFrequency.value}:'
              '${parkingCountdownReminderSignature(parkingCountdown)}:'
              '$dataSignature'
        : 'system-off';
    final syncGeneration = notificationSyncGeneration;
    if (_systemNotificationSignature != systemSignature) {
      _systemNotificationSignature = systemSignature;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _applySystemNotificationSchedule(
          syncGeneration: syncGeneration,
          settings: settings,
          car: car,
          items: items,
          records: records,
          today: today,
          parkingCountdown: parkingCountdown,
        );
      });
    }
    final inAppSignature =
        '${settings.inAppNotificationsEnabled}:'
        '${settings.maintenanceDueEnabled}:$dataSignature';
    if (_inAppNotificationSignature != inAppSignature) {
      _inAppNotificationSignature = inAppSignature;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showDueInAppNotifications(
          syncGeneration: syncGeneration,
          settings: settings,
          car: car,
          items: items,
          records: records,
          today: today,
        );
      });
    }
  }

  /// 首启权限链（只跑一次，由偏好 systemNotificationPermissionRequested 把关）：
  ///  1. 请求过 → 只把系统真实开关回写到偏好（用户可能在系统设置改过）；
  ///  2. 没请求过 → 弹系统权限对话框，记录"已请求过"和授权结果；
  ///  3. 回写后失效偏好 provider + 清空签名强制重排。
  /// ⚠ 多个 await 之后使用 ref，没有 mounted 保护（R13）。
  Future<void> _ensureInitialSystemNotificationPermission() async {
    if (_checkingInitialSystemPermission || !mounted) {
      return;
    }
    _checkingInitialSystemPermission = true;
    try {
      final repository = ref.read(lunioRepositoryProvider);
      final requested = await repository.getPreferenceValue(
        'systemNotificationPermissionRequested',
      );
      if (requested == 'true') {
        final enabled = await LunioNotificationService.instance
            .notificationsEnabled();
        final currentValue = await repository.getPreferenceValue(
          'systemNotificationsEnabled',
        );
        if (currentValue != enabled.toString()) {
          await repository.setPreferenceValue(
            'systemNotificationsEnabled',
            enabled.toString(),
          );
          invalidatePreferenceProviders(ref);
        }
        return;
      }
      final granted = await LunioNotificationService.instance
          .requestNotificationPermission();
      await repository.setPreferenceValue(
        'systemNotificationPermissionRequested',
        'true',
      );
      await repository.setPreferenceValue(
        'systemNotificationsEnabled',
        granted.toString(),
      );
      invalidatePreferenceProviders(ref);
      if (mounted) {
        _systemNotificationSignature = null;
        setState(() {});
      }
    } finally {
      _checkingInitialSystemPermission = false;
    }
  }

  /// ★ 系统通知重排（真正的调度执行体，签名变化时被调用）。
  ///
  /// 守卫：同步代数已变（恢复/清空作废）或已在执行中 → 直接放弃
  /// （⚠ 放弃的新签名已被记录，除非再有数据变化否则不会重试，R3）。
  ///
  /// 执行链：开关关 → 全部取消；查系统权限（必要时补请求）→ 权限没了
  /// 回写偏好并取消 → buildScheduledNotifications 组装通知（8000/8900）
  /// → Android 申请精确闹钟 → rescheduleNotifications（内部先 cancel
  /// 1000 个 id 再逐条 zonedSchedule，避开停车到点时刻）。
  Future<void> _applySystemNotificationSchedule({
    required int syncGeneration,
    required LunioNotificationSettings settings,
    required Car car,
    required List<MaintenanceItem> items,
    required List<MaintenanceRecord> records,
    required LocalDate today,
    required ParkingCountdown? parkingCountdown,
  }) async {
    if (syncGeneration != notificationSyncGeneration) {
      return;
    }
    if (_syncingSystemNotifications) {
      return;
    }
    _syncingSystemNotifications = true;
    try {
      if (!settings.systemNotificationsEnabled) {
        await LunioNotificationService.instance.cancelLunioNotifications();
        return;
      }
      final repository = ref.read(lunioRepositoryProvider);
      var notificationsEnabled = await LunioNotificationService.instance
          .notificationsEnabled();
      if (!notificationsEnabled) {
        final requested = await repository.getPreferenceValue(
          'systemNotificationPermissionRequested',
        );
        if (requested != 'true') {
          notificationsEnabled = await LunioNotificationService.instance
              .requestNotificationPermission();
          await repository.setPreferenceValue(
            'systemNotificationPermissionRequested',
            'true',
          );
        }
      }
      if (!notificationsEnabled) {
        await repository.setPreferenceValue(
          'systemNotificationsEnabled',
          'false',
        );
        invalidatePreferenceProviders(ref);
        await LunioNotificationService.instance.cancelLunioNotifications();
        return;
      }
      final notifications = await buildScheduledNotifications(
        ref: ref,
        settings: settings,
        car: car,
        items: items,
        records: records,
        today: today,
      );
      if (notifications.isEmpty) {
        await LunioNotificationService.instance.rescheduleNotifications(
          notifications,
          reservedDateTimes: reservedNotificationDateTimes(parkingCountdown),
        );
        return;
      }
      final exactAlarmGranted = await LunioNotificationService.instance
          .requestExactAlarmPermission();
      await LunioNotificationService.instance.rescheduleNotifications(
        notifications,
        exactAlarm: exactAlarmGranted,
        reservedDateTimes: reservedNotificationDateTimes(parkingCountdown),
      );
    } finally {
      _syncingSystemNotifications = false;
    }
  }

  /// ★ 应用内提醒弹窗（应用内签名变化时被调用）。
  ///
  /// 收集两类到期提醒：保养项目（逐个查 snooze/当日 ack 偏好过滤）
  /// + 里程更新（按推断频率判断是否到期）。有到期项则依次弹窗：
  ///  - "知道了" → 写当日 ack 偏好（今天不再弹）；
  ///  - "15 天内不再提醒" → 写 snooze 偏好（系统通知也一并静默）。
  /// 弹窗有动作 → 清空两个签名强制下一帧重排系统通知
  /// （snooze 影响通知内容）。
  Future<void> _showDueInAppNotifications({
    required int syncGeneration,
    required LunioNotificationSettings settings,
    required Car car,
    required List<MaintenanceItem> items,
    required List<MaintenanceRecord> records,
    required LocalDate today,
  }) async {
    if (syncGeneration != notificationSyncGeneration) {
      return;
    }
    if (_checkingInAppNotifications ||
        !settings.inAppNotificationsEnabled ||
        !mounted) {
      return;
    }
    _checkingInAppNotifications = true;
    try {
      final repository = ref.read(lunioRepositoryProvider);
      final dueNotices = <ReminderViewData>[];
      for (final notice in maintenanceNotices(
        settings: settings,
        car: car,
        items: items,
        records: records,
        today: today,
      )) {
        final itemId = notice.item.id;
        if (itemId == null) {
          continue;
        }
        if (!await isSnoozed(
              repository,
              maintenanceReminderSnoozeKey(itemId),
              today,
            ) &&
            !await isAcknowledgedToday(
              repository,
              maintenanceInAppReminderAcknowledgedKey(itemId),
              today,
            )) {
          dueNotices.add(notice);
        }
      }
      final showMileageReminder =
          car.id != null &&
          mileageUpdateReminderDue(car: car, records: records, today: today) &&
          !await isSnoozed(
            repository,
            mileageUpdateSnoozeKey(car.id!),
            today,
          ) &&
          !await isAcknowledgedToday(
            repository,
            mileageUpdateInAppAcknowledgedKey(car.id!),
            today,
          );
      if ((dueNotices.isEmpty && !showMileageReminder) || !mounted) {
        return;
      }
      var changedSystemSchedule = false;
      if (dueNotices.isNotEmpty && mounted) {
        final action = await showMaintenanceReminderDialog(
          context: context,
          ref: ref,
          car: car,
          maintenanceNotices: dueNotices,
          today: today,
        );
        if (action == ReminderDialogAction.snoozed) {
          changedSystemSchedule = true;
        }
        if (action != null) {
          changedSystemSchedule = true;
          if (action == ReminderDialogAction.acknowledged) {
            for (final notice in dueNotices) {
              final itemId = notice.item.id;
              if (itemId != null) {
                await repository.setPreferenceValue(
                  maintenanceInAppReminderAcknowledgedKey(itemId),
                  today.toString(),
                );
              }
            }
          }
        }
      }
      if (showMileageReminder && mounted) {
        final action = await showMileageUpdateReminderDialog(
          context: context,
          ref: ref,
          car: car,
          today: today,
        );
        if (action == ReminderDialogAction.snoozed) {
          changedSystemSchedule = true;
        }
        if (action != null) {
          changedSystemSchedule = true;
          final carId = car.id;
          if (action == ReminderDialogAction.acknowledged && carId != null) {
            await repository.setPreferenceValue(
              mileageUpdateInAppAcknowledgedKey(carId),
              today.toString(),
            );
          }
        }
      }
      if (changedSystemSchedule && mounted) {
        _systemNotificationSignature = null;
        _inAppNotificationSignature = null;
        setState(() {});
      }
    } finally {
      _checkingInAppNotifications = false;
    }
  }
}

/// 底部导航单个 tab 项（图标 + 文字，选中态主色胶囊底）。
class _BottomNavItem extends StatelessWidget {
  const _BottomNavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    final foreground = selected ? Colors.white : tokens.muted;
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        excludeSemantics: true,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            height: 56,
            decoration: BoxDecoration(
              color: selected ? tokens.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  selected ? selectedIcon : icon,
                  color: foreground,
                  size: 21,
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: foreground,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
