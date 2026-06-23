// ignore_for_file: use_key_in_widget_constructors, library_private_types_in_public_api

import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/date/local_date.dart';
import '../../../core/notifications/lunio_notification_service.dart';
import '../../../core/theme/lunio_tokens.dart';
import '../../../core/widgets/lunio_components.dart';
import '../../../data/repositories/lunio_repository.dart';
import '../../../domain/entities/car.dart';
import '../../../domain/entities/maintenance_item.dart';
import '../../../domain/entities/maintenance_record.dart';
import '../../../domain/entities/notification_settings.dart';
import '../../../domain/entities/parking_countdown.dart';
import '../../../domain/entities/reminder.dart';
import '../../../domain/rules/maintenance_rules.dart';
import '../../../domain/rules/parking_countdown_rules.dart';
import '../profile/profile_page.dart';
import '../records/records_page.dart';
import '../shared/shell_shared.dart';

class ReminderPreviewPage extends ConsumerStatefulWidget {
  const ReminderPreviewPage();

  @override
  ConsumerState<ReminderPreviewPage> createState() =>
      ReminderPreviewPageState();
}

class ReminderPreviewPageState extends ConsumerState<ReminderPreviewPage> {
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
      loading: () => const LoadingPage(title: '保养提醒'),
      error: (error, stackTrace) => ErrorPage(title: '保养提醒', error: error),
      data: (car) => LunioPage(
        title: '保养提醒',
        trailing: canSwitchCar
            ? LunioIconButton(
                icon: Icons.directions_car_outlined,
                tooltip: '切换车辆',
                onPressed: () => showVehicleSwitcher(context, ref),
              )
            : null,
        children: [
          if (car == null)
            EmptyVehicleCard(onAdd: () => showAddCarSheet(context, ref))
          else
            LunioHeroCard(
              title: '${car.brand} ${car.model}',
              subtitle: '上路 ${car.roadDate} · 当前应用车辆',
              metrics: [
                LunioMetric(
                  label: '当前里程',
                  value: formatNumber(car.currentMileageKm),
                ),
                LunioMetric(
                  label: '到期概览',
                  value: today.when(
                    loading: () => '计算中',
                    error: (error, stackTrace) => '日期失败',
                    data: (value) =>
                        dueOverviewText(items, records, car, value),
                  ),
                ),
              ],
            ),
          if (car != null) ...[
            const SizedBox(height: 12),
            ReminderActionRow(
              onAddRecord: () => showMaintenanceRecordFormSheet(context, ref),
              onParkingCountdown: currentParkingCountdown == null
                  ? () => showParkingCountdownSheet(
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
            ParkingCountdownCard(
              countdown: currentParkingCountdown,
              now: now,
              onEnd: () => clearParkingCountdown(ref),
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
                      LunioCard(child: Text('日期加载失败：${friendlyError(error)}')),
                  data: (value) => ReminderList(
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

class ReminderActionRow extends StatelessWidget {
  const ReminderActionRow({
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

class ParkingCountdownCard extends StatelessWidget {
  const ParkingCountdownCard({
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
    final elapsedSeconds = now.difference(countdown.startedAt).inSeconds;
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
                        painter: ReminderProgressRingPainter(
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
                                    ? _formatCountdownClock(elapsedSeconds)
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
                                  ? '停车时长'
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
            child: SmallActionButton(
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

class ParkingCountdownForm extends StatefulWidget {
  const ParkingCountdownForm({
    required this.now,
    required this.initial,
    required this.onSubmit,
  });

  final DateTime now;
  final ParkingCountdown? initial;
  final Future<void> Function(ParkingCountdown countdown) onSubmit;

  @override
  State<ParkingCountdownForm> createState() => ParkingCountdownFormState();
}

class ParkingCountdownFormState extends State<ParkingCountdownForm> {
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
            ParkingDurationChip(
              label: '0.5 小时',
              selected: _durationMinutes == 30,
              onPressed: saving ? null : () => _setDurationMinutes(30),
            ),
            ParkingDurationChip(
              label: '1 小时',
              selected: _durationMinutes == 60,
              onPressed: saving ? null : () => _setDurationMinutes(60),
            ),
            ParkingDurationChip(
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
    final selected = await showParkingEntryTimePicker(
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
        errorText = friendlyError(error);
      });
    }
  }
}

class ParkingEntryTimePicker extends StatefulWidget {
  const ParkingEntryTimePicker({required this.initial});

  final DateTime initial;

  @override
  State<ParkingEntryTimePicker> createState() => ParkingEntryTimePickerState();
}

class ParkingEntryTimePickerState extends State<ParkingEntryTimePicker> {
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

Future<DateTime?> showParkingEntryTimePicker(
  BuildContext context, {
  required DateTime initial,
}) {
  return showLunioModalSheet<DateTime>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => ParkingEntryTimePicker(initial: initial),
  );
}

class ParkingDurationChip extends StatelessWidget {
  const ParkingDurationChip({
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

Future<void> showParkingCountdownSheet(
  BuildContext context,
  WidgetRef ref, {
  required DateTime now,
  ParkingCountdown? initial,
}) {
  return showLunioModalSheet<void>(
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
          child: ParkingCountdownForm(
            now: now,
            initial: initial,
            onSubmit: (countdown) => saveParkingCountdown(ref, countdown),
          ),
        ),
      );
    },
  );
}

Future<void> saveParkingCountdown(
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

Future<void> clearParkingCountdown(WidgetRef ref) async {
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

class ReminderList extends StatelessWidget {
  const ReminderList({
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
      return LunioCard(child: Text('保养项目加载失败：${friendlyError(items.error!)}'));
    }
    if (records.hasError) {
      return LunioCard(
        child: Text('保养记录加载失败：${friendlyError(records.error!)}'),
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
          ReminderRow(row: row),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class ReminderRow extends StatelessWidget {
  const ReminderRow({required this.row});

  final ReminderViewData row;

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
          onTap: () => showReminderRecordDetail(context, row),
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
                        painter: ReminderProgressRingPainter(
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

void showReminderRecordDetail(BuildContext context, ReminderViewData row) {
  final record = row.latestRecord;
  showLunioModalSheet<void>(
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
                          child: ReminderRecordMetric(
                            label: '上次保养日期',
                            value: record.date.toString(),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ReminderRecordMetric(
                            label: '上次保养里程',
                            value: '${formatNumber(record.mileageKm)} km',
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

class ReminderRecordMetric extends StatelessWidget {
  const ReminderRecordMetric({required this.label, required this.value});

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

class ReminderProgressRingPainter extends CustomPainter {
  const ReminderProgressRingPainter({
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
  bool shouldRepaint(ReminderProgressRingPainter oldDelegate) {
    return percent != oldDelegate.percent ||
        color != oldDelegate.color ||
        backgroundColor != oldDelegate.backgroundColor ||
        strokeWidth != oldDelegate.strokeWidth;
  }
}

enum ReminderDialogAction { acknowledged, snoozed }

Future<ReminderDialogAction?> showMaintenanceReminderDialog({
  required BuildContext context,
  required WidgetRef ref,
  required Car car,
  required List<ReminderViewData> maintenanceNotices,
  required LocalDate today,
}) {
  return showLunioDialog<ReminderDialogAction>(
    context: context,
    barrierDismissible: true,
    builder: (context) {
      return _MaintenanceReminderDialog(
        car: car,
        maintenanceNotices: maintenanceNotices,
        today: today,
        onSnoozeAll: () async {
          final repository = ref.read(lunioRepositoryProvider);
          final until = snoozeUntilDate(today).toString();
          for (final notice in maintenanceNotices) {
            final itemId = notice.item.id;
            if (itemId != null) {
              await repository.setPreferenceValue(
                maintenanceReminderSnoozeKey(itemId),
                until,
              );
            }
          }
        },
      );
    },
  );
}

Future<ReminderDialogAction?> showMileageUpdateReminderDialog({
  required BuildContext context,
  required WidgetRef ref,
  required Car car,
  required LocalDate today,
}) {
  return showLunioDialog<ReminderDialogAction>(
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
                mileageUpdateSnoozeKey(carId),
                snoozeUntilDate(today).toString(),
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
  final List<ReminderViewData> maintenanceNotices;
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
                ReminderNotificationSegment(
                  title: notice.title,
                  body: dueNoticeText(notice),
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
                            ).pop(ReminderDialogAction.acknowledged),
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
    Navigator.of(context).pop(ReminderDialogAction.snoozed);
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
                          ).pop(ReminderDialogAction.acknowledged),
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
    Navigator.of(context).pop(ReminderDialogAction.snoozed);
  }
}

class ReminderViewData {
  const ReminderViewData({
    required this.item,
    required this.progress,
    required this.latestRecord,
  });

  final MaintenanceItem item;
  final ReminderProgress progress;
  final MaintenanceRecord? latestRecord;

  String get title => item.name;

  int get displayPercent => displayPercentForThresholds(
    percent: progress.percent,
    notOverdueUpperLimit: item.notOverdueUpperLimit,
    overdueUpperLimit: item.overdueUpperLimit,
  );

  String get percentText => formatPercent(displayPercent);

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
      details.add(mileageReminderText(progress.mileageRemainingKm!));
    }
    if (item.remindByTime && progress.daysRemaining != null) {
      details.add(timeReminderText(progress.daysRemaining!));
    }
    if (details.isEmpty) {
      details.add('未设置提醒规则');
    }
    return details;
  }
}

List<ReminderViewData> _buildReminderRows({
  required Car car,
  required List<MaintenanceItem> items,
  required List<MaintenanceRecord> records,
  required LocalDate today,
}) {
  final rows = <ReminderViewData>[];
  for (final item in items.where((item) => item.enabled && item.id != null)) {
    final latestRecord = latestRecordForItem(records, item.id!);
    final progress = MaintenanceRules.progressForItem(
      item: item,
      latestRecord: latestRecord,
      currentMileageKm: car.currentMileageKm,
      noHistoryBaselineDate: car.roadDate,
      today: today,
    );
    rows.add(
      ReminderViewData(
        item: item,
        progress: progress,
        latestRecord: latestRecord,
      ),
    );
  }
  rows.sort((left, right) {
    final statusCompare = reminderStatusRank(
      right.progress.status,
    ).compareTo(reminderStatusRank(left.progress.status));
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

Future<List<LunioScheduledNotification>> buildScheduledNotifications({
  required WidgetRef ref,
  required LunioNotificationSettings settings,
  required Car car,
  required List<MaintenanceItem> items,
  required List<MaintenanceRecord> records,
  required LocalDate today,
}) async {
  final repository = ref.read(lunioRepositoryProvider);
  final notifications = <LunioScheduledNotification>[];
  final activeMaintenanceNotices = <ReminderViewData>[];
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
    )) {
      activeMaintenanceNotices.add(notice);
    }
  }
  if (activeMaintenanceNotices.isNotEmpty) {
    notifications.add(
      LunioScheduledNotification(
        id: 8000,
        title: '保养提醒',
        body: maintenanceNoticeSummaryForRows(car, activeMaintenanceNotices),
        repeatFrequency: maintenanceRepeatFrequency(
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
      mileageUpdateReminderDue(car: car, records: records, today: today) &&
      !await isSnoozed(repository, mileageUpdateSnoozeKey(car.id!), today)) {
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

List<DateTime> reservedNotificationDateTimes(
  ParkingCountdown? parkingCountdown,
) {
  if (parkingCountdown == null) {
    return const [];
  }
  return [parkingCountdown.endsAt];
}

String parkingCountdownReminderSignature(ParkingCountdown? parkingCountdown) {
  if (parkingCountdown == null) {
    return 'parking:none';
  }
  return 'parking:${parkingCountdown.endsAt.toIso8601String()}';
}

String reminderNotificationDataSignature({
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

bool mileageUpdateReminderDue({
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

ReminderRepeatFrequency maintenanceRepeatFrequency({
  required LunioNotificationSettings settings,
  required Car car,
  required List<MaintenanceItem> items,
  required List<MaintenanceRecord> records,
  required LocalDate today,
}) {
  return settings.dueRepeatFrequency;
}

String maintenanceNoticeSummaryForRows(
  Car car,
  List<ReminderViewData> notices,
) {
  final first = notices.first;
  return '${car.brand} ${car.model}：到期 ${notices.length} 项。'
      '最紧急：${first.title}，${dueReasonText(first)}';
}

String dueReasonText(ReminderViewData row) {
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

String dueNoticeText(ReminderViewData row) {
  final details = <String>[];
  final daysRemaining = row.progress.daysRemaining;
  if (row.item.remindByTime && daysRemaining != null && daysRemaining <= 0) {
    details.add(
      daysRemaining == 0
          ? '时间今日到期'
          : '已超 ${formatReminderDuration(daysRemaining.abs())}',
    );
  }
  final mileageRemaining = row.progress.mileageRemainingKm;
  if (row.item.remindByMileage &&
      mileageRemaining != null &&
      mileageRemaining <= 0) {
    details.add(
      mileageRemaining == 0
          ? '里程已到期'
          : '已超 ${formatNumber(mileageRemaining.abs())}km',
    );
  }
  if (details.isEmpty) {
    return dueReasonText(row);
  }
  return details.join(' · ');
}

String mileageUpdateSnoozeKey(int carId) {
  return 'mileageUpdateSnoozedUntil:$carId';
}

String mileageUpdateInAppAcknowledgedKey(int carId) {
  return 'mileageUpdateInAppAcknowledgedOn:$carId';
}

String maintenanceReminderSnoozeKey(int itemId) {
  return 'maintenanceReminderSnoozedUntil:$itemId';
}

String maintenanceInAppReminderAcknowledgedKey(int itemId) {
  return 'maintenanceInAppReminderAcknowledgedOn:$itemId';
}

LocalDate snoozeUntilDate(LocalDate today) {
  return LocalDate.fromDateTime(
    today.toDateTime().add(const Duration(days: 15)),
  );
}

Future<bool> isSnoozed(
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

Future<bool> isAcknowledgedToday(
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

List<ReminderViewData> maintenanceNotices({
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
  final notices = <ReminderViewData>[];
  for (final row in rows) {
    if (noticeDueForRow(settings, row)) {
      notices.add(row);
    }
  }
  return notices;
}

bool noticeDueForRow(LunioNotificationSettings settings, ReminderViewData row) {
  if (!settings.maintenanceDueEnabled) {
    return false;
  }
  return row.progress.status == ReminderStatus.warning ||
      row.progress.status == ReminderStatus.danger;
}

MaintenanceRecord? latestRecordForItem(
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

int reminderStatusRank(ReminderStatus status) {
  return switch (status) {
    ReminderStatus.normal => 0,
    ReminderStatus.warning => 1,
    ReminderStatus.danger => 2,
  };
}

String dueOverviewText(
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
