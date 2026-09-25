// 我的页（/me）：个人中心。
//
// 结构：我的车辆（车辆列表 + 添加入口）/ 数据与工具（通知提醒、备份、
// 恢复、清空数据、手动日期[开发者模式专属]、加油预测开关[开发者模式
// 专属]、主题切换）/ 版本 footer。
// 各行的逻辑分流：静态行在 settings_data.dart，通知/手动日期 sheet 在
// settings_notifications.dart / settings_manual_date.dart；备份导出/恢复/
// 清空的编排走动作层"备份与数据重置"分节（ADR 0007，2026-09-25 收编），
// 本页只留成功/失败反馈薄壳（确认框也在动作层，取消静默）。
//
// 开发者模式彩蛋：版本号连点 5 次开关（关闭时连带清掉手动日期与
// 加油预测偏好）。
// ignore_for_file: use_key_in_widget_constructors, library_private_types_in_public_api

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/date/local_date.dart';
import '../../../core/theme/lunio_tokens.dart';
import '../../../core/widgets/lunio_components.dart';
import '../../../domain/entities/car.dart';
import '../shared/shell_shared.dart';
import 'maintenance_items.dart';
import 'settings_data.dart';
import 'settings_manual_date.dart';
import 'settings_notifications.dart';
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
    // 三页统一 loading/error 形态（§5.2）：主数据（车辆列表）就绪前
    // 整页占位，与提醒页/记录页同构。其余偏好 provider 在内容区内部
    // 各自带"读取中/读取失败"文案。
    return cars.when(
      loading: () => const LoadingPage(title: '个人中心'),
      error: (error, stackTrace) => ErrorPage(title: '个人中心', error: error),
      data: (cars) => _buildContent(context, cars),
    );
  }

  Widget _buildContent(BuildContext context, List<Car> cars) {
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
    final hasCars = cars.isNotEmpty;
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
            VehicleList(
              cars: cars,
              appliedCarId: appliedCar?.id,
              today: today,
              onAdd: () => showAddCarSheet(context, ref),
              onEdit: (car) => showEditCarSheet(context, ref, car),
              onManageItems: (car) =>
                  showMaintenanceItemsSheet(context, car: car),
              onApply: (carId) => applyCar(ref, carId),
              onDelete: (car) => deleteCar(context, ref, car),
            ),
          ],
        ),
        const SizedBox(height: 18),
        LunioSection(
          title: '数据与工具',
          children: [
            ProfileSettingRow(
              title: '费用统计',
              subtitle: '总费用、项目占比、年度走势',
              trailingLabel: '查看',
              onTap: () => context.push('/cost-stats'),
            ),
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
              title: '备份数据',
              subtitle: '导出全部车辆、项目配置和保养记录',
              trailingLabel: '导出',
              onTap: () => _exportBackup(context),
            ),
            ProfileSettingRow(
              title: '恢复数据',
              subtitle: '选择备份文件并恢复本地数据',
              trailingLabel: '恢复',
              onTap: () => _restoreBackup(context),
            ),
            ProfileSettingRow(
              title: '清空数据',
              subtitle: '删除本地车辆、项目和记录',
              trailingLabel: '清空',
              onTap: () => _clearAllData(context),
            ),
            if (developerMode.maybeWhen(
              data: (value) => value,
              orElse: () => false,
            )) ...[
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
              _FuelPredictionSettingRow(
                enabled: ref
                    .watch(fuelPredictionEnabledProvider)
                    .maybeWhen(data: (value) => value, orElse: () => false),
                onChanged: (value) =>
                    _setFuelPredictionEnabled(context, value),
              ),
            ],
            ThemeModeSettingRow(
              mode: themeMode.maybeWhen(
                data: (value) => value,
                orElse: () => ThemeMode.system,
              ),
              onChanged: (mode) => setThemeModePreference(ref, mode),
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
  /// 写哪些 key（关闭时连带关手动日期与加油预测）收在动作层。
  Future<void> _handleVersionTap(BuildContext context) async {
    versionTapCount += 1;
    if (versionTapCount < 5) {
      return;
    }
    versionTapCount = 0;
    final enabled = ref
        .read(developerModeProvider)
        .maybeWhen(data: (value) => value, orElse: () => false);
    await setDeveloperModeEnabled(ref, !enabled);
    if (context.mounted) {
      showStatusOverlay(
        context,
        enabled ? '开发者模式已关闭' : '开发者模式已开启',
        StatusOverlayTone.info,
      );
    }
  }

  /// 加油预测开关：动作层写偏好 + 失效 provider。
  /// AppShell watch 该 provider，底部"加油"tab 实时出现/消失（无需重启）。
  Future<void> _setFuelPredictionEnabled(
    BuildContext context,
    bool value,
  ) async {
    await setFuelPredictionEnabled(ref, value);
    if (context.mounted) {
      showStatusOverlay(
        context,
        value ? '已开启，底部新增加油入口' : '已关闭加油预测',
        StatusOverlayTone.success,
      );
    }
  }

  /// 备份导出反馈薄壳：动作层读库编码 + 原生保存框（取消保存框静默
  /// 返回 false），成功/失败 overlay 留在页面（ADR 0007）。
  Future<void> _exportBackup(BuildContext context) async {
    try {
      final saved = await exportBackup(ref);
      if (saved && context.mounted) {
        showStatusOverlay(context, '备份完成', StatusOverlayTone.success);
      }
    } catch (error) {
      if (context.mounted) {
        showStatusOverlay(context, '备份失败：$error', StatusOverlayTone.error);
      }
    }
  }

  /// 恢复备份反馈薄壳：确认框/选文件在动作层，取消静默返回 false。
  /// 唯一约束冲突（恢复文件数据重复或冲突，事务已回滚）弹"未写入任何
  /// 数据"对话框，其他失败 toast——错误分类属 UI 反馈决策留页面；文本
  /// 识别是 ADR 0009 明文的驱动层兜底口径（不可在 throw 点包装）。
  Future<void> _restoreBackup(BuildContext context) async {
    try {
      final restored = await restoreBackupFromFile(context, ref);
      if (restored && context.mounted) {
        showStatusOverlay(context, '恢复完成', StatusOverlayTone.success);
      }
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      if (isUniqueConstraintError(error)) {
        await showMessageDialog(
          context: context,
          title: '恢复失败',
          message: '恢复文件中的部分数据重复或冲突，本次恢复未写入任何数据。',
          tone: StatusOverlayTone.error,
        );
      } else {
        showStatusOverlay(context, '恢复失败：$error', StatusOverlayTone.error);
      }
    }
  }

  /// 清空数据反馈薄壳：确认框在动作层，取消静默返回 false。
  Future<void> _clearAllData(BuildContext context) async {
    try {
      final cleared = await clearAllData(context, ref);
      if (cleared && context.mounted) {
        showStatusOverlay(context, '已清空数据', StatusOverlayTone.success);
      }
    } catch (error) {
      if (context.mounted) {
        showStatusOverlay(context, '清空失败：$error', StatusOverlayTone.error);
      }
    }
  }
}

/// 加油预测开关行（开发者模式专属）：标题 + 副标题 + 右侧 Switch。
/// 与 ProfileSettingRow 同款容器样式，但整行动作用开关而非按钮。
class _FuelPredictionSettingRow extends StatelessWidget {
  const _FuelPredictionSettingRow({
    required this.enabled,
    required this.onChanged,
  });

  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: tokens.surface,
          borderRadius: BorderRadius.circular(tokens.radiusLarge),
          border: Border.all(color: tokens.line),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('加油预测', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 5),
                  Text(
                    enabled ? '开启 · 底部显示加油入口' : '关闭',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Switch(value: enabled, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}
