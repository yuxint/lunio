// OBD 会话日志模块单测（2026-11-18 拍板功能）：临时目录驱动，零真实
// 用户目录。覆盖 store（列表/读取/删除/清理）与 recorder（起行/读数/
// 事件/收尾/文件名解析）与生产 sink 的串行链与清理触发。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lunio/domain/entities/diagnostics_probe.dart';
import 'package:lunio/domain/entities/diagnostics_parse_type.dart';
import 'package:lunio/features/shell/diagnostics/elm327_parser.dart';
import 'package:lunio/features/shell/diagnostics/obd_session_log.dart';

void main() {
  late Directory tempDir;
  late ObdSessionLogStore store;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('obd_session_test');
    store = ObdSessionLogStore(directory: tempDir);
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  /// 造一个会话文件（start + N 条读数 + disconnect 收尾）。
  Future<void> seedSession(DateTime at, int readings) async {
    final recorder = ObdSessionLogRecorder(directory: tempDir);
    await recorder.start(at: at, device: 'dev-1');
    for (var i = 0; i < readings; i++) {
      await recorder.appendReading(
        probeName: '水温',
        command: '0167',
        display: '${90 + i}℃',
        noDataReason: null,
        at: at.add(Duration(seconds: 10 * (i + 1))),
      );
    }
    await recorder.close(reason: '主动断开', at: at.add(const Duration(minutes: 5)));
  }

  group('recorder', () {
    test('start/appendReading/close 全链：行契约与文件名', () async {
      final at = DateTime(2026, 11, 18, 20, 28, 30);
      await seedSession(at, 3);
      final files = tempDir.listSync().whereType<File>().toList();
      expect(files, hasLength(1));
      expect(
        files.single.uri.pathSegments.last,
        'session-20261118-202830.jsonl',
      );
      final lines = (await files.single.readAsString())
          .split('\n')
          .where((l) => l.trim().isNotEmpty)
          .toList();
      // start + 3 读数 + disconnect = 5 行。
      expect(lines, hasLength(5));
      final start = jsonDecode(lines.first) as Map<String, Object?>;
      expect(start['t'], 'start');
      expect(start['device'], 'dev-1');
      final reading = jsonDecode(lines[1]) as Map<String, Object?>;
      expect(reading['t'], 'r');
      expect(reading['probe'], '水温');
      expect(reading['v'], '90℃');
      final end = jsonDecode(lines.last) as Map<String, Object?>;
      expect(end['e'], 'disconnect');
      expect(end['reason'], '主动断开');
    });

    test('无数据读数带原因 r；display null', () async {
      final at = DateTime(2026, 11, 18, 20, 28, 30);
      final recorder = ObdSessionLogRecorder(directory: tempDir);
      await recorder.start(at: at);
      await recorder.appendReading(
        probeName: '油量',
        command: '012F',
        display: null,
        noDataReason: '超时',
        at: at.add(const Duration(seconds: 10)),
      );
      await recorder.close(at: at.add(const Duration(minutes: 1)));
      final lines = tempDir
          .listSync()
          .whereType<File>()
          .single
          .readAsStringSync()
          .split('\n')
          .where((l) => l.trim().isNotEmpty)
          .toList();
      final reading = jsonDecode(lines[1]) as Map<String, Object?>;
      expect(reading['v'], isNull);
      expect(reading['r'], '超时');
    });

    test('未 start 直接 append 静默；重复 start 抛 StateError', () async {
      final at = DateTime(2026, 11, 18, 20, 28, 30);
      final recorder = ObdSessionLogRecorder(directory: tempDir);
      // 未 start：append 静默（无文件）。
      await recorder.appendReading(
        probeName: '水温',
        command: '0167',
        display: '90℃',
        noDataReason: null,
        at: at,
      );
      expect(tempDir.listSync().whereType<File>(), isEmpty);
      // start 后重复 start 抛错。
      await recorder.start(at: at);
      expect(
        () => recorder.start(at: at),
        throwsStateError,
      );
      await recorder.close(at: at.add(const Duration(minutes: 1)));
    });

    test('同秒两次 start：第二个文件名顺延 1 秒，不截断旧会话', () async {
      final at = DateTime(2026, 11, 18, 20, 28, 30);
      final first = ObdSessionLogRecorder(directory: tempDir);
      await first.start(at: at, device: 'dev-1');
      final second = ObdSessionLogRecorder(directory: tempDir);
      await second.start(at: at, device: 'dev-2');
      final names = [
        for (final f in tempDir.listSync().whereType<File>())
          f.uri.pathSegments.last,
      ]..sort();
      expect(names[0], 'session-20261118-202830.jsonl');
      expect(names[1], 'session-20261118-202831.jsonl');
      // 第一份文件未被截断：start 行的 device 仍是 dev-1。
      final firstContent = await File(
        '${tempDir.path}/session-20261118-202830.jsonl',
      ).readAsString();
      expect(firstContent, contains('"device":"dev-1"'));
      await first.close(at: at);
      await second.close(at: at);
    });
  });

  group('store', () {
    test('list 倒序 + 条数/大小；readContent；delete', () async {
      await seedSession(DateTime(2026, 11, 18, 20, 28, 30), 3);
      await seedSession(DateTime(2026, 11, 18, 21, 0, 0), 1);
      final entries = await store.list();
      expect(entries, hasLength(2));
      // 新的在前。
      expect(entries.first.startedAt.hour, 21);
      expect(entries.first.lineCount, 3); // start+1+disconnect
      expect(entries.last.lineCount, 5); // start+3+disconnect
      expect(entries.last.bytes, greaterThan(0));
      final content = await store.readContent(entries.last.fileName);
      expect(content, contains('"t":"start"'));
      await store.delete(entries.last.fileName);
      expect(await store.list(), hasLength(1));
    });

    test('坏名文件跳过；非 jsonl 后缀跳过', () async {
      File('${tempDir.path}/session-bad.jsonl').writeAsStringSync('{}');
      File('${tempDir.path}/session-20261118-202830.txt').writeAsStringSync('{}');
      expect(await store.list(), isEmpty);
    });

    test('cleanup：7 天过期删、50 上限删最旧', () async {
      final now = DateTime(2026, 11, 18, 22, 0, 0);
      // 8 天前、2 天前各一个。
      await seedSession(now.subtract(const Duration(days: 8)), 1);
      await seedSession(now.subtract(const Duration(days: 2)), 1);
      final deleted = await store.cleanup(now: now);
      expect(deleted, 1);
      final entries = await store.list();
      expect(entries, hasLength(1));
      expect(entries.single.startedAt.day, now.subtract(const Duration(days: 2)).day);
    });

    test('cleanup：50 上限内不动，超限删最旧', () async {
      final now = DateTime(2026, 11, 18, 22, 0, 0);
      for (var i = 0; i < 51; i++) {
        await seedSession(
          now.subtract(Duration(minutes: 60 * (52 - i))),
          1,
        );
      }
      final deleted = await store.cleanup(now: now);
      expect(deleted, 1);
      expect(await store.list(), hasLength(50));
    });
  });

  group('ProductionObdSessionLogSink', () {
    test('start→reading→end 串行落盘 + 清理触发', () async {
      final sink = ProductionObdSessionLogSink(store: store);
      final at = DateTime(2026, 11, 18, 20, 28, 30);
      final probe = DiagnosticsProbe(
        id: 1,
        carId: 1,
        name: '水温',
        command: '0167',
        parseType: DiagnosticsParseType.coolantTempAux,
        enabled: true,
      );
      sink.onSessionStart(at, deviceId: 'dev-1');
      sink.onProbeReading(
        probe,
        const ObdValue(display: '95℃', celsius: 95),
        at.add(const Duration(seconds: 10)),
      );
      sink.onSessionEnd(at.add(const Duration(minutes: 5)), reason: '主动断开');
      // 串行链完成后再断言（chainIdle 测试钩子，替代睡眠等待——睡眠
      // 时长随机器负载抖动，深审非确定性修复）。
      await sink.chainIdle;
      final entries = await store.list();
      expect(entries, hasLength(1));
      final content = await store.readContent(entries.single.fileName);
      expect(content, contains('"t":"start"'));
      expect(content, contains('"v":"95℃"'));
      expect(content, contains('"e":"disconnect"'));
    });

    test('currentRecordingFileName 跟随 start/close 翻转（删除保护数据源）', () async {
      final sink = ProductionObdSessionLogSink(store: store);
      final at = DateTime(2026, 11, 18, 20, 28, 30);
      sink.onSessionStart(at, deviceId: 'dev-1');
      await sink.chainIdle;
      expect(sink.currentRecordingFileName, isNotNull);
      sink.onSessionEnd(at, reason: '手动断开');
      await sink.chainIdle;
      expect(sink.currentRecordingFileName, isNull);
    });

    test('生命周期事件落 lifecycle 行（后台停摆归因，2026-11-20）', () async {
      final sink = ProductionObdSessionLogSink(store: store);
      final at = DateTime(2026, 11, 20, 7, 40, 41);
      sink.onSessionStart(at, deviceId: 'dev-1');
      sink.onAppLifecycle('paused', at.add(const Duration(seconds: 1)));
      sink.onAppLifecycle('resumed', at.add(const Duration(minutes: 10)));
      await sink.chainIdle;
      final entries = await store.list();
      final content = await store.readContent(entries.single.fileName);
      expect(content, contains('"e":"lifecycle"'));
      expect(content, contains('"s":"paused"'));
      expect(content, contains('"s":"resumed"'));
    });

    test('无会话时生命周期事件静默丢弃（不建文件）', () async {
      final sink = ProductionObdSessionLogSink(store: store);
      sink.onAppLifecycle('paused', DateTime(2026, 11, 20, 7, 40, 41));
      await sink.chainIdle;
      expect(await store.list(), isEmpty);
    });

    test('油量门限拒绝落 fuel_gate 行（2026-11-21）', () async {
      final sink = ProductionObdSessionLogSink(store: store);
      final at = DateTime(2026, 11, 21, 8, 36, 44);
      sink.onSessionStart(at, deviceId: 'dev-1');
      sink.onFuelGateRejected(
        probeName: '油量',
        raw: 27,
        held: 40,
        samples: 3,
        span: 13,
        at: at.add(const Duration(seconds: 1)),
      );
      await sink.chainIdle;
      final entries = await store.list();
      final content = await store.readContent(entries.single.fileName);
      expect(content, contains('"e":"fuel_gate"'));
      expect(content, contains('"probe":"油量"'));
      expect(content, contains('"raw":27.0'));
      expect(content, contains('"held":40.0'));
      expect(content, contains('"n":3'));
      expect(content, contains('"span":13.0'));
    });
  });
}
