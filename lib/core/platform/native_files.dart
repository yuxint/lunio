// 文件导出/选择的原生桥（MethodChannel ≈ Flutter↔原生的 RPC 调用）。
//
// Dart 侧只声明"方法名 + 参数"，真正实现分别在：
//  - Android: android/app/src/main/kotlin/com/example/lunio/MainActivity.kt
//    （ACTION_CREATE_DOCUMENT / ACTION_OPEN_DOCUMENT 系统文件选择器）
//  - iOS: ios/Runner/SceneDelegate.swift（临时文件 + UIDocumentPicker）
//
// ⚠ 未捕获 MissingPluginException：若原生侧没注册该 channel
// （iOS scene 时机问题等），调用会抛未处理异常（审查报告 R7）。
import 'package:flutter/services.dart';

class NativeFiles {
  const NativeFiles._();

  static const _channel = MethodChannel('lunio/native_files');

  /// 导出 JSON 文件：弹出系统保存对话框，用户选位置后写入 content。
  /// 返回是否成功（用户取消/失败为 false）。
  static Future<bool> exportJsonFile({
    required String filename,
    required String content,
  }) {
    return _channel
        .invokeMethod<bool>('exportJsonFile', {
          'filename': filename,
          'content': content,
        })
        .then((value) => value ?? false);
  }

  /// 选择并读取一个 JSON 文件：弹出系统文件选择器，返回文件内容字符串；
  /// 用户取消返回 null。备份导入的第一步。
  static Future<String?> pickJsonFile() {
    return _channel.invokeMethod<String>('pickJsonFile');
  }
}
