// NativeNotificationSettings 桥的单元测试：通道契约与异常翻译。
//
// 锁法与 native_live_activities_test 一致（9-26 架构审查：四个未设防
// 的桥补契约测试）。该桥两端都注册（Android MainActivity.kt /
// iOS SceneDelegate.swift），无平台守卫——测试环境默认平台即 Android，
// 透传用例天然覆盖双端语义。这里锁死 Dart 侧契约：
//  - 调用 openNotificationSettings、原样回传原生结果（null 归一 false）；
//  - 平台异常 / 通道缺失翻译为 false，不上抛（UI 据此提示
//    "无法打开系统设置"）。
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunio/core/platform/native_notification_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('lunio/native_notification_settings');
  late List<MethodCall> calls;

  /// 通道应答函数（null = 原生无应答）。
  Object? Function(MethodCall call)? responder;

  /// 被测入口的短名（全名超出 80 列）。
  Future<bool> open() =>
      NativeNotificationSettings.openNotificationSettings();

  setUp(() {
    calls = <MethodCall>[];
    responder = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return responder?.call(call);
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('calls openNotificationSettings and passes through the result',
      () async {
    responder = (call) => true;

    expect(await open(), isTrue);
    expect(calls.single.method, 'openNotificationSettings');
  });

  test('native null result translates to false', () async {
    expect(await open(), isFalse);
  });

  test('translates a platform exception into false', () async {
    responder =
        (call) => throw PlatformException(code: 'mock', message: '打不开');

    expect(await open(), isFalse);
  });

  test('translates a missing channel into false', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);

    expect(await open(), isFalse);
  });
}
