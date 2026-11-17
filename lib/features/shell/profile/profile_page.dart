// 我的页（/me）：个人中心。
//
// 结构：我的车辆（车辆列表 + 添加入口）/ 数据与工具（设置入口行、
// 备份、恢复、清空数据、进入诊断页[诊断开关开才显示]、手动日期[开发
// 者模式专属]）/ 版本 footer。2026-11-16 拍板（ADR 0028）：通知提醒与
// 主题模式、加油预测与车辆诊断开关迁往二级「设置」页
// （settings_page.dart），加油预测与车辆诊断不再挂开发者门控；费用
// 统计行删除（记录页头部汇总行是既有入口）。
// 各行的逻辑分流：静态行在 settings_data.dart，通知/手动日期 sheet 在
// settings_notifications.dart / settings_manual_date.dart；备份导出/
// 恢复/清空的编排走动作层"备份与数据重置"分节（ADR 0007，2026-09-25
// 收编），本页只留成功/失败反馈薄壳（确认框也在动作层，取消静默）。
//
// 开发者模式彩蛋：版本号连点 5 次开关（关闭时连带清掉手动日期偏好）。
// ignore_for_file: use_key_in_widget_constructors, library_private_types_in_public_api

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/date/local_date.dart';
import '../../../core/widgets/lunio_components.dart';
import '../../../domain/entities/car.dart';
import '../../../domain/errors/lunio_error.dart';
import '../shared/shell_shared.dart';
import 'maintenance_items.dart';
import 'settings_data.dart';
import 'settings_manual_date.dart';
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
    final diagnosticsEnabled = ref
        .watch(diagnosticsEnabledProvider)
        .maybeWhen(data: (value) => value, orElse: () => false);
    final manualDate = ref.watch(manualDatePreferenceProvider);
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
              title: '设置',
              subtitle: '通知提醒、主题模式、功能开关',
              trailingLabel: '查看',
              onTap: () => context.push('/settings'),
            ),
            ProfileSettingRow(
              title: '备份数据',
              subtitle: '导出全部车辆、项目配置和保养记录',
              trailingLabel: '备份',
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
            // 车辆诊断转正（ADR 0028）：入口行移出开发者区块，诊断开关
            // 开即显示在清空数据下方。
            if (diagnosticsEnabled)
              ProfileSettingRow(
                title: '进入诊断页',
                subtitle: '连接适配器、读取油量水温',
                trailingLabel: '进入',
                onTap: () => context.push('/diagnostics'),
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
  /// 失败反馈三级（ADR 0009 修订节，2026-10-01 起全按类型分支）：
  /// 恢复预校验拒绝（typed backupInvalidData——实体校验失败/同车同日
  /// 重复）弹对话框给 throw 点的具体原因；驱动层唯一约束冲突（预校验
  /// 拦不住的最后防线，恢复事务边界已包装成 typed uniqueConstraint，
  /// 事务已回滚）按 kind 弹恢复场景的通用对话框；其余失败 toast。
  /// 错误分类属 UI 反馈决策留页面。
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
      if (error is LunioErrorException) {
        await showMessageDialog(
          context: context,
          title: '恢复失败',
          message: error.kind == LunioErrorKind.uniqueConstraint
              ? '恢复文件中的部分数据重复或冲突，本次恢复未写入任何数据。'
              : '${error.message}\n本次恢复未写入任何数据。',
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

