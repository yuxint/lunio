// NativeLiveActivities 桥的单元测试：通道参数、平台守卫、异常翻译。
//
// iOS 执行体（ParkingCountdownActivityController）与扩展 UI 无法在本机
// 构建/运行验证（模拟器构建不可用，ADR 0012 后果第 1 条），那半边走
// 真机验收；这里锁死 Dart 侧契约：
//  - start 送毫秒时间戳、原样回传原生结果；
//  - 平台异常 / 通道缺失翻译为 false / null，不上抛；
//  - 非 iOS 平台全部自禁用（零通道调用）。
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunio/core/platform/native_live_activities.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('lunio/native_live_activities');
  late NativeLiveActivities bridge;
  late List<MethodCall> calls;

  /// 通道应答函数（由 mockIOS 设置；null = 原生无应答）。
  Object? Function(MethodCall call)? responder;

  /// 声明 iOS 平台并设置通道应答。[handler] 返回通道应答（默认 null）。
  void mockIOS({Object? Function(MethodCall call)? handler}) {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    responder = handler;
  }

  /// 模拟通道未装配：撤掉 mock handler，invokeMethod 抛
  /// MissingPluginException（桥翻译为 false / null）。
  void mockChannelMissing() {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  }

  setUp(() {
    bridge = NativeLiveActivities();
    calls = <MethodCall>[];
    responder = null;
    // 记录型 mock handler 不分平台常驻注册：非 iOS 用例的"零通道调用"
    // 断言只有在守卫被删、调用真的落到这里留下记录时才可能失败——若按
    // 平台条件注册（守卫删了只会走 MissingPluginException），断言恒真，
    // 锁不住 _supported 守卫。
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

  group('start', () {
    test('sends millisecond timestamps and returns the native result', () async {
      mockIOS(handler: (call) => true);
      final endsAt = DateTime.fromMillisecondsSinceEpoch(5000);

      final started = await bridge.start(
        startedAt: DateTime.fromMillisecondsSinceEpoch(1000),
        endsAt: endsAt,
      );

      expect(started, isTrue);
      expect(calls.single.method, 'start');
      expect(calls.single.arguments['startedAtMs'], 1000.0);
      expect(calls.single.arguments['endsAtMs'], 5000.0);
    });

    test('translates a platform exception into false', () async {
      mockIOS(
        handler: (call) => throw PlatformException(code: 'mock', message: '关了'),
      );

      final started = await bridge.start(
        startedAt: DateTime.now(),
        endsAt: DateTime.now().add(const Duration(minutes: 1)),
      );

      expect(started, isFalse);
    });

    test('is a no-op off iOS', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;

      final started = await bridge.start(
        startedAt: DateTime.now(),
        endsAt: DateTime.now().add(const Duration(minutes: 1)),
      );

      expect(started, isFalse);
      expect(calls, isEmpty);
    });
  });

  group('status', () {
    test('decodes a running snapshot from the native map', () async {
      mockIOS(
        handler: (call) => <String, Object?>{
          'running': true,
          'expired': true,
          'endsAtMs': 5000.0,
        },
      );

      final snapshot = await bridge.status();

      expect(snapshot, isNotNull);
      expect(snapshot!.running, isTrue);
      expect(snapshot.expired, isTrue);
      expect(
        snapshot.endsAt,
        DateTime.fromMillisecondsSinceEpoch(5000),
      );
    });

    test('returns a not-running snapshot without endsAt', () async {
      mockIOS(handler: (call) => <String, Object?>{'running': false});

      final snapshot = await bridge.status();

      expect(snapshot!.running, isFalse);
      expect(snapshot.endsAt, isNull);
    });

    test('returns null off iOS', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;

      expect(await bridge.status(), isNull);
      expect(calls, isEmpty);
    });

    test('returns null when the channel is missing', () async {
      mockChannelMissing();

      expect(await bridge.status(), isNull);
    });
  });

  group('stop / markExpired', () {
    test('stop passes through on iOS and no-ops elsewhere', () async {
      mockIOS(handler: (call) => true);
      expect(await bridge.stop(), isTrue);
      expect(calls.single.method, 'stop');

      calls.clear();
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(await bridge.stop(), isFalse);
      expect(calls, isEmpty);
    });

    test('markExpired passes through on iOS', () async {
      mockIOS(handler: (call) => true);

      expect(await bridge.markExpired(), isTrue);
      expect(calls.single.method, 'markExpired');
    });
  });
}
