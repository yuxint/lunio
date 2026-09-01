// 主壳层：三个 tab（提醒/记录/我的）共用的页面骨架。
//
// 职责（≈ 主页面 Controller + 布局）：
//  1. 挂载当前 tab 页面 + 自绘悬浮底部导航栏（go_router 路由切换）；
//  2. 生命周期监听（WidgetsBindingObserver ≈ Android Activity 的
//     onResume/onPause 回调）：前台恢复时转交通知同步控制器、刷新导航 inset；
//  3. Android 三键导航栏 inset 适配（三键模式下补导航栏高度）；
//  4. 通知同步引擎已抽到 NotificationSyncController（reminders/
//     notification_sync_controller.dart）：initState 创建并 start
//     （listenManual 驱动），build 不再承担任何同步副作用，只渲染。
//
// ConsumerStatefulWidget = "有状态 + 能用 Riverpod 容器"的组件。
// State 的字段（下划线开头）≈ Controller 的私有成员变量。
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/platform/native_system_ui.dart';
import '../../core/theme/lunio_tokens.dart';
import 'fuel/fuel_page.dart';
import 'profile/profile_page.dart';
import 'records/records_page.dart';
import 'reminders/notification_sync_controller.dart';
import 'reminders/reminder_page.dart';
import 'shared/shell_shared.dart';

/// 主壳层组件。selectedIndex 是"固定 tab 位"：
/// 0=提醒 1=记录 2=加油 3=我的。加油位只有在"加油预测"开关打开时
/// 才出现在底部导航（路由常驻，关闭时本组件负责兜底重定向）。
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.selectedIndex});

  final int selectedIndex;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell>
    with WidgetsBindingObserver {
  /// 通知同步控制器：提醒数据 → 系统通知重排/应用内弹窗的协调器。
  /// initState 创建并 start（订阅 6 个 provider），dispose 关闭。
  late final NotificationSyncController _notificationSync;

  /// 跨零点刷新定时器：对准下一个 00:00:00 触发，失效
  /// effectiveTodayProvider（"今天"缓存跨零点会过期，提醒页的到期
  /// 概览/待关注项目、"我的"页车龄都会停在昨天的日期）。失效后各
  /// watch 方自动重建，通知同步控制器也监听该 provider，会静默重排
  /// 系统通知；触发后重新排下一个零点。App 在后台时定时器挂起，
  /// 回到前台的瞬间补触发，效果一致。手动日期开启时失效重算结果
  /// 不变（手动日期优先），无害。
  Timer? _midnightRefreshTimer;

  // ---- Android 三键导航 inset 适配 ----
  double _androidThreeButtonNavigationInset = 0.0;

  /// 异步刷新的请求序号：只接受最新一次请求的结果
  /// （requestId + mounted 双检查防竞态，写法正确）。
  int _systemNavigationRequestId = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _notificationSync = NotificationSyncController(
      ref: ref,
      shellContext: () => mounted ? context : null,
      isAlive: () => mounted,
    );
    _notificationSync.start();
    _scheduleMidnightDateRefresh();
    _refreshAndroidSystemNavigationInset();
  }

  @override
  void dispose() {
    _notificationSync.dispose();
    _midnightRefreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// 排一个对准下一个零点的定时器：触发时失效生效"今天"，再排次日。
  void _scheduleMidnightDateRefresh() {
    final now = DateTime.now();
    final nextMidnight = DateTime(now.year, now.month, now.day + 1);
    _midnightRefreshTimer = Timer(nextMidnight.difference(now), () {
      if (!mounted) {
        return;
      }
      ref.invalidate(effectiveTodayProvider);
      _scheduleMidnightDateRefresh();
    });
  }

  /// 回到前台：清空应用内提醒签名（强制重新检查弹窗，实现"用户处理完
  /// 提醒离开再回来，若又到期会再次提醒"），并刷新导航 inset
  /// （用户可能在系统设置里切了导航方式）。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _notificationSync.onAppResumed();
      _refreshAndroidSystemNavigationInset();
    }
  }

  @override
  void didChangeMetrics() {
    _refreshAndroidSystemNavigationInset();
  }

  /// 每帧 build：渲染当前 tab 页 + 底部导航。
  /// 通知同步已由控制器 listenManual 驱动，这里不做任何同步副作用。
  ///
  /// 加油预测开关打开时还顺带 watch 油价控制器（≈ 启动时检查油价：
  /// 缓存过期/换省/无缓存就静默拉一次，见 fuel_price_controller）。
  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    final fuelEnabled = ref
        .watch(fuelPredictionEnabledProvider)
        .maybeWhen(data: (value) => value, orElse: () => false);
    if (fuelEnabled) {
      ref.watch(fuelPriceControllerProvider);
    }
    // 兜底：加油 tab 只在开关打开时存在。开关关闭后若仍停在 /fuel
    // （如冷启动恢复了旧路由），渲染提醒页内容并跳回 /me。
    final selectedIndex = widget.selectedIndex;
    final onDisabledFuel = selectedIndex == 2 && !fuelEnabled;
    final effectiveIndex = onDisabledFuel ? 0 : selectedIndex;
    if (onDisabledFuel) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          if (context.mounted) {
            context.go('/me');
          }
        }
      });
    }
    final pages = [
      const ReminderPreviewPage(),
      const RecordsPreviewPage(),
      const FuelPreviewPage(),
      const ProfilePreviewPage(),
    ];

    return Scaffold(
      backgroundColor: tokens.background,
      body: SafeArea(child: pages[effectiveIndex]),
      bottomNavigationBar: Padding(
        padding: EdgeInsets.fromLTRB(
          14,
          0,
          14,
          12 + _androidThreeButtonNavigationInset,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: tokens.surface.withValues(alpha: 0.88),
            borderRadius: BorderRadius.circular(tokens.radiusXl),
            border: Border.all(color: tokens.line.withValues(alpha: 0.9)),
            boxShadow: [
              BoxShadow(
                color: tokens.ink.withValues(alpha: 0.16),
                blurRadius: 46,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                _BottomNavItem(
                  icon: Icons.home_repair_service_outlined,
                  selectedIcon: Icons.home_repair_service,
                  label: '提醒',
                  selected: effectiveIndex == 0,
                  onTap: () {
                    dismissTransientUi(context);
                    context.go('/reminders');
                  },
                ),
                const SizedBox(width: 6),
                _BottomNavItem(
                  icon: Icons.format_list_bulleted_outlined,
                  selectedIcon: Icons.format_list_bulleted,
                  label: '记录',
                  selected: effectiveIndex == 1,
                  onTap: () {
                    dismissTransientUi(context);
                    context.go('/records');
                  },
                ),
                if (fuelEnabled) ...[
                  const SizedBox(width: 6),
                  _BottomNavItem(
                    icon: Icons.local_gas_station_outlined,
                    selectedIcon: Icons.local_gas_station,
                    label: '加油',
                    selected: effectiveIndex == 2,
                    onTap: () {
                      dismissTransientUi(context);
                      context.go('/fuel');
                    },
                  ),
                ],
                const SizedBox(width: 6),
                _BottomNavItem(
                  icon: Icons.person_outline,
                  selectedIcon: Icons.person,
                  label: '我的',
                  selected: effectiveIndex == 3,
                  onTap: () {
                    dismissTransientUi(context);
                    context.go('/me');
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 查询 Android 导航模式并更新 inset（异步，带 requestId 防乱序）。
  /// 三键导航 → inset = 导航栏高度；手势导航 → 0。
  Future<void> _refreshAndroidSystemNavigationInset() async {
    final requestId = ++_systemNavigationRequestId;
    if (defaultTargetPlatform != TargetPlatform.android) {
      _updateAndroidSystemNavigationInset(0.0, requestId);
      return;
    }

    final info = await NativeSystemUi.getSystemNavigationInfo();
    if (!mounted || requestId != _systemNavigationRequestId) {
      return;
    }
    final nextInset = info?.usesThreeButtonNavigation == true
        ? info!.navigationBarHeight
        : 0.0;
    _updateAndroidSystemNavigationInset(nextInset, requestId);
  }

  void _updateAndroidSystemNavigationInset(double nextInset, int requestId) {
    if (!mounted || requestId != _systemNavigationRequestId) {
      return;
    }
    if (_androidThreeButtonNavigationInset == nextInset) {
      return;
    }
    setState(() => _androidThreeButtonNavigationInset = nextInset);
  }
}

/// 底部导航单个 tab 项（图标 + 文字，选中态主色胶囊底）。
class _BottomNavItem extends StatelessWidget {
  const _BottomNavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    final foreground = selected ? Colors.white : tokens.muted;
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        excludeSemantics: true,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            height: 56,
            decoration: BoxDecoration(
              color: selected ? tokens.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  selected ? selectedIcon : icon,
                  color: foreground,
                  size: 21,
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: foreground,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
