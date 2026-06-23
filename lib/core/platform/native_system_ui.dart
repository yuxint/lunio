import 'package:flutter/services.dart';

class NativeSystemNavigationInfo {
  const NativeSystemNavigationInfo({
    required this.navigationMode,
    required this.navigationBarHeight,
  });

  final int navigationMode;
  final double navigationBarHeight;

  bool get usesThreeButtonNavigation => navigationMode == 0;
}

class NativeSystemUi {
  const NativeSystemUi._();

  static const _channel = MethodChannel('lunio/native_system_ui');

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
