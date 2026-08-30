// 跳转系统通知设置页的原生桥。
//
// Android: MainActivity.kt 打开本应用通知设置（带 fallback）；
// iOS: SceneDelegate.swift 用 UIApplicationOpenSettingsURLString。
// 通知设置 sheet 里的"系统设置"按钮走这里（iOS 上返回后 sheet 会关闭）。
//
// 与 native_files 不同，这里捕获了 PlatformException/MissingPluginException
// 失败返回 false，由 UI 提示"无法打开系统设置"。
import 'package:flutter/services.dart';

class NativeNotificationSettings {
  const NativeNotificationSettings._();

  static const _channel = MethodChannel('lunio/native_notification_settings');

  /// 打开当前 App 的系统通知设置页。返回是否成功。
  static Future<bool> openNotificationSettings() async {
    try {
      return await _channel.invokeMethod<bool>('openNotificationSettings') ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
