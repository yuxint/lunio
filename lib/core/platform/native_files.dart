import 'package:flutter/services.dart';

class NativeFiles {
  const NativeFiles._();

  static const _channel = MethodChannel('lunio/native_files');

  static Future<void> exportJsonFile({
    required String filename,
    required String content,
  }) {
    return _channel.invokeMethod<void>('exportJsonFile', {
      'filename': filename,
      'content': content,
    });
  }

  static Future<String?> pickJsonFile() {
    return _channel.invokeMethod<String>('pickJsonFile');
  }
}
