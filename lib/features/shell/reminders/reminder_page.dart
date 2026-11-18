// 提醒页（/reminders，默认首页）。
//
// 页面结构（自上而下）：
//   1. LoadingPage / ErrorPage：应用车辆加载中/失败；
//   2. 无车 → EmptyVehicleCard（"还没有车辆"+ 新增入口）；
//      有车 → LunioHeroCard 大渐变卡（品牌车型 + 当前里程 + 到期概览，
//      右上角"更新里程"打开快捷改里程 sheet + 「连接OBD」快速连接胶囊
//      按钮（ADR 0027，诊断开关开且有设备记忆才显示））；
//   3. 已连接时英雄卡下方插油量水温信息卡（ObdReadingsCard，实时读数，
//      点击进诊断页）；
//   4. ReminderActionRow：新增保养记录 / 停车倒计时 两个按钮；
//   5. 停车倒计时进行中 → ParkingCountdownCard（进度环 + 结束按钮）；
//   6. ReminderList：平铺量规清单（ADR 0018 修订节，见 reminder_list.dart）。
//
// 性能（R11 修复后）：停车倒计时卡片内部 1s Timer 自刷新，
// 页面本身不再有周期性重建；英雄卡"到期概览"只在数据变化时重算。
// ignore_for_file: use_key_in_widget_constructors, library_private_types_in_public_api

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/theme/lunio_tokens.dart';
import '../../../core/widgets/lunio_components.dart';
import '../../../data/repositories/diagnostics_repository.dart'
    show DiagnosticsRepository;
import '../../../domain/entities/car.dart';
import '../../../domain/entities/reminder.dart';
import '../../../domain/entities/sync_metadata.dart';
import '../../../domain/entities/diagnostics_probe.dart';
import '../diagnostics/diagnostics_connection_controller.dart';
import '../diagnostics/elm327_parser.dart' show ObdValue;
import '../diagnostics/obd_runtime.dart';
import '../profile/vehicles.dart';
import '../records/records_page.dart';
import '../shared/shell_shared.dart';
import '../../../domain/rules/diagnostics_rules.dart';
import 'obd_quick_connect.dart';
import 'parking_countdown.dart';
import 'reminder_list.dart';
import 'reminder_rows.dart';

/// 提醒页组件。
class ReminderPreviewPage extends ConsumerStatefulWidget {
  const ReminderPreviewPage();

  @override
  ConsumerState<ReminderPreviewPage> createState() =>
      ReminderPreviewPageState();
}

class ReminderPreviewPageState extends ConsumerState<ReminderPreviewPage> {
  /// build：watch 全部数据 → 按加载态/空态/正常态渲染。
  /// 停车倒计时卡自刷新秒级进度（卡片内部 Timer），页面无周期重建。
  /// now 用系统真实时间（停车倒计时不受手动日期影响），
  /// 作为倒计时表单的初始入场时间和卡片首帧基准。
  /// canSwitchCar：多于一辆车时右上角显示"切换车辆"按钮。
  @override
  Widget build(BuildContext context) {
    final appliedCar = ref.watch(appliedCarProvider);
    final cars = ref.watch(carsProvider);
    final reminderRows = ref.watch(reminderRowsProvider);
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
    // OBD 快速连接（ADR 0027）：App 级连接控制器 + 显隐两条件（诊断开
    // 关开 + 有设备记忆）+ 后台核心检测点清单（轮询换防的数据源）。
    final connection = ref.watch(obdConnectionControllerProvider);
    final diagnosticsEnabled = ref
        .watch(diagnosticsEnabledProvider)
        .maybeWhen(data: (value) => value, orElse: () => false);
    final lastObdDeviceId = ref
        .watch(lastObdDeviceIdProvider)
        .maybeWhen(data: (value) => value, orElse: () => null);
    // 到期概览指标：就绪时按分段渲染（超期/到期染进度条同源的语义色，
    // 2026-11-16 拍板接受渐变底对比度代价），loading/error 沿用纯文本。
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    final overviewMetric = reminderRows.when(
      loading: () => const LunioMetric(label: '到期概览', value: '计算中'),
      error: (error, stackTrace) =>
          const LunioMetric(label: '到期概览', value: '加载失败'),
      data: (value) => LunioMetric(
        label: '到期概览',
        // 保留纯文本投影（无障碍读屏/测试查找走它），渲染用分段。
        value: dueOverviewText(value),
        segments: dueOverviewSegments(value)
            .map(
              (segment) => LunioMetricSegment(
                segment.text,
                color: _overviewSegmentColor(segment.status, tokens),
              ),
            )
            .toList(),
      ),
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
          else ...[
            // 英雄卡与油量水温信息卡共享连接状态（按钮四态/卡片显隐/
            // 读数刷新），ListenableBuilder 一处收口。
            ListenableBuilder(
              listenable: connection,
              builder: (context, _) {
                final state = connection.state;
                final connected =
                    state.phase == DiagnosticsConnectionPhase.connected;
                // 后台核心清单换防（不触发通知的快照推入）：检测点数据
                // 到位后把油量/水温两条推给连接控制器，轮询按作用域取用。
                final carId = car.id;
                final probesAsync = carId == null
                    ? null
                    : ref.watch(diagnosticsProbesProvider(carId));
                final probes = probesAsync?.maybeWhen(
                  data: (value) => value,
                  orElse: () => null,
                );
                if (probes != null) {
                  connection.setBackgroundProbes(
                    _coreProbesOf(probes),
                  );
                }
                final fuelProbe = probes == null
                    ? null
                    : _probeByCatalogKey(
                        probes,
                        DiagnosticsRepository.builtInFuelLevelKey,
                      );
                final coolantProbe = probes == null
                    ? null
                    : _probeByCatalogKey(
                        probes,
                        DiagnosticsRepository.builtInCoolantKey,
                      );
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LunioHeroCard(
                      title: '${car.brand} ${car.model}',
                      actionLabel: '更新里程',
                      onAction: () =>
                          showQuickMileageUpdateSheet(context, ref, car),
                      secondaryAction: diagnosticsEnabled && lastObdDeviceId != null
                          ? ObdQuickConnectButton(
                              phase: state.phase,
                              onTap: () =>
                                  _handleObdConnectTap(context, connection),
                            )
                          : null,
                      metrics: [
                        LunioMetric(
                          label: '当前里程',
                          value: formatNumber(car.currentMileageKm),
                        ),
                        overviewMetric,
                      ],
                    ),
                    if (connected &&
                        fuelProbe != null &&
                        coolantProbe != null) ...[
                      const SizedBox(height: 12),
                      ObdReadingsCard(
                        fuelDisplay: switch (
                            connection.liveReadingFor(fuelProbe)?.reading) {
                          final ObdValue v => v.display,
                          _ => null,
                        },
                        coolantDisplay: switch (
                            connection.liveReadingFor(coolantProbe)?.reading) {
                          final ObdValue v => v.display,
                          _ => null,
                        },
                        coolantTone: switch (
                            connection.liveReadingFor(coolantProbe)?.reading) {
                          ObdValue(:final celsius?) =>
                              DiagnosticsRules.coolantTempTone(celsius),
                          _ => null,
                        },
                        onRefresh: connection.requestImmediatePoll,
                        onOpen: () => context.push('/diagnostics'),
                      ),
                    ],
                  ],
                );
              },
            ),
          ],
          if (car != null) ...[
            const SizedBox(height: 12),
            ReminderActionRow(
              onAddRecord: () => showMaintenanceRecordFormSheet(context, ref),
              onParkingCountdown: currentParkingCountdown == null
                  ? () => showParkingCountdownSheet(context, ref)
                  : null,
            ),
          ],
          SizedBox(height: currentParkingCountdown == null ? 14 : 22),
          if (currentParkingCountdown != null) ...[
            ParkingCountdownCard(
              countdown: currentParkingCountdown,
              now: now,
              onEnd: () => clearParkingCountdown(ref),
              onExpired: () => notifyParkingCountdownExpired(ref),
            ),
            const SizedBox(height: 22),
          ],
          if (car != null) const ReminderList(),
        ],
      ),
    );
  }

  /// 「连接OBD」按钮点击（ADR 0027）：绿=断开；黄=无效果；白/红=直连
  /// 设备记忆（不落扫描）。失败 toast 错误文案（Disconnected 事件经流
  /// 递送，让一拍再读 statusError）。
  Future<void> _handleObdConnectTap(
    BuildContext context,
    DiagnosticsConnectionController connection,
  ) async {
    final phase = connection.state.phase;
    if (phase == DiagnosticsConnectionPhase.connected) {
      await connection.disconnectManually();
      return;
    }
    if (phase == DiagnosticsConnectionPhase.connecting ||
        phase == DiagnosticsConnectionPhase.scanning) {
      return;
    }
    final ok = await connection.connectRemembered();
    if (!ok) {
      await Future<void>.delayed(Duration.zero);
      final error = connection.state.statusError;
      if (context.mounted) {
        showStatusOverlay(
          context,
          error ?? '连接失败，请重试',
          StatusOverlayTone.error,
        );
      }
    }
  }

  /// 按内置 catalogKey 定位检测点（与诊断页同一份 key 常量，单一事实源）。
  DiagnosticsProbe? _probeByCatalogKey(
    List<DiagnosticsProbe> probes,
    String catalogKey,
  ) {
    for (final probe in probes) {
      if (probe.catalogKey == catalogKey) {
        return probe;
      }
    }
    return null;
  }

  /// 后台核心清单：油量 + 水温 + 里程表三条（2026-11-18 拍板：里程表
  /// 升内置后进背景轮询，ECU 里程同步「只要连接就更新」，ADR 0026 修订节）。
  List<DiagnosticsProbe> _coreProbesOf(List<DiagnosticsProbe> probes) {
    return [
      for (final probe in probes)
        if (probe.catalogKey == DiagnosticsRepository.builtInFuelLevelKey ||
            probe.catalogKey == DiagnosticsRepository.builtInCoolantKey ||
            probe.catalogKey == DiagnosticsRepository.builtInOdometerKey)
          probe,
    ];
  }
}

// ---------------- 到期概览的分段配色 ----------------

/// 概览分段 → 颜色：danger/warning 染进度条同源的语义色（2026-11-16
/// 拍板：值文案与项目提醒进度条颜色保持一致，接受浅色渐变底上对比度
/// 下降的代价），其余（中性段）走默认白。
Color? _overviewSegmentColor(ReminderStatus? status, LunioTokens tokens) {
  return switch (status) {
    ReminderStatus.danger => tokens.danger,
    ReminderStatus.warning => tokens.warning,
    _ => null,
  };
}

/// 两个主操作按钮的行：新增保养记录（打开记录表单 sheet）+
/// 停车倒计时（倒计时进行中时禁用——必须先结束当前倒计时）。
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
          child: LunioPrimaryButton(
            label: '新增保养记录',
            icon: Icons.post_add,
            onPressed: onAddRecord,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: LunioPrimaryButton(
            label: '停车倒计时',
            icon: Icons.timer_outlined,
            onPressed: onParkingCountdown,
          ),
        ),
      ],
    );
  }
}

// ---------------- 快捷更新里程（英雄卡"更新里程"入口） ----------------

/// 快捷更新里程 sheet：输入框默认留空 + autofocus 自动弹数字键盘，
/// 保存走动作层 updateCar（写库 → 失效车辆家族，与编辑车辆表单同通道，
/// 同步元数据也按 pendingUpdate 处理）。装载/守卫/pop/toast 时序归
/// showLunioFormSheet（ADR 0016）。
/// 新里程不高于当前里程（含相等）时先弹确认框警示——里程表只增不减，
/// 输小了九成是手误；确认后仍可保存，与编辑车辆表单"允许改小"的现行
/// 规则不冲突（宽松规则是否收敛见审查台账 R36，本次只给快捷入口加摩擦）。
void showQuickMileageUpdateSheet(BuildContext context, WidgetRef ref, Car car) {
  final controller = TextEditingController();
  showLunioFormSheetNoLoad<void>(
    context: context,
    title: '更新里程',
    subtitle: '当前 ${formatMileageKm(car.currentMileageKm)}，输入新的当前里程',
    builder: (sheetContext, handle) {
      return _QuickMileageForm(
        controller: controller,
        car: car,
        handle: handle,
        // 写库+失效收进动作层（ADR 0007）；关 sheet 与成功 toast 归
        // 表单运行时（ADR 0016）。
        onSubmit: (mileage) => updateCar(
          ref,
          car.copyWith(
            currentMileageKm: mileage,
            sync: SyncMetadata(
              status: SyncStatus.pendingUpdate,
              updatedAt: DateTime.now(),
            ),
          ),
        ),
      );
    },
    successMessage: '里程已更新',
  );
}

/// 快捷更新里程表单：纯整数里程（km），留空提交按校验错误处理；
/// 未调高（≤ 当前里程）的确认框在提交时拦截，确认后才落库。
class _QuickMileageForm extends StatefulWidget
    implements FormSheetHandleWidget {
  const _QuickMileageForm({
    required this.controller,
    required this.car,
    required this.handle,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final Car car;

  /// 表单运行时把手（ADR 0016）：saving/行内错误/提交/关闭都经它。
  @override
  final FormSheetHandle<void> handle;
  final Future<void> Function(int mileage) onSubmit;

  @override
  State<_QuickMileageForm> createState() => _QuickMileageFormState();
}

class _QuickMileageFormState extends State<_QuickMileageForm>
    with FormSheetHandleHost<_QuickMileageForm> {

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LunioNumberField(
          controller: widget.controller,
          enabled: !saving,
          autofocus: true,
          decimals: 0,
          labelText: '当前里程',
          suffixText: 'km',
          onSubmitted: (_) => saving ? null : _submit(),
        ),
        if (errorText != null) ...[
          const SizedBox(height: 10),
          LunioInlineMessage(message: errorText!, tone: LunioStatusTone.danger),
        ],
        const SizedBox(height: 18),
        LunioFormActions(
          confirmLabel: '保存里程',
          onCancel: () => widget.handle.close(),
          onConfirm: _submit,
          saving: saving,
        ),
      ],
    );
  }

  Future<void> _submit() async {
    final text = widget.controller.text.trim();
    // 输入过滤器已限纯数字，这里兜底处理留空；负数不可能出现。
    final mileage = int.tryParse(text);
    if (text.isEmpty || mileage == null) {
      setFormError('请输入当前里程');
      return;
    }
    if (mileage <= widget.car.currentMileageKm) {
      // 确认框在提交生命周期之前：取消 = 留场继续改，不产生错误提示。
      final confirmed = await showConfirmDialog(
        context: context,
        title: '里程未调高',
        message:
            '新里程（${formatMileageKm(mileage)}）不高于当前里程'
            '（${formatMileageKm(widget.car.currentMileageKm)}），确认仍要保存吗？',
        confirmLabel: '仍要保存',
        // 非破坏性确认：确认键用主色而非删除红。
        destructive: false,
      );
      if (confirmed != true) {
        return;
      }
    }
    await widget.handle.submit(() => widget.onSubmit(mileage));
  }
}
