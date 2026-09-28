// 文件导出/选择的原生桥（MethodChannel ≈ Flutter↔原生的 RPC 调用）。
//
// Dart 侧只声明"方法名 + 参数"，真正实现分别在：
//  - Android: android/app/src/main/kotlin/com/example/lunio/MainActivity.kt
//    （ACTION_CREATE_DOCUMENT / ACTION_OPEN_DOCUMENT 系统文件选择器）
//  - iOS: ios/Runner/SceneDelegate.swift（临时文件 + UIDocumentPicker）
//
// 异常翻译与降级日志统一走 native_channel.dart 的 guardedChannelCall
// （PlatformException / MissingPluginException → 哨兵值并 debugPrint，
// 本文件不再手写 catch）：失败按"用户取消"处理，不让异常冒泡打断
// 备份/恢复流程（R7）。pickJsonFile 的 null 有两义——用户取消（原生
// 正常回 null）与失败（异常降级），日志可区分，调用方语义不变。
import 'package:flutter/services.dart';

import 'native_channel.dart';

class NativeFiles {
  const NativeFiles._();

  static const _channel = MethodChannel('lunio/native_files');

  /// 导出 JSON 文件：弹出系统保存对话框，用户选位置后写入 content。
  /// 返回是否成功（用户取消/失败为 false）。
  static Future<bool> exportJsonFile({
    required String filename,
    required String content,
  }) async {
    return guardedChannelCall(
      channel: _channel.name,
      method: 'exportJsonFile',
      fallback: false,
      invoke: () async =>
          await _channel.invokeMethod<bool>('exportJsonFile', {
                'filename': filename,
                'content': content,
              }) ??
              false,
    );
  }

  /// 选择并读取一个 JSON 文件：弹出系统文件选择器，返回文件内容字符串；
  /// 用户取消返回 null。备份导入的第一步。
  static Future<String?> pickJsonFile() async {
    return guardedChannelCall<String?>(
      channel: _channel.name,
      method: 'pickJsonFile',
      fallback: null,
      invoke: () => _channel.invokeMethod<String>('pickJsonFile'),
    );
  }
}
