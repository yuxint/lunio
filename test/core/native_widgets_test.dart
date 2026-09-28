// NativeWidgets 桥的单元测试：通道参数、平台守卫、异常翻译。
//
// 锁法与 native_live_activities_test 一致（9-26 架构审查：五个桥的
// 异常翻译收编 guardedChannelCall 时，为未设防的四个桥补齐 Dart 侧
// 契约测试——method 名/参数键在重构期改名即被抓，不再只能靠运行时
// 日志）。iOS 执行体（LunioWidgetsExtension）无法本机验证，那半边走
// 真机验收；这里锁死 Dart 侧契约：
//  - updateSnapshot 送 'json' 键、原样回传原生结果（null 归一 false）；
//  - 平台异常 / 通道缺失翻译为 false，不上抛；
//  - 非 iOS 平台自禁用（零通道调用）。
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunio/core/platform/native_widgets.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('lunio/native_widgets');
  late NativeWidgets bridge;
  late List<MethodCall> calls;

  /// 通道应答函数（由 mockIOS 设置；null = 原生无应答）。
  Object? Function(MethodCall call)? responder;

  /// 声明 iOS 平台并设置通道应答。[handler] 返回通道应答（默认 null）。
  void mockIOS({Object? Function(MethodCall call)? handler}) {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    responder = handler;
  }

  setUp(() {
    bridge = NativeWidgets();
    calls = <MethodCall>[];
    responder = null;
    // 记录型 mock handler 不分平台常驻注册：非 iOS 用例的"零通道调用"
    // 断言只有在守卫被删、调用真的落到这里留下记录时才可能失败——
    // 锁不住 _supported 守卫的写法见 native_live_activities_test 注释。
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return responder?.call(call);
        });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('sends snapshot json and returns the native result', () async {
    mockIOS(handler: (call) => true);

    final saved = await bridge.updateSnapshot('{"schemaVersion":1}');

    expect(saved, isTrue);
    expect(calls.single.method, 'updateSnapshot');
    expect(calls.single.arguments['json'], '{"schemaVersion":1}');
  });

  test('native null result translates to false', () async {
    mockIOS();

    expect(await bridge.updateSnapshot('{}'), isFalse);
  });

  test('translates a platform exception into false', () async {
    mockIOS(
      handler: (call) => throw PlatformException(code: 'mock', message: '保存失败'),
    );

    expect(await bridge.updateSnapshot('{}'), isFalse);
  });

  test('translates a missing channel into false', () async {
    mockIOS();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);

    expect(await bridge.updateSnapshot('{}'), isFalse);
  });

  test('is a no-op off iOS', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;

    expect(await bridge.updateSnapshot('{}'), isFalse);
    expect(calls, isEmpty);
  });
}
