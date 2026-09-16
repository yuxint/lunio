// 桌面小组件快照（iOS Home Screen Widget / WidgetKit）的原生桥。
//
// iOS 14+ 由 SceneDelegate.swift 的 lunio/native_widgets 通道实现：把
// Dart 侧组装好的快照 JSON 写进 App Group 共享存储并请求 WidgetKit
// 重载时间线（ADR 0013）。其他平台、通道尚未随 scene 装配好等场景一律
// 静默返回 false，调用方降级为"不写"——桌面小组件缺失不影响 App 任何
// 功能，也不提示、不报错。
//
// 桥只负责传话：什么时候写快照的编排规则在 widget_snapshot_controller。
//
// 与 native_live_activities 同款：普通可实例化类（通道可注入），测试
// 用假实现覆盖方法即可驱动各路径，不必 mock 方法通道。
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class NativeWidgets {
  NativeWidgets({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('lunio/native_widgets');

  final MethodChannel _channel;

  /// 桌面小组件是 iOS 专属能力：其他平台方法自禁用（≈ 接口返回
  /// "不支持"），Android 行为零变化。
  bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  /// 写入小组件快照并请求系统刷新时间线。返回是否送达原生侧；非 iOS、
  /// 系统侧保存失败（App Group 未配置等）、通道不可用等返回 false
  /// （不抛异常）。快照 JSON 契约见 widget_snapshot.dart。
  Future<bool> updateSnapshot(String json) async {
    if (!_supported) {
      return false;
    }
    try {
      return await _channel.invokeMethod<bool>('updateSnapshot', {
            'json': json,
          }) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
