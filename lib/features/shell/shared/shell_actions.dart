// shell 层通用动作（≈ 抽出来的几个 Controller 方法）：
// 切换应用车辆、写主题偏好、删除车辆。被 vehicles/profile_page 复用。
//
// 通知同步代数在 providers.dart 里的
// notificationSyncGenerationProvider（NotifierProvider），见 R8。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/notifications/lunio_notification_service.dart';
import '../../../domain/entities/car.dart';
import 'modal_feedback.dart';

/// 切换当前应用车辆：写 appliedCarId 偏好 + 失效车辆类 provider。
Future<void> applyCar(BuildContext context, WidgetRef ref, int carId) async {
  await ref.read(lunioRepositoryProvider).setAppliedCarId(carId);
  invalidateVehicleProviders(ref);
}

/// 写主题偏好（'light'/'dark'/'system'）+ 失效偏好类 provider。
/// themeModePreferenceProvider 重算 → LunioApp 重建（router 单例不变，
/// 当前页面保持）。context 参数当前未使用（保留签名一致性）。
Future<void> setThemeModePreference(
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

/// 删除车辆：先弹确认对话框，确认后走 Repository 的级联删除事务，
/// 再失效车辆类 provider（appliedCar 回退逻辑在 Repository 内处理）。
///
/// 通知同步代数 bump + 显式取消 8000/8900 系系统通知（R1）：同步控制器
/// 在无车时（car == null）直接短路不走重排，删除最后一辆车后旧调度
/// 无人清理，必须在此显式取消；非最后一辆车的场景取消后也会随
/// invalidate 触发的重排恢复，代价可忽略。停车 9001/9002 与车辆无关，
/// 不在此处理（由倒计时保存/结束/清空数据路径负责）。
Future<void> deleteCar(BuildContext context, WidgetRef ref, Car car) async {
  final confirmed = await showConfirmDialog(
    context: context,
    title: '删除车辆',
    message: '确定删除 ${car.brand} ${car.model}？相关项目和记录会同步删除。',
    confirmLabel: '删除',
  );
  if (confirmed != true || car.id == null) {
    return;
  }
  ref.read(notificationSyncGenerationProvider.notifier).bump();
  await ref.read(lunioRepositoryProvider).deleteCar(car.id!);
  await LunioNotificationService.instance.cancelLunioNotifications();
  invalidateVehicleProviders(ref);
}
