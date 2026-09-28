// 跳转系统通知设置页的原生桥。
//
// Android: MainActivity.kt 打开本应用通知设置（带 fallback）；
// iOS: SceneDelegate.swift 用 UIApplicationOpenSettingsURLString。
// 通知设置 sheet 里的"系统设置"按钮走这里（iOS 上返回后 sheet 会关闭）。
//
// 异常翻译与降级日志统一走 native_channel.dart 的 guardedChannelCall
// （本文件不再手写 catch）：失败返回 false，由 UI 提示
// "无法打开系统设置"。两端都注册了该通道，无平台守卫。
import 'package:flutter/services.dart';

import 'native_channel.dart';

class NativeNotificationSettings {
  const NativeNotificationSettings._();

  static const _channel = MethodChannel('lunio/native_notification_settings');

  /// 打开当前 App 的系统通知设置页。返回是否成功。
  static Future<bool> openNotificationSettings() async {
    return guardedChannelCall(
      channel: _channel.name,
      method: 'openNotificationSettings',
      fallback: false,
      invoke: () async =>
          await _channel.invokeMethod<bool>('openNotificationSettings') ??
          false,
    );
  }
}
