// 应用启动入口（相当于 Java 里 `public static void main` 所在的启动类）。
//
// 本文件是整个 App 的起点，只做三件事：
//  1. 初始化 Flutter 引擎绑定；
//  2. 初始化系统通知服务（时区 + 通知插件，iOS/Android 原生能力）；
//  3. 挂载根组件 LunioApp 并注入 Riverpod 容器。
//
// Java 对照：
// - `runApp(...)` ≈ Spring Boot 的 `SpringApplication.run(...)`，
//   区别是它启动的是 UI 组件树而不是 Web 容器。
// - `ProviderScope` ≈ Spring 的 IoC 容器（ApplicationContext），
//   所有页面通过它读取"Bean"（本项目里叫 Provider，见 lib/app/providers.dart）。
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/lunio_app.dart';
import 'core/notifications/lunio_notification_service.dart';

/// main 之前的异步初始化入口。
///
/// Dart 的 `main` 可以声明为 `async`（Java 的 main 不行），配合 `await`
/// 语义等价于 Java 里 `CompletableFuture.get()` 的阻塞等待，但不会卡 UI
/// ——因为此刻 UI 还没启动。
Future<void> main() async {
  // 使用 Flutter 插件（通知、文件桥等）前必须先确保引擎绑定就绪，
  // 否则 MethodChannel 调用会抛异常。类似在 Spring 启动最早期初始化基础设施。
  WidgetsFlutterBinding.ensureInitialized();

  // 通知服务是单例（instance），这里完成两件事：
  //  1) 初始化时区数据库（通知按本地时区的"明早 9:00"这种墙钟时间调度）；
  //  2) 初始化 flutter_local_notifications 插件。
  // 初始化失败（原生插件异常等）不能让 App 起不来（白屏）：捕获后把
  // 服务标记为不可用——通知能力整体降级为 no-op，数据与 UI 照常运行。
  try {
    await LunioNotificationService.instance.initialize();
  } catch (error) {
    LunioNotificationService.instance.markInitializationFailed();
    debugPrint('通知服务初始化失败，App 以无通知模式启动：$error');
  }

  // ProviderScope 是 Riverpod 的根容器：包裹整个组件树后，
  // 所有子组件才能通过 ref.read / ref.watch 获取 Provider。
  runApp(const ProviderScope(child: LunioApp()));
}
