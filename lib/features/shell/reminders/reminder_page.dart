// 提醒页（/reminders，默认首页）。
//
// 页面结构（自上而下）：
//   1. LoadingPage / ErrorPage：应用车辆加载中/失败；
//   2. 无车 → EmptyVehicleCard（"还没有车辆"+ 新增入口）；
//      有车 → LunioHeroCard 大渐变卡（品牌车型 + 当前里程 + 到期概览）；
//   3. ReminderActionRow：新增保养记录 / 停车倒计时 两个按钮；
//   4. 停车倒计时进行中 → ParkingCountdownCard（进度环 + 结束按钮）；
//   5. ReminderList：待关注项目列表（进度环 + 状态徽章）。
//
// ⚠ 性能：250ms Timer.periodic 对整页 setState（停车倒计时刷新需要秒级
// 重新计算，但重建范围是整页，且无倒计时时也在空转，见审查报告 R11）。
// ignore_for_file: use_key_in_widget_constructors, library_private_types_in_public_api

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/widgets/lunio_components.dart';
import '../profile/vehicles.dart';
import '../records/records_page.dart';
import '../shared/shell_shared.dart';
import 'parking_countdown.dart';
import 'reminder_list.dart';
import 'reminder_notifications.dart';

// 17-20 行的 re-export：把 parking_countdown / reminder_dialogs /
// reminder_notifications 的符号从本文件再导出。实际调用方都直接 import
// 源文件，这里的 barrel 无消费者（R30）。
export 'parking_countdown.dart'
    show clearParkingCountdown, showParkingCountdownSheet;
export 'reminder_dialogs.dart';
export 'reminder_notifications.dart';

/// 提醒页组件。
class ReminderPreviewPage extends ConsumerStatefulWidget {
  const ReminderPreviewPage();

  @override
  ConsumerState<ReminderPreviewPage> createState() =>
      ReminderPreviewPageState();
}

class ReminderPreviewPageState extends ConsumerState<ReminderPreviewPage> {
  /// 250ms 周期定时器：驱动停车倒计时的秒级刷新。
  /// 每次触发 setState 重建整页（Timer 在 dispose 正确取消，无泄漏，
  /// 但重建范围过大是已知性能问题 R11）。
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

  /// build：watch 全部数据 → 按加载态/空态/正常态渲染。
  /// now 用系统真实时间（停车倒计时不受手动日期影响）。
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
