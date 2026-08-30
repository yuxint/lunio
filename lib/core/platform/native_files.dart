// 文件导出/选择的原生桥（MethodChannel ≈ Flutter↔原生的 RPC 调用）。
//
// Dart 侧只声明"方法名 + 参数"，真正实现分别在：
//  - Android: android/app/src/main/kotlin/com/example/lunio/MainActivity.kt
//    （ACTION_CREATE_DOCUMENT / ACTION_OPEN_DOCUMENT 系统文件选择器）
//  - iOS: ios/Runner/SceneDelegate.swift（临时文件 + UIDocumentPicker）
//
// channel 调用统一捕获 PlatformException / MissingPluginException
// （原生侧未注册 channel、或系统选择器被系统杀掉等情况）：
// 失败按"用户取消"处理并 debugPrint，不让异常冒泡打断备份/恢复流程（R7）。
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class NativeFiles {
  const NativeFiles._();

  static const _channel = MethodChannel('lunio/native_files');

  /// 导出 JSON 文件：弹出系统保存对话框，用户选位置后写入 content。
  /// 返回是否成功（用户取消/失败为 false）。
  static Future<bool> exportJsonFile({
    required String filename,
    required String content,
  }) async {
    try {
      final saved = await _channel.invokeMethod<bool>('exportJsonFile', {
        'filename': filename,
        'content': content,
      });
      return saved ?? false;
    } on PlatformException catch (error) {
      debugPrint('exportJsonFile PlatformException: $error');
      return false;
    } on MissingPluginException catch (error) {
      debugPrint('exportJsonFile MissingPluginException: $error');
      return false;
    }
  }

  /// 选择并读取一个 JSON 文件：弹出系统文件选择器，返回文件内容字符串；
  /// 用户取消返回 null。备份导入的第一步。
  static Future<String?> pickJsonFile() async {
    try {
      return await _channel.invokeMethod<String>('pickJsonFile');
    } on PlatformException catch (error) {
      debugPrint('pickJsonFile PlatformException: $error');
      return null;
    } on MissingPluginException catch (error) {
      debugPrint('pickJsonFile MissingPluginException: $error');
      return null;
    }
  }
}
