import 'package:flutter/services.dart';

class NativeFiles {
  const NativeFiles._();

  static const _channel = MethodChannel('lunio/native_files');

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

  static Future<String?> pickJsonFile() {
    return _channel.invokeMethod<String>('pickJsonFile');
  }
}
