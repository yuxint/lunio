// 设置页（/settings，pushed 子页，ADR 0028）：我的页的二级整合页面。
//
// 「通用」分区 = 通知提醒行（点行弹现有通知设置 sheet，表单与保存/
// 取消不变）+ 主题模式三段选择（行内即改）；「功能开关」分区 = 加油
// 预测开关（保留开启 toast）+ 车辆诊断开关（关开关断开 App 级连接，
// 动作层收尾）。2026-11-16 拍板：二级菜单用独立页面形态，不用 sheet
// 叠 sheet；通知设置保留自己的 sheet。
//
// 形态同 /cost-stats、/diagnostics 两个 pushed 子页先例：默认转场，
// 返回键在 LunioTopBar leading 位；pushed 子页不经过 AppShell，
// Scaffold（页面底色）自己提供。
//
// ≈ Java 的 View：State 只持有表单/sheet 触发与反馈薄壳，写库与失效
// 编排全部在动作层（ADR 0007）。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/theme/lunio_tokens.dart';
import '../../../core/widgets/lunio_components.dart';
import '../shared/shell_shared.dart';
import 'settings_data.dart';
import 'settings_notifications.dart';

/// 设置页主组件。
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notificationSettings = ref.watch(notificationSettingsProvider);
    final themeMode = ref.watch(themeModePreferenceProvider);
    final fuelPredictionEnabled = ref
        .watch(fuelPredictionEnabledProvider)
        .maybeWhen(data: (value) => value, orElse: () => false);
    final diagnosticsEnabled = ref
        .watch(diagnosticsEnabledProvider)
        .maybeWhen(data: (value) => value, orElse: () => false);
    // pushed 子页不经过 AppShell，Scaffold（页面底色）要自己提供——
    // 页内 InkWell/chips 需要 Material 祖先，与诊断页同款。
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    return Scaffold(
      backgroundColor: tokens.background,
      body: LunioPage(
        title: '设置',
        leading: LunioIconButton(
          icon: Icons.arrow_back_ios_new,
          tooltip: '返回',
          onPressed: () => context.pop(),
        ),
        bottomPadding: 24,
        children: [
          LunioSection(
            title: '通用',
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
              ThemeModeSettingRow(
                mode: themeMode.maybeWhen(
                  data: (value) => value,
                  orElse: () => ThemeMode.system,
                ),
                onChanged: (mode) => setThemeModePreference(ref, mode),
              ),
            ],
          ),
          const SizedBox(height: 18),
          LunioSection(
            title: '功能开关',
            children: [
              _SettingsSwitchRow(
                title: '加油预测',
                subtitle: fuelPredictionEnabled
                    ? '开启 · 底部显示加油入口'
                    : '关闭',
                enabled: fuelPredictionEnabled,
                onChanged: (value) async {
                  await setFuelPredictionEnabled(ref, value);
                  if (context.mounted) {
                    showStatusOverlay(
                      context,
                      value ? '已开启，底部新增加油入口' : '已关闭加油预测',
                      StatusOverlayTone.success,
                    );
                  }
                },
              ),
              _SettingsSwitchRow(
                title: '车辆诊断',
                subtitle: '连接 OBD 读取油量水温等',
                enabled: diagnosticsEnabled,
                // 无 toast：入口行随开关即时显隐，本身就是可见反馈。
                onChanged: (value) => setDiagnosticsEnabled(ref, value),
              ),
            ],
          ),
        ],
      ),
    );
  }

}

/// 设置页开关行：标题 + 副标题 + 右侧 Switch。与 ProfileSettingRow 同款
/// 容器样式，但整行动作为开关而非按钮（原我的页开发者区块开关行组件
/// 随开关迁移，2026-11-16 从 profile_page.dart 迁入此处）。
class _SettingsSwitchRow extends StatelessWidget {
  const _SettingsSwitchRow({
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
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
                  Text(title, style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 5),
                  Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
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
