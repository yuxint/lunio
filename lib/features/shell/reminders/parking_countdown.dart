// ignore_for_file: use_key_in_widget_constructors, library_private_types_in_public_api

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/notifications/lunio_notification_service.dart';
import '../../../core/theme/lunio_tokens.dart';
import '../../../core/widgets/lunio_components.dart';
import '../../../domain/entities/parking_countdown.dart';
import '../../../domain/entities/reminder.dart';
import '../../../domain/rules/parking_countdown_rules.dart';
import '../shared/shell_shared.dart';
import 'reminder_list.dart';

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
