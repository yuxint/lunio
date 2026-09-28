// 方法通道调用的统一降级守卫（lib/core/platform 五个原生桥共用）。
//
// 职责只有一条：把「通道调用失败」翻译成调用方的哨兵值（false/null），
// 并在唯一一个地方记一行日志。≈ Java 里把 RPC 客户端的异常翻译收在
// 统一的代理/拦截器里，而不是每个调用点手写 try/catch。
//
// 此前这条策略手抄在五个桥（native_files / native_live_activities /
// native_widgets / native_notification_settings / native_system_ui）的
// 18 处 catch 子句里、且只有 native_files 记日志——载荷键改名、通道名
// 拼错等契约漂移在运行时与「设备不支持」不可区分（9-26 架构审查三轮）。
//
// 静默降级语义本身是产品决策（ADR 0012 决定 6：非 iOS/低版本/系统
// 开关关闭一律静默返回"未启用"），本函数不改变它，只是让它可诊断：
//  - PlatformException：原生侧拒绝（参数不符、系统调用失败）——契约
//    漂移最常见的信号；
//  - MissingPluginException：通道尚未随 scene 生命周期装配好（启动
//    早期竞态，SceneDelegate 挂载重试窗口内属已知正常）。与前者同记、
//    靠消息里的异常类型区分。
// 日志走 debugPrint 不挂 kDebugMode：量极小（每次降级一行），真机
// profile/release 构建排障也要看得到。
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 执行一次方法通道调用，失败翻译为 [fallback] 并记一行日志，不抛异常。
///
/// [invoke] 是实际的通道调用闭包——由调用方决定 invokeMethod 的类型
/// 参数与返回形状（bool / String? / Map / 自定义 DTO 都适用），哨兵
/// 语义（含 `?? fallback` 的空结果归一）也留在调用方，与迁移前逐字节
/// 等价。[channel] 与 [method] 只用于日志定位，格式
/// `[channel] method 异常类型: 详情`。
Future<T> guardedChannelCall<T>({
  required String channel,
  required String method,
  required Future<T> Function() invoke,
  required T fallback,
}) async {
  try {
    return await invoke();
  } on PlatformException catch (error) {
    debugPrint('[$channel] $method PlatformException: $error');
    return fallback;
  } on MissingPluginException catch (error) {
    debugPrint('[$channel] $method MissingPluginException: $error');
    return fallback;
  }
}
