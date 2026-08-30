// 路由配置（相当于 Java Web 里 Spring MVC 的 Router/Controller 映射表）。
//
// 本 App 是"单壳层 + 三个平级入口"结构：提醒、记录、我的。
// 没有嵌套子路由，三个入口各自渲染 AppShell，仅 selectedIndex 不同，
// 由 AppShell 内部的底部导航栏高亮对应 tab。
//
// 关键设计：appRouter 是**顶层全局单例**（不是每次 build 新建）。
// 这样主题切换时 MaterialApp.router 重建也不会重建路由对象，
// 避免切主题导致页面跳回默认 tab（/reminders）。
import 'package:go_router/go_router.dart';

import '../features/shell/app_shell.dart';

/// 全局路由单例。修改主题偏好 → LunioApp 重建 → 复用同一个 router 实例
/// → 当前所在页面保持不变。不要把它挪进任何 Widget/Provider 内部。
final appRouter = buildAppRouter();

/// 构建 GoRouter 实例。三个 GoRoute 分别对应底部导航的三个入口。
GoRouter buildAppRouter() {
  return GoRouter(
    // 冷启动后的初始页面：提醒页（产品默认首屏）。
    initialLocation: '/reminders',
    routes: [
      GoRoute(
        path: '/reminders',
        // NoTransitionPage：切换 tab 时不播放转场动画，行为像普通 App 底部导航。
        // selectedIndex 传给 AppShell 用于高亮底部导航栏的对应项。
        pageBuilder: (context, state) =>
            const NoTransitionPage(child: AppShell(selectedIndex: 0)),
      ),
      GoRoute(
        path: '/records',
        pageBuilder: (context, state) =>
            const NoTransitionPage(child: AppShell(selectedIndex: 1)),
      ),
      GoRoute(
        path: '/me',
        pageBuilder: (context, state) =>
            const NoTransitionPage(child: AppShell(selectedIndex: 2)),
      ),
    ],
  );
}
