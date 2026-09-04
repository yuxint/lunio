// 停车倒计时：卡片展示 + 开始/结束表单 + 时间选择器 + 保存/清除动作。
//
// 用户流程：
//   提醒页点"停车倒计时" → showParkingCountdownSheet（表单：入场时间 +
//   免费时长[快捷 0.5/1/2 小时]）→ saveParkingCountdown（写偏好 +
//   调系统通知：Android 常驻 chronometer 通知 + 到点闹钟）；
//   卡片内部 1s Timer 自刷新剩余时间（R11：不再由整页 250ms ticker
//   驱动重建）；点"结束" → clearParkingCountdown（删偏好 + 取消两条
//   系统通知）。
//
// 状态颜色复用保养提醒三态：剩余 >20% 绿 / ≤20% 黄 / 到期红（改计正时长）。
// 注意：倒计时用系统真实时间，不受开发者模式手动日期影响；
// 到期后不会自动清除（偏好里一直留着，须手动"结束"才能开始新的，R9）。
// ignore_for_file: use_key_in_widget_constructors, library_private_types_in_public_api

import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/format/clock.dart';
import '../../../core/theme/lunio_tokens.dart';
import '../../../core/widgets/lunio_components.dart';
import '../../../domain/entities/parking_countdown.dart';
import '../../../domain/entities/reminder.dart';
import '../../../domain/rules/parking_countdown_rules.dart';
import '../shared/shell_shared.dart';
import 'notification_coordinator.dart';
import 'reminder_list.dart';

/// 倒计时进行中的展示卡片（提醒页内嵌）：入场信息 + 进度环 +
/// 剩余/超时时长 + 到点时刻 + "结束"按钮。
///
/// R11 后卡片自驱动刷新：内部 1s Timer 每秒从 appDateContext 读系统
/// 真实时间并 setState——重建范围只有这张卡，提醒页其余部分不再跟随
/// 秒级重建（原实现是页面级 250ms ticker 整页 setState）。
/// now 参数是首次构建的基准时间（页面 watch 时传入），之后由 Timer 接管。
class ParkingCountdownCard extends ConsumerStatefulWidget {
  const ParkingCountdownCard({
    required this.countdown,
    required this.now,
    required this.onEnd,
  });

  final ParkingCountdown countdown;
  final DateTime now;
  final VoidCallback onEnd;

  @override
  ConsumerState<ParkingCountdownCard> createState() =>
      _ParkingCountdownCardState();
}

class _ParkingCountdownCardState extends ConsumerState<ParkingCountdownCard> {
  Timer? _ticker;

  /// 卡片当前使用的"现在"（每秒刷新；倒计时存在即计时，
  /// 到点后继续正计"停车时长"）。
  late DateTime _now;

  @override
  void initState() {
    super.initState();
    _now = widget.now;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        return;
      }
      setState(() => _now = ref.read(appDateContextProvider).readSystemNow());
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    final countdown = widget.countdown;
    final progress = ParkingCountdownRules.progress(
      countdown: countdown,
      now: _now,
    );
    final color = _parkingStatusColor(tokens, progress.status);
    final animatedPercent = progress.status == ReminderStatus.danger
        ? 100.0
        : progress.percentRemaining;
    final elapsedSeconds = _now.difference(countdown.startedAt).inSeconds;
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
                      '${formatClock(countdown.startedAt)} 入场 · 免费 ${_formatParkingDurationOption(countdown.durationSeconds)}',
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
                      ? '${formatClock(countdown.endsAt)} 已到点'
                      : '${formatClock(countdown.endsAt)} 前离场',
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
              onPressed: widget.onEnd,
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

/// 倒计时开始表单：入场时间（点开时间轮选择器）+ 免费时长输入框
/// + 快捷时长 chip + 校验 + 开始按钮。入口仅在无倒计时且按钮可用，
/// 无编辑分支（原 initial 死分支已删，R26）。
class ParkingCountdownForm extends StatefulWidget {
  const ParkingCountdownForm({required this.now, required this.onSubmit});

  final DateTime now;
  final Future<void> Function(ParkingCountdown countdown) onSubmit;

  @override
  State<ParkingCountdownForm> createState() => ParkingCountdownFormState();
}

class ParkingCountdownFormState extends State<ParkingCountdownForm>
    with LunioFormSubmit {
  late DateTime entryTime;
  late final TextEditingController durationMinutesController;

  @override
  void initState() {
    super.initState();
    entryTime = widget.now;
    durationMinutesController = TextEditingController(text: '30');
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
          value: formatClock(entryTime),
          enabled: !saving,
          onTap: saving ? null : _pickEntryTime,
        ),
        const SizedBox(height: 10),
        LunioNumberField(
          controller: durationMinutesController,
          enabled: !saving,
          labelText: '免费时长',
          suffixText: '分钟',
          onChanged: (_) => setFormError(null),
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
        LunioFormActions(
          confirmLabel: '开始计时',
          onCancel: () => Navigator.of(context).pop(),
          onConfirm: _submit,
          saving: saving,
        ),
      ],
    );
  }

  /// 点"入场时间"打开时:分:秒三轮滚轮选择器（日期固定为 initial 的日期，
  /// 不可跨天——入场时间只能选当天）。
  Future<void> _pickEntryTime() async {
    final selected = await showParkingEntryTimePicker(
      context,
      initial: entryTime,
    );
    if (selected == null || !mounted) {
      return;
    }
    setState(() => entryTime = selected);
    setFormError(null);
  }

  int? get _durationMinutes {
    return int.tryParse(durationMinutesController.text.trim());
  }

  void _setDurationMinutes(int minutes) {
    setState(() => durationMinutesController.text = minutes.toString());
    setFormError(null);
  }

  /// 提交：校验免费时长为正整数 → 构造 ParkingCountdown（分钟→秒）→
  /// onSubmit（保存+通知）→ 成功关 sheet；失败经提交运行器在表单内
  /// 展示中文错误。
  Future<void> _submit() async {
    final durationMinutes = _durationMinutes;
    if (durationMinutes == null || durationMinutes <= 0) {
      setFormError('免费时长必须填写正整数分钟');
      return;
    }
    await runSubmit(() async {
      await widget.onSubmit(
        ParkingCountdown(
          startedAt: entryTime,
          durationSeconds: durationMinutes * 60,
        ),
      );
      if (mounted) {
        Navigator.of(context).pop();
      }
    });
  }
}

/// 时/分/秒三个滚轮（CupertinoPicker，iOS 风格的 picker 在两端通用）。
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
    return Column(
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
        LunioFormActions(
          confirmLabel: '确定',
          onCancel: () => Navigator.of(context).pop(),
          onConfirm: () => Navigator.of(context).pop(
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
      ],
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

/// 时间选择器入口（sheet 弹出），返回所选 DateTime 或 null。
Future<DateTime?> showParkingEntryTimePicker(
  BuildContext context, {
  required DateTime initial,
}) {
  return showLunioModalSheet<DateTime>(
    context: context,
    builder: (context) => PrototypeSheetFrame(
      title: '选择入场时间',
      subtitle: '按当前日期选择时、分、秒。',
      child: ParkingEntryTimePicker(initial: initial),
    ),
  );
}

/// 快捷时长 chip（0.5/1/2 小时）。
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

/// 停车计时 sheet 入口（提醒页"停车倒计时"按钮）。
/// 点按钮的此刻实时取系统时间（不用页面构建时缓存的时间，页面开久了
/// 会过期），秒/毫秒截成 0：入场时间默认整分，需要秒再手动调滚轮。
/// bottomInset 跟随键盘高度，键盘弹起时把内容顶上去。
/// context 是页面级 context：传给 saveParkingCountdown 做"页面仍在
/// 挂载"的检查（sheet 可能先一步关闭）。
Future<void> showParkingCountdownSheet(
  BuildContext context,
  WidgetRef ref,
) {
  return showLunioModalSheet<void>(
    context: context,
    builder: (sheetContext) {
      final bottomInset = MediaQuery.of(sheetContext).viewInsets.bottom;
      final tappedNow = ref.read(appDateContextProvider).readSystemNow();
      final entryTime = DateTime(
        tappedNow.year,
        tappedNow.month,
        tappedNow.day,
        tappedNow.hour,
        tappedNow.minute,
      );
      return PrototypeSheetFrame(
        title: '停车计时',
        subtitle: '设置入场时间和免费停车时长。',
        bottomInset: bottomInset,
        child: ParkingCountdownForm(
          now: entryTime,
          onSubmit: (countdown) =>
              saveParkingCountdown(context, ref, countdown),
        ),
      );
    },
  );
}

/// ★ 保存倒计时的完整动作链：
///  1. 写偏好 parkingCountdown + 失效 provider（卡片立即出现）；
///  2. 通知尾巴委托协调器 onParkingCountdownSaved：请求权限（被拒回写
///     "系统通知关闭"）、比对同步代数（R8）、申请精确闹钟、调度
///     9001 到点闹钟 + 9002 Android 常驻通知。
/// await 后检查页面 context 仍挂载（R13）；sheet 提前关闭时通知尾巴
/// 照常走完（调度不依赖页面）。
Future<void> saveParkingCountdown(
  BuildContext context,
  WidgetRef ref,
  ParkingCountdown countdown,
) async {
  await ref.read(lunioPreferencesProvider).saveParkingCountdown(countdown);
  if (!context.mounted) {
    return;
  }
  ref.invalidate(parkingCountdownProvider);
  await ref
      .read(notificationCoordinatorProvider)
      .onParkingCountdownSaved(countdown);
}

/// ★ 结束倒计时：删偏好 + 失效 provider + 通知收尾委托协调器
/// （系统通知开着时取消 9001/9002 两条系统通知，关着时本来就没调度过）。
/// await 后检查页面 context 仍挂载（R13）。
Future<void> clearParkingCountdown(BuildContext context, WidgetRef ref) async {
  await ref.read(lunioPreferencesProvider).clearParkingCountdown();
  if (!context.mounted) {
    return;
  }
  ref.invalidate(parkingCountdownProvider);
  await ref.read(notificationCoordinatorProvider).onParkingCountdownCleared();
}

// ---- 私有格式化函数 ----
// HH:mm:ss 的 formatClock 已合并到 shared/formatters.dart（§5.3.3，
// 与通知服务共用同一实现）；其余为倒计时专用格式化。

/// 倒计时数字：≥1 小时显示 HH:mm:ss，否则 mm:ss。
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

/// 中文时长（"1小时 30分钟"）。
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

/// 卡片副标题的免费时长文案（三个快捷档显示友好文案，其余走通用格式化）。
String _formatParkingDurationOption(int seconds) {
  return switch (seconds) {
    1800 => '0.5 小时',
    3600 => '1 小时',
    7200 => '2 小时',
    _ => _formatCountdownDuration(seconds),
  };
}

/// 提醒三态 → token 颜色。
Color _parkingStatusColor(LunioTokens tokens, ReminderStatus status) {
  return status.tone.statusForeground(tokens);
}
