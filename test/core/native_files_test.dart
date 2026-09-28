// NativeFiles 桥的单元测试：通道参数、取消/失败语义、异常翻译。
//
// 锁法与 native_live_activities_test 一致（9-26 架构审查：四个未设防
// 的桥补契约测试——本桥是备份导出/恢复的核心链路，最值得锁）。该桥
// 两端都注册（Android MainActivity.kt / iOS SceneDelegate.swift），无
// 平台守卫。这里锁死 Dart 侧契约：
//  - exportJsonFile 送 filename/content、原样回传原生结果；
//  - pickJsonFile 原样回传文件内容；原生正常回 null（用户取消）与
//    异常降级 null 语义相同、路径不同，两路径都锁；
//  - 平台异常 / 通道缺失翻译为 false / null，不上抛（R7：备份/恢复
//    流程不被异常打断）。
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunio/core/platform/native_files.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('lunio/native_files');
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

  group('exportJsonFile', () {
    test('sends filename and content, returns the native result', () async {
      responder = (call) => true;

      final saved = await NativeFiles.exportJsonFile(
        filename: 'lunio-backup.json',
        content: '{"schemaVersion":3}',
      );

      expect(saved, isTrue);
      expect(calls.single.method, 'exportJsonFile');
      expect(calls.single.arguments['filename'], 'lunio-backup.json');
      expect(calls.single.arguments['content'], '{"schemaVersion":3}');
    });

    test('user cancel (native null) is false', () async {
      expect(
        await NativeFiles.exportJsonFile(filename: 'a.json', content: '{}'),
        isFalse,
      );
    });

    test('translates a platform exception into false', () async {
      responder = (call) =>
          throw PlatformException(code: 'picker_active', message: '占线');

      expect(
        await NativeFiles.exportJsonFile(filename: 'a.json', content: '{}'),
        isFalse,
      );
    });

    test('translates a missing channel into false', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);

      expect(
        await NativeFiles.exportJsonFile(filename: 'a.json', content: '{}'),
        isFalse,
      );
    });
  });

  group('pickJsonFile', () {
    test('returns the file content from the native side', () async {
      responder = (call) => '{"schemaVersion":3}';

      expect(await NativeFiles.pickJsonFile(), '{"schemaVersion":3}');
      expect(calls.single.method, 'pickJsonFile');
    });

    test('user cancel (native null) stays null without exceptions', () async {
      expect(await NativeFiles.pickJsonFile(), isNull);
    });

    test('translates a platform exception into null', () async {
      responder =
          (call) => throw PlatformException(code: 'read_failed', message: '坏了');

      expect(await NativeFiles.pickJsonFile(), isNull);
    });

    test('translates a missing channel into null', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);

      expect(await NativeFiles.pickJsonFile(), isNull);
    });
  });
}
