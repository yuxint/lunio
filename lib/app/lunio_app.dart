// 根组件：MaterialApp 的挂载点（相当于 Spring Boot 装配类 + 全局配置）。
//
// 职责只有两个：
//  1. 根据用户偏好（浅色/深色/跟随系统）决定 MaterialApp.themeMode；
//  2. 把全局路由单例 appRouter 挂到 MaterialApp.router 上。
//
// ConsumerWidget 表示这是一个"能从 Riverpod 容器取数"的组件——
// Java 对照：相当于一个支持 @Autowired 注入的 Bean，ref 就是注入器。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'app_router.dart';
import 'providers.dart';
import '../core/theme/lunio_theme.dart';

class LunioApp extends ConsumerWidget {
  const LunioApp({super.key, this.routerConfig});

  /// 测试用的路由注入口。生产环境为 null，走全局单例 appRouter。
  final GoRouter? routerConfig;

  /// build 是 Flutter 组件的"渲染函数"：返回组件树描述，类似模板方法。
  /// 它会被框架反复调用（依赖变化时），因此必须保持无副作用、可重入。
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // watch：订阅主题偏好。偏好被 invalidate（缓存失效）后会重新读取数据库，
    // 届时本 build 再次执行，MaterialApp.themeMode 随之更新。
    // maybeWhen：FutureProvider 的结果包装类 AsyncValue——
    // 数据库还没读完（loading/失败）时先回退 ThemeMode.system。
    final themeMode = ref
        .watch(themeModePreferenceProvider)
        .maybeWhen(data: (value) => value, orElse: () => ThemeMode.system);
    return MaterialApp.router(
      title: 'Lunio',
      // 浅色/深色两套 ThemeData（见 core/theme/lunio_theme.dart），
      // themeMode 决定当前用哪套：light / dark / system（跟随系统）。
      theme: buildLunioTheme(),
      darkTheme: buildLunioTheme(brightness: Brightness.dark),
      themeMode: themeMode,
      // 优先用注入的路由（测试），否则用全局单例——切主题不重置当前页面。
      routerConfig: routerConfig ?? appRouter,
      debugShowCheckedModeBanner: false,
    );
  }
}
