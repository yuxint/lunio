// 提醒页（/reminders，默认首页）。
//
// 页面结构（自上而下）：
//   1. LoadingPage / ErrorPage：应用车辆加载中/失败；
//   2. 无车 → EmptyVehicleCard（"还没有车辆"+ 新增入口）；
//      有车 → LunioHeroCard 大渐变卡（品牌车型 + 当前里程 + 到期概览，
//      右上角"更新里程"打开快捷改里程 sheet，见文件末尾）；
//   3. ReminderActionRow：新增保养记录 / 停车倒计时 两个按钮；
//   4. 停车倒计时进行中 → ParkingCountdownCard（进度环 + 结束按钮）；
//   5. ReminderList：待关注项目列表（进度环 + 状态徽章）。
//
// 性能（R11 修复后）：停车倒计时卡片内部 1s Timer 自刷新，
// 页面本身不再有周期性重建；英雄卡"到期概览"只在数据变化时重算。
// ignore_for_file: use_key_in_widget_constructors, library_private_types_in_public_api

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/widgets/lunio_components.dart';
import '../../../domain/entities/car.dart';
import '../../../domain/entities/sync_metadata.dart';
import '../profile/vehicles.dart';
import '../records/records_page.dart';
import '../shared/shell_shared.dart';
import 'parking_countdown.dart';
import 'reminder_list.dart';
import 'reminder_notifications.dart';

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
              actionLabel: '更新里程',
              onAction: () => showQuickMileageUpdateSheet(context, ref, car),
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
                  ? () => showParkingCountdownSheet(context, ref)
                  : null,
            ),
          ],
          SizedBox(height: currentParkingCountdown == null ? 14 : 22),
          if (currentParkingCountdown != null) ...[
            ParkingCountdownCard(
              countdown: currentParkingCountdown,
              now: now,
              onEnd: () => clearParkingCountdown(context, ref),
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
                      LunioEmptyCard('日期加载失败：${friendlyError(error)}'),
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

// ---------------- 快捷更新里程（英雄卡"更新里程"入口） ----------------

/// 快捷更新里程 sheet：输入框默认留空 + autofocus 自动弹数字键盘，
/// 保存走动作层 updateCar（写库 → 失效车辆家族，与编辑车辆表单同通道，
/// 同步元数据也按 pendingUpdate 处理）。
/// 新里程不高于当前里程（含相等）时先弹确认框警示——里程表只增不减，
/// 输小了九成是手误；确认后仍可保存，与编辑车辆表单"允许改小"的现行
/// 规则不冲突（宽松规则是否收敛见审查台账 R36，本次只给快捷入口加摩擦）。
void showQuickMileageUpdateSheet(BuildContext context, WidgetRef ref, Car car) {
  final controller = TextEditingController();
  showLunioModalSheet<void>(
    context: context,
    builder: (sheetContext) {
      return PrototypeSheetFrame(
        title: '更新里程',
        subtitle: '当前 ${formatMileageKm(car.currentMileageKm)}，输入新的当前里程',
        bottomInset: MediaQuery.of(sheetContext).viewInsets.bottom,
        child: _QuickMileageForm(
          controller: controller,
          car: car,
          onSubmit: (mileage) async {
            // 写库+失效收进动作层（ADR 0007），这里只留反馈薄壳；
            // 双 context 写法与 fuel_page 的手填价一致（pop 用 sheet 的
            // context，toast 用打开 sheet 前的外层 context）。
            await updateCar(
              ref,
              car.copyWith(
                currentMileageKm: mileage,
                sync: SyncMetadata(
                  status: SyncStatus.pendingUpdate,
                  updatedAt: DateTime.now(),
                ),
              ),
            );
            if (sheetContext.mounted) {
              Navigator.of(sheetContext).pop();
            }
            if (context.mounted) {
              showStatusOverlay(
                context,
                '里程已更新',
                StatusOverlayTone.success,
              );
            }
          },
        ),
      );
    },
  );
}

/// 快捷更新里程表单：纯整数里程（km），留空提交按校验错误处理；
/// 未调高（≤ 当前里程）的确认框在提交时拦截，确认后才落库。
class _QuickMileageForm extends StatefulWidget {
  const _QuickMileageForm({
    required this.controller,
    required this.car,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final Car car;
  final Future<void> Function(int mileage) onSubmit;

  @override
  State<_QuickMileageForm> createState() => _QuickMileageFormState();
}

class _QuickMileageFormState extends State<_QuickMileageForm>
    with LunioFormSubmit {
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
          onCancel: () => Navigator.of(context).pop(),
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
    await runSubmit(() => widget.onSubmit(mileage));
  }
}
