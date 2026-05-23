import 'package:flutter/services.dart';

class NativeFiles {
  const NativeFiles._();

  static const _channel = MethodChannel('lunio/native_files');

  static Future<void> shareFile(String path) {
    return _channel.invokeMethod<void>('shareFile', {'path': path});
  }

  static Future<String?> pickJsonFile() {
    return _channel.invokeMethod<String>('pickJsonFile');
  }
}
