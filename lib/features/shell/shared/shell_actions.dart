// shell 层保存动作层（≈ Spring 里一组薄 Service 方法）：每个业务变更
// 一个具名函数，内部固定编排"写库 → 失效对应 provider 家族 →（需要时）
// 通知域收尾"。providers.dart 顶部警告的"手动失效模式"由此收口：UI
// 不再手排失效序列，新保存路径进这里，不会漏调 invalidate。
//
// 与调用方的分工（ADR 0007）：
//  - 本层只收 WidgetRef（纯 Dart 编排，不碰 BuildContext、不弹 UI）；
//  - 确认框、关 sheet、成功 toast 留在调用方（pop 用 sheet 的 context，
//    toast 用打开 sheet 前的外层 context，见 fuel_page 的双 context 写法）；
//  - 异常按"没抛即成功"穿透，由表单的行内错误机制翻译展示（本层不吞）。
//
// 与通知协调器（LunioNotificationCoordinator）的分工：协调器拥有通知域
// 协议（权限对账、通知清扫、抑制读写），本层在业务动作内部组合协调器，
// 是它的上层入口。deleteCar 例外地保留了确认框：删除是破坏性操作，
// 确认文案属于 UI 决策。
//
// 分域分节：车辆 / 保养记录 / 保养项目 / 偏好 / 加油 / 通知设置。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/date/local_date.dart';
import '../../../domain/entities/car.dart';
import '../../../domain/entities/fuel_price.dart';
import '../../../domain/entities/maintenance_item.dart';
import '../../../domain/entities/maintenance_record.dart';
import '../../../domain/entities/notification_settings.dart';
import '../../../domain/entities/sync_metadata.dart';
import '../reminders/notification_coordinator.dart';
import 'modal_feedback.dart';

// ---- 车辆 ----

/// 切换当前应用车辆：写 appliedCarId 偏好 + 失效车辆类 provider。
Future<void> applyCar(WidgetRef ref, int carId) async {
  await ref.read(lunioPreferencesProvider).setAppliedCarId(carId);
  invalidateVehicleProviders(ref);
}

/// 新增车辆（含向导整组保养项目）：走 Repository 的建车事务 →
/// 失效车辆家族（车辆列表、目录对账、当前应用车辆一起刷新）。
Future<void> createCar(
  WidgetRef ref,
  Car car,
  List<MaintenanceItem> items,
) async {
  await ref
      .read(lunioRepositoryProvider)
      .createCarWithMaintenanceItems(car, items);
  invalidateVehicleProviders(ref);
}

/// 编辑车辆（里程/上路日期/油箱容积）：写库 → 失效车辆家族。
Future<void> updateCar(WidgetRef ref, Car car) async {
  await ref.read(lunioRepositoryProvider).updateCar(car);
  invalidateVehicleProviders(ref);
}

/// 删除车辆：先弹确认对话框，确认后走协调器的删车清扫模板
/// （内部先升同步代数作废在途任务（R8），删库后取消 8000/8900 系
/// 系统通知（R1：删最后一辆车后同步控制器无车短路不重排，必须显式
/// 取消）），再失效车辆类 provider（appliedCar 回退逻辑在 Repository
/// 内处理）。
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
  await ref
      .read(notificationCoordinatorProvider)
      .runCarDeletion(
        () => ref.read(lunioRepositoryProvider).deleteCar(car.id!),
      );
  invalidateVehicleProviders(ref);
}

// ---- 保养记录 ----

/// 保存保养记录（含项目同步更新）：内部按 id 判断新增/编辑，都走
/// Repository 的"记录+项目"事务 → 失效车辆家族（记录列表与提醒页的
/// 进度环都挂在车辆家族上）。
Future<void> saveMaintenanceRecord(
  WidgetRef ref,
  MaintenanceRecord record,
  List<MaintenanceItem> itemUpdates,
) async {
  final repository = ref.read(lunioRepositoryProvider);
  if (record.id == null) {
    await repository.saveMaintenanceRecordWithItemUpdates(
      record: record,
      itemUpdates: itemUpdates,
    );
  } else {
    await repository.updateMaintenanceRecordWithItemUpdates(
      record: record,
      itemUpdates: itemUpdates,
    );
  }
  invalidateVehicleProviders(ref);
}

/// 删除整条保养记录（确认框由调用方负责弹）。
Future<void> removeMaintenanceRecord(WidgetRef ref, int recordId) async {
  await ref.read(lunioRepositoryProvider).deleteMaintenanceRecord(recordId);
  invalidateVehicleProviders(ref);
}

/// 从记录移除单个项目（只剩一项时 Repository 会连记录一起删；
/// 确认框由调用方负责弹）。
Future<void> removeMaintenanceRecordItem(
  WidgetRef ref, {
  required int recordId,
  required int itemId,
}) async {
  await ref
      .read(lunioRepositoryProvider)
      .removeMaintenanceRecordItem(recordId: recordId, itemId: itemId);
  invalidateVehicleProviders(ref);
}

// ---- 保养项目 ----

/// 保存保养项目：内部按 id 判断新增/编辑 → 失效车辆家族。
Future<void> saveMaintenanceItem(WidgetRef ref, MaintenanceItem item) async {
  final repository = ref.read(lunioRepositoryProvider);
  if (item.id == null) {
    await repository.saveMaintenanceItem(item);
  } else {
    await repository.updateMaintenanceItem(item);
  }
  invalidateVehicleProviders(ref);
}

/// 启停保养项目（停用最后一个启用项会抛错，由调用方翻译展示）。
Future<void> setMaintenanceItemEnabled(
  WidgetRef ref,
  MaintenanceItem item,
  bool enabled,
) async {
  await ref.read(lunioRepositoryProvider).setMaintenanceItemEnabled(
        itemId: item.id!,
        enabled: enabled,
        sync: SyncMetadata(
          status: SyncStatus.pendingUpdate,
          updatedAt: DateTime.now(),
        ),
      );
  invalidateVehicleProviders(ref);
}

/// 删除保养项目（有历史记录会抛错，由调用方翻译展示）。
Future<void> removeMaintenanceItem(WidgetRef ref, int itemId) async {
  await ref.read(lunioRepositoryProvider).deleteMaintenanceItem(itemId);
  invalidateVehicleProviders(ref);
}

// ---- 偏好 ----

/// 写主题偏好 + 失效偏好类 provider。themeModePreferenceProvider 重算
/// → LunioApp 重建（router 单例不变，当前页面保持）。
Future<void> setThemeModePreference(WidgetRef ref, ThemeMode mode) async {
  await ref.read(lunioPreferencesProvider).setThemeMode(mode);
  invalidatePreferenceProviders(ref);
}

/// 保存手动日期（null = 关闭）：manualDateEnabled 与 manualDate 两个
/// key 的成对写收在偏好门面 saveManualDateOverride 里 → 失效偏好家族
/// （生效日期上下文随 provider 重算）。
Future<void> saveManualDate(WidgetRef ref, LocalDate? date) async {
  await ref.read(lunioPreferencesProvider).saveManualDateOverride(date);
  invalidatePreferenceProviders(ref);
}

/// 开关开发者模式。关闭时连带关闭手动日期与加油预测——加油预测的
/// 开关入口只在开发者模式里可见，留着偏好会让底部"加油"tab 无法
/// 关闭。这条连带规则收在本函数，UI 不再各自记得写哪些 key。
Future<void> setDeveloperModeEnabled(WidgetRef ref, bool enabled) async {
  final preferences = ref.read(lunioPreferencesProvider);
  if (enabled) {
    await preferences.setDeveloperModeEnabled(true);
  } else {
    await preferences.setDeveloperModeEnabled(false);
    await preferences.saveManualDateOverride(null);
    await preferences.setFuelPredictionEnabled(false);
  }
  invalidatePreferenceProviders(ref);
}

/// 开关加油预测（底部"加油"tab 的显隐开关，AppShell watch 该 provider
/// 实时增删 tab）。
Future<void> setFuelPredictionEnabled(WidgetRef ref, bool value) async {
  await ref.read(lunioPreferencesProvider).setFuelPredictionEnabled(value);
  invalidatePreferenceProviders(ref);
}

// ---- 加油 ----

/// 保存省份选择：写全局偏好 + 整族失效加油相关缓存（换省后缓存里的
/// 价格、手填价、预估金额全部随 provider 重算）。
Future<void> saveFuelProvince(WidgetRef ref, String province) async {
  await ref.read(lunioPreferencesProvider).setFuelProvince(province);
  invalidateFuelPreferenceProviders(ref);
}

/// 保存油品选择：写全局偏好 + 整族失效（同上）。
Future<void> saveFuelGrade(WidgetRef ref, FuelGrade grade) async {
  await ref.read(lunioPreferencesProvider).setFuelGrade(grade);
  invalidateFuelPreferenceProviders(ref);
}

/// 保存手填油价（pricePerLiter 传 null 表示重置回数据源价格）：写临时
/// 偏好 + 单点失效手填价缓存。加油域的失效粒度与偏好家族不同，只需
/// 逐出 fuelManualPriceProvider（省份/油品选择未变，无需整族失效）。
Future<void> saveFuelManualPrice(
  WidgetRef ref, {
  required String province,
  required FuelGrade grade,
  required double? pricePerLiter,
}) async {
  await ref.read(fuelRepositoryProvider).setFuelManualPrice(
        province: province,
        grade: grade,
        pricePerLiter: pricePerLiter,
      );
  ref.invalidate(fuelManualPriceProvider);
}

// ---- 通知设置 ----

/// 保存通知设置：先对账系统真实开关（用户可能刚从系统设置页返回，
/// 以系统为准），再经协调器一个事务批量写 3 个偏好 key（协调器内部
/// 失效偏好缓存，本函数不再单独失效）。
Future<void> saveNotificationSettings(
  WidgetRef ref,
  LunioNotificationSettings settings,
) async {
  final coordinator = ref.read(notificationCoordinatorProvider);
  final systemNotificationsEnabled =
      await coordinator.reconcileSystemEnabled();
  await coordinator.saveNotificationSettings(
    settings.copyWith(
      systemNotificationsEnabled: systemNotificationsEnabled,
    ),
  );
}
