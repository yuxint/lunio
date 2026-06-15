import 'package:flutter/services.dart';

class NativeNotificationSettings {
  const NativeNotificationSettings._();

  static const _channel = MethodChannel('lunio/native_notification_settings');

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
