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

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.selectedIndex});

  final int selectedIndex;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell>
    with WidgetsBindingObserver {
  String? _systemNotificationSignature;
  String? _inAppNotificationSignature;
  bool _syncingSystemNotifications = false;
  bool _checkingInAppNotifications = false;
  bool _checkingInitialSystemPermission = false;
  double _androidThreeButtonNavigationInset = 0.0;
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
