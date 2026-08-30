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
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/platform/native_system_ui.dart';
import '../../core/theme/lunio_tokens.dart';
import 'profile/profile_page.dart';
import 'records/records_page.dart';
import 'reminders/notification_sync_controller.dart';
import 'reminders/reminder_page.dart';
import 'shared/shell_shared.dart';

/// 主壳层组件。selectedIndex 来自路由（0/1/2 对应三个入口）。
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
    _refreshAndroidSystemNavigationInset();
  }

  @override
  void dispose() {
    _notificationSync.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
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
  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    final pages = [
      const ReminderPreviewPage(),
      const RecordsPreviewPage(),
      const ProfilePreviewPage(),
    ];

    return Scaffold(
      backgroundColor: tokens.background,
      body: SafeArea(child: pages[widget.selectedIndex]),
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
                  selected: widget.selectedIndex == 0,
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
                  selected: widget.selectedIndex == 1,
                  onTap: () {
                    dismissTransientUi(context);
                    context.go('/records');
                  },
                ),
                const SizedBox(width: 6),
                _BottomNavItem(
                  icon: Icons.person_outline,
                  selectedIcon: Icons.person,
                  label: '我的',
                  selected: widget.selectedIndex == 2,
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
