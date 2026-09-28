// NativeSystemUi 桥的单元测试：通道契约、返回值形状校验、异常翻译。
//
// 锁法与 native_live_activities_test 一致（9-26 架构审查：四个未设防
// 的桥补契约测试）。该桥仅 Android 实现（iOS 不注册通道），无平台
// 守卫——Dart 侧靠 MissingPluginException → null 跳过适配。这里锁死
// Dart 侧契约：
//  - 调用 getSystemNavigationInfo、按返回键解码 DTO（高度 num → double）；
//  - 返回值形状不对（键缺失/类型不符）→ null，不走异常路径；
//  - 平台异常 / 通道缺失翻译为 null，不上抛。
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunio/core/platform/native_system_ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('lunio/native_system_ui');
  late List<MethodCall> calls;

  /// 通道应答函数（null = 原生无应答）。
  Object? Function(MethodCall call)? responder;

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

  test('decodes a valid navigation info map', () async {
    responder = (call) => <String, Object?>{
          'navigationMode': 0,
          'navigationBarHeight': 44,
        };

    final info = await NativeSystemUi.getSystemNavigationInfo();

    expect(info, isNotNull);
    expect(info!.navigationMode, 0);
    expect(info.navigationBarHeight, 44.0);
    expect(info.usesThreeButtonNavigation, isTrue);
    expect(calls.single.method, 'getSystemNavigationInfo');
  });

  test('returns null on an invalid shape (missing or mistyped keys)',
      () async {
    responder = (call) => <String, Object?>{'navigationMode': 'three-button'};

    expect(await NativeSystemUi.getSystemNavigationInfo(), isNull);

    responder = (call) => <String, Object?>{};
    expect(await NativeSystemUi.getSystemNavigationInfo(), isNull);
  });

  test('translates a platform exception into null', () async {
    responder =
        (call) => throw PlatformException(code: 'mock', message: '读不到');

    expect(await NativeSystemUi.getSystemNavigationInfo(), isNull);
  });

  test('returns null when the channel is missing (the iOS path)', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);

    expect(await NativeSystemUi.getSystemNavigationInfo(), isNull);
  });
}
