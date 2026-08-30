// 读取系统导航信息（仅 Android 实现）的原生桥。
//
// 用途：AppShell 适配 Android 三键导航栏——三键模式下系统导航栏
// 不占 safeArea，需要原生侧读实际高度来补 inset（详见 app_shell.dart）。
// iOS 未实现该 channel，Dart 侧返回 null 自然跳过适配。
import 'package:flutter/services.dart';

/// 原生返回的导航信息 DTO。
class NativeSystemNavigationInfo {
  const NativeSystemNavigationInfo({
    required this.navigationMode,
    required this.navigationBarHeight,
  });

  /// 0 = 三键导航，其他值 = 手势导航（与 Android 系统常量对应）。
  final int navigationMode;

  /// 导航栏像素高度（已由原生换算为逻辑像素 dp）。
  final double navigationBarHeight;

  bool get usesThreeButtonNavigation => navigationMode == 0;
}

class NativeSystemUi {
  const NativeSystemUi._();

  static const _channel = MethodChannel('lunio/native_system_ui');

  /// 读取当前导航模式与高度；channel 不存在/返回异常一律返回 null
  /// （调用方按"无需适配"处理）。
  static Future<NativeSystemNavigationInfo?> getSystemNavigationInfo() async {
    try {
      final result = await _channel.invokeMapMethod<String, Object?>(
        'getSystemNavigationInfo',
      );
      final navigationMode = result?['navigationMode'];
      final navigationBarHeight = result?['navigationBarHeight'];
      if (navigationMode is! int || navigationBarHeight is! num) {
        return null;
      }
      return NativeSystemNavigationInfo(
        navigationMode: navigationMode,
        navigationBarHeight: navigationBarHeight.toDouble(),
      );
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}
