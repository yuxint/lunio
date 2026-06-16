import 'dart:async';
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/date/local_date.dart';
import '../../core/notifications/lunio_notification_service.dart';
import '../../core/platform/native_files.dart';
import '../../core/platform/native_notification_settings.dart';
import '../../core/theme/lunio_tokens.dart';
import '../../core/widgets/lunio_components.dart';
import '../../data/backup/backup_codec.dart';
import '../../data/repositories/lunio_repository.dart';
import '../../domain/entities/car.dart';
import '../../domain/entities/maintenance_item.dart';
import '../../domain/entities/maintenance_record.dart';
import '../../domain/entities/notification_settings.dart';
import '../../domain/entities/parking_countdown.dart';
import '../../domain/entities/reminder.dart';
import '../../domain/entities/sync_metadata.dart';
import '../../domain/entities/vehicle_default_maintenance_item.dart';
import '../../domain/entities/vehicle_model.dart';
import '../../domain/rules/maintenance_rules.dart';
import '../../domain/rules/parking_countdown_rules.dart';

int _notificationSyncGeneration = 0;

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
      if (mounted) {
        setState(() {});
      }
    }
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
      const _ReminderPreviewPage(),
      const _RecordsPreviewPage(),
      const _ProfilePreviewPage(),
    ];

    return Scaffold(
      backgroundColor: tokens.background,
      body: SafeArea(child: pages[widget.selectedIndex]),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
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
                    _dismissTransientUi(context);
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
                    _dismissTransientUi(context);
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
                    _dismissTransientUi(context);
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
    final dataSignature = _reminderNotificationDataSignature(
      car: car,
      items: items,
      records: records,
      today: today,
    );
    final systemSignature = settings.systemNotificationsEnabled
        ? '${settings.dueRepeatFrequency.value}:'
              '${_parkingCountdownReminderSignature(parkingCountdown)}:'
              '$dataSignature'
        : 'system-off';
    final syncGeneration = _notificationSyncGeneration;
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
    if (syncGeneration != _notificationSyncGeneration) {
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
      final notifications = await _buildScheduledNotifications(
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
          reservedDateTimes: _reservedNotificationDateTimes(parkingCountdown),
        );
        return;
      }
      final exactAlarmGranted = await LunioNotificationService.instance
          .requestExactAlarmPermission();
      await LunioNotificationService.instance.rescheduleNotifications(
        notifications,
        exactAlarm: exactAlarmGranted,
        reservedDateTimes: _reservedNotificationDateTimes(parkingCountdown),
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
    if (syncGeneration != _notificationSyncGeneration) {
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
      final dueNotices = <_ReminderViewData>[];
      for (final notice in _maintenanceNotices(
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
        if (!await _isSnoozed(
              repository,
              _maintenanceReminderSnoozeKey(itemId),
              today,
            ) &&
            !await _isAcknowledgedToday(
              repository,
              _maintenanceInAppReminderAcknowledgedKey(itemId),
              today,
            )) {
          dueNotices.add(notice);
        }
      }
      final showMileageReminder =
          car.id != null &&
          _mileageUpdateReminderDue(car: car, records: records, today: today) &&
          !await _isSnoozed(
            repository,
            _mileageUpdateSnoozeKey(car.id!),
            today,
          ) &&
          !await _isAcknowledgedToday(
            repository,
            _mileageUpdateInAppAcknowledgedKey(car.id!),
            today,
          );
      if ((dueNotices.isEmpty && !showMileageReminder) || !mounted) {
        return;
      }
      var changedSystemSchedule = false;
      if (dueNotices.isNotEmpty && mounted) {
        final action = await _showMaintenanceReminderDialog(
          context: context,
          ref: ref,
          car: car,
          maintenanceNotices: dueNotices,
          today: today,
        );
        if (action == _ReminderDialogAction.snoozed) {
          changedSystemSchedule = true;
        }
        if (action != null) {
          changedSystemSchedule = true;
          if (action == _ReminderDialogAction.acknowledged) {
            for (final notice in dueNotices) {
              final itemId = notice.item.id;
              if (itemId != null) {
                await repository.setPreferenceValue(
                  _maintenanceInAppReminderAcknowledgedKey(itemId),
                  today.toString(),
                );
              }
            }
          }
        }
      }
      if (showMileageReminder && mounted) {
        final action = await _showMileageUpdateReminderDialog(
          context: context,
          ref: ref,
          car: car,
          today: today,
        );
        if (action == _ReminderDialogAction.snoozed) {
          changedSystemSchedule = true;
        }
        if (action != null) {
          changedSystemSchedule = true;
          final carId = car.id;
          if (action == _ReminderDialogAction.acknowledged && carId != null) {
            await repository.setPreferenceValue(
              _mileageUpdateInAppAcknowledgedKey(carId),
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

class _ReminderPreviewPage extends ConsumerStatefulWidget {
  const _ReminderPreviewPage();

  @override
  ConsumerState<_ReminderPreviewPage> createState() =>
      _ReminderPreviewPageState();
}

class _ReminderPreviewPageState extends ConsumerState<_ReminderPreviewPage> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appliedCar = ref.watch(appliedCarProvider);
    final cars = ref.watch(carsProvider);
    final items = ref.watch(appliedCarMaintenanceItemsProvider);
    final records = ref.watch(appliedCarRecordsProvider);
    final today = ref.watch(effectiveTodayProvider);
    final parkingCountdown = ref.watch(parkingCountdownProvider);
    final currentParkingCountdown = parkingCountdown.maybeWhen(
      data: (value) => value,
      orElse: () => null,
    );
    final now = ref.watch(appDateContextProvider).readSystemNow();
    final canSwitchCar = cars.maybeWhen(
      data: (value) => value.length > 1,
      orElse: () => false,
    );
    return appliedCar.when(
      loading: () => const _LoadingPage(title: '保养提醒'),
      error: (error, stackTrace) => _ErrorPage(title: '保养提醒', error: error),
      data: (car) => LunioPage(
        title: '保养提醒',
        trailing: canSwitchCar
            ? LunioIconButton(
                icon: Icons.directions_car_outlined,
                tooltip: '切换车辆',
                onPressed: () => _showVehicleSwitcher(context, ref),
              )
            : null,
        children: [
          if (car == null)
            _EmptyVehicleCard(onAdd: () => _showAddCarSheet(context, ref))
          else
            LunioHeroCard(
              title: '${car.brand} ${car.model}',
              subtitle: '上路 ${car.roadDate} · 当前应用车辆',
              metrics: [
                LunioMetric(
                  label: '当前里程',
                  value: _formatNumber(car.currentMileageKm),
                ),
                LunioMetric(
                  label: '到期概览',
                  value: today.when(
                    loading: () => '计算中',
                    error: (error, stackTrace) => '日期失败',
                    data: (value) =>
                        _dueOverviewText(items, records, car, value),
                  ),
                ),
              ],
            ),
          if (car != null) ...[
            const SizedBox(height: 12),
            _ReminderActionRow(
              onAddRecord: () => _showMaintenanceRecordFormSheet(context, ref),
              onParkingCountdown: currentParkingCountdown == null
                  ? () => _showParkingCountdownSheet(
                      context,
                      ref,
                      now: now,
                      initial: currentParkingCountdown,
                    )
                  : null,
            ),
          ],
          SizedBox(height: currentParkingCountdown == null ? 14 : 22),
          if (currentParkingCountdown != null) ...[
            _ParkingCountdownCard(
              countdown: currentParkingCountdown,
              now: now,
              onEnd: () => _clearParkingCountdown(ref),
            ),
            const SizedBox(height: 22),
          ],
          if (car != null)
            LunioSection(
              title: '待关注项目',
              children: [
                today.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, stackTrace) =>
                      LunioCard(child: Text('日期加载失败：${_friendlyError(error)}')),
                  data: (value) => _ReminderList(
                    car: car,
                    items: items,
                    records: records,
                    today: value,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.labels,
    required this.selectedIndexes,
    required this.onSelected,
  });

  final List<String> labels;
  final Set<int> selectedIndexes;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var index = 0; index < labels.length; index++) ...[
            Builder(
              builder: (context) {
                final selected = selectedIndexes.contains(index);
                return InkWell(
                  onTap: () => onSelected(index),
                  borderRadius: BorderRadius.circular(12),
                  overlayColor: WidgetStateProperty.all(Colors.transparent),
                  splashColor: Colors.transparent,
                  highlightColor: Colors.transparent,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        height: 34,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: selected ? tokens.primarySoft : tokens.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: selected
                                ? tokens.primary.withValues(alpha: 0.34)
                                : tokens.line,
                          ),
                        ),
                        child: Text(
                          labels[index],
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(
                                color: selected ? tokens.primary : tokens.ink,
                              ),
                        ),
                      ),
                      if (selected)
                        Positioned(
                          right: 2,
                          bottom: 2,
                          child: Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              color: tokens.primary,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: tokens.surface,
                                width: 1.5,
                              ),
                            ),
                            child: const Icon(
                              Icons.check,
                              size: 9,
                              color: Colors.white,
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
            if (index != labels.length - 1) const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _ItemPills extends StatelessWidget {
  const _ItemPills({required this.labels});

  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    final textStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: tokens.ink,
      fontWeight: FontWeight.w700,
    );
    final textScaler = MediaQuery.textScalerOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final rows = _packedPillRows(
          labels: labels,
          maxWidth: constraints.maxWidth,
          textStyle: textStyle,
          textScaler: textScaler,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) ...[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (
                    var itemIndex = 0;
                    itemIndex < rows[rowIndex].length;
                    itemIndex++
                  ) ...[
                    if (itemIndex > 0) const SizedBox(width: 6),
                    SizedBox(
                      width: rows[rowIndex][itemIndex].width,
                      child: _ItemPill(
                        label: rows[rowIndex][itemIndex].label,
                        style: textStyle,
                      ),
                    ),
                  ],
                ],
              ),
              if (rowIndex < rows.length - 1) const SizedBox(height: 6),
            ],
          ],
        );
      },
    );
  }
}

class _ItemPill extends StatelessWidget {
  const _ItemPill({required this.label, required this.style});

  final String label;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    return Container(
      constraints: const BoxConstraints(minHeight: 28),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: tokens.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: tokens.line.withValues(alpha: 0.72)),
      ),
      child: Center(
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: style,
        ),
      ),
    );
  }
}

class _PackedPill {
  const _PackedPill({required this.label, required this.width});

  final String label;
  final double width;
}

List<List<_PackedPill>> _packedPillRows({
  required List<String> labels,
  required double maxWidth,
  required TextStyle? textStyle,
  required TextScaler textScaler,
}) {
  if (labels.isEmpty) {
    return const [];
  }
  if (!maxWidth.isFinite || maxWidth <= 0) {
    return [
      labels.map((label) => _PackedPill(label: label, width: 0)).toList(),
    ];
  }
  const spacing = 6.0;
  const horizontalPadding = 18.0;
  const measurementSlack = 4.0;
  const minPillWidth = 58.0;
  final remaining = labels
      .map(
        (label) => _PackedPill(
          label: label,
          width:
              (_measureTextWidth(label, textStyle, textScaler) +
                      horizontalPadding +
                      measurementSlack)
                  .clamp(minPillWidth, maxWidth),
        ),
      )
      .toList();
  final rows = <List<_PackedPill>>[];
  while (remaining.isNotEmpty) {
    final row = <_PackedPill>[];
    var usedWidth = 0.0;
    while (remaining.isNotEmpty) {
      var selectedIndex = -1;
      for (var index = 0; index < remaining.length; index++) {
        final extraSpacing = row.isEmpty ? 0.0 : spacing;
        if (usedWidth + extraSpacing + remaining[index].width <= maxWidth) {
          selectedIndex = index;
          break;
        }
      }
      if (selectedIndex == -1) {
        if (row.isEmpty) {
          selectedIndex = 0;
        } else {
          break;
        }
      }
      final item = remaining.removeAt(selectedIndex);
      usedWidth += (row.isEmpty ? 0.0 : spacing) + item.width;
      row.add(item);
    }
    rows.add(row);
  }
  return rows;
}

double _measureTextWidth(String text, TextStyle? style, TextScaler textScaler) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    maxLines: 1,
    textDirection: TextDirection.ltr,
    textScaler: textScaler,
  )..layout();
  return painter.width;
}

class _SmallActionButton extends StatelessWidget {
  const _SmallActionButton({
    required this.label,
    required this.onPressed,
    this.danger = false,
    this.primary = false,
    this.secondary = false,
    this.muted = false,
    this.tooltip,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool danger;
  final bool primary;
  final bool secondary;
  final bool muted;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    final backgroundColor = danger
        ? tokens.dangerSoft
        : primary
        ? tokens.primarySoft
        : secondary
        ? tokens.secondarySoft
        : muted
        ? tokens.surface3
        : tokens.surface2;
    final foregroundColor = onPressed == null
        ? tokens.subtle
        : danger
        ? tokens.danger
        : primary
        ? tokens.primary
        : secondary
        ? tokens.secondary
        : muted
        ? tokens.muted
        : tokens.ink;
    return SizedBox(
      height: 34,
      child: Tooltip(
        message: tooltip ?? label,
        child: TextButton(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            backgroundColor: backgroundColor,
            foregroundColor: foregroundColor,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(11),
            ),
          ),
          child: Text(label),
        ),
      ),
    );
  }
}

class _PrototypeSheetFrame extends StatelessWidget {
  const _PrototypeSheetFrame({
    required this.title,
    required this.child,
    this.subtitle,
    this.bottomInset = 0,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    final content = Padding(
      padding: EdgeInsets.fromLTRB(18, 12, 18, 18 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 48,
              height: 5,
              decoration: BoxDecoration(
                color: tokens.line,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleLarge),
                    if (subtitle != null) ...[
                      const SizedBox(height: 5),
                      Text(
                        subtitle!,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
    final sheet = Container(
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        boxShadow: [
          BoxShadow(
            color: tokens.ink.withValues(alpha: 0.18),
            blurRadius: 54,
            offset: const Offset(0, -20),
          ),
        ],
      ),
      child: SingleChildScrollView(child: content),
    );
    return sheet;
  }
}

class _ChoiceChipButton extends StatelessWidget {
  const _ChoiceChipButton({
    required this.label,
    required this.selected,
    required this.onTap,
    this.enabled = true,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        constraints: const BoxConstraints(minHeight: 36),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? tokens.primarySoft : tokens.surface2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? tokens.primary.withValues(alpha: 0.3)
                : tokens.line,
          ),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: selected ? tokens.primary : tokens.ink,
          ),
        ),
      ),
    );
  }
}

class _ReminderActionRow extends StatelessWidget {
  const _ReminderActionRow({
    required this.onAddRecord,
    required this.onParkingCountdown,
  });

  final VoidCallback onAddRecord;
  final VoidCallback? onParkingCountdown;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: LunioPrimaryButton(label: '新增保养记录', onPressed: onAddRecord),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: LunioPrimaryButton(
            label: '停车倒计时',
            onPressed: onParkingCountdown,
          ),
        ),
      ],
    );
  }
}

class _ParkingCountdownCard extends StatelessWidget {
  const _ParkingCountdownCard({
    required this.countdown,
    required this.now,
    required this.onEnd,
  });

  final ParkingCountdown countdown;
  final DateTime now;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    final progress = ParkingCountdownRules.progress(
      countdown: countdown,
      now: now,
    );
    final color = _parkingStatusColor(tokens, progress.status);
    final animatedPercent = progress.status == ReminderStatus.danger
        ? 100.0
        : progress.percentRemaining;
    return LunioCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            children: [
              _ParkingIcon(),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '停车倒计时',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_formatClock(countdown.startedAt)} 入场 · 免费 ${_formatParkingDurationOption(countdown.durationSeconds)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              LunioStatusBadge(
                label: _parkingStatusText(progress.status),
                tone: _parkingStatusTone(progress.status),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Center(
            child: SizedBox.square(
              dimension: 152,
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(end: animatedPercent),
                duration: const Duration(milliseconds: 250),
                curve: Curves.linear,
                builder: (context, percent, child) {
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      CustomPaint(
                        size: const Size.square(152),
                        painter: _ReminderProgressRingPainter(
                          percent: percent,
                          color: color,
                          backgroundColor: tokens.surface3,
                          strokeWidth: 10,
                        ),
                      ),
                      SizedBox(
                        width: 112,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                progress.status == ReminderStatus.danger
                                    ? '+${_formatCountdownClock(progress.expiredSeconds)}'
                                    : _formatCountdownClock(
                                        progress.remainingSeconds,
                                      ),
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(
                                      color: color,
                                      fontWeight: FontWeight.w900,
                                    ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              progress.status == ReminderStatus.danger
                                  ? '已超时'
                                  : '剩余时间',
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: tokens.muted,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 14),
          Center(
            child: Column(
              children: [
                Text(
                  progress.status == ReminderStatus.danger
                      ? '${_formatClock(countdown.endsAt)} 已到点'
                      : '${_formatClock(countdown.endsAt)} 前离场',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: _SmallActionButton(
              label: '结束',
              onPressed: onEnd,
              secondary: true,
            ),
          ),
        ],
      ),
    );
  }
}

class _ParkingIcon extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: tokens.primarySoft,
        borderRadius: BorderRadius.circular(tokens.radiusMedium),
      ),
      child: Icon(Icons.local_parking, color: tokens.primary),
    );
  }
}

class _ParkingCountdownForm extends StatefulWidget {
  const _ParkingCountdownForm({
    required this.now,
    required this.initial,
    required this.onSubmit,
  });

  final DateTime now;
  final ParkingCountdown? initial;
  final Future<void> Function(ParkingCountdown countdown) onSubmit;

  @override
  State<_ParkingCountdownForm> createState() => _ParkingCountdownFormState();
}

class _ParkingCountdownFormState extends State<_ParkingCountdownForm> {
  late DateTime entryTime;
  late final TextEditingController durationMinutesController;
  bool saving = false;
  String? errorText;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    entryTime = initial?.startedAt ?? widget.now;
    durationMinutesController = TextEditingController(
      text: ((initial?.durationSeconds ?? 1800) ~/ 60).toString(),
    );
  }

  @override
  void dispose() {
    durationMinutesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LunioPickerTile(
          label: '入场时间',
          value: _formatClock(entryTime),
          enabled: !saving,
          onTap: saving ? null : _pickEntryTime,
        ),
        const SizedBox(height: 10),
        TextField(
          controller: durationMinutesController,
          enabled: !saving,
          keyboardType: TextInputType.text,
          textInputAction: TextInputAction.done,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: (_) => setState(() => errorText = null),
          onSubmitted: (_) => FocusScope.of(context).unfocus(),
          decoration: const InputDecoration(
            labelText: '免费时长',
            suffixText: '分钟',
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _ParkingDurationChip(
              label: '0.5 小时',
              selected: _durationMinutes == 30,
              onPressed: saving ? null : () => _setDurationMinutes(30),
            ),
            _ParkingDurationChip(
              label: '1 小时',
              selected: _durationMinutes == 60,
              onPressed: saving ? null : () => _setDurationMinutes(60),
            ),
            _ParkingDurationChip(
              label: '2 小时',
              selected: _durationMinutes == 120,
              onPressed: saving ? null : () => _setDurationMinutes(120),
            ),
          ],
        ),
        if (errorText != null) ...[
          const SizedBox(height: 10),
          LunioInlineMessage(message: errorText!, tone: LunioStatusTone.danger),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: LunioSecondaryButton(
                label: '取消',
                onPressed: saving ? null : () => Navigator.of(context).pop(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: LunioPrimaryButton(
                label: saving ? '保存中' : '开始计时',
                onPressed: saving ? null : _submit,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _pickEntryTime() async {
    final selected = await _showParkingEntryTimePicker(
      context,
      initial: entryTime,
    );
    if (selected == null || !mounted) {
      return;
    }
    setState(() {
      entryTime = selected;
      errorText = null;
    });
  }

  int? get _durationMinutes {
    return int.tryParse(durationMinutesController.text.trim());
  }

  void _setDurationMinutes(int minutes) {
    setState(() {
      durationMinutesController.text = minutes.toString();
      errorText = null;
    });
  }

  Future<void> _submit() async {
    final durationMinutes = _durationMinutes;
    if (durationMinutes == null || durationMinutes <= 0) {
      setState(() => errorText = '免费时长必须填写正整数分钟');
      return;
    }
    setState(() {
      saving = true;
      errorText = null;
    });
    try {
      await widget.onSubmit(
        ParkingCountdown(
          startedAt: entryTime,
          durationSeconds: durationMinutes * 60,
        ),
      );
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        saving = false;
        errorText = _friendlyError(error);
      });
    }
  }
}

class _ParkingEntryTimePicker extends StatefulWidget {
  const _ParkingEntryTimePicker({required this.initial});

  final DateTime initial;

  @override
  State<_ParkingEntryTimePicker> createState() =>
      _ParkingEntryTimePickerState();
}

class _ParkingEntryTimePickerState extends State<_ParkingEntryTimePicker> {
  late int hour;
  late int minute;
  late int second;

  @override
  void initState() {
    super.initState();
    hour = widget.initial.hour;
    minute = widget.initial.minute;
    second = widget.initial.second;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
      child: LunioSheetScaffold(
        title: '选择入场时间',
        subtitle: '按当前日期选择时、分、秒。',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: _TimePartWheel(
                    label: '时',
                    value: hour,
                    count: 24,
                    onChanged: (value) => setState(() => hour = value),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _TimePartWheel(
                    label: '分',
                    value: minute,
                    count: 60,
                    onChanged: (value) => setState(() => minute = value),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _TimePartWheel(
                    label: '秒',
                    value: second,
                    count: 60,
                    onChanged: (value) => setState(() => second = value),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: LunioSecondaryButton(
                    label: '取消',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: LunioPrimaryButton(
                    label: '确定',
                    onPressed: () => Navigator.of(context).pop(
                      DateTime(
                        widget.initial.year,
                        widget.initial.month,
                        widget.initial.day,
                        hour,
                        minute,
                        second,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TimePartWheel extends StatefulWidget {
  const _TimePartWheel({
    required this.label,
    required this.value,
    required this.count,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int count;
  final ValueChanged<int> onChanged;

  @override
  State<_TimePartWheel> createState() => _TimePartWheelState();
}

class _TimePartWheelState extends State<_TimePartWheel> {
  late final FixedExtentScrollController controller;

  @override
  void initState() {
    super.initState();
    controller = FixedExtentScrollController(initialItem: widget.value);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    final textStyle = Theme.of(
      context,
    ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700);
    return Column(
      children: [
        Text(
          widget.label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: tokens.muted,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 154,
          child: CupertinoPicker(
            scrollController: controller,
            itemExtent: 36,
            magnification: 1.08,
            useMagnifier: true,
            selectionOverlay: const CupertinoPickerDefaultSelectionOverlay(),
            onSelectedItemChanged: widget.onChanged,
            children: [
              for (var index = 0; index < widget.count; index++)
                Center(
                  child: Text(
                    index.toString().padLeft(2, '0'),
                    style: textStyle,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

Future<DateTime?> _showParkingEntryTimePicker(
  BuildContext context, {
  required DateTime initial,
}) {
  return _showLunioModalSheet<DateTime>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _ParkingEntryTimePicker(initial: initial),
  );
}

class _ParkingDurationChip extends StatelessWidget {
  const _ParkingDurationChip({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: selected ? Colors.white : tokens.primary,
        backgroundColor: selected ? tokens.primary : tokens.primarySoft,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        minimumSize: const Size(0, 34),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(label),
    );
  }
}

Future<void> _showParkingCountdownSheet(
  BuildContext context,
  WidgetRef ref, {
  required DateTime now,
  ParkingCountdown? initial,
}) {
  return _showLunioModalSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) {
      final bottomInset = MediaQuery.of(context).viewInsets.bottom;
      return Padding(
        padding: EdgeInsets.fromLTRB(18, 0, 18, bottomInset + 16),
        child: LunioSheetScaffold(
          title: '停车计时',
          subtitle: '设置入场时间和免费停车时长。',
          child: _ParkingCountdownForm(
            now: now,
            initial: initial,
            onSubmit: (countdown) => _saveParkingCountdown(ref, countdown),
          ),
        ),
      );
    },
  );
}

Future<void> _saveParkingCountdown(
  WidgetRef ref,
  ParkingCountdown countdown,
) async {
  await ref.read(lunioRepositoryProvider).saveParkingCountdown(countdown);
  ref.invalidate(parkingCountdownProvider);
  final settings = await ref.read(notificationSettingsProvider.future);
  if (!settings.systemNotificationsEnabled) {
    return;
  }
  final granted = await LunioNotificationService.instance
      .requestNotificationPermission();
  await ref
      .read(lunioRepositoryProvider)
      .setPreferenceValue('systemNotificationPermissionRequested', 'true');
  if (granted) {
    final exactAlarmGranted = await LunioNotificationService.instance
        .requestExactAlarmPermission();
    await LunioNotificationService.instance
        .scheduleParkingCountdownNotification(
          countdown,
          exactAlarm: exactAlarmGranted,
        );
  } else {
    await ref
        .read(lunioRepositoryProvider)
        .setPreferenceValue('systemNotificationsEnabled', 'false');
    invalidatePreferenceProviders(ref);
  }
}

Future<void> _clearParkingCountdown(WidgetRef ref) async {
  await ref.read(lunioRepositoryProvider).clearParkingCountdown();
  ref.invalidate(parkingCountdownProvider);
  final settings = await ref.read(notificationSettingsProvider.future);
  if (settings.systemNotificationsEnabled) {
    await LunioNotificationService.instance
        .cancelParkingCountdownNotification();
  }
}

String _formatClock(DateTime dateTime) {
  final hour = dateTime.hour.toString().padLeft(2, '0');
  final minute = dateTime.minute.toString().padLeft(2, '0');
  final second = dateTime.second.toString().padLeft(2, '0');
  return '$hour:$minute:$second';
}

String _formatCountdownClock(int seconds) {
  final safeSeconds = seconds < 0 ? 0 : seconds;
  final hours = safeSeconds ~/ 3600;
  final minutes = (safeSeconds % 3600) ~/ 60;
  final remainingSeconds = safeSeconds % 60;
  if (hours > 0) {
    return [
      hours.toString().padLeft(2, '0'),
      minutes.toString().padLeft(2, '0'),
      remainingSeconds.toString().padLeft(2, '0'),
    ].join(':');
  }
  return [
    minutes.toString().padLeft(2, '0'),
    remainingSeconds.toString().padLeft(2, '0'),
  ].join(':');
}

String _formatCountdownDuration(int seconds) {
  if (seconds <= 0) {
    return '0秒';
  }
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  final remainingSeconds = seconds % 60;
  final parts = <String>[
    if (hours > 0) '$hours小时',
    if (minutes > 0) '$minutes分钟',
    if (remainingSeconds > 0) '$remainingSeconds秒',
  ];
  return parts.join(' ');
}

String _formatParkingDurationOption(int seconds) {
  return switch (seconds) {
    1800 => '0.5 小时',
    3600 => '1 小时',
    7200 => '2 小时',
    _ => _formatCountdownDuration(seconds),
  };
}

String _parkingStatusText(ReminderStatus status) {
  return switch (status) {
    ReminderStatus.normal => '剩余充足',
    ReminderStatus.warning => '即将到点',
    ReminderStatus.danger => '已超时',
  };
}

LunioStatusTone _parkingStatusTone(ReminderStatus status) {
  return switch (status) {
    ReminderStatus.normal => LunioStatusTone.normal,
    ReminderStatus.warning => LunioStatusTone.warning,
    ReminderStatus.danger => LunioStatusTone.danger,
  };
}

Color _parkingStatusColor(LunioTokens tokens, ReminderStatus status) {
  return _parkingStatusTone(status).statusForeground(tokens);
}

class _ReminderList extends StatelessWidget {
  const _ReminderList({
    required this.car,
    required this.items,
    required this.records,
    required this.today,
  });

  final Car car;
  final AsyncValue<List<MaintenanceItem>> items;
  final AsyncValue<List<MaintenanceRecord>> records;
  final LocalDate today;

  @override
  Widget build(BuildContext context) {
    if (items.isLoading || records.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (items.hasError) {
      return LunioCard(child: Text('保养项目加载失败：${_friendlyError(items.error!)}'));
    }
    if (records.hasError) {
      return LunioCard(
        child: Text('保养记录加载失败：${_friendlyError(records.error!)}'),
      );
    }
    if ((records.value ?? const <MaintenanceRecord>[]).isEmpty) {
      return LunioCard(
        child: Text(
          '暂无保养记录，记录首保后再生成保养提醒。',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }
    final rows = _buildReminderRows(
      car: car,
      items: items.value ?? const [],
      records: records.value ?? const [],
      today: today,
    );
    if (rows.isEmpty) {
      return LunioCard(
        child: Text(
          '暂无启用的保养项目，请先在“我的”里配置保养项目。',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }
    return Column(
      children: [
        for (final row in rows) ...[
          _ReminderRow(row: row),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _ReminderRow extends StatelessWidget {
  const _ReminderRow({required this.row});

  final _ReminderViewData row;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    final color = row.tone.statusForeground(tokens);
    return LunioCard(
      padding: EdgeInsets.zero,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(tokens.radiusLarge),
        child: InkWell(
          onTap: () => _showReminderRecordDetail(context, row),
          borderRadius: BorderRadius.circular(tokens.radiusLarge),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                SizedBox.square(
                  dimension: 58,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CustomPaint(
                        size: const Size.square(58),
                        painter: _ReminderProgressRingPainter(
                          percent: row.displayPercent.toDouble(),
                          color: color,
                          backgroundColor: tokens.surface3,
                        ),
                      ),
                      SizedBox(
                        width: 44,
                        height: 22,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            row.percentText,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: color,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              row.title,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          LunioStatusBadge(label: row.badge, tone: row.tone),
                        ],
                      ),
                      const SizedBox(height: 6),
                      for (final detail in row.detailTexts) ...[
                        Text(
                          detail,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        if (detail != row.detailTexts.last)
                          const SizedBox(height: 2),
                      ],
                    ],
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

void _showReminderRecordDetail(BuildContext context, _ReminderViewData row) {
  final record = row.latestRecord;
  _showLunioModalSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) {
      final tokens = Theme.of(context).extension<LunioTokens>()!;
      return Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
        child: LunioSheetScaffold(
          title: row.title,
          subtitle: row.badge == '正常' ? '保养状态正常' : '当前状态：${row.badge}',
          child: record == null
              ? Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: tokens.surface2,
                    borderRadius: BorderRadius.circular(tokens.radiusLarge),
                  ),
                  child: Text(
                    '暂无上次保养记录',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: tokens.muted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _ReminderRecordMetric(
                            label: '上次保养日期',
                            value: record.date.toString(),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _ReminderRecordMetric(
                            label: '上次保养里程',
                            value: '${_formatNumber(record.mileageKm)} km',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
        ),
      );
    },
  );
}

class _ReminderRecordMetric extends StatelessWidget {
  const _ReminderRecordMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tokens.surface2,
        borderRadius: BorderRadius.circular(tokens.radiusLarge),
        border: Border.all(color: tokens.line.withValues(alpha: 0.72)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: tokens.muted,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
    );
  }
}

class _ReminderProgressRingPainter extends CustomPainter {
  const _ReminderProgressRingPainter({
    required this.percent,
    required this.color,
    required this.backgroundColor,
    this.strokeWidth = 6,
  });

  final double percent;
  final Color color;
  final Color backgroundColor;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.shortestSide - strokeWidth) / 2;
    final backgroundPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = strokeWidth;
    final foregroundPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = strokeWidth;
    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawCircle(center, radius, backgroundPaint);
    canvas.drawArc(
      rect,
      -1.5708,
      6.2832 * (percent / 100).clamp(0, 1),
      false,
      foregroundPaint,
    );
  }

  @override
  bool shouldRepaint(_ReminderProgressRingPainter oldDelegate) {
    return percent != oldDelegate.percent ||
        color != oldDelegate.color ||
        backgroundColor != oldDelegate.backgroundColor ||
        strokeWidth != oldDelegate.strokeWidth;
  }
}

class _RecordsPreviewPage extends ConsumerStatefulWidget {
  const _RecordsPreviewPage();

  @override
  ConsumerState<_RecordsPreviewPage> createState() =>
      _RecordsPreviewPageState();
}

class _RecordsPreviewPageState extends ConsumerState<_RecordsPreviewPage> {
  int selectedMode = 0;
  final selectedYears = <int>{};
  final selectedItemIds = <int>{};

  @override
  Widget build(BuildContext context) {
    final car = ref
        .watch(appliedCarProvider)
        .maybeWhen(data: (value) => value, orElse: () => null);
    final records = ref.watch(appliedCarRecordsProvider);
    final items = ref
        .watch(appliedCarMaintenanceItemsProvider)
        .maybeWhen(
          data: (value) => value,
          orElse: () => const <MaintenanceItem>[],
        );
    return LunioPage(
      title: '保养记录',
      children: [
        LunioSegmentedControl(
          values: const ['按周期', '按项目'],
          selectedIndex: selectedMode,
          onSelected: (index) => setState(() => selectedMode = index),
        ),
        const SizedBox(height: 14),
        records.maybeWhen(
          data: (value) {
            final years = _recordYears(value);
            selectedYears.removeWhere((year) => !years.contains(year));
            final itemIds = items
                .map((item) => item.id)
                .whereType<int>()
                .toSet();
            selectedItemIds.removeWhere((itemId) => !itemIds.contains(itemId));
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _FilterBar(
                  labels: ['全部年份', for (final year in years) '$year年'],
                  selectedIndexes: _selectedFilterIndexes(
                    values: years,
                    selectedValues: selectedYears,
                  ),
                  onSelected: (index) => setState(() {
                    if (index == 0) {
                      selectedYears.clear();
                      return;
                    }
                    _toggleSelection(selectedYears, years[index - 1]);
                  }),
                ),
                const SizedBox(height: 8),
                _FilterBar(
                  labels: ['全部项目', for (final item in items) item.name],
                  selectedIndexes: _selectedFilterIndexes(
                    values: items
                        .map((item) => item.id)
                        .whereType<int>()
                        .toList(),
                    selectedValues: selectedItemIds,
                  ),
                  onSelected: (index) => setState(() {
                    if (index == 0) {
                      selectedItemIds.clear();
                      return;
                    }
                    final itemId = items[index - 1].id;
                    if (itemId != null) {
                      _toggleSelection(selectedItemIds, itemId);
                    }
                  }),
                ),
              ],
            );
          },
          orElse: () => const SizedBox.shrink(),
        ),
        const SizedBox(height: 14),
        records.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stackTrace) =>
              LunioCard(child: Text('记录加载失败：${_friendlyError(error)}')),
          data: (value) {
            if (car == null) {
              return const LunioCard(child: Text('请先新增车辆'));
            }
            if (value.isEmpty) {
              return LunioCard(
                child: Text(
                  '暂无保养记录，点击右下角 + 新增。',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              );
            }
            final filteredRecords = _filterRecords(
              records: value,
              years: selectedYears,
              itemIds: selectedItemIds,
            );
            if (filteredRecords.isEmpty) {
              return LunioCard(
                child: Text(
                  '没有符合筛选条件的记录',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              );
            }
            if (selectedMode == 0) {
              return _RecordCycleList(
                records: filteredRecords,
                items: items,
                onEdit: (record) => _showMaintenanceRecordFormSheet(
                  context,
                  ref,
                  record: record,
                ),
                onDelete: (record) =>
                    _deleteMaintenanceRecord(context, ref, record),
              );
            }
            return _RecordItemList(
              records: filteredRecords,
              items: items,
              selectedItemIds: selectedItemIds,
              onEdit: (record, itemId) =>
                  _showMaintenanceRecordFormSheet(context, ref, record: record),
              onDelete: (record, itemId) =>
                  _deleteMaintenanceRecordItem(context, ref, record, itemId),
            );
          },
        ),
      ],
    );
  }
}

class _RecordCycleList extends StatelessWidget {
  const _RecordCycleList({
    required this.records,
    required this.items,
    required this.onEdit,
    required this.onDelete,
  });

  final List<MaintenanceRecord> records;
  final List<MaintenanceItem> items;
  final ValueChanged<MaintenanceRecord> onEdit;
  final ValueChanged<MaintenanceRecord> onDelete;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    return Column(
      children: [
        for (final record in records) ...[
          LunioCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      record.date.toString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Spacer(),
                    const SizedBox(width: 10),
                    Text(
                      _formatMoney(record.costCents),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: tokens.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Text(
                            '${_formatNumber(record.mileageKm)} km',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          if ((record.note ?? '').trim().isNotEmpty) ...[
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                record.note!.trim(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _SmallActionButton(
                          label: '编辑',
                          onPressed: () => onEdit(record),
                        ),
                        const SizedBox(width: 8),
                        _SmallActionButton(
                          label: '删除',
                          danger: true,
                          onPressed: () => onDelete(record),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _ItemPills(labels: _recordItemNameList(record, items)),
              ],
            ),
          ),
          if (record != records.last) const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _RecordItemList extends StatelessWidget {
  const _RecordItemList({
    required this.records,
    required this.items,
    required this.selectedItemIds,
    required this.onEdit,
    required this.onDelete,
  });

  final List<MaintenanceRecord> records;
  final List<MaintenanceItem> items;
  final Set<int> selectedItemIds;
  final void Function(MaintenanceRecord record, int itemId) onEdit;
  final void Function(MaintenanceRecord record, int itemId) onDelete;

  @override
  Widget build(BuildContext context) {
    final rows =
        <({MaintenanceRecord record, int itemId, MaintenanceItem? item})>[];
    for (final record in records) {
      for (final itemId in record.itemIds) {
        if (selectedItemIds.isNotEmpty && !selectedItemIds.contains(itemId)) {
          continue;
        }
        rows.add((
          record: record,
          itemId: itemId,
          item: _itemById(items, itemId),
        ));
      }
    }
    if (rows.isEmpty) {
      return LunioCard(
        child: Text(
          '没有符合筛选条件的记录',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }
    return Column(
      children: [
        for (final row in rows) ...[
          LunioCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.item?.name ?? '未知项目',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${row.record.date} · ${_formatNumber(row.record.mileageKm)} km',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    const SizedBox(width: 10),
                    _SmallActionButton(
                      label: '编辑',
                      onPressed: () => onEdit(row.record, row.itemId),
                    ),
                    const SizedBox(width: 8),
                    _SmallActionButton(
                      label: '删除',
                      danger: true,
                      onPressed: () => onDelete(row.record, row.itemId),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

List<int> _recordYears(List<MaintenanceRecord> records) {
  final years = records.map((record) => record.date.year).toSet().toList()
    ..sort((left, right) => right.compareTo(left));
  return years;
}

List<MaintenanceRecord> _filterRecords({
  required List<MaintenanceRecord> records,
  required Set<int> years,
  required Set<int> itemIds,
}) {
  return records.where((record) {
    if (years.isNotEmpty && !years.contains(record.date.year)) {
      return false;
    }
    if (itemIds.isNotEmpty &&
        !record.itemIds.any((itemId) => itemIds.contains(itemId))) {
      return false;
    }
    return true;
  }).toList();
}

Set<int> _selectedFilterIndexes({
  required List<int> values,
  required Set<int> selectedValues,
}) {
  if (selectedValues.isEmpty) {
    return {0};
  }
  final indexes = <int>{};
  for (var index = 0; index < values.length; index++) {
    if (selectedValues.contains(values[index])) {
      indexes.add(index + 1);
    }
  }
  return indexes.isEmpty ? {0} : indexes;
}

void _toggleSelection(Set<int> values, int value) {
  if (!values.add(value)) {
    values.remove(value);
  }
}

class _ProfilePreviewPage extends ConsumerStatefulWidget {
  const _ProfilePreviewPage();

  @override
  ConsumerState<_ProfilePreviewPage> createState() =>
      _ProfilePreviewPageState();
}

class _ProfilePreviewPageState extends ConsumerState<_ProfilePreviewPage> {
  int versionTapCount = 0;

  @override
  Widget build(BuildContext context) {
    final cars = ref.watch(carsProvider);
    final developerMode = ref.watch(developerModeProvider);
    final manualDate = ref.watch(manualDatePreferenceProvider);
    final notificationSettings = ref.watch(notificationSettingsProvider);
    final themeMode = ref.watch(themeModePreferenceProvider);
    final today = ref
        .watch(effectiveTodayProvider)
        .maybeWhen(
          data: (value) => value,
          orElse: () => LocalDate.fromDateTime(DateTime.now()),
        );
    final appliedCar = ref
        .watch(appliedCarProvider)
        .maybeWhen(data: (value) => value, orElse: () => null);
    final hasCars = cars.maybeWhen(
      data: (value) => value.isNotEmpty,
      orElse: () => false,
    );
    return LunioPage(
      title: '个人中心',
      bottomPadding: 72,
      children: [
        LunioSection(
          title: '我的车辆',
          trailing: hasCars
              ? TextButton(
                  onPressed: () => _showAddCarSheet(context, ref),
                  child: const Text('添加'),
                )
              : null,
          children: [
            cars.when(
              loading: () => const LunioCard(child: Text('车辆加载中...')),
              error: (error, stackTrace) =>
                  LunioCard(child: Text('车辆加载失败：${_friendlyError(error)}')),
              data: (items) => _VehicleList(
                cars: items,
                appliedCarId: appliedCar?.id,
                today: today,
                onAdd: () => _showAddCarSheet(context, ref),
                onEdit: (car) => _showEditCarSheet(context, ref, car),
                onManageItems: (car) =>
                    _showMaintenanceItemsSheet(context, ref, car: car),
                onApply: (carId) => _applyCar(context, ref, carId),
                onDelete: (car) => _deleteCar(context, ref, car),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        LunioSection(
          title: '数据与工具',
          children: [
            _ProfileSettingRow(
              title: '通知提醒',
              subtitle: notificationSettings.when(
                loading: () => '读取中',
                error: (error, stackTrace) => '读取失败',
                data: _notificationSettingsSubtitle,
              ),
              trailingLabel: '设置',
              onTap: () => _showNotificationSettingsSheet(context, ref),
            ),
            _ProfileSettingRow(
              title: '备份',
              subtitle: '导出全部车辆、项目配置和保养记录',
              trailingLabel: '导出',
              onTap: () => _exportBackup(context, ref),
            ),
            _ProfileSettingRow(
              title: '恢复',
              subtitle: '选择备份文件并恢复本地数据',
              trailingLabel: '恢复',
              onTap: () => _restoreBackupFromFile(context, ref),
            ),
            _ProfileSettingRow(
              title: '清空数据',
              subtitle: '删除本地车辆、项目和记录',
              trailingLabel: '清空',
              onTap: () => _clearAllData(context, ref),
            ),
            if (developerMode.maybeWhen(
              data: (value) => value,
              orElse: () => false,
            ))
              _ProfileSettingRow(
                title: '手动日期',
                subtitle: manualDate.when(
                  loading: () => '读取中',
                  error: (error, stackTrace) => '读取失败',
                  data: (value) =>
                      value == null ? '关闭 · 使用系统日期' : '开启 · $value',
                ),
                trailingLabel: '设置',
                onTap: () => _showManualDateSheet(context, ref),
              ),
            _ThemeModeSettingRow(
              mode: themeMode.maybeWhen(
                data: (value) => value,
                orElse: () => ThemeMode.system,
              ),
              onChanged: (mode) => _setThemeMode(context, ref, mode),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _VersionFooter(
          developerModeEnabled: developerMode.maybeWhen(
            data: (value) => value,
            orElse: () => false,
          ),
          onTap: () => _handleVersionTap(context),
        ),
      ],
    );
  }

  Future<void> _handleVersionTap(BuildContext context) async {
    versionTapCount += 1;
    if (versionTapCount < 5) {
      return;
    }
    versionTapCount = 0;
    final repository = ref.read(lunioRepositoryProvider);
    final enabled = ref
        .read(developerModeProvider)
        .maybeWhen(data: (value) => value, orElse: () => false);
    if (enabled) {
      await repository.setPreferenceValue('developerModeEnabled', 'false');
      await repository.setPreferenceValue('manualDateEnabled', 'false');
      await repository.setPreferenceValue('manualDate', null);
      invalidatePreferenceProviders(ref);
      if (context.mounted) {
        _showStatusOverlay(context, '开发者模式已关闭', _StatusOverlayTone.info);
      }
      return;
    }
    await repository.setPreferenceValue('developerModeEnabled', 'true');
    invalidatePreferenceProviders(ref);
    if (context.mounted) {
      _showStatusOverlay(context, '开发者模式已开启', _StatusOverlayTone.info);
    }
  }
}

String _notificationSettingsSubtitle(LunioNotificationSettings settings) {
  return '手机系统通知、应用内通知';
}

class _VersionFooter extends StatelessWidget {
  const _VersionFooter({
    required this.developerModeEnabled,
    required this.onTap,
  });

  final bool developerModeEnabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    return Center(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            developerModeEnabled ? '版本 1.0.0 · 开发者模式' : '版本 1.0.0',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: tokens.muted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileSettingRow extends StatelessWidget {
  const _ProfileSettingRow({
    required this.title,
    required this.subtitle,
    required this.trailingLabel,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String trailingLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: tokens.surface,
          borderRadius: BorderRadius.circular(tokens.radiusLarge),
          border: Border.all(color: tokens.line),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 5),
                  Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            const SizedBox(width: 12),
            TextButton(
              onPressed: onTap,
              style: TextButton.styleFrom(
                backgroundColor: tokens.surface2,
                foregroundColor: tokens.primary,
                minimumSize: const Size(0, 34),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(tokens.radiusSmall),
                  side: BorderSide(color: tokens.line),
                ),
              ),
              child: Text(trailingLabel),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThemeModeSettingRow extends StatelessWidget {
  const _ThemeModeSettingRow({required this.mode, required this.onChanged});

  final ThemeMode mode;
  final ValueChanged<ThemeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(tokens.radiusLarge),
        border: Border.all(color: tokens.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('主题模式', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          LunioSegmentedControl(
            values: const ['跟随系统', '浅色', '深色'],
            selectedIndex: switch (mode) {
              ThemeMode.light => 1,
              ThemeMode.dark => 2,
              ThemeMode.system => 0,
            },
            onSelected: (index) {
              final nextMode = switch (index) {
                1 => ThemeMode.light,
                2 => ThemeMode.dark,
                _ => ThemeMode.system,
              };
              if (nextMode == mode) {
                return;
              }
              onChanged(nextMode);
            },
          ),
        ],
      ),
    );
  }
}

class _VehicleList extends StatelessWidget {
  const _VehicleList({
    required this.cars,
    required this.appliedCarId,
    required this.today,
    required this.onAdd,
    required this.onEdit,
    required this.onManageItems,
    required this.onApply,
    required this.onDelete,
  });

  final List<Car> cars;
  final int? appliedCarId;
  final LocalDate today;
  final VoidCallback onAdd;
  final ValueChanged<Car> onEdit;
  final ValueChanged<Car> onManageItems;
  final ValueChanged<int> onApply;
  final ValueChanged<Car> onDelete;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    if (cars.isEmpty) {
      return _EmptyVehicleCard(onAdd: onAdd);
    }
    return Column(
      children: [
        for (final car in cars) ...[
          Builder(
            builder: (context) {
              final selected = car.id == appliedCarId;
              return LunioCard(
                backgroundColor: selected ? tokens.primarySoft : null,
                child: Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${car.brand} ${car.model}',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleMedium,
                                    ),
                                  ),
                                  if (selected)
                                    const LunioStatusBadge(
                                      label: '当前',
                                      tone: LunioStatusTone.normal,
                                    ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '${_formatMileageKm(car.currentMileageKm)} · ${car.roadDate} · ${_formatCarAge(car.roadDate, today)}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        _CarVisual(selected: selected),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _SmallActionButton(
                          label: selected ? '已应用' : '应用',
                          onPressed: car.id == null
                              ? null
                              : selected
                              ? null
                              : () => onApply(car.id!),
                        ),
                        const SizedBox(width: 8),
                        _SmallActionButton(
                          label: '编辑',
                          onPressed: () => onEdit(car),
                        ),
                        const SizedBox(width: 8),
                        _SmallActionButton(
                          label: '项目',
                          onPressed: () => onManageItems(car),
                        ),
                        const SizedBox(width: 8),
                        _SmallActionButton(
                          label: '删除',
                          danger: true,
                          onPressed: () => onDelete(car),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _CarVisual extends StatelessWidget {
  const _CarVisual({this.selected = false});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    return CustomPaint(
      size: const Size(70, 38),
      painter: _CarVisualPainter(
        bodyStart: tokens.primary,
        bodyEnd: tokens.primaryStrong,
        windowColor: selected ? tokens.surface : tokens.primarySoft,
        wheelColor: tokens.ink,
      ),
    );
  }
}

class _CarVisualPainter extends CustomPainter {
  const _CarVisualPainter({
    required this.bodyStart,
    required this.bodyEnd,
    required this.windowColor,
    required this.wheelColor,
  });

  final Color bodyStart;
  final Color bodyEnd;
  final Color windowColor;
  final Color wheelColor;

  @override
  void paint(Canvas canvas, Size size) {
    final bodyPaint = Paint()
      ..shader = LinearGradient(
        colors: [bodyStart, bodyEnd],
      ).createShader(Offset.zero & size);
    final windowPaint = Paint()..color = windowColor;
    final wheelPaint = Paint()..color = wheelColor;
    final body = RRect.fromRectAndCorners(
      Rect.fromLTWH(5, 12, 60, 18),
      topLeft: const Radius.circular(18),
      topRight: const Radius.circular(22),
      bottomLeft: const Radius.circular(10),
      bottomRight: const Radius.circular(10),
    );
    final window = RRect.fromRectAndCorners(
      Rect.fromLTWH(18, 7, 32, 18),
      topLeft: const Radius.circular(20),
      topRight: const Radius.circular(20),
      bottomLeft: const Radius.circular(6),
      bottomRight: const Radius.circular(6),
    );
    canvas
      ..drawRRect(body, bodyPaint)
      ..drawRRect(window, windowPaint)
      ..drawCircle(const Offset(18, 32), 5, wheelPaint)
      ..drawCircle(const Offset(57, 32), 5, wheelPaint);
  }

  @override
  bool shouldRepaint(_CarVisualPainter oldDelegate) {
    return bodyStart != oldDelegate.bodyStart ||
        bodyEnd != oldDelegate.bodyEnd ||
        windowColor != oldDelegate.windowColor ||
        wheelColor != oldDelegate.wheelColor;
  }
}

class _EmptyVehicleCard extends StatelessWidget {
  const _EmptyVehicleCard({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return LunioCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('还没有车辆', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 14),
          Tooltip(
            message: '新增车辆',
            child: LunioPrimaryButton(label: '新增车辆', onPressed: onAdd),
          ),
        ],
      ),
    );
  }
}

class _LoadingPage extends StatelessWidget {
  const _LoadingPage({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return LunioPage(
      title: title,
      children: const [Center(child: CircularProgressIndicator())],
    );
  }
}

class _ErrorPage extends StatelessWidget {
  const _ErrorPage({required this.title, required this.error});

  final String title;
  final Object error;

  @override
  Widget build(BuildContext context) {
    return LunioPage(
      title: title,
      children: [LunioCard(child: Text('加载失败：${_friendlyError(error)}'))],
    );
  }
}

class _AddCarForm extends StatefulWidget {
  const _AddCarForm({
    required this.vehicleModels,
    required this.today,
    this.initialCar,
    required this.onSubmit,
    this.submitLabel,
  });

  final List<VehicleModel> vehicleModels;
  final LocalDate today;
  final Car? initialCar;
  final Future<void> Function(Car car) onSubmit;
  final String? submitLabel;

  @override
  State<_AddCarForm> createState() => _AddCarFormState();
}

class _AddCarFormState extends State<_AddCarForm> {
  late String selectedBrand;
  late String selectedModel;
  late final TextEditingController mileageController;
  late LocalDate roadDate;
  String? errorText;
  bool saving = false;

  bool get isEditing => widget.initialCar?.id != null;

  @override
  void initState() {
    super.initState();
    final initialCar = widget.initialCar;
    final options = widget.vehicleModels;
    selectedBrand = initialCar?.brand ?? options.first.brand;
    selectedModel = initialCar?.model ?? _modelsForBrand(selectedBrand).first;
    mileageController = TextEditingController(
      text: initialCar?.currentMileageKm.toString() ?? '0',
    );
    roadDate = initialCar?.roadDate ?? widget.today;
  }

  @override
  void dispose() {
    mileageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isEditing)
          LunioPickerTile(
            label: '品牌车型',
            value: '${widget.initialCar!.brand} ${widget.initialCar!.model}',
            enabled: false,
            onTap: null,
          )
        else
          _VehicleModelPicker(
            vehicleModels: widget.vehicleModels,
            selectedBrand: selectedBrand,
            selectedModel: selectedModel,
            enabled: !saving,
            onSelected: (brand, model) {
              setState(() {
                selectedBrand = brand;
                selectedModel = model;
              });
            },
          ),
        const SizedBox(height: 10),
        TextField(
          controller: mileageController,
          enabled: !saving,
          keyboardType: TextInputType.text,
          textInputAction: TextInputAction.done,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onTap: () {
            if (!isEditing) {
              _clearZero(mileageController);
            }
          },
          onSubmitted: (_) => FocusScope.of(context).unfocus(),
          decoration: _numberInputDecoration(labelText: '当前里程'),
        ),
        const SizedBox(height: 10),
        LunioPickerTile(
          label: '上路日期',
          value: _formatDateForUser(roadDate),
          enabled: !saving,
          onTap: _pickRoadDate,
        ),
        if (errorText != null) ...[
          const SizedBox(height: 10),
          LunioInlineMessage(message: errorText!, tone: LunioStatusTone.danger),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: LunioSecondaryButton(
                label: '取消',
                onPressed: saving ? null : () => Navigator.of(context).pop(),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: LunioPrimaryButton(
                label: saving
                    ? '保存中'
                    : widget.submitLabel ?? (isEditing ? '保存车辆' : '保存车辆'),
                onPressed: saving ? null : _submit,
              ),
            ),
          ],
        ),
      ],
    );
  }

  List<String> _modelsForBrand(String brand) {
    return widget.vehicleModels
        .where((model) => model.brand == brand)
        .map((model) => model.model)
        .toList();
  }

  void _clearZero(TextEditingController controller) {
    if (controller.text == '0') {
      controller.clear();
    }
  }

  Future<void> _pickRoadDate() async {
    final picked = await _showSimpleDatePicker(
      context,
      initialDate: roadDate,
      firstDate: const LocalDate(1990, 1, 1),
      lastDate: LocalDate.fromDateTime(
        widget.today.toDateTime().add(const Duration(days: 365)),
      ),
      today: widget.today,
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() => roadDate = picked);
  }

  Future<void> _submit() async {
    final mileage = int.tryParse(mileageController.text);
    if (mileage == null || mileage < 0) {
      setState(() => errorText = '当前里程必须是非负整数');
      return;
    }
    final initialCar = widget.initialCar;
    setState(() {
      saving = true;
      errorText = null;
    });
    try {
      await widget.onSubmit(
        Car(
          id: initialCar?.id,
          brand: initialCar?.brand ?? selectedBrand,
          model: initialCar?.model ?? selectedModel,
          currentMileageKm: mileage,
          roadDate: roadDate,
          sync: SyncMetadata(
            status: isEditing
                ? SyncStatus.pendingUpdate
                : SyncStatus.pendingCreate,
            updatedAt: DateTime.now(),
          ),
        ),
      );
      if (mounted) {
        setState(() => saving = false);
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        saving = false;
        errorText = _friendlyError(error);
      });
    }
  }
}

class _AddCarWizard extends StatefulWidget {
  const _AddCarWizard({
    required this.vehicleModels,
    required this.today,
    required this.loadDefaultItems,
    required this.onMaintenanceStepChanged,
    required this.onSubmit,
  });

  final List<VehicleModel> vehicleModels;
  final LocalDate today;
  final Future<List<VehicleDefaultMaintenanceItem>> Function(Car car)
  loadDefaultItems;
  final ValueChanged<bool> onMaintenanceStepChanged;
  final Future<void> Function(Car car, List<MaintenanceItem> items) onSubmit;

  @override
  State<_AddCarWizard> createState() => _AddCarWizardState();
}

class _AddCarWizardState extends State<_AddCarWizard> {
  Car? carDraft;
  List<MaintenanceItem>? itemDrafts;
  List<VehicleDefaultMaintenanceItem>? defaultItemTemplates;
  String? itemModelKey;
  bool editingCarDraft = false;
  bool loadingItems = false;
  bool saving = false;
  String? errorText;

  @override
  Widget build(BuildContext context) {
    final car = carDraft;
    final items = itemDrafts;
    if (car == null || editingCarDraft) {
      return _AddCarForm(
        vehicleModels: widget.vehicleModels,
        today: widget.today,
        initialCar: carDraft,
        submitLabel: '下一步',
        onSubmit: _handleCarDraft,
      );
    }
    if (items == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return _AddCarMaintenanceItemsStep(
      car: car,
      items: items,
      saving: saving || loadingItems,
      errorText: errorText,
      onBack: saving ? null : _returnToCarStep,
      onChanged: (nextItems) => setState(() => itemDrafts = nextItems),
      onAdd: saving ? null : _addItem,
      onRestoreDefaults: saving ? null : () => _restoreDefaultItems(car, items),
      onSubmit: saving ? null : _submit,
    );
  }

  Future<void> _handleCarDraft(Car car) async {
    final nextKey = '${car.brand}\u0000${car.model}';
    widget.onMaintenanceStepChanged(true);
    setState(() {
      carDraft = car;
      editingCarDraft = false;
      loadingItems = itemModelKey != nextKey || itemDrafts == null;
      errorText = null;
    });
    if (!loadingItems) {
      return;
    }
    try {
      final defaultItems = await widget.loadDefaultItems(car);
      if (!mounted) {
        return;
      }
      setState(() {
        itemModelKey = nextKey;
        defaultItemTemplates = defaultItems;
        itemDrafts = defaultItems
            .map((item) => _maintenanceItemFromDefault(item, car.sync))
            .toList();
        loadingItems = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        carDraft = null;
        editingCarDraft = false;
        loadingItems = false;
        errorText = _friendlyError(error);
      });
      widget.onMaintenanceStepChanged(false);
    }
  }

  void _returnToCarStep() {
    widget.onMaintenanceStepChanged(false);
    setState(() => editingCarDraft = true);
  }

  Future<void> _submit() async {
    final car = carDraft;
    final items = itemDrafts;
    if (car == null || items == null) {
      return;
    }
    if (!items.any((item) => item.enabled)) {
      setState(() => errorText = '至少保留一个可用保养项目');
      return;
    }
    setState(() {
      saving = true;
      errorText = null;
    });
    try {
      await widget.onSubmit(car, items);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        saving = false;
        errorText = _friendlyError(error);
      });
    }
  }

  void _addItem() {
    final sync = SyncMetadata(
      status: SyncStatus.pendingCreate,
      updatedAt: DateTime.now(),
    );
    final item = MaintenanceItem(
      carsId: 0,
      name: '',
      enabled: true,
      remindByMileage: true,
      remindByTime: true,
      sortOrder: (itemDrafts?.length ?? 0) + 999,
      sync: sync,
    );
    _showDraftMaintenanceItemFormSheet(
      context,
      item: item,
      onSubmit: (nextItem) {
        setState(() {
          itemDrafts = [...?itemDrafts, nextItem];
        });
      },
    );
  }

  Future<void> _restoreDefaultItems(
    Car car,
    List<MaintenanceItem> items,
  ) async {
    final templates = defaultItemTemplates;
    if (templates == null || templates.isEmpty) {
      return;
    }
    final selected = await _showRestoreDefaultItemsSheet(
      context,
      defaultItems: templates,
      itemDrafts: items,
    );
    if (!mounted || selected == null || selected.isEmpty) {
      return;
    }
    setState(() {
      itemDrafts = [
        ...items,
        for (final item in selected)
          _maintenanceItemFromDefault(item, car.sync),
      ];
    });
  }
}

class _AddCarMaintenanceItemsStep extends StatelessWidget {
  const _AddCarMaintenanceItemsStep({
    required this.car,
    required this.items,
    required this.saving,
    required this.errorText,
    required this.onBack,
    required this.onChanged,
    required this.onAdd,
    required this.onRestoreDefaults,
    required this.onSubmit,
  });

  final Car car;
  final List<MaintenanceItem> items;
  final bool saving;
  final String? errorText;
  final VoidCallback? onBack;
  final ValueChanged<List<MaintenanceItem>> onChanged;
  final VoidCallback? onAdd;
  final VoidCallback? onRestoreDefaults;
  final VoidCallback? onSubmit;

  @override
  Widget build(BuildContext context) {
    final maxListHeight = MediaQuery.sizeOf(context).height * 0.42;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _ItemPills(labels: ['${car.brand} ${car.model}'])),
            const SizedBox(width: 12),
            _SmallActionButton(label: '新增', onPressed: onAdd, primary: true),
            const SizedBox(width: 8),
            _SmallActionButton(label: '恢复', onPressed: onRestoreDefaults),
          ],
        ),
        const SizedBox(height: 12),
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxListHeight),
          child: SingleChildScrollView(
            child: _MaintenanceItemList(
              items: items,
              onEdit: saving ? (_) {} : (item) => _editItem(context, item),
              onToggle: saving ? (_) {} : _toggleItem,
              onDelete: saving ? (_) {} : _deleteItem,
            ),
          ),
        ),
        if (errorText != null) ...[
          const SizedBox(height: 10),
          LunioInlineMessage(message: errorText!, tone: LunioStatusTone.danger),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: LunioSecondaryButton(label: '上一步', onPressed: onBack),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: LunioPrimaryButton(
                label: saving ? '保存中' : '保存车辆',
                onPressed: onSubmit,
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _editItem(BuildContext context, MaintenanceItem item) {
    _showDraftMaintenanceItemFormSheet(
      context,
      item: item,
      onSubmit: (nextItem) {
        onChanged([
          for (final current in items)
            if (identical(current, item)) nextItem else current,
        ]);
      },
    );
  }

  void _toggleItem(MaintenanceItem item) {
    final nextEnabled = !item.enabled;
    if (!nextEnabled &&
        items
            .where((current) => current.enabled && !identical(current, item))
            .isEmpty) {
      return;
    }
    onChanged([
      for (final current in items)
        if (identical(current, item))
          current.copyWith(enabled: nextEnabled)
        else
          current,
    ]);
  }

  void _deleteItem(MaintenanceItem item) {
    final nextItems = items
        .where((current) => !identical(current, item))
        .toList();
    if (!nextItems.any((current) => current.enabled)) {
      return;
    }
    onChanged(nextItems);
  }
}

Future<List<VehicleDefaultMaintenanceItem>?> _showRestoreDefaultItemsSheet(
  BuildContext context, {
  required List<VehicleDefaultMaintenanceItem> defaultItems,
  required List<MaintenanceItem> itemDrafts,
}) {
  return _showLunioModalSheet<List<VehicleDefaultMaintenanceItem>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return _PrototypeSheetFrame(
        title: '恢复默认项目',
        subtitle: '选择要补回的默认保养项目，保存车辆前只会更新当前页面配置',
        child: _RestoreDefaultItemsSheet(
          defaultItems: defaultItems,
          itemDrafts: itemDrafts,
        ),
      );
    },
  );
}

class _RestoreDefaultItemsSheet extends StatefulWidget {
  const _RestoreDefaultItemsSheet({
    required this.defaultItems,
    required this.itemDrafts,
  });

  final List<VehicleDefaultMaintenanceItem> defaultItems;
  final List<MaintenanceItem> itemDrafts;

  @override
  State<_RestoreDefaultItemsSheet> createState() =>
      _RestoreDefaultItemsSheetState();
}

class _RestoreDefaultItemsSheetState extends State<_RestoreDefaultItemsSheet> {
  late final Set<String> existingNames;
  late final Set<String> selectedNames;

  @override
  void initState() {
    super.initState();
    existingNames = widget.itemDrafts
        .map((item) => _normalizeItemName(item.name))
        .toSet();
    selectedNames = {
      for (final item in widget.defaultItems)
        if (!existingNames.contains(_normalizeItemName(item.itemName)))
          _normalizeItemName(item.itemName),
    };
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    final recoverableCount = widget.defaultItems
        .where(
          (item) => !existingNames.contains(_normalizeItemName(item.itemName)),
        )
        .length;
    final maxListHeight = MediaQuery.sizeOf(context).height * 0.42;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxListHeight),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final item in widget.defaultItems) ...[
                  _RestoreDefaultItemRow(
                    item: item,
                    selected: selectedNames.contains(
                      _normalizeItemName(item.itemName),
                    ),
                    enabled: !existingNames.contains(
                      _normalizeItemName(item.itemName),
                    ),
                    onChanged: (selected) => setState(() {
                      final key = _normalizeItemName(item.itemName);
                      if (selected) {
                        selectedNames.add(key);
                      } else {
                        selectedNames.remove(key);
                      }
                    }),
                  ),
                  if (item != widget.defaultItems.last)
                    const SizedBox(height: 8),
                ],
              ],
            ),
          ),
        ),
        if (recoverableCount == 0) ...[
          const SizedBox(height: 10),
          const LunioInlineMessage(message: '当前页面已包含全部默认项目'),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: LunioSecondaryButton(
                label: '取消',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: LunioPrimaryButton(
                label: '恢复',
                onPressed: selectedNames.isEmpty
                    ? null
                    : () {
                        Navigator.of(context).pop([
                          for (final item in widget.defaultItems)
                            if (selectedNames.contains(
                              _normalizeItemName(item.itemName),
                            ))
                              item,
                        ]);
                      },
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          '已存在的同名项目不会重复恢复',
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: tokens.subtle),
        ),
      ],
    );
  }
}

class _RestoreDefaultItemRow extends StatelessWidget {
  const _RestoreDefaultItemRow({
    required this.item,
    required this.selected,
    required this.enabled,
    required this.onChanged,
  });

  final VehicleDefaultMaintenanceItem item;
  final bool selected;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    return InkWell(
      onTap: enabled ? () => onChanged(!selected) : null,
      borderRadius: BorderRadius.circular(tokens.radiusMedium),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: enabled ? tokens.surface2 : tokens.surface3,
          borderRadius: BorderRadius.circular(tokens.radiusMedium),
          border: Border.all(color: tokens.line),
        ),
        child: Row(
          children: [
            Checkbox(
              value: enabled ? selected : false,
              onChanged: enabled ? (value) => onChanged(value ?? false) : null,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.itemName,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: enabled ? tokens.ink : tokens.muted,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _defaultItemRuleText(item),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: enabled ? tokens.muted : tokens.subtle,
                    ),
                  ),
                ],
              ),
            ),
            if (!enabled)
              Text(
                '已存在',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: tokens.subtle,
                  fontWeight: FontWeight.w700,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _VehicleModelPicker extends StatelessWidget {
  const _VehicleModelPicker({
    required this.vehicleModels,
    required this.selectedBrand,
    required this.selectedModel,
    required this.enabled,
    required this.onSelected,
  });

  final List<VehicleModel> vehicleModels;
  final String selectedBrand;
  final String selectedModel;
  final bool enabled;
  final void Function(String brand, String model) onSelected;

  @override
  Widget build(BuildContext context) {
    return LunioPickerTile(
      label: '品牌车型',
      value: '$selectedBrand $selectedModel',
      enabled: enabled,
      onTap: () async {
        final value = await _showVehicleModelPickerSheet(
          context,
          vehicleModels: vehicleModels,
          selectedBrand: selectedBrand,
          selectedModel: selectedModel,
        );
        if (value != null) {
          onSelected(value.$1, value.$2);
        }
      },
    );
  }
}

Future<(String, String)?> _showVehicleModelPickerSheet(
  BuildContext context, {
  required List<VehicleModel> vehicleModels,
  required String selectedBrand,
  required String selectedModel,
}) {
  return _showLunioModalSheet<(String, String)>(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    backgroundColor: Colors.transparent,
    builder: (context) => _PrototypeSheetFrame(
      title: '选择车型',
      subtitle: '选择车辆品牌和车型，默认保养项目会随车型创建',
      bottomInset: MediaQuery.of(context).viewInsets.bottom,
      child: _VehicleModelPickerSheet(
        vehicleModels: vehicleModels,
        selectedBrand: selectedBrand,
        selectedModel: selectedModel,
      ),
    ),
  );
}

class _VehicleModelPickerSheet extends StatefulWidget {
  const _VehicleModelPickerSheet({
    required this.vehicleModels,
    required this.selectedBrand,
    required this.selectedModel,
  });

  final List<VehicleModel> vehicleModels;
  final String selectedBrand;
  final String selectedModel;

  @override
  State<_VehicleModelPickerSheet> createState() =>
      _VehicleModelPickerSheetState();
}

class _VehicleModelPickerSheetState extends State<_VehicleModelPickerSheet> {
  final searchController = TextEditingController();
  late String selectedBrand;

  @override
  void initState() {
    super.initState();
    selectedBrand = widget.selectedBrand;
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    final keyword = searchController.text.trim();
    final filteredModels = keyword.isEmpty
        ? widget.vehicleModels
        : widget.vehicleModels
              .where(
                (model) => '${model.brand}${model.model}'.contains(keyword),
              )
              .toList();
    final brands = <String>[];
    for (final model in filteredModels) {
      if (!brands.contains(model.brand)) {
        brands.add(model.brand);
      }
    }
    if (!brands.contains(selectedBrand) && brands.isNotEmpty) {
      selectedBrand = brands.first;
    }
    final models = filteredModels
        .where((model) => model.brand == selectedBrand)
        .toList();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: searchController,
          decoration: const InputDecoration(
            labelText: '搜索品牌或车型',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 10),
        ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.48,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: tokens.surface2,
              borderRadius: BorderRadius.circular(tokens.radiusLarge),
              border: Border.all(color: tokens.line),
            ),
            child: brands.isEmpty
                ? Center(
                    child: Text(
                      '没有匹配车型',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  )
                : Row(
                    children: [
                      SizedBox(
                        width: 124,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(8),
                          itemCount: brands.length,
                          itemBuilder: (context, index) {
                            final brand = brands[index];
                            return _PickerOption(
                              label: brand,
                              selected: brand == selectedBrand,
                              enabled: true,
                              onTap: () => setState(() {
                                selectedBrand = brand;
                              }),
                            );
                          },
                        ),
                      ),
                      Container(width: 1, color: tokens.line),
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.all(8),
                          itemCount: models.length,
                          itemBuilder: (context, index) {
                            final model = models[index];
                            final selected =
                                model.brand == widget.selectedBrand &&
                                model.model == widget.selectedModel;
                            return _PickerOption(
                              label: model.model,
                              selected: selected,
                              enabled: true,
                              onTap: () => Navigator.of(
                                context,
                              ).pop((model.brand, model.model)),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

class _PickerOption extends StatelessWidget {
  const _PickerOption({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(tokens.radiusSmall),
      child: Container(
        height: 42,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        margin: const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(
          color: selected ? tokens.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(tokens.radiusSmall),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: selected ? tokens.primary : tokens.muted,
          ),
        ),
      ),
    );
  }
}

void _showAddCarSheet(BuildContext context, WidgetRef ref) {
  _showLunioModalSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    backgroundColor: Colors.transparent,
    builder: (context) {
      var isMaintenanceStep = false;
      return StatefulBuilder(
        builder: (context, setSheetState) {
          return _PrototypeSheetFrame(
            title: isMaintenanceStep ? '保养项目' : '添加车辆',
            subtitle: isMaintenanceStep ? '以下保养项目只做参考，具体以官方保养手册为准' : null,
            bottomInset: MediaQuery.of(context).viewInsets.bottom,
            child: Consumer(
              builder: (context, ref, child) {
                final vehicleModels = ref.watch(vehicleModelsProvider);
                final today = ref.watch(effectiveTodayProvider);
                if (vehicleModels.isLoading || today.isLoading) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (vehicleModels.hasError) {
                  return LunioInlineMessage(message: '车型加载失败，请稍后重试');
                }
                if (today.hasError) {
                  return LunioInlineMessage(message: '日期加载失败，请稍后重试');
                }
                return vehicleModels.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, stackTrace) =>
                      LunioInlineMessage(message: '车型加载失败，请稍后重试'),
                  data: (models) {
                    if (models.isEmpty) {
                      return const LunioInlineMessage(message: '暂无可选车型');
                    }
                    return _AddCarWizard(
                      vehicleModels: models,
                      today: today.value!,
                      loadDefaultItems: (car) async {
                        final repository = ref.read(lunioRepositoryProvider);
                        await repository.ensureBootstrapData();
                        return repository.listDefaultItemsForModel(
                          brand: car.brand,
                          model: car.model,
                        );
                      },
                      onMaintenanceStepChanged: (nextValue) {
                        if (isMaintenanceStep == nextValue) {
                          return;
                        }
                        setSheetState(() {
                          isMaintenanceStep = nextValue;
                        });
                      },
                      onSubmit: (car, items) async {
                        final repository = ref.read(lunioRepositoryProvider);
                        await repository.createCarWithMaintenanceItems(
                          car,
                          items,
                        );
                        invalidateVehicleProviders(ref);
                        if (context.mounted) {
                          Navigator.of(context).pop();
                        }
                      },
                    );
                  },
                );
              },
            ),
          );
        },
      );
    },
  );
}

void _showEditCarSheet(BuildContext context, WidgetRef ref, Car car) {
  _showLunioModalSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return _PrototypeSheetFrame(
        title: '编辑车辆',
        subtitle: '品牌车型保持稳定，可更新当前里程和上路日期',
        bottomInset: MediaQuery.of(context).viewInsets.bottom,
        child: Consumer(
          builder: (context, ref, child) {
            final vehicleModels = ref.watch(vehicleModelsProvider);
            final today = ref.watch(effectiveTodayProvider);
            if (vehicleModels.isLoading || today.isLoading) {
              return const Center(child: CircularProgressIndicator());
            }
            if (vehicleModels.hasError) {
              return LunioInlineMessage(message: '车型加载失败，请稍后重试');
            }
            if (today.hasError) {
              return LunioInlineMessage(message: '日期加载失败，请稍后重试');
            }
            return vehicleModels.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stackTrace) =>
                  LunioInlineMessage(message: '车型加载失败，请稍后重试'),
              data: (models) => _AddCarForm(
                vehicleModels: models.isEmpty
                    ? [
                        VehicleModel(
                          brand: car.brand,
                          model: car.model,
                          sortOrder: 0,
                          sync: SyncMetadata(
                            status: SyncStatus.synced,
                            updatedAt: DateTime.now(),
                          ),
                        ),
                      ]
                    : models,
                today: today.value!,
                initialCar: car,
                onSubmit: (updatedCar) async {
                  await ref.read(lunioRepositoryProvider).updateCar(updatedCar);
                  invalidateVehicleProviders(ref);
                  if (context.mounted) {
                    Navigator.of(context).pop();
                  }
                },
              ),
            );
          },
        ),
      );
    },
  );
}

void _showVehicleSwitcher(BuildContext context, WidgetRef ref) {
  final cars = ref
      .read(carsProvider)
      .maybeWhen(data: (value) => value, orElse: () => const <Car>[]);
  final appliedCarId = ref
      .read(appliedCarProvider)
      .maybeWhen(data: (value) => value?.id, orElse: () => null);
  if (cars.length <= 1) {
    _showStatusOverlay(
      context,
      cars.isEmpty ? '请先新增车辆' : '当前只有一辆车',
      _StatusOverlayTone.info,
    );
    return;
  }
  _showLunioModalSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return _PrototypeSheetFrame(
        title: '选择应用车辆',
        subtitle: '提醒、记录和新增保养记录会跟随当前车辆',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final car in cars) ...[
              _SwitchCarCard(
                car: car,
                selected: car.id == appliedCarId,
                onTap: car.id == null
                    ? null
                    : () async {
                        await _applyCar(context, ref, car.id!);
                        if (context.mounted) {
                          Navigator.of(context).pop();
                        }
                      },
              ),
              const SizedBox(height: 10),
            ],
          ],
        ),
      );
    },
  );
}

class _SwitchCarCard extends StatelessWidget {
  const _SwitchCarCard({
    required this.car,
    required this.selected,
    required this.onTap,
  });

  final Car car;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    return Material(
      color: selected ? tokens.primarySoft : tokens.surface,
      borderRadius: BorderRadius.circular(tokens.radiusLarge),
      child: InkWell(
        onTap: selected ? null : onTap,
        borderRadius: BorderRadius.circular(tokens.radiusLarge),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(tokens.radiusLarge),
            border: Border.all(color: selected ? tokens.primary : tokens.line),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${car.brand} ${car.model}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${_formatNumber(car.currentMileageKm)} km · ${car.roadDate} · ${selected ? "当前应用" : "点击切换"}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              const _CarVisual(),
            ],
          ),
        ),
      ),
    );
  }
}

class _MaintenanceRecordForm extends ConsumerStatefulWidget {
  const _MaintenanceRecordForm({
    required this.car,
    required this.items,
    required this.initialDate,
    required this.today,
    this.record,
    required this.reloadItems,
    required this.onSubmit,
  });

  final Car car;
  final List<MaintenanceItem> items;
  final LocalDate initialDate;
  final LocalDate today;
  final MaintenanceRecord? record;
  final Future<List<MaintenanceItem>> Function() reloadItems;
  final Future<void> Function(
    MaintenanceRecord record,
    List<MaintenanceItem> itemUpdates,
  )
  onSubmit;

  @override
  ConsumerState<_MaintenanceRecordForm> createState() =>
      _MaintenanceRecordFormState();
}

class _MaintenanceRecordFormState
    extends ConsumerState<_MaintenanceRecordForm> {
  late LocalDate recordDate;
  late final TextEditingController mileageController;
  late final TextEditingController costController;
  late final TextEditingController noteController;
  late final Set<int> selectedItemIds;
  late List<MaintenanceItem> formItems;
  MaintenanceRecord? recordDraft;
  final intervalDrafts = <_RecordIntervalDraft>[];
  bool saving = false;
  String? errorText;

  bool get isEditing => widget.record != null;

  @override
  void initState() {
    super.initState();
    final record = widget.record;
    recordDate = record?.date ?? widget.initialDate;
    mileageController = TextEditingController(
      text: (record?.mileageKm ?? widget.car.currentMileageKm).toString(),
    );
    costController = TextEditingController(
      text: record == null ? '0' : (record.costCents / 100).toStringAsFixed(2),
    );
    noteController = TextEditingController(text: record?.note ?? '');
    selectedItemIds = {...?record?.itemIds};
    formItems = widget.items;
  }

  @override
  void dispose() {
    _disposeIntervalDrafts();
    mileageController.dispose();
    costController.dispose();
    noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (recordDraft != null) {
      return _buildIntervalStep(context);
    }
    final availableItems = widget.record == null
        ? formItems.where((item) => item.enabled).toList()
        : formItems
              .where(
                (item) => item.enabled || selectedItemIds.contains(item.id),
              )
              .toList();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LunioPickerTile(
          label: '保养日期',
          value: _formatDateForUser(recordDate),
          enabled: !saving,
          onTap: _pickRecordDate,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: mileageController,
                enabled: !saving,
                keyboardType: TextInputType.text,
                textInputAction: TextInputAction.done,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onTap: () {
                  if (!isEditing) {
                    _clearZero(mileageController);
                  }
                },
                onSubmitted: (_) => FocusScope.of(context).unfocus(),
                decoration: _numberInputDecoration(labelText: '保养里程'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: costController,
                enabled: !saving,
                keyboardType: TextInputType.text,
                textInputAction: TextInputAction.done,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                onTap: () {
                  _clearZero(costController);
                },
                onSubmitted: (_) => FocusScope.of(context).unfocus(),
                decoration: _numberInputDecoration(labelText: '费用'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          controller: noteController,
          enabled: !saving,
          minLines: 2,
          maxLines: 3,
          decoration: const InputDecoration(labelText: '备注'),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                '保养项目',
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
            _SmallActionButton(
              label: '新增',
              primary: true,
              onPressed: saving ? null : _addMaintenanceItem,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final item in availableItems)
              _ChoiceChipButton(
                label: item.enabled ? item.name : '${item.name}（已禁用）',
                selected: item.id != null && selectedItemIds.contains(item.id),
                enabled: !saving && item.id != null,
                onTap: () {
                  setState(() {
                    if (selectedItemIds.contains(item.id)) {
                      selectedItemIds.remove(item.id);
                    } else {
                      selectedItemIds.add(item.id!);
                    }
                  });
                },
              ),
          ],
        ),
        if (errorText != null) ...[
          const SizedBox(height: 10),
          LunioInlineMessage(message: errorText!, tone: LunioStatusTone.danger),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: LunioSecondaryButton(
                label: '取消',
                onPressed: saving ? null : () => Navigator.of(context).pop(),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: LunioPrimaryButton(
                label: '下一步',
                onPressed: saving ? null : _goToIntervalStep,
              ),
            ),
          ],
        ),
      ],
    );
  }

  MaintenanceRecord? _buildRecordDraft() {
    final mileage = int.tryParse(mileageController.text);
    final cost = double.tryParse(costController.text);
    if (mileage == null || mileage < 0) {
      setState(() => errorText = '保养里程必须是非负整数');
      return null;
    }
    if (cost == null || cost < 0) {
      setState(() => errorText = '费用必须是非负数字');
      return null;
    }
    if (selectedItemIds.isEmpty) {
      setState(() => errorText = '至少选择一个保养项目');
      return null;
    }

    return MaintenanceRecord(
      id: widget.record?.id,
      carId: widget.car.id!,
      date: recordDate,
      itemIds: selectedItemIds.toList(),
      costCents: (cost * 100).round(),
      mileageKm: mileage,
      note: noteController.text.trim().isEmpty
          ? null
          : noteController.text.trim(),
      sync: SyncMetadata(
        status: isEditing ? SyncStatus.pendingUpdate : SyncStatus.pendingCreate,
        updatedAt: DateTime.now(),
      ),
    );
  }

  void _goToIntervalStep() {
    final draft = _buildRecordDraft();
    if (draft == null) {
      return;
    }
    final selectedItems = formItems
        .where((item) => item.id != null && selectedItemIds.contains(item.id))
        .toList();
    if (selectedItems.isEmpty) {
      setState(() => errorText = '至少选择一个保养项目');
      return;
    }
    _disposeIntervalDrafts();
    intervalDrafts.addAll(
      selectedItems.map((item) => _RecordIntervalDraft(item: item)),
    );
    setState(() {
      recordDraft = draft;
      errorText = null;
    });
  }

  Widget _buildIntervalStep(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('确认下次提醒间隔', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        Text(
          '保存后会同时更新本次保养项目的默认提醒间隔。',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        for (final draft in intervalDrafts) ...[
          Text(draft.item.name, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          if (draft.item.remindByMileage) ...[
            _RecordIntervalInputRow(
              title: '按里程提醒',
              controller: draft.mileageController,
              unit: 'km',
              enabled: !saving,
            ),
            const SizedBox(height: 10),
          ],
          if (draft.item.remindByTime) ...[
            _RecordIntervalInputRow(
              title: '按时间提醒',
              controller: draft.monthsController,
              unit: '月',
              enabled: !saving,
            ),
            const SizedBox(height: 10),
          ],
        ],
        if (errorText != null) ...[
          const SizedBox(height: 2),
          LunioInlineMessage(message: errorText!, tone: LunioStatusTone.danger),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: LunioSecondaryButton(
                label: '上一步',
                onPressed: saving
                    ? null
                    : () {
                        _disposeIntervalDrafts();
                        setState(() {
                          recordDraft = null;
                          errorText = null;
                        });
                      },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: LunioPrimaryButton(
                label: saving ? '保存中' : '保存记录',
                onPressed: saving ? null : _submit,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _submit() async {
    final draft = recordDraft;
    if (draft == null) {
      _goToIntervalStep();
      return;
    }
    final itemUpdates = _buildItemUpdates();
    if (itemUpdates == null) {
      return;
    }
    setState(() {
      saving = true;
      errorText = null;
    });
    try {
      await widget.onSubmit(draft, itemUpdates);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        saving = false;
        errorText = _friendlyError(error);
      });
    }
  }

  List<MaintenanceItem>? _buildItemUpdates() {
    final updates = <MaintenanceItem>[];
    for (final draft in intervalDrafts) {
      final item = draft.item;
      final mileageInterval = item.remindByMileage
          ? int.tryParse(draft.mileageController.text)
          : item.mileageIntervalKm;
      final timeInterval = item.remindByTime
          ? int.tryParse(draft.monthsController.text)
          : item.timeIntervalMonths;

      if (item.remindByMileage &&
          (mileageInterval == null || mileageInterval <= 0)) {
        setState(() => errorText = '${item.name} 的里程间隔必须填写正整数');
        return null;
      }
      if (item.remindByTime && (timeInterval == null || timeInterval <= 0)) {
        setState(() => errorText = '${item.name} 的时间间隔必须填写正整数');
        return null;
      }
      if (mileageInterval == item.mileageIntervalKm &&
          timeInterval == item.timeIntervalMonths) {
        continue;
      }
      updates.add(
        MaintenanceItem(
          id: item.id,
          carsId: item.carsId,
          name: item.name,
          enabled: item.enabled,
          remindByMileage: item.remindByMileage,
          remindByTime: item.remindByTime,
          mileageIntervalKm: item.remindByMileage ? mileageInterval : null,
          timeIntervalMonths: item.remindByTime ? timeInterval : null,
          notOverdueUpperLimit: item.notOverdueUpperLimit,
          overdueUpperLimit: item.overdueUpperLimit,
          sortOrder: item.sortOrder,
          sync: SyncMetadata(
            status: SyncStatus.pendingUpdate,
            updatedAt: DateTime.now(),
          ),
        ),
      );
    }
    return updates;
  }

  Future<void> _addMaintenanceItem() async {
    final beforeIds = formItems.map((item) => item.id).whereType<int>().toSet();
    final saved = await _showMaintenanceItemFormSheet(
      context,
      ref,
      carId: widget.car.id!,
    );
    if (saved != true || !mounted) {
      return;
    }
    final refreshedItems = await widget.reloadItems();
    if (!mounted) {
      return;
    }
    MaintenanceItem? newItem;
    for (final item in refreshedItems) {
      if (item.id != null && !beforeIds.contains(item.id)) {
        newItem = item;
        break;
      }
    }
    setState(() {
      formItems = refreshedItems;
      if (newItem?.id != null) {
        selectedItemIds.add(newItem!.id!);
      }
    });
  }

  void _clearZero(TextEditingController controller) {
    if (controller.text == '0' || controller.text == '0.00') {
      controller.clear();
    }
  }

  void _disposeIntervalDrafts() {
    for (final draft in intervalDrafts) {
      draft.dispose();
    }
    intervalDrafts.clear();
  }

  Future<void> _pickRecordDate() async {
    final picked = await _showSimpleDatePicker(
      context,
      initialDate: recordDate,
      firstDate: widget.car.roadDate,
      lastDate: LocalDate.fromDateTime(
        widget.today.toDateTime().add(const Duration(days: 365)),
      ),
      today: widget.today,
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() => recordDate = picked);
  }
}

class _RecordIntervalDraft {
  _RecordIntervalDraft({required this.item})
    : mileageController = TextEditingController(
        text: item.remindByMileage
            ? (item.mileageIntervalKm ?? 5000).toString()
            : '',
      ),
      monthsController = TextEditingController(
        text: item.remindByTime
            ? (item.timeIntervalMonths ?? 1).toString()
            : '',
      );

  final MaintenanceItem item;
  final TextEditingController mileageController;
  final TextEditingController monthsController;

  void dispose() {
    mileageController.dispose();
    monthsController.dispose();
  }
}

class _RecordIntervalInputRow extends StatelessWidget {
  const _RecordIntervalInputRow({
    required this.title,
    required this.controller,
    required this.unit,
    required this.enabled,
  });

  final String title;
  final TextEditingController controller;
  final String unit;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    return Container(
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: tokens.surface2,
        borderRadius: BorderRadius.circular(tokens.radiusMedium),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: enabled ? tokens.ink : tokens.subtle,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 116,
            child: TextField(
              controller: controller,
              enabled: enabled,
              keyboardType: TextInputType.text,
              textInputAction: TextInputAction.done,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onSubmitted: (_) => FocusScope.of(context).unfocus(),
              textAlign: TextAlign.center,
              decoration: _numberInputDecoration(suffixText: unit).copyWith(
                fillColor: enabled
                    ? tokens.surface
                    : tokens.surface3.withValues(alpha: 0.55),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                constraints: const BoxConstraints(minHeight: 46),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _showMaintenanceRecordFormSheet(
  BuildContext context,
  WidgetRef ref, {
  MaintenanceRecord? record,
}) async {
  final car = await ref.read(appliedCarProvider.future);
  final items = await ref.read(appliedCarMaintenanceItemsProvider.future);
  final today = await ref.read(effectiveTodayProvider.future);
  if (!context.mounted) {
    return;
  }
  if (car?.id == null) {
    _showStatusOverlay(context, '请先新增车辆', _StatusOverlayTone.info);
    return;
  }
  if (items
      .where(
        (item) => item.enabled || record?.itemIds.contains(item.id) == true,
      )
      .isEmpty) {
    _showStatusOverlay(context, '请先配置可用保养项目', _StatusOverlayTone.info);
    return;
  }
  _showLunioModalSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return _PrototypeSheetFrame(
        title: record == null ? '新增保养记录' : '编辑保养记录',
        subtitle: '${car!.brand} ${car.model}',
        bottomInset: MediaQuery.of(context).viewInsets.bottom,
        child: _MaintenanceRecordForm(
          car: car,
          items: items,
          initialDate: today,
          today: today,
          record: record,
          reloadItems: () => ref
              .read(lunioRepositoryProvider)
              .listMaintenanceItemsForCar(car.id!),
          onSubmit: (value, itemUpdates) async {
            final repository = ref.read(lunioRepositoryProvider);
            if (value.id == null) {
              await repository.saveMaintenanceRecordWithItemUpdates(
                record: value,
                itemUpdates: itemUpdates,
              );
            } else {
              await repository.updateMaintenanceRecordWithItemUpdates(
                record: value,
                itemUpdates: itemUpdates,
              );
            }
            invalidateVehicleProviders(ref);
            if (context.mounted) {
              Navigator.of(context).pop();
            }
          },
        ),
      );
    },
  );
}

Future<void> _deleteMaintenanceRecord(
  BuildContext context,
  WidgetRef ref,
  MaintenanceRecord record,
) async {
  final confirmed = await _showConfirmDialog(
    context: context,
    title: '删除保养记录',
    message: '确定删除 ${record.date} 的保养记录？',
    confirmLabel: '删除',
  );
  if (confirmed != true || record.id == null) {
    return;
  }
  await ref.read(lunioRepositoryProvider).deleteMaintenanceRecord(record.id!);
  invalidateVehicleProviders(ref);
}

Future<void> _deleteMaintenanceRecordItem(
  BuildContext context,
  WidgetRef ref,
  MaintenanceRecord record,
  int itemId,
) async {
  final itemName = ref
      .read(appliedCarMaintenanceItemsProvider)
      .maybeWhen(
        data: (items) => _itemById(items, itemId)?.name,
        orElse: () => null,
      );
  final confirmed = await _showConfirmDialog(
    context: context,
    title: '删除保养项目',
    message: '确定从 ${record.date} 的保养记录中删除 ${itemName ?? '该项目'}？',
    confirmLabel: '删除',
  );
  if (confirmed != true || record.id == null) {
    return;
  }
  await ref
      .read(lunioRepositoryProvider)
      .removeMaintenanceRecordItem(recordId: record.id!, itemId: itemId);
  invalidateVehicleProviders(ref);
}

void _showMaintenanceItemsSheet(
  BuildContext context,
  WidgetRef ref, {
  Car? car,
}) {
  _showLunioModalSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    backgroundColor: Colors.transparent,
    builder: (context) => _MaintenanceItemsSheetRoute(car: car),
  );
}

class _MaintenanceItemsSheetRoute extends StatefulWidget {
  const _MaintenanceItemsSheetRoute({required this.car});

  final Car? car;

  @override
  State<_MaintenanceItemsSheetRoute> createState() =>
      _MaintenanceItemsSheetRouteState();
}

class _MaintenanceItemsSheetRouteState
    extends State<_MaintenanceItemsSheetRoute> {
  final refreshListenable = ValueNotifier<int>(0);

  @override
  void dispose() {
    refreshListenable.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _PrototypeSheetFrame(
      title: '保养项目',
      child: _MaintenanceItemsSheetContent(
        initialCar: widget.car,
        refreshListenable: refreshListenable,
      ),
    );
  }
}

class _MaintenanceItemsSheetContent extends ConsumerStatefulWidget {
  const _MaintenanceItemsSheetContent({
    required this.initialCar,
    required this.refreshListenable,
  });

  final Car? initialCar;
  final ValueNotifier<int> refreshListenable;

  @override
  ConsumerState<_MaintenanceItemsSheetContent> createState() =>
      _MaintenanceItemsSheetContentState();
}

class _MaintenanceItemsSheetContentState
    extends ConsumerState<_MaintenanceItemsSheetContent> {
  final scrollController = ScrollController();
  List<MaintenanceItem>? items;
  bool itemsLoading = false;
  String? itemsError;
  int? loadedCarId;
  int loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    widget.refreshListenable.addListener(_handleExternalRefresh);
  }

  @override
  void didUpdateWidget(_MaintenanceItemsSheetContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshListenable == widget.refreshListenable) {
      return;
    }
    oldWidget.refreshListenable.removeListener(_handleExternalRefresh);
    widget.refreshListenable.addListener(_handleExternalRefresh);
  }

  @override
  void dispose() {
    widget.refreshListenable.removeListener(_handleExternalRefresh);
    scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final targetCar =
        widget.initialCar ??
        ref
            .watch(appliedCarProvider)
            .maybeWhen(data: (value) => value, orElse: () => null);
    if (targetCar?.id == null) {
      return const LunioInlineMessage(message: '请先新增车辆');
    }
    _ensureItemsLoaded(targetCar!.id!);
    final maxListHeight = MediaQuery.sizeOf(context).height * 0.54;
    final currentItems = items;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _ItemPills(
                labels: ['${targetCar.brand} ${targetCar.model}'],
              ),
            ),
            const SizedBox(width: 12),
            _SmallActionButton(
              label: '新增',
              onPressed: () async {
                final saved = await _showMaintenanceItemFormSheet(
                  context,
                  ref,
                  carId: targetCar.id!,
                );
                if (saved == true) {
                  widget.refreshListenable.value += 1;
                }
              },
              primary: true,
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (itemsLoading && currentItems == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 28),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (itemsError != null && currentItems == null)
          Text('加载失败：$itemsError')
        else ...[
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxListHeight),
            child: SingleChildScrollView(
              controller: scrollController,
              child: _MaintenanceItemList(
                items: currentItems ?? const [],
                onEdit: (item) async {
                  final saved = await _showMaintenanceItemFormSheet(
                    context,
                    ref,
                    carId: item.carsId,
                    item: item,
                  );
                  if (saved == true) {
                    await _reload(targetCar.id!);
                  }
                },
                onToggle: (item) async {
                  await _toggleMaintenanceItem(context, ref, item);
                  await _reload(targetCar.id!);
                },
                onDelete: (item) async {
                  await _deleteMaintenanceItem(context, ref, item);
                  await _reload(targetCar.id!);
                },
              ),
            ),
          ),
          if (itemsError != null) ...[
            const SizedBox(height: 10),
            LunioInlineMessage(
              message: '刷新失败：$itemsError',
              tone: LunioStatusTone.danger,
            ),
          ],
        ],
      ],
    );
  }

  void _ensureItemsLoaded(int carId) {
    if (loadedCarId == carId && (items != null || itemsLoading)) {
      return;
    }
    loadedCarId = carId;
    items = null;
    itemsError = null;
    itemsLoading = true;
    _loadItems(carId, resetScroll: true);
  }

  Future<void> _reload(int carId) async {
    if (!mounted) {
      return;
    }
    setState(() {
      loadedCarId = carId;
      itemsError = null;
      itemsLoading = items == null;
    });
    await _loadItems(carId);
  }

  void _handleExternalRefresh() {
    final carId = loadedCarId;
    if (carId == null) {
      return;
    }
    unawaited(_reload(carId));
  }

  Future<void> _loadItems(int carId, {bool resetScroll = false}) async {
    final generation = ++loadGeneration;
    try {
      final nextItems = await ref
          .read(lunioRepositoryProvider)
          .listMaintenanceItemsForCar(carId);
      if (!mounted || generation != loadGeneration || loadedCarId != carId) {
        return;
      }
      setState(() {
        items = nextItems;
        itemsError = null;
        itemsLoading = false;
      });
      if (resetScroll && scrollController.hasClients) {
        scrollController.jumpTo(0);
      }
    } catch (error) {
      if (!mounted || generation != loadGeneration || loadedCarId != carId) {
        return;
      }
      setState(() {
        itemsError = _friendlyError(error);
        itemsLoading = false;
      });
    }
  }
}

class _MaintenanceItemList extends StatelessWidget {
  const _MaintenanceItemList({
    required this.items,
    required this.onEdit,
    required this.onToggle,
    required this.onDelete,
  });

  final List<MaintenanceItem> items;
  final ValueChanged<MaintenanceItem> onEdit;
  final ValueChanged<MaintenanceItem> onToggle;
  final ValueChanged<MaintenanceItem> onDelete;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(
        child: Text('暂无保养项目', style: Theme.of(context).textTheme.bodyMedium),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final item in items) ...[
          _MaintenanceItemCard(
            item: item,
            onEdit: () => onEdit(item),
            onToggle: () => onToggle(item),
            onDelete: () => onDelete(item),
          ),
          if (item != items.last) const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _MaintenanceItemCard extends StatelessWidget {
  const _MaintenanceItemCard({
    required this.item,
    required this.onEdit,
    required this.onToggle,
    required this.onDelete,
  });

  final MaintenanceItem item;
  final VoidCallback onEdit;
  final VoidCallback onToggle;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    final actions = Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        _SmallActionButton(label: '编辑', onPressed: onEdit, secondary: true),
        const SizedBox(width: 8),
        _SmallActionButton(
          label: item.enabled ? '已启用' : '已禁用',
          onPressed: onToggle,
          primary: item.enabled,
          muted: !item.enabled,
        ),
        if (onDelete != null) ...[
          const SizedBox(width: 8),
          _SmallActionButton(
            label: '删除',
            tooltip: '删除',
            onPressed: onDelete,
            danger: true,
          ),
        ],
      ],
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(tokens.radiusLarge),
        border: Border.all(color: tokens.line),
        boxShadow: [
          BoxShadow(
            color: tokens.ink.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(item.name, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 5),
          Text(
            _itemRuleText(item),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 10),
          Align(alignment: Alignment.centerRight, child: actions),
        ],
      ),
    );
  }
}

class _MaintenanceItemForm extends StatefulWidget {
  const _MaintenanceItemForm({
    required this.carId,
    this.item,
    required this.onSubmit,
  });

  final int carId;
  final MaintenanceItem? item;
  final Future<void> Function(MaintenanceItem item) onSubmit;

  @override
  State<_MaintenanceItemForm> createState() => _MaintenanceItemFormState();
}

class _MaintenanceItemFormState extends State<_MaintenanceItemForm> {
  late final TextEditingController nameController;
  late final TextEditingController mileageController;
  late final TextEditingController monthsController;
  bool remindByMileage = true;
  bool remindByTime = true;
  bool enabled = true;
  bool saving = false;
  String? errorText;

  bool get isEditing => widget.item != null;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    nameController = TextEditingController(text: item?.name ?? '');
    mileageController = TextEditingController(
      text: item?.mileageIntervalKm?.toString() ?? '',
    );
    monthsController = TextEditingController(
      text: item?.timeIntervalMonths?.toString() ?? '',
    );
    remindByMileage = item?.remindByMileage ?? true;
    remindByTime = item?.remindByTime ?? true;
    enabled = item?.enabled ?? true;
  }

  @override
  void dispose() {
    nameController.dispose();
    mileageController.dispose();
    monthsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: nameController,
          enabled: !saving,
          decoration: const InputDecoration(labelText: '项目名称'),
        ),
        const SizedBox(height: 10),
        _ReminderRuleInputRow(
          title: '按里程提醒',
          value: remindByMileage,
          controller: mileageController,
          unit: 'km',
          onChanged: saving
              ? null
              : (value) => setState(() => remindByMileage = value),
        ),
        const SizedBox(height: 10),
        _ReminderRuleInputRow(
          title: '按时间提醒',
          value: remindByTime,
          controller: monthsController,
          unit: '月',
          onChanged: saving
              ? null
              : (value) => setState(() => remindByTime = value),
        ),
        if (errorText != null) ...[
          const SizedBox(height: 10),
          LunioInlineMessage(message: errorText!, tone: LunioStatusTone.danger),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: LunioSecondaryButton(
                label: '取消',
                onPressed: saving ? null : () => Navigator.of(context).pop(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: LunioPrimaryButton(
                label: saving ? '保存中' : '保存项目',
                onPressed: saving ? null : _submit,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _submit() async {
    final name = nameController.text.trim();
    final mileageInterval = int.tryParse(mileageController.text);
    final timeInterval = int.tryParse(monthsController.text);
    if (name.isEmpty) {
      setState(() => errorText = '项目名称不能为空');
      return;
    }
    if (!remindByMileage && !remindByTime) {
      setState(() => errorText = '至少选择一种提醒方式');
      return;
    }
    if (remindByMileage && (mileageInterval == null || mileageInterval <= 0)) {
      setState(() => errorText = '里程间隔必须填写正整数');
      return;
    }
    if (remindByTime && (timeInterval == null || timeInterval <= 0)) {
      setState(() => errorText = '时间间隔必须填写正整数');
      return;
    }
    setState(() {
      saving = true;
      errorText = null;
    });
    final item = widget.item;
    try {
      await widget.onSubmit(
        MaintenanceItem(
          id: item?.id,
          carsId: widget.carId,
          name: name,
          enabled: enabled,
          remindByMileage: remindByMileage,
          remindByTime: remindByTime,
          mileageIntervalKm: remindByMileage ? mileageInterval : null,
          timeIntervalMonths: remindByTime ? timeInterval : null,
          notOverdueUpperLimit: item?.notOverdueUpperLimit ?? 100,
          overdueUpperLimit: item?.overdueUpperLimit ?? 125,
          sortOrder: item?.sortOrder ?? 999,
          sync: SyncMetadata(
            status: isEditing
                ? SyncStatus.pendingUpdate
                : SyncStatus.pendingCreate,
            updatedAt: DateTime.now(),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        saving = false;
        errorText = _friendlyError(error);
      });
    }
  }
}

class _ReminderRuleInputRow extends StatelessWidget {
  const _ReminderRuleInputRow({
    required this.title,
    required this.value,
    required this.controller,
    required this.unit,
    required this.onChanged,
  });

  final String title;
  final bool value;
  final TextEditingController controller;
  final String unit;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    return Container(
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: tokens.surface2,
        borderRadius: BorderRadius.circular(tokens.radiusMedium),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: onChanged == null ? tokens.subtle : tokens.ink,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 116,
            child: TextField(
              controller: controller,
              enabled: value && onChanged != null,
              keyboardType: TextInputType.text,
              textInputAction: TextInputAction.done,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onSubmitted: (_) => FocusScope.of(context).unfocus(),
              textAlign: TextAlign.center,
              decoration: _numberInputDecoration(suffixText: unit).copyWith(
                fillColor: value
                    ? tokens.surface
                    : tokens.surface3.withValues(alpha: 0.55),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                constraints: const BoxConstraints(minHeight: 46),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

Future<bool?> _showMaintenanceItemFormSheet(
  BuildContext context,
  WidgetRef ref, {
  required int carId,
  MaintenanceItem? item,
}) {
  return _showLunioModalSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return _PrototypeSheetFrame(
        title: item == null ? '新增保养项目' : '编辑保养项目',
        bottomInset: MediaQuery.of(context).viewInsets.bottom,
        child: _MaintenanceItemForm(
          carId: carId,
          item: item,
          onSubmit: (value) async {
            final repository = ref.read(lunioRepositoryProvider);
            if (value.id == null) {
              await repository.saveMaintenanceItem(value);
            } else {
              await repository.updateMaintenanceItem(value);
            }
            invalidateVehicleProviders(ref);
            if (context.mounted) {
              Navigator.of(context).pop(true);
            }
          },
        ),
      );
    },
  );
}

Future<bool?> _showDraftMaintenanceItemFormSheet(
  BuildContext context, {
  required MaintenanceItem item,
  required ValueChanged<MaintenanceItem> onSubmit,
}) {
  return _showLunioModalSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return _PrototypeSheetFrame(
        title: item.name.isEmpty ? '新增保养项目' : '编辑保养项目',
        bottomInset: MediaQuery.of(context).viewInsets.bottom,
        child: _MaintenanceItemForm(
          carId: 0,
          item: item,
          onSubmit: (value) async {
            onSubmit(value);
            if (context.mounted) {
              Navigator.of(context).pop(true);
            }
          },
        ),
      );
    },
  );
}

Future<void> _toggleMaintenanceItem(
  BuildContext context,
  WidgetRef ref,
  MaintenanceItem item,
) async {
  final nextEnabled = !item.enabled;
  try {
    await ref
        .read(lunioRepositoryProvider)
        .setMaintenanceItemEnabled(
          itemId: item.id!,
          enabled: nextEnabled,
          sync: SyncMetadata(
            status: SyncStatus.pendingUpdate,
            updatedAt: DateTime.now(),
          ),
        );
    invalidateVehicleProviders(ref);
  } catch (error) {
    if (context.mounted) {
      _showStatusOverlay(
        context,
        _friendlyError(error),
        _StatusOverlayTone.error,
      );
    }
  }
}

Future<void> _deleteMaintenanceItem(
  BuildContext context,
  WidgetRef ref,
  MaintenanceItem item,
) async {
  final confirmed = await _showConfirmDialog(
    context: context,
    title: '删除保养项目',
    message: '确定删除 ${item.name}？有历史记录的项目不能删除。',
    confirmLabel: '删除',
  );
  if (confirmed != true || item.id == null) {
    return;
  }
  try {
    await ref.read(lunioRepositoryProvider).deleteMaintenanceItem(item.id!);
    invalidateVehicleProviders(ref);
  } catch (error) {
    if (context.mounted) {
      _showStatusOverlay(
        context,
        _friendlyError(error),
        _StatusOverlayTone.error,
      );
    }
  }
}

Future<void> _exportBackup(BuildContext context, WidgetRef ref) async {
  try {
    final payload = await ref
        .read(lunioRepositoryProvider)
        .exportBackupPayload();
    const codec = BackupCodec();
    final json = codec.encode(payload);
    final saved = await NativeFiles.exportJsonFile(
      filename: _backupFilename(DateTime.now()),
      content: json,
    );
    if (saved && context.mounted) {
      _showStatusOverlay(context, '备份完成', _StatusOverlayTone.success);
    }
  } catch (error) {
    if (context.mounted) {
      _showStatusOverlay(context, '备份失败：$error', _StatusOverlayTone.error);
    }
  }
}

Future<void> _restoreBackupFromFile(BuildContext context, WidgetRef ref) async {
  final confirmed = await _showConfirmDialog(
    context: context,
    title: '恢复数据',
    message: '恢复会先清空本地车辆、保养项目、保养记录和偏好，再写入备份文件中的数据。该操作不可撤销。',
    confirmLabel: '恢复',
  );
  if (confirmed != true) {
    return;
  }
  try {
    final json = await NativeFiles.pickJsonFile();
    if (json == null) {
      return;
    }
    const codec = BackupCodec();
    final payload = codec.decode(json);
    _notificationSyncGeneration++;
    await ref.read(lunioRepositoryProvider).restoreBackupPayload(payload);
    invalidateAllAppDataProviders(ref);
    if (context.mounted) {
      _showStatusOverlay(context, '恢复完成', _StatusOverlayTone.success);
    }
  } catch (error) {
    if (context.mounted) {
      if (_isUniqueConstraintError(error)) {
        await _showMessageDialog(
          context: context,
          title: '恢复失败',
          message: '恢复文件中的部分数据重复或冲突，本次恢复未写入任何数据。',
          tone: _StatusOverlayTone.error,
        );
      } else {
        _showStatusOverlay(context, '恢复失败：$error', _StatusOverlayTone.error);
      }
    }
  }
}

String _backupFilename(DateTime dateTime) {
  String twoDigits(int value) => value.toString().padLeft(2, '0');
  return 'lunio-backup-'
      '${dateTime.year}'
      '${twoDigits(dateTime.month)}'
      '${twoDigits(dateTime.day)}-'
      '${twoDigits(dateTime.hour)}'
      '${twoDigits(dateTime.minute)}'
      '${twoDigits(dateTime.second)}.json';
}

Future<void> _clearAllData(BuildContext context, WidgetRef ref) async {
  final confirmed = await _showConfirmDialog(
    context: context,
    title: '清空数据',
    message: '确定清空本地车辆、保养项目、保养记录和偏好？该操作不可撤销。',
    confirmLabel: '清空',
  );
  if (confirmed != true) {
    return;
  }
  _notificationSyncGeneration++;
  await ref.read(lunioRepositoryProvider).clearAllData();
  invalidateAllAppDataProviders(ref);
}

Future<void> _showNotificationSettingsSheet(
  BuildContext context,
  WidgetRef ref,
) async {
  var initialSettings = ref
      .read(notificationSettingsProvider)
      .maybeWhen(
        data: (value) => value,
        orElse: () => const LunioNotificationSettings(),
      );
  final systemNotificationsEnabled = await _refreshSystemNotificationPreference(
    ref,
  );
  if (!context.mounted) {
    return;
  }
  initialSettings = initialSettings.copyWith(
    systemNotificationsEnabled: systemNotificationsEnabled,
  );
  _showLunioModalSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) {
      return Padding(
        padding: EdgeInsets.fromLTRB(
          18,
          0,
          18,
          MediaQuery.of(sheetContext).viewInsets.bottom + 24,
        ),
        child: _NotificationSettingsForm(
          initialSettings: initialSettings,
          onOpenSystemSettings: () async {
            final opened =
                await NativeNotificationSettings.openNotificationSettings();
            if (sheetContext.mounted) {
              Navigator.of(sheetContext).pop();
            }
            if (!opened && context.mounted) {
              _showStatusOverlay(
                context,
                '无法打开系统设置，请在系统设置中搜索 Lunio',
                _StatusOverlayTone.info,
              );
            }
          },
          onSubmit: (settings) async {
            final systemNotificationsEnabled =
                await _refreshSystemNotificationPreference(ref);
            await _saveNotificationSettings(
              ref,
              settings.copyWith(
                systemNotificationsEnabled: systemNotificationsEnabled,
              ),
            );
            invalidatePreferenceProviders(ref);
            if (sheetContext.mounted) {
              Navigator.of(sheetContext).pop();
            }
          },
        ),
      );
    },
  );
}

Future<bool> _refreshSystemNotificationPreference(WidgetRef ref) async {
  final repository = ref.read(lunioRepositoryProvider);
  final currentValue = await repository.getPreferenceValue(
    'systemNotificationsEnabled',
  );
  try {
    final enabled = await LunioNotificationService.instance
        .notificationsEnabled();
    if (currentValue != enabled.toString()) {
      await repository.setPreferenceValue(
        'systemNotificationsEnabled',
        enabled.toString(),
      );
      invalidatePreferenceProviders(ref);
    }
    return enabled;
  } catch (_) {
    return currentValue != 'false';
  }
}

Future<void> _saveNotificationSettings(
  WidgetRef ref,
  LunioNotificationSettings settings,
) async {
  final repository = ref.read(lunioRepositoryProvider);
  await repository.setPreferenceValue(
    'systemNotificationsEnabled',
    settings.systemNotificationsEnabled.toString(),
  );
  await repository.setPreferenceValue(
    'inAppNotificationsEnabled',
    settings.inAppNotificationsEnabled.toString(),
  );
  await repository.setPreferenceValue(
    'maintenanceDueEnabled',
    settings.maintenanceDueEnabled.toString(),
  );
  await repository.setPreferenceValue(
    'maintenanceDueRepeat',
    settings.dueRepeatFrequency.value,
  );
}

enum _ReminderDialogAction { acknowledged, snoozed }

Future<_ReminderDialogAction?> _showMaintenanceReminderDialog({
  required BuildContext context,
  required WidgetRef ref,
  required Car car,
  required List<_ReminderViewData> maintenanceNotices,
  required LocalDate today,
}) {
  return _showLunioDialog<_ReminderDialogAction>(
    context: context,
    barrierDismissible: true,
    builder: (context) {
      return _MaintenanceReminderDialog(
        car: car,
        maintenanceNotices: maintenanceNotices,
        today: today,
        onSnoozeAll: () async {
          final repository = ref.read(lunioRepositoryProvider);
          final until = _snoozeUntilDate(today).toString();
          for (final notice in maintenanceNotices) {
            final itemId = notice.item.id;
            if (itemId != null) {
              await repository.setPreferenceValue(
                _maintenanceReminderSnoozeKey(itemId),
                until,
              );
            }
          }
        },
      );
    },
  );
}

Future<_ReminderDialogAction?> _showMileageUpdateReminderDialog({
  required BuildContext context,
  required WidgetRef ref,
  required Car car,
  required LocalDate today,
}) {
  return _showLunioDialog<_ReminderDialogAction>(
    context: context,
    barrierDismissible: true,
    builder: (context) {
      return _MileageUpdateReminderDialog(
        car: car,
        onSnooze: () async {
          final carId = car.id;
          if (carId == null) {
            return;
          }
          await ref
              .read(lunioRepositoryProvider)
              .setPreferenceValue(
                _mileageUpdateSnoozeKey(carId),
                _snoozeUntilDate(today).toString(),
              );
        },
      );
    },
  );
}

class _MaintenanceReminderDialog extends StatefulWidget {
  const _MaintenanceReminderDialog({
    required this.car,
    required this.maintenanceNotices,
    required this.today,
    required this.onSnoozeAll,
  });

  final Car car;
  final List<_ReminderViewData> maintenanceNotices;
  final LocalDate today;
  final Future<void> Function() onSnoozeAll;

  @override
  State<_MaintenanceReminderDialog> createState() =>
      _MaintenanceReminderDialogState();
}

class _MaintenanceReminderDialogState
    extends State<_MaintenanceReminderDialog> {
  bool saving = false;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      backgroundColor: Colors.transparent,
      child: Container(
        width: double.infinity,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.82,
        ),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: tokens.surface,
          borderRadius: BorderRadius.circular(tokens.radiusLarge),
          border: Border.all(color: tokens.line),
          boxShadow: [
            BoxShadow(
              color: tokens.ink.withValues(alpha: 0.16),
              blurRadius: 36,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('保养提醒', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              for (final notice in widget.maintenanceNotices) ...[
                _ReminderNotificationSegment(
                  title: notice.title,
                  body: _dueNoticeText(notice),
                ),
                const SizedBox(height: 10),
              ],
              Row(
                children: [
                  Expanded(
                    child: LunioSecondaryButton(
                      label: saving ? '处理中...' : '15 天内不再提醒',
                      onPressed: saving ? null : _snoozeAll,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: saving
                          ? null
                          : () => Navigator.of(
                              context,
                            ).pop(_ReminderDialogAction.acknowledged),
                      child: const Text('知道了'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _snoozeAll() async {
    setState(() => saving = true);
    await widget.onSnoozeAll();
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop(_ReminderDialogAction.snoozed);
  }
}

class _MileageUpdateReminderDialog extends StatefulWidget {
  const _MileageUpdateReminderDialog({
    required this.car,
    required this.onSnooze,
  });

  final Car car;
  final Future<void> Function() onSnooze;

  @override
  State<_MileageUpdateReminderDialog> createState() =>
      _MileageUpdateReminderDialogState();
}

class _MileageUpdateReminderDialogState
    extends State<_MileageUpdateReminderDialog> {
  bool saving = false;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      backgroundColor: Colors.transparent,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: tokens.surface,
          borderRadius: BorderRadius.circular(tokens.radiusLarge),
          border: Border.all(color: tokens.line),
          boxShadow: [
            BoxShadow(
              color: tokens.ink.withValues(alpha: 0.16),
              blurRadius: 36,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('更新当前里程', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              '建议更新 ${widget.car.brand} ${widget.car.model} 的当前里程。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: LunioSecondaryButton(
                    label: saving ? '处理中...' : '15 天内不再提醒',
                    onPressed: saving ? null : _snooze,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: saving
                        ? null
                        : () => Navigator.of(
                            context,
                          ).pop(_ReminderDialogAction.acknowledged),
                    child: const Text('知道了'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _snooze() async {
    setState(() => saving = true);
    await widget.onSnooze();
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop(_ReminderDialogAction.snoozed);
  }
}

class _ReminderNotificationSegment extends StatelessWidget {
  const _ReminderNotificationSegment({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tokens.surface2,
        borderRadius: BorderRadius.circular(tokens.radiusMedium),
        border: Border.all(color: tokens.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          Text(body, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _NotificationSettingsForm extends StatefulWidget {
  const _NotificationSettingsForm({
    required this.initialSettings,
    required this.onOpenSystemSettings,
    required this.onSubmit,
  });

  final LunioNotificationSettings initialSettings;
  final Future<void> Function() onOpenSystemSettings;
  final Future<void> Function(LunioNotificationSettings settings) onSubmit;

  @override
  State<_NotificationSettingsForm> createState() =>
      _NotificationSettingsFormState();
}

class _NotificationSettingsFormState extends State<_NotificationSettingsForm> {
  static const dueRepeatOptions = [
    ReminderRepeatFrequency.weekly,
    ReminderRepeatFrequency.everyTwoWeeks,
    ReminderRepeatFrequency.monthly,
  ];

  late bool inAppNotificationsEnabled;
  late ReminderRepeatFrequency dueRepeatFrequency;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    final settings = widget.initialSettings;
    inAppNotificationsEnabled = settings.inAppNotificationsEnabled;
    dueRepeatFrequency = dueRepeatOptions.contains(settings.dueRepeatFrequency)
        ? settings.dueRepeatFrequency
        : ReminderRepeatFrequency.weekly;
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('通知提醒', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 14),
          _SystemNotificationStatusRow(
            enabled: widget.initialSettings.systemNotificationsEnabled,
            onOpenSettings: saving ? null : widget.onOpenSystemSettings,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('应用内通知'),
            value: inAppNotificationsEnabled,
            onChanged: saving
                ? null
                : (value) => setState(() => inAppNotificationsEnabled = value),
          ),
          const SizedBox(height: 6),
          Text('到期后提醒次数', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          LunioSegmentedControl(
            values: dueRepeatOptions
                .map((frequency) => frequency.label)
                .toList(),
            selectedIndex: dueRepeatOptions.contains(dueRepeatFrequency)
                ? dueRepeatOptions.indexOf(dueRepeatFrequency)
                : 0,
            onSelected: saving
                ? (_) {}
                : (index) => setState(
                    () => dueRepeatFrequency = dueRepeatOptions[index],
                  ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: LunioSecondaryButton(
                  label: '取消',
                  onPressed: saving ? null : () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: saving ? null : _submit,
                  child: Text(saving ? '保存中...' : '保存设置'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    setState(() => saving = true);
    try {
      await widget.onSubmit(
        LunioNotificationSettings(
          systemNotificationsEnabled:
              widget.initialSettings.systemNotificationsEnabled,
          inAppNotificationsEnabled: inAppNotificationsEnabled,
          maintenanceDueEnabled: true,
          dueRepeatFrequency: dueRepeatFrequency,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => saving = false);
      }
    }
  }
}

class _SystemNotificationStatusRow extends StatelessWidget {
  const _SystemNotificationStatusRow({
    required this.enabled,
    required this.onOpenSettings,
  });

  final bool enabled;
  final Future<void> Function()? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: tokens.surface2,
          borderRadius: BorderRadius.circular(tokens.radiusMedium),
          border: Border.all(color: tokens.line),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('手机系统通知'),
                  const SizedBox(height: 4),
                  Text(
                    enabled ? '系统已开启' : '系统已关闭',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: tokens.muted),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: onOpenSettings == null
                  ? null
                  : () {
                      onOpenSettings!();
                    },
              child: const Text('系统设置'),
            ),
          ],
        ),
      ),
    );
  }
}

void _showManualDateSheet(BuildContext context, WidgetRef ref) {
  final initialDate = ref
      .read(manualDatePreferenceProvider)
      .maybeWhen(data: (value) => value, orElse: () => null);
  final fallbackDate = ref
      .read(effectiveTodayProvider)
      .maybeWhen(
        data: (value) => value,
        orElse: () => LocalDate.fromDateTime(DateTime.now()),
      );
  _showLunioModalSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) {
      return Padding(
        padding: EdgeInsets.fromLTRB(
          18,
          0,
          18,
          MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: _ManualDateForm(
          initialDate: initialDate,
          fallbackDate: fallbackDate,
          onSubmit: (date) async {
            final repository = ref.read(lunioRepositoryProvider);
            if (date == null) {
              await repository.setPreferenceValue('manualDateEnabled', 'false');
              await repository.setPreferenceValue('manualDate', null);
            } else {
              await repository.setPreferenceValue('manualDateEnabled', 'true');
              await repository.setPreferenceValue(
                'manualDate',
                date.toString(),
              );
            }
            invalidatePreferenceProviders(ref);
            if (context.mounted) {
              Navigator.of(context).pop();
            }
          },
        ),
      );
    },
  );
}

class _ManualDateForm extends StatefulWidget {
  const _ManualDateForm({
    required this.initialDate,
    required this.fallbackDate,
    required this.onSubmit,
  });

  final LocalDate? initialDate;
  final LocalDate fallbackDate;
  final Future<void> Function(LocalDate? date) onSubmit;

  @override
  State<_ManualDateForm> createState() => _ManualDateFormState();
}

class _ManualDateFormState extends State<_ManualDateForm> {
  late LocalDate selectedDate;
  late bool enabled;
  bool saving = false;
  String? errorText;

  @override
  void initState() {
    super.initState();
    enabled = widget.initialDate != null;
    selectedDate = widget.initialDate ?? widget.fallbackDate;
  }

  @override
  void dispose() => super.dispose();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('手动日期', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          '开启后，保养提醒里的“今天”会使用该日期。',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 14),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('启用手动日期'),
          value: enabled,
          onChanged: saving ? null : (value) => setState(() => enabled = value),
        ),
        if (enabled) ...[
          const SizedBox(height: 12),
          LunioPickerTile(
            label: '日期',
            value: _formatDateForUser(selectedDate),
            enabled: !saving,
            onTap: _pickDate,
          ),
        ],
        if (errorText != null) ...[
          const SizedBox(height: 10),
          LunioInlineMessage(message: errorText!, tone: LunioStatusTone.danger),
        ],
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: LunioSecondaryButton(
                label: '取消',
                onPressed: saving ? null : () => Navigator.of(context).pop(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: LunioPrimaryButton(
                label: saving ? '保存中' : '保存日期',
                onPressed: saving ? null : _submit,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _submit() async {
    final date = enabled ? selectedDate : null;
    setState(() {
      saving = true;
      errorText = null;
    });
    try {
      await widget.onSubmit(date);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        saving = false;
        errorText = _friendlyError(error);
      });
    }
  }

  Future<void> _pickDate() async {
    final picked = await _showSimpleDatePicker(
      context,
      initialDate: selectedDate,
      firstDate: const LocalDate(1990, 1, 1),
      lastDate: LocalDate.fromDateTime(
        DateTime.now().add(const Duration(days: 3650)),
      ),
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() => selectedDate = picked);
  }
}

Future<LocalDate?> _showSimpleDatePicker(
  BuildContext context, {
  required LocalDate initialDate,
  required LocalDate firstDate,
  required LocalDate lastDate,
  LocalDate? today,
}) {
  return _showLunioModalSheet<LocalDate>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.72,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
        child: _SimpleDatePicker(
          initialDate: initialDate,
          firstDate: firstDate,
          lastDate: lastDate,
          today: today ?? LocalDate.fromDateTime(DateTime.now()),
        ),
      ),
    ),
  );
}

class _SimpleDatePicker extends StatefulWidget {
  const _SimpleDatePicker({
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
    required this.today,
  });

  final LocalDate initialDate;
  final LocalDate firstDate;
  final LocalDate lastDate;
  final LocalDate today;

  @override
  State<_SimpleDatePicker> createState() => _SimpleDatePickerState();
}

class _SimpleDatePickerState extends State<_SimpleDatePicker> {
  late LocalDate selectedDate;
  late int visibleYear;
  late int visibleMonth;
  late int visibleYearPageStart;
  _DatePickerMode mode = _DatePickerMode.day;

  @override
  void initState() {
    super.initState();
    selectedDate = widget.initialDate;
    visibleYear = selectedDate.year;
    visibleMonth = selectedDate.month;
    visibleYearPageStart = _yearPageStartFor(visibleYear);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    return LunioSheetScaffold(
      title: '选择日期',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _DatePickerHeader(
            mode: mode,
            visibleYear: visibleYear,
            visibleMonth: visibleMonth,
            yearPageStart: visibleYearPageStart,
            canGoPrevious: _canGoPrevious(),
            canGoNext: _canGoNext(),
            onPrevious: _goPrevious,
            onNext: _goNext,
            onYearTap: () => setState(() {
              visibleYearPageStart = _yearPageStartFor(visibleYear);
              mode = _DatePickerMode.year;
            }),
            onMonthTap: () => setState(() => mode = _DatePickerMode.month),
          ),
          if (_todayInRange()) ...[
            const SizedBox(height: 2),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _selectToday,
                icon: const Icon(Icons.today_outlined, size: 18),
                label: const Text('今天'),
                style: TextButton.styleFrom(
                  foregroundColor: tokens.primary,
                  minimumSize: const Size(0, 32),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
          ],
          const SizedBox(height: 2),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 160),
            child: switch (mode) {
              _DatePickerMode.day => _buildDayGrid(context),
              _DatePickerMode.month => _buildMonthGrid(context),
              _DatePickerMode.year => _buildYearGrid(context),
            },
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: LunioSecondaryButton(
                  label: '取消',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: LunioPrimaryButton(
                  label: '确定',
                  onPressed: () => Navigator.of(context).pop(selectedDate),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDayGrid(BuildContext context) {
    final firstWeekday = DateTime(visibleYear, visibleMonth, 1).weekday;
    final daysInMonth = DateTime(visibleYear, visibleMonth + 1, 0).day;
    final leadingBlankCount = firstWeekday - 1;
    final cells = leadingBlankCount + daysInMonth;
    final totalCells = ((cells + 6) ~/ 7) * 7;
    return Column(
      key: const ValueKey(_DatePickerMode.day),
      children: [
        Table(
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            TableRow(
              children: [
                for (final label in const ['一', '二', '三', '四', '五', '六', '日'])
                  SizedBox(
                    height: 20,
                    child: Center(
                      child: Text(
                        label,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                  ),
              ],
            ),
            for (var row = 0; row < totalCells ~/ 7; row++)
              TableRow(
                children: [
                  for (var column = 0; column < 7; column++)
                    Padding(
                      padding: EdgeInsets.only(
                        top: row == 0 ? 0 : 6,
                        left: column == 0 ? 0 : 3,
                        right: column == 6 ? 0 : 3,
                      ),
                      child: _dateCellForIndex(
                        row * 7 + column,
                        leadingBlankCount,
                        daysInMonth,
                      ),
                    ),
                ],
              ),
          ],
        ),
      ],
    );
  }

  Widget _dateCellForIndex(int index, int leadingBlankCount, int daysInMonth) {
    if (index < leadingBlankCount || index >= leadingBlankCount + daysInMonth) {
      return const SizedBox(height: 42);
    }
    return SizedBox(
      height: 42,
      child: _DateCell(
        date: LocalDate(
          visibleYear,
          visibleMonth,
          index - leadingBlankCount + 1,
        ),
        selectedDate: selectedDate,
        firstDate: widget.firstDate,
        lastDate: widget.lastDate,
        onSelected: (date) => setState(() => selectedDate = date),
      ),
    );
  }

  Widget _buildMonthGrid(BuildContext context) {
    return _DateOptionTable(
      key: const ValueKey(_DatePickerMode.month),
      children: [
        for (var month = 1; month <= 12; month++)
          _DateOptionCell(
            label: '$month月',
            selected:
                visibleYear == selectedDate.year && month == selectedDate.month,
            enabled: _monthEnabled(visibleYear, month),
            onTap: () => _selectMonth(month),
          ),
      ],
    );
  }

  Widget _buildYearGrid(BuildContext context) {
    return _DateOptionTable(
      key: const ValueKey(_DatePickerMode.year),
      children: [
        for (var offset = 0; offset < 12; offset++)
          _DateOptionCell(
            label: '${visibleYearPageStart + offset}年',
            selected: visibleYearPageStart + offset == visibleYear,
            enabled: _yearEnabled(visibleYearPageStart + offset),
            onTap: () => _selectYear(visibleYearPageStart + offset),
          ),
      ],
    );
  }

  bool _canGoPrevious() {
    return switch (mode) {
      _DatePickerMode.day =>
        visibleYear > widget.firstDate.year ||
            (visibleYear == widget.firstDate.year &&
                visibleMonth > widget.firstDate.month),
      _DatePickerMode.month => visibleYear > widget.firstDate.year,
      _DatePickerMode.year => visibleYearPageStart > widget.firstDate.year,
    };
  }

  bool _canGoNext() {
    return switch (mode) {
      _DatePickerMode.day =>
        visibleYear < widget.lastDate.year ||
            (visibleYear == widget.lastDate.year &&
                visibleMonth < widget.lastDate.month),
      _DatePickerMode.month => visibleYear < widget.lastDate.year,
      _DatePickerMode.year => visibleYearPageStart + 11 < widget.lastDate.year,
    };
  }

  void _goPrevious() {
    setState(() {
      switch (mode) {
        case _DatePickerMode.day:
          _moveMonth(-1);
        case _DatePickerMode.month:
          visibleYear -= 1;
          _clampVisibleMonth();
          selectedDate = _dateForVisibleMonth(selectedDate.day);
        case _DatePickerMode.year:
          visibleYearPageStart -= 12;
      }
    });
  }

  void _goNext() {
    setState(() {
      switch (mode) {
        case _DatePickerMode.day:
          _moveMonth(1);
        case _DatePickerMode.month:
          visibleYear += 1;
          _clampVisibleMonth();
          selectedDate = _dateForVisibleMonth(selectedDate.day);
        case _DatePickerMode.year:
          visibleYearPageStart += 12;
      }
    });
  }

  void _moveMonth(int delta) {
    visibleMonth += delta;
    if (visibleMonth < 1) {
      visibleYear -= 1;
      visibleMonth = 12;
    }
    if (visibleMonth > 12) {
      visibleYear += 1;
      visibleMonth = 1;
    }
    selectedDate = _dateForVisibleMonth(selectedDate.day);
  }

  void _selectYear(int year) {
    setState(() {
      visibleYear = year;
      _clampVisibleMonth();
      selectedDate = _dateForVisibleMonth(selectedDate.day);
      mode = _DatePickerMode.month;
    });
  }

  void _selectMonth(int month) {
    setState(() {
      visibleMonth = month;
      selectedDate = _dateForVisibleMonth(selectedDate.day);
      mode = _DatePickerMode.day;
    });
  }

  void _selectToday() {
    final today = widget.today;
    setState(() {
      selectedDate = today;
      visibleYear = today.year;
      visibleMonth = today.month;
      visibleYearPageStart = _yearPageStartFor(today.year);
      mode = _DatePickerMode.day;
    });
  }

  void _clampVisibleMonth() {
    final firstMonth = visibleYear == widget.firstDate.year
        ? widget.firstDate.month
        : 1;
    final lastMonth = visibleYear == widget.lastDate.year
        ? widget.lastDate.month
        : 12;
    visibleMonth = visibleMonth.clamp(firstMonth, lastMonth);
  }

  LocalDate _dateForVisibleMonth(int preferredDay) {
    final daysInMonth = DateTime(visibleYear, visibleMonth + 1, 0).day;
    var date = LocalDate(
      visibleYear,
      visibleMonth,
      preferredDay.clamp(1, daysInMonth),
    );
    if (date.compareTo(widget.firstDate) < 0) {
      date = widget.firstDate;
    }
    if (date.compareTo(widget.lastDate) > 0) {
      date = widget.lastDate;
    }
    visibleYear = date.year;
    visibleMonth = date.month;
    return date;
  }

  bool _todayInRange() {
    final today = widget.today;
    return today.compareTo(widget.firstDate) >= 0 &&
        today.compareTo(widget.lastDate) <= 0;
  }

  bool _monthEnabled(int year, int month) {
    final monthStart = LocalDate(year, month, 1);
    final monthEnd = LocalDate(year, month, DateTime(year, month + 1, 0).day);
    return monthEnd.compareTo(widget.firstDate) >= 0 &&
        monthStart.compareTo(widget.lastDate) <= 0;
  }

  bool _yearEnabled(int year) {
    return year >= widget.firstDate.year && year <= widget.lastDate.year;
  }

  int _yearPageStartFor(int year) {
    return year - year % 12;
  }
}

enum _DatePickerMode { day, month, year }

class _DateOptionTable extends StatelessWidget {
  const _DateOptionTable({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final totalCells = ((children.length + 2) ~/ 3) * 3;
    return Table(
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        for (var row = 0; row < totalCells ~/ 3; row++)
          TableRow(
            children: [
              for (var column = 0; column < 3; column++)
                Padding(
                  padding: EdgeInsets.only(
                    top: row == 0 ? 0 : 10,
                    left: column == 0 ? 0 : 5,
                    right: column == 2 ? 0 : 5,
                  ),
                  child: SizedBox(
                    height: 58,
                    child: row * 3 + column < children.length
                        ? children[row * 3 + column]
                        : const SizedBox.shrink(),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

class _DatePickerHeader extends StatelessWidget {
  const _DatePickerHeader({
    required this.mode,
    required this.visibleYear,
    required this.visibleMonth,
    required this.yearPageStart,
    required this.canGoPrevious,
    required this.canGoNext,
    required this.onPrevious,
    required this.onNext,
    required this.onYearTap,
    required this.onMonthTap,
  });

  final _DatePickerMode mode;
  final int visibleYear;
  final int visibleMonth;
  final int yearPageStart;
  final bool canGoPrevious;
  final bool canGoNext;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onYearTap;
  final VoidCallback onMonthTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          tooltip: _previousTooltip,
          onPressed: canGoPrevious ? onPrevious : null,
          style: IconButton.styleFrom(
            backgroundColor: tokens.surface2,
            foregroundColor: tokens.ink,
          ),
        ),
        Expanded(child: Center(child: _buildTitle(context))),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          tooltip: _nextTooltip,
          onPressed: canGoNext ? onNext : null,
          style: IconButton.styleFrom(
            backgroundColor: tokens.surface2,
            foregroundColor: tokens.ink,
          ),
        ),
      ],
    );
  }

  Widget _buildTitle(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    if (mode == _DatePickerMode.year) {
      return Text(
        '$yearPageStart-${yearPageStart + 11}年',
        style: Theme.of(context).textTheme.titleMedium,
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton(
          onPressed: onYearTap,
          style: TextButton.styleFrom(
            foregroundColor: tokens.ink,
            padding: const EdgeInsets.symmetric(horizontal: 10),
          ),
          child: Text(
            '$visibleYear年',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        TextButton(
          onPressed: onMonthTap,
          style: TextButton.styleFrom(
            foregroundColor: tokens.ink,
            padding: const EdgeInsets.symmetric(horizontal: 10),
          ),
          child: Text(
            '$visibleMonth月',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      ],
    );
  }

  String get _previousTooltip {
    return switch (mode) {
      _DatePickerMode.day => '上个月',
      _DatePickerMode.month => '上一年',
      _DatePickerMode.year => '上一组年份',
    };
  }

  String get _nextTooltip {
    return switch (mode) {
      _DatePickerMode.day => '下个月',
      _DatePickerMode.month => '下一年',
      _DatePickerMode.year => '下一组年份',
    };
  }
}

class _DateOptionCell extends StatelessWidget {
  const _DateOptionCell({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(tokens.radiusMedium),
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? tokens.primary : tokens.surface2,
          borderRadius: BorderRadius.circular(tokens.radiusMedium),
          border: Border.all(color: selected ? tokens.primary : tokens.line),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: selected
                ? Colors.white
                : enabled
                ? tokens.ink
                : tokens.subtle.withValues(alpha: 0.45),
          ),
        ),
      ),
    );
  }
}

class _DateCell extends StatelessWidget {
  const _DateCell({
    required this.date,
    required this.selectedDate,
    required this.firstDate,
    required this.lastDate,
    required this.onSelected,
  });

  final LocalDate date;
  final LocalDate selectedDate;
  final LocalDate firstDate;
  final LocalDate lastDate;
  final ValueChanged<LocalDate> onSelected;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    final selected = date == selectedDate;
    final enabled =
        date.compareTo(firstDate) >= 0 && date.compareTo(lastDate) <= 0;
    return InkWell(
      onTap: enabled ? () => onSelected(date) : null,
      borderRadius: BorderRadius.circular(tokens.radiusSmall),
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? tokens.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(tokens.radiusSmall),
        ),
        child: Text(
          '${date.day}',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: selected
                ? Colors.white
                : enabled
                ? tokens.ink
                : tokens.subtle.withValues(alpha: 0.45),
          ),
        ),
      ),
    );
  }
}

class _ReminderViewData {
  const _ReminderViewData({
    required this.item,
    required this.progress,
    required this.latestRecord,
  });

  final MaintenanceItem item;
  final ReminderProgress progress;
  final MaintenanceRecord? latestRecord;

  String get title => item.name;

  int get displayPercent => _displayPercentForThresholds(
    percent: progress.percent,
    notOverdueUpperLimit: item.notOverdueUpperLimit,
    overdueUpperLimit: item.overdueUpperLimit,
  );

  String get percentText => _formatPercent(displayPercent);

  LunioStatusTone get tone {
    return switch (progress.status) {
      ReminderStatus.normal => LunioStatusTone.normal,
      ReminderStatus.warning => LunioStatusTone.warning,
      ReminderStatus.danger => LunioStatusTone.danger,
    };
  }

  String get badge {
    return switch (progress.status) {
      ReminderStatus.normal => '正常',
      ReminderStatus.warning => '到期',
      ReminderStatus.danger => '超期',
    };
  }

  List<String> get detailTexts {
    final details = <String>[];
    if (item.remindByMileage && progress.mileageRemainingKm != null) {
      details.add(_mileageReminderText(progress.mileageRemainingKm!));
    }
    if (item.remindByTime && progress.daysRemaining != null) {
      details.add(_timeReminderText(progress.daysRemaining!));
    }
    if (details.isEmpty) {
      details.add('未设置提醒规则');
    }
    return details;
  }
}

List<_ReminderViewData> _buildReminderRows({
  required Car car,
  required List<MaintenanceItem> items,
  required List<MaintenanceRecord> records,
  required LocalDate today,
}) {
  final rows = <_ReminderViewData>[];
  for (final item in items.where((item) => item.enabled && item.id != null)) {
    final latestRecord = _latestRecordForItem(records, item.id!);
    final progress = MaintenanceRules.progressForItem(
      item: item,
      latestRecord: latestRecord,
      currentMileageKm: car.currentMileageKm,
      noHistoryBaselineDate: car.roadDate,
      today: today,
    );
    rows.add(
      _ReminderViewData(
        item: item,
        progress: progress,
        latestRecord: latestRecord,
      ),
    );
  }
  rows.sort((left, right) {
    final statusCompare = _statusRank(
      right.progress.status,
    ).compareTo(_statusRank(left.progress.status));
    if (statusCompare != 0) {
      return statusCompare;
    }
    final progressCompare = right.progress.percent.compareTo(
      left.progress.percent,
    );
    if (progressCompare != 0) {
      return progressCompare;
    }
    return left.item.sortOrder.compareTo(right.item.sortOrder);
  });
  return rows;
}

Future<List<LunioScheduledNotification>> _buildScheduledNotifications({
  required WidgetRef ref,
  required LunioNotificationSettings settings,
  required Car car,
  required List<MaintenanceItem> items,
  required List<MaintenanceRecord> records,
  required LocalDate today,
}) async {
  final repository = ref.read(lunioRepositoryProvider);
  final notifications = <LunioScheduledNotification>[];
  final activeMaintenanceNotices = <_ReminderViewData>[];
  for (final notice in _maintenanceNotices(
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
    if (!await _isSnoozed(
      repository,
      _maintenanceReminderSnoozeKey(itemId),
      today,
    )) {
      activeMaintenanceNotices.add(notice);
    }
  }
  if (activeMaintenanceNotices.isNotEmpty) {
    notifications.add(
      LunioScheduledNotification(
        id: 8000,
        title: '保养提醒',
        body: _maintenanceNoticeSummaryForRows(car, activeMaintenanceNotices),
        repeatFrequency: _maintenanceRepeatFrequency(
          settings: settings,
          car: car,
          items: items,
          records: records,
          today: today,
        ),
      ),
    );
  }
  if (car.id != null &&
      _mileageUpdateReminderDue(car: car, records: records, today: today) &&
      !await _isSnoozed(repository, _mileageUpdateSnoozeKey(car.id!), today)) {
    notifications.add(
      LunioScheduledNotification(
        id: 8900,
        title: '更新车辆里程',
        body: '建议更新 ${car.brand} ${car.model} 的当前里程。',
        repeatFrequency: MaintenanceRules.mileageUpdateFrequencyForRecords(
          records,
        ),
        scheduledMinuteOffset: 5,
        androidChannelId: 'lunio_mileage_update_heads_up',
        androidChannelName: 'Lunio 里程更新提醒',
      ),
    );
  }
  return notifications;
}

List<DateTime> _reservedNotificationDateTimes(
  ParkingCountdown? parkingCountdown,
) {
  if (parkingCountdown == null) {
    return const [];
  }
  return [parkingCountdown.endsAt];
}

String _parkingCountdownReminderSignature(ParkingCountdown? parkingCountdown) {
  if (parkingCountdown == null) {
    return 'parking:none';
  }
  return 'parking:${parkingCountdown.endsAt.toIso8601String()}';
}

String _reminderNotificationDataSignature({
  required Car car,
  required List<MaintenanceItem> items,
  required List<MaintenanceRecord> records,
  required LocalDate today,
}) {
  final itemSignature = items
      .map((item) {
        return [
          item.id,
          item.carsId,
          item.enabled,
          item.remindByMileage,
          item.remindByTime,
          item.mileageIntervalKm,
          item.timeIntervalMonths,
          item.notOverdueUpperLimit,
          item.overdueUpperLimit,
          item.sortOrder,
          item.sync.updatedAt.toIso8601String(),
          item.sync.version,
        ].join(',');
      })
      .join('|');
  final recordSignature = records
      .map((record) {
        return [
          record.id,
          record.carId,
          record.date,
          record.mileageKm,
          record.itemIds.join('+'),
          record.sync.updatedAt.toIso8601String(),
          record.sync.version,
        ].join(',');
      })
      .join('|');
  return [
    car.id,
    car.currentMileageKm,
    car.sync.updatedAt.toIso8601String(),
    today,
    itemSignature,
    recordSignature,
  ].join(';');
}

bool _mileageUpdateReminderDue({
  required Car car,
  required List<MaintenanceRecord> records,
  required LocalDate today,
}) {
  final frequency = MaintenanceRules.mileageUpdateFrequencyForRecords(records);
  return MaintenanceRules.mileageUpdateDue(
    lastMileageUpdatedDate: LocalDate.fromDateTime(car.sync.updatedAt),
    frequency: frequency,
    today: today,
  );
}

ReminderRepeatFrequency _maintenanceRepeatFrequency({
  required LunioNotificationSettings settings,
  required Car car,
  required List<MaintenanceItem> items,
  required List<MaintenanceRecord> records,
  required LocalDate today,
}) {
  return settings.dueRepeatFrequency;
}

String _maintenanceNoticeSummaryForRows(
  Car car,
  List<_ReminderViewData> notices,
) {
  final first = notices.first;
  return '${car.brand} ${car.model}：到期 ${notices.length} 项。'
      '最紧急：${first.title}，${_dueReasonText(first)}';
}

String _dueReasonText(_ReminderViewData row) {
  final mileageDue =
      row.item.remindByMileage &&
      row.progress.mileageRemainingKm != null &&
      row.progress.mileageRemainingKm! <= 0;
  final timeDue =
      row.item.remindByTime &&
      row.progress.daysRemaining != null &&
      row.progress.daysRemaining! <= 0;
  if (mileageDue && timeDue) {
    return '里程和时间到期';
  }
  if (mileageDue) {
    return '里程到期';
  }
  if (timeDue) {
    return '时间到期';
  }
  return '到期';
}

String _dueNoticeText(_ReminderViewData row) {
  final details = <String>[];
  final daysRemaining = row.progress.daysRemaining;
  if (row.item.remindByTime && daysRemaining != null && daysRemaining <= 0) {
    details.add(
      daysRemaining == 0
          ? '时间今日到期'
          : '已超 ${_formatReminderDuration(daysRemaining.abs())}',
    );
  }
  final mileageRemaining = row.progress.mileageRemainingKm;
  if (row.item.remindByMileage &&
      mileageRemaining != null &&
      mileageRemaining <= 0) {
    details.add(
      mileageRemaining == 0
          ? '里程已到期'
          : '已超 ${_formatNumber(mileageRemaining.abs())}km',
    );
  }
  if (details.isEmpty) {
    return _dueReasonText(row);
  }
  return details.join(' · ');
}

String _mileageUpdateSnoozeKey(int carId) {
  return 'mileageUpdateSnoozedUntil:$carId';
}

String _mileageUpdateInAppAcknowledgedKey(int carId) {
  return 'mileageUpdateInAppAcknowledgedOn:$carId';
}

String _maintenanceReminderSnoozeKey(int itemId) {
  return 'maintenanceReminderSnoozedUntil:$itemId';
}

String _maintenanceInAppReminderAcknowledgedKey(int itemId) {
  return 'maintenanceInAppReminderAcknowledgedOn:$itemId';
}

LocalDate _snoozeUntilDate(LocalDate today) {
  return LocalDate.fromDateTime(
    today.toDateTime().add(const Duration(days: 15)),
  );
}

Future<bool> _isSnoozed(
  LunioRepository repository,
  String key,
  LocalDate today,
) async {
  final value = await repository.getPreferenceValue(key);
  if (value == null) {
    return false;
  }
  final until = LocalDate.tryParse(value);
  if (until == null) {
    return false;
  }
  return until.compareTo(today) >= 0;
}

Future<bool> _isAcknowledgedToday(
  LunioRepository repository,
  String key,
  LocalDate today,
) async {
  final value = await repository.getPreferenceValue(key);
  if (value == null) {
    return false;
  }
  final acknowledgedOn = LocalDate.tryParse(value);
  if (acknowledgedOn == null) {
    return false;
  }
  return acknowledgedOn == today;
}

List<_ReminderViewData> _maintenanceNotices({
  required LunioNotificationSettings settings,
  required Car car,
  required List<MaintenanceItem> items,
  required List<MaintenanceRecord> records,
  required LocalDate today,
}) {
  if (records.isEmpty) {
    return const [];
  }
  final rows = _buildReminderRows(
    car: car,
    items: items,
    records: records,
    today: today,
  );
  final notices = <_ReminderViewData>[];
  for (final row in rows) {
    if (_noticeDueForRow(settings, row)) {
      notices.add(row);
    }
  }
  return notices;
}

bool _noticeDueForRow(
  LunioNotificationSettings settings,
  _ReminderViewData row,
) {
  if (!settings.maintenanceDueEnabled) {
    return false;
  }
  return row.progress.status == ReminderStatus.warning ||
      row.progress.status == ReminderStatus.danger;
}

MaintenanceRecord? _latestRecordForItem(
  List<MaintenanceRecord> records,
  int itemId,
) {
  MaintenanceRecord? latest;
  for (final record in records) {
    if (!record.itemIds.contains(itemId)) {
      continue;
    }
    if (latest == null ||
        record.date.compareTo(latest.date) > 0 ||
        (record.date == latest.date && record.mileageKm > latest.mileageKm)) {
      latest = record;
    }
  }
  return latest;
}

int _statusRank(ReminderStatus status) {
  return switch (status) {
    ReminderStatus.normal => 0,
    ReminderStatus.warning => 1,
    ReminderStatus.danger => 2,
  };
}

String _dueOverviewText(
  AsyncValue<List<MaintenanceItem>> items,
  AsyncValue<List<MaintenanceRecord>> records,
  Car car,
  LocalDate today,
) {
  if (items.isLoading || records.isLoading) {
    return '计算中';
  }
  if (items.hasError || records.hasError) {
    return '加载失败';
  }
  if ((records.value ?? const <MaintenanceRecord>[]).isEmpty) {
    return '暂无';
  }
  final rows = _buildReminderRows(
    car: car,
    items: items.value ?? const [],
    records: records.value ?? const [],
    today: today,
  );
  if (rows.isEmpty) {
    return '无项目';
  }
  final overdueCount = rows
      .where((row) => row.progress.status == ReminderStatus.danger)
      .length;
  final dueCount = rows
      .where((row) => row.progress.status == ReminderStatus.warning)
      .length;
  if (overdueCount > 0 && dueCount > 0) {
    return '超期 $overdueCount / 到期 $dueCount';
  }
  if (overdueCount > 0) {
    return '超期 $overdueCount';
  }
  if (dueCount > 0) {
    return '到期 $dueCount';
  }
  return '全部正常';
}

InputDecoration _numberInputDecoration({
  String? labelText,
  String? suffixText,
}) {
  return InputDecoration(labelText: labelText, suffixText: suffixText);
}

int _displayPercentForThresholds({
  required double percent,
  required double notOverdueUpperLimit,
  required double overdueUpperLimit,
}) {
  var display = percent.round();
  if (percent < notOverdueUpperLimit &&
      display >= notOverdueUpperLimit.ceil()) {
    display = notOverdueUpperLimit.ceil() - 1;
  }
  if (percent < overdueUpperLimit && display >= overdueUpperLimit.ceil()) {
    display = overdueUpperLimit.ceil() - 1;
  }
  return display;
}

String _formatPercent(int percent) {
  return percent > 999 ? '999%+' : '$percent%';
}

String _itemRuleText(MaintenanceItem item) {
  final rules = <String>[];
  if (item.remindByMileage) {
    rules.add(_formatCompactMileageText(item.mileageIntervalKm ?? 0));
  }
  if (item.remindByTime) {
    rules.add(_formatCompactTimeText(item.timeIntervalMonths ?? 0));
  }
  return rules.isEmpty ? '提醒：未设置' : '提醒：${rules.join('/')}';
}

String _defaultItemRuleText(VehicleDefaultMaintenanceItem item) {
  final rules = <String>[];
  if (item.remindByMileage) {
    rules.add(_formatCompactMileageText(item.mileageIntervalKm ?? 0));
  }
  if (item.remindByTime) {
    rules.add(_formatCompactTimeText(item.timeIntervalMonths ?? 0));
  }
  return rules.isEmpty ? '提醒：未设置' : '提醒：${rules.join('/')}';
}

String _normalizeItemName(String value) => value.trim();

MaintenanceItem _maintenanceItemFromDefault(
  VehicleDefaultMaintenanceItem item,
  SyncMetadata sync,
) {
  return MaintenanceItem(
    carsId: 0,
    name: item.itemName,
    enabled: true,
    remindByMileage: item.remindByMileage,
    remindByTime: item.remindByTime,
    mileageIntervalKm: item.mileageIntervalKm,
    timeIntervalMonths: item.timeIntervalMonths,
    notOverdueUpperLimit: item.notOverdueUpperLimit,
    overdueUpperLimit: item.overdueUpperLimit,
    sortOrder: item.sortOrder,
    sync: sync,
  );
}

List<String> _recordItemNameList(
  MaintenanceRecord record,
  List<MaintenanceItem> items,
) {
  return record.itemIds
      .map((id) => _itemById(items, id)?.name ?? '未知项目')
      .toList();
}

MaintenanceItem? _itemById(List<MaintenanceItem> items, int itemId) {
  for (final item in items) {
    if (item.id == itemId) {
      return item;
    }
  }
  return null;
}

String _formatMoney(int costCents) {
  return '¥${(costCents / 100).toStringAsFixed(2)}';
}

String _formatMileageKm(int value) {
  return '${_formatNumber(value)}km';
}

String _formatCarAge(LocalDate roadDate, LocalDate today) {
  final months = roadDate.monthsUntil(today).clamp(0, 1200);
  final years = months / 12;
  final text = years.toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '');
  return '$text年';
}

String _formatCompactMileageText(int value) {
  if (value >= 10000) {
    final wan = value / 10000;
    final text = wan == wan.roundToDouble()
        ? wan.toStringAsFixed(0)
        : wan.toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '');
    return '$text万公里';
  }
  return '${_formatNumber(value)}公里';
}

String _formatCompactTimeText(int months) {
  if (months < 12) {
    return '$months个月';
  }
  if (months % 12 == 0) {
    return '${months ~/ 12}年';
  }
  final years = months / 12;
  final text = years.toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '');
  return '$text年';
}

String _mileageReminderText(int remainingKm) {
  if (remainingKm > 0) {
    return '里程：距离下次约 ${_formatNumber(remainingKm)} 公里';
  }
  if (remainingKm == 0) {
    return '里程：已到期';
  }
  return '里程：已超 ${_formatNumber(remainingKm.abs())} 公里';
}

String _timeReminderText(int remainingDays) {
  if (remainingDays > 0) {
    return '时间：距离下次约 ${_formatReminderDuration(remainingDays)}';
  }
  if (remainingDays == 0) {
    return '时间：今日到期';
  }
  return '时间：已超 ${_formatReminderDuration(remainingDays.abs())}';
}

String _formatReminderDuration(int days) {
  if (days < 30) {
    return '$days天';
  }
  if (days < 365) {
    return '${days ~/ 30}个月';
  }
  final months = days ~/ 30;
  final years = months ~/ 12;
  final restMonths = months % 12;
  if (restMonths == 0) {
    return '$years年';
  }
  return '$years年$restMonths个月';
}

Future<void> _applyCar(BuildContext context, WidgetRef ref, int carId) async {
  await ref.read(lunioRepositoryProvider).setAppliedCarId(carId);
  invalidateVehicleProviders(ref);
}

Future<void> _setThemeMode(
  BuildContext context,
  WidgetRef ref,
  ThemeMode mode,
) async {
  final value = switch (mode) {
    ThemeMode.light => 'light',
    ThemeMode.dark => 'dark',
    ThemeMode.system => 'system',
  };
  await ref
      .read(lunioRepositoryProvider)
      .setPreferenceValue('themeMode', value);
  invalidatePreferenceProviders(ref);
}

Future<T?> _showLunioModalSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  bool showDragHandle = false,
  Color? backgroundColor,
  bool barrierDismissible = true,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierColor: Colors.transparent,
    barrierDismissible: false,
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (context, animation, secondaryAnimation) {
      final child = Material(
        type: MaterialType.transparency,
        child: builder(context),
      );
      return _LunioModalBackdrop(
        alignment: Alignment.bottomCenter,
        barrierDismissible: barrierDismissible,
        useSafeArea: false,
        child: FractionallySizedBox(
          widthFactor: 1,
          child: backgroundColor == Colors.transparent
              ? child
              : _LunioDefaultSheetSurface(
                  showDragHandle: showDragHandle,
                  child: child,
                ),
        ),
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(opacity: animation, child: child);
    },
  );
}

Future<T?> _showLunioDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierColor: Colors.transparent,
    barrierDismissible: false,
    transitionDuration: const Duration(milliseconds: 160),
    pageBuilder: (context, animation, secondaryAnimation) {
      return _LunioModalBackdrop(
        alignment: Alignment.center,
        barrierDismissible: barrierDismissible,
        useSafeArea: true,
        child: builder(context),
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final scale = Tween<double>(
        begin: 0.98,
        end: 1,
      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));
      return FadeTransition(
        opacity: animation,
        child: ScaleTransition(scale: scale, child: child),
      );
    },
  );
}

class _LunioModalBackdrop extends StatelessWidget {
  const _LunioModalBackdrop({
    required this.alignment,
    required this.barrierDismissible,
    required this.useSafeArea,
    required this.child,
  });

  final AlignmentGeometry alignment;
  final bool barrierDismissible;
  final bool useSafeArea;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scrimOpacity = isDark ? 0.30 : 0.18;
    return SizedBox.expand(
      child: Stack(
        children: [
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
              child: ColoredBox(
                color: Colors.black.withValues(alpha: scrimOpacity),
              ),
            ),
          ),
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: barrierDismissible
                  ? () => Navigator.of(context).maybePop()
                  : null,
            ),
          ),
          if (useSafeArea)
            SafeArea(
              child: _LunioModalContent(alignment: alignment, child: child),
            )
          else
            _LunioModalContent(alignment: alignment, child: child),
        ],
      ),
    );
  }
}

class _LunioModalContent extends StatelessWidget {
  const _LunioModalContent({required this.alignment, required this.child});

  final AlignmentGeometry alignment;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: GestureDetector(onTap: () {}, child: child),
    );
  }
}

class _LunioDefaultSheetSurface extends StatelessWidget {
  const _LunioDefaultSheetSurface({
    required this.showDragHandle,
    required this.child,
  });

  final bool showDragHandle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    return Container(
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(tokens.radiusXl),
        ),
        boxShadow: [
          BoxShadow(
            color: tokens.ink.withValues(alpha: 0.18),
            blurRadius: 54,
            offset: const Offset(0, -20),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showDragHandle) ...[
            const SizedBox(height: 8),
            Container(
              width: 48,
              height: 5,
              decoration: BoxDecoration(
                color: tokens.line,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 8),
          ],
          child,
        ],
      ),
    );
  }
}

Future<void> _deleteCar(BuildContext context, WidgetRef ref, Car car) async {
  final confirmed = await _showConfirmDialog(
    context: context,
    title: '删除车辆',
    message: '确定删除 ${car.brand} ${car.model}？相关项目和记录会同步删除。',
    confirmLabel: '删除',
  );
  if (confirmed != true || car.id == null) {
    return;
  }
  await ref.read(lunioRepositoryProvider).deleteCar(car.id!);
  invalidateVehicleProviders(ref);
}

Future<bool?> _showConfirmDialog({
  required BuildContext context,
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = true,
}) {
  return _showLunioDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (context) {
      final tokens = Theme.of(context).extension<LunioTokens>()!;
      final confirmColor = destructive ? tokens.danger : tokens.primary;
      return Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        backgroundColor: Colors.transparent,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: tokens.surface,
            borderRadius: BorderRadius.circular(tokens.radiusLarge),
            border: Border.all(color: tokens.line),
            boxShadow: [
              BoxShadow(
                color: tokens.ink.withValues(alpha: 0.16),
                blurRadius: 36,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(message, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: LunioSecondaryButton(
                      label: '取消',
                      onPressed: () => Navigator.of(context).pop(false),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                        backgroundColor: confirmColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            tokens.radiusMedium,
                          ),
                        ),
                      ),
                      onPressed: () => Navigator.of(context).pop(true),
                      child: Text(confirmLabel),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}

Future<void> _showMessageDialog({
  required BuildContext context,
  required String title,
  required String message,
  required _StatusOverlayTone tone,
}) {
  return _showLunioDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (context) {
      final tokens = Theme.of(context).extension<LunioTokens>()!;
      final toneColor = _statusToneColor(tokens, tone);
      return Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        backgroundColor: Colors.transparent,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: tokens.surface,
            borderRadius: BorderRadius.circular(tokens.radiusLarge),
            border: Border.all(color: tokens.line),
            boxShadow: [
              BoxShadow(
                color: tokens.ink.withValues(alpha: 0.16),
                blurRadius: 36,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(_statusToneIcon(tone), color: toneColor, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(message, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                    backgroundColor: toneColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(tokens.radiusMedium),
                    ),
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('确认'),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

void _dismissTransientUi(BuildContext context) {
  FocusManager.instance.primaryFocus?.unfocus();
  _hideStatusOverlay();
  ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
}

enum _StatusOverlayTone { success, error, info }

OverlayEntry? _statusOverlayEntry;

void _hideStatusOverlay() {
  _statusOverlayEntry?.remove();
  _statusOverlayEntry = null;
}

void _showStatusOverlay(
  BuildContext context,
  String message,
  _StatusOverlayTone tone,
) {
  final tokens = Theme.of(context).extension<LunioTokens>()!;
  final overlay = Overlay.maybeOf(context);
  if (overlay == null) {
    return;
  }
  _hideStatusOverlay();
  final entry = OverlayEntry(
    builder: (context) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: _StatusOverlay(
            message: message,
            tokens: tokens,
            tone: tone,
            onDismiss: _hideStatusOverlay,
          ),
        ),
      );
    },
  );
  _statusOverlayEntry = entry;
  overlay.insert(entry);
}

class _StatusOverlay extends StatefulWidget {
  const _StatusOverlay({
    required this.message,
    required this.tokens,
    required this.tone,
    required this.onDismiss,
  });

  final String message;
  final LunioTokens tokens;
  final _StatusOverlayTone tone;
  final VoidCallback onDismiss;

  @override
  State<_StatusOverlay> createState() => _StatusOverlayState();
}

class _StatusOverlayState extends State<_StatusOverlay> {
  Timer? timer;

  @override
  void initState() {
    super.initState();
    timer = Timer(const Duration(milliseconds: 1600), widget.onDismiss);
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = widget.tokens;
    final toneColor = _statusToneColor(tokens, widget.tone);
    return Material(
      color: Colors.transparent,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tokens.surface,
          borderRadius: BorderRadius.circular(tokens.radiusMedium),
          border: Border.all(color: tokens.line),
          boxShadow: [
            BoxShadow(
              color: tokens.ink.withValues(alpha: 0.16),
              blurRadius: 28,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_statusToneIcon(widget.tone), color: toneColor, size: 20),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  widget.message,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: tokens.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Color _statusToneColor(LunioTokens tokens, _StatusOverlayTone tone) {
  return switch (tone) {
    _StatusOverlayTone.success => tokens.success,
    _StatusOverlayTone.error => tokens.danger,
    _StatusOverlayTone.info => tokens.primary,
  };
}

IconData _statusToneIcon(_StatusOverlayTone tone) {
  return switch (tone) {
    _StatusOverlayTone.success => Icons.check_circle_outline,
    _StatusOverlayTone.error => Icons.error_outline,
    _StatusOverlayTone.info => Icons.info_outline,
  };
}

bool _isUniqueConstraintError(Object error) {
  final message = error.toString();
  return message.contains('UNIQUE constraint') ||
      message.contains('SqliteException(2067)');
}

String _friendlyError(Object error) {
  final message = error.toString();
  if (message.contains('这辆车当天')) {
    return message.replaceFirst('Bad state: ', '');
  }
  if (message.contains('UNIQUE constraint') ||
      message.contains('SqliteException(2067')) {
    return '这条数据已经保存过了';
  }
  if (message.contains('At least one maintenance item must stay enabled')) {
    return '至少保留一个可用保养项目';
  }
  if (message.contains('Maintenance item has history records')) {
    return '已有保养记录的项目不能删除';
  }
  if (message.contains('contains missing items')) {
    return '选择的保养项目不存在，请重新选择';
  }
  if (message.contains('items from another car')) {
    return '保养项目不属于当前车辆，请重新选择';
  }
  return '操作失败，请稍后重试';
}

String _formatDateForUser(LocalDate date) {
  return '${date.year}年${date.month}月${date.day}日';
}

String _formatNumber(int value) {
  final text = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < text.length; i++) {
    final fromEnd = text.length - i;
    buffer.write(text[i]);
    if (fromEnd > 1 && fromEnd % 3 == 1) {
      buffer.write(',');
    }
  }
  return buffer.toString();
}
