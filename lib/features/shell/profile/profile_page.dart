// 我的页（/me）：个人中心。
//
// 结构：我的车辆（车辆列表 + 添加入口）/ 数据与工具（通知提醒、备份、
// 恢复、清空数据、手动日期[开发者模式专属]、主题切换）/ 版本 footer。
// 各行的实际逻辑都在 vehicles.dart / maintenance_items.dart / settings_data.dart。
//
// 开发者模式彩蛋：版本号连点 5 次开关（关闭时连带清掉手动日期偏好）。
// ignore_for_file: use_key_in_widget_constructors, library_private_types_in_public_api

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/date/local_date.dart';
import '../../../core/widgets/lunio_components.dart';
import '../shared/shell_shared.dart';
import 'maintenance_items.dart';
import 'settings_data.dart';
import 'vehicles.dart';

/// 我的页主组件。
class ProfilePreviewPage extends ConsumerStatefulWidget {
  const ProfilePreviewPage();

  @override
  ConsumerState<ProfilePreviewPage> createState() => ProfilePreviewPageState();
}

class ProfilePreviewPageState extends ConsumerState<ProfilePreviewPage> {
  /// 版本号连点计数（开发者模式彩蛋）。
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
                  onPressed: () => showAddCarSheet(context, ref),
                  child: const Text('添加'),
                )
              : null,
          children: [
            cars.when(
              loading: () => const LunioCard(child: Text('车辆加载中...')),
              error: (error, stackTrace) =>
                  LunioCard(child: Text('车辆加载失败：${friendlyError(error)}')),
              data: (items) => VehicleList(
                cars: items,
                appliedCarId: appliedCar?.id,
                today: today,
                onAdd: () => showAddCarSheet(context, ref),
                onEdit: (car) => showEditCarSheet(context, ref, car),
                onManageItems: (car) =>
                    showMaintenanceItemsSheet(context, ref, car: car),
                onApply: (carId) => applyCar(context, ref, carId),
                onDelete: (car) => deleteCar(context, ref, car),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        LunioSection(
          title: '数据与工具',
          children: [
            ProfileSettingRow(
              title: '通知提醒',
              subtitle: notificationSettings.when(
                loading: () => '读取中',
                error: (error, stackTrace) => '读取失败',
                data: notificationSettingsSubtitle,
              ),
              trailingLabel: '设置',
              onTap: () => showNotificationSettingsSheet(context, ref),
            ),
            ProfileSettingRow(
              title: '备份',
              subtitle: '导出全部车辆、项目配置和保养记录',
              trailingLabel: '导出',
              onTap: () => exportBackup(context, ref),
            ),
            ProfileSettingRow(
              title: '恢复',
              subtitle: '选择备份文件并恢复本地数据',
              trailingLabel: '恢复',
              onTap: () => restoreBackupFromFile(context, ref),
            ),
            ProfileSettingRow(
              title: '清空数据',
              subtitle: '删除本地车辆、项目和记录',
              trailingLabel: '清空',
              onTap: () => clearAllData(context, ref),
            ),
            if (developerMode.maybeWhen(
              data: (value) => value,
              orElse: () => false,
            ))
              ProfileSettingRow(
                title: '手动日期',
                subtitle: manualDate.when(
                  loading: () => '读取中',
                  error: (error, stackTrace) => '读取失败',
                  data: (value) =>
                      value == null ? '关闭 · 使用系统日期' : '开启 · $value',
                ),
                trailingLabel: '设置',
                onTap: () => showManualDateSheet(context, ref),
              ),
            ThemeModeSettingRow(
              mode: themeMode.maybeWhen(
                data: (value) => value,
                orElse: () => ThemeMode.system,
              ),
              onChanged: (mode) => setThemeModePreference(context, ref, mode),
            ),
          ],
        ),
        const SizedBox(height: 12),
        VersionFooter(
          developerModeEnabled: developerMode.maybeWhen(
            data: (value) => value,
            orElse: () => false,
          ),
          onTap: () => _handleVersionTap(context),
        ),
      ],
    );
  }

  /// 版本号连点 5 次 → 切换开发者模式：
  /// 开 → 写 developerModeEnabled=true（"手动日期"设置行出现）；
  /// 关 → 同时清 manualDateEnabled / manualDate（回到系统日期）。
  /// 每次写库后 invalidate 偏好 provider 刷新 UI + toast 反馈。
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
        showStatusOverlay(context, '开发者模式已关闭', StatusOverlayTone.info);
      }
      return;
    }
    await repository.setPreferenceValue('developerModeEnabled', 'true');
    invalidatePreferenceProviders(ref);
    if (context.mounted) {
      showStatusOverlay(context, '开发者模式已开启', StatusOverlayTone.info);
    }
  }
}
