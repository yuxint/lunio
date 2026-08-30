// shell 层通用动作（≈ 抽出来的几个 Controller 方法）：
// 切换应用车辆、写主题偏好、删除车辆。被 vehicles/profile_page 复用。
//
// ⚠ 本文件还定义了全局可变变量 notificationSyncGeneration——
// "通知同步代数"：恢复备份/清空数据时自增，用于作废 AppShell 里
// 已经启动但尚未完成的在途通知调度任务（比对快照代数决定放弃执行）。
// 用全局变量做并发控制绕过了 provider 体系，且覆盖不了所有在途任务
// （见审查报告 R8）。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../domain/entities/car.dart';
import 'modal_feedback.dart';

/// 通知同步代数（全局计数器）。settings_data.dart 恢复/清空时 ++，
/// app_shell.dart 的调度任务执行前比对，代数变了就放弃。
int notificationSyncGeneration = 0;

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
  await ref.read(lunioRepositoryProvider).deleteCar(car.id!);
  invalidateVehicleProviders(ref);
}
