// 车辆诊断页 widget 测试夹具（票 05）：门闩（completer gate）驱动的
// 可控 Mock 传输层 + 会话定时。零真实定时器——门闩是纯 Completer，
// 超时/轮进位/字节到达全部由用例逐拍释放（对齐 elm327_session_test 的
// _DelayGate 配方），测试零 pending timer 残留、全决定性。
//
// 时序配方：
//  - 字节到达走 [chunkGate]（Mock 延时接缝）："deliverChunks" 释放 =
//    在途指令的响应字节到达（多 ECU 分片同拍）。
//  - 会话定时走 [timeGate]（会话延时接缝）："advanceRound" 释放 = 一拍
//    时钟：已完成请求的超时闩无副作用释放 + 轮间隔闩释放进下一轮。
//    （仅当无在途请求时调用，否则在途请求被误判超时。）
//  - 时钟注入固定时刻（行尾"最后更新时间"断言确定性）。
import 'dart:async';
import 'dart:convert';

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lunio/features/shell/diagnostics/ble_obd_transport.dart';
import 'package:lunio/features/shell/diagnostics/elm327_session.dart';
import 'package:lunio/features/shell/diagnostics/mock_obd_transport.dart';
import 'package:lunio/features/shell/diagnostics/obd_transport.dart';
import 'package:lunio/features/shell/diagnostics/obd_runtime.dart';

/// 即时应答脚本（单块，字节到达时机由 chunkGate 控）。
MockObdScript rigResp(String text) {
  return MockObdScript(
    chunks: [latin1.encode(text)],
    firstChunkDelay: Duration.zero,
    chunkGap: Duration.zero,
  );
}

/// 标准应答表：AT 序列 + 内置三条一轮的语料值（油量 0x60 = 37.6%，
/// 水温 0x82 = 90℃，电压 11.2V）。
Map<String, MockObdScript> rigStandardResponses() {
  return {
    'ATZ': rigResp('\r\rELM327 v2.3\r\r>'),
    'ATE0': rigResp('OK\r\r>'),
    'ATL0': rigResp('OK\r\r>'),
    'ATSP7': rigResp('OK\r\r>'),
    '012F': rigResp('41 2F 60 \r\r>'),
    '0105': rigResp('41 05 82 \r\r>'),
    'ATRV': rigResp('11.2V\r\r>'),
  };
}

/// 门闩：记录每次请求的时长并挂起，用例整体放行（completeAll）。
class RigGate {
  final requests = <Duration>[];
  final _completers = <Completer<void>>[];

  Future<void> gate(Duration d) {
    requests.add(d);
    final completer = Completer<void>();
    _completers.add(completer);
    return completer.future;
  }

  /// 放行当前全部未完成闩。
  void completeAll() {
    for (final completer in _completers) {
      if (!completer.isCompleted) {
        completer.complete();
      }
    }
  }

  /// 只放行指定时长的闩（区分 300ms 响应超时与 1s 轮询拍）。
  void completeDuration(Duration duration) {
    for (var index = 0; index < requests.length; index++) {
      if (requests[index] == duration && !_completers[index].isCompleted) {
        _completers[index].complete();
      }
    }
  }
}

/// 诊断页测试装具。
class DiagnosticsRig {
  DiagnosticsRig({
    Map<String, MockObdScript>? responses,
    this.connectError,
  }) {
    mock = MockObdTransport(
      responses: responses ?? rigStandardResponses(),
      delay: (d) => chunkGate.gate(d),
    );
    sessionFactory = (deviceId) {
      lastDeviceId = deviceId;
      return Elm327Session(
        transport: connectError == null
            ? mock
            : _ThrowingConnectTransport(connectError!),
        now: connectError == null ? () => fixedNow : DateTime.now,
        delay: connectError == null
            ? (d) => timeGate.gate(d)
            : (d) => Future<void>.delayed(d),
        responseTimeout: const Duration(milliseconds: 300),
      );
    };
  }

  /// 会话工厂最近一次收到的设备标识（连接流程传参断言用）。
  String? lastDeviceId;

  /// 注入的传输层建链失败错误（非 null = 会话建链必失败，直连降级分
  /// 流用例用）。
  final Object? connectError;

  /// 可控 Mock（测试表 + 字节门闩延时）。
  late final MockObdTransport mock;

  /// 受控假扫描器（obdScannerProvider 覆盖用；emit 推清单）。
  final FakeObdScanner scanner = FakeObdScanner();

  /// 字节到达门闩（Mock 延时接缝）。
  final RigGate chunkGate = RigGate();

  /// 会话定时门闩（会话延时接缝：超时/轮间隔）。
  final RigGate timeGate = RigGate();

  /// 固定时钟（全部读取打点同一时刻，行尾时间断言确定性）。
  final DateTime fixedNow = DateTime(2026, 5, 19, 14, 30, 0);

  /// 会话工厂（obdSessionFactoryProvider 覆盖用）。
  late final Elm327Session Function(String deviceId) sessionFactory;

  /// pumpApp 的 extraOverrides。
  List<dynamic> get overrides => [
        obdSessionFactoryProvider.overrideWithValue(sessionFactory),
        obdScannerProvider.overrideWithValue(scanner),
      ];

  /// 释放字节门闩 + 泵帧：在途指令的响应到达，请求完成，下一条指令
  /// 开跑（其字节门闩挂起等下一次释放）。
  Future<void> deliverChunks(WidgetTester tester) async {
    chunkGate.completeAll();
    await tester.pump();
  }

  /// 只放行响应超时闩（300ms）：让在途静默请求落行级无数据。用于
  /// "单条超时/无数据不连坐"类用例，不能连带放行 1s 轮询拍。
  Future<void> completeProbeTimeout(WidgetTester tester) async {
    timeGate.completeDuration(const Duration(milliseconds: 300));
    await tester.pump();
  }

  /// 释放轮询拍进入下一轮：每检测点默认 30 秒间隔（ADR 0023），按
  /// 1 秒拍推进 31 拍（第 30 拍把倒计时减到 0，第 31 拍触发下一轮）。
  /// 仅当无在途请求（值已全部渲染）时调用；已完成请求的 300ms 超时
  /// 闩无副作用放行。
  Future<void> advanceRound(WidgetTester tester) async {
    for (var tick = 0; tick < 31; tick++) {
      timeGate.completeAll();
      await tester.pump();
    }
  }

  /// 逐拍推进直至 finder 出现（connect + 一轮 ≈ 7 拍，20 拍封顶防死循环）。
  Future<void> advanceUntil(
    WidgetTester tester,
    Finder finder,
  ) async {
    for (var step = 0; step < 20; step++) {
      if (finder.evaluate().isNotEmpty) {
        return;
      }
      await deliverChunks(tester);
    }
    fail('advanceUntil 20 拍内未见目标（finder: $finder）——门闩时序或应答表有问题');
  }
}

/// 受控假扫描器（ObdScanner 接缝的测试替身）：results 是广播流，用例
/// 经 emit 推清单；gateError/startError 模拟门禁与扫描启动失败；
/// gateCalls/startCalls/stopCalls 断言调用次数。
class FakeObdScanner implements ObdScanner {
  final _entries = StreamController<List<BleObdScanEntry>>.broadcast();
  int gateCalls = 0;
  int startCalls = 0;
  int stopCalls = 0;

  /// 已发射清单（emit 经 [mergeScanEntries] 与真扫描器同一合并契约——
  /// 首见定序跨拍保持；start 复位镜像真扫描器的新扫描会话）。
  List<BleObdScanEntry> _last = const [];

  /// ensureReady 抛出的错误（null = 门禁通过）。
  Object? gateError;

  /// start 抛出的错误（null = 正常启动）。
  Object? startError;

  @override
  Stream<List<BleObdScanEntry>> get results => _entries.stream;

  @override
  Future<void> ensureReady() async {
    gateCalls++;
    final error = gateError;
    if (error != null) {
      throw error;
    }
  }

  @override
  Future<void> start() async {
    startCalls++;
    _last = const [];
    final error = startError;
    if (error != null) {
      throw error;
    }
  }

  @override
  Future<void> stop() async {
    stopCalls++;
  }

  /// 推一批扫描结果（测试手动调用）。经 [mergeScanEntries] 整备——
  /// 与真扫描器同一契约（空名过滤 + 首见定序），替身忠实镜像数据源
  /// 行为，widget 用例经接缝端到端锁过滤与顺序稳定性。
  void emit(List<BleObdScanEntry> entries) {
    _last = mergeScanEntries(_last, entries);
    _entries.add(_last);
  }
}

/// 建链即抛的传输层桩（直连降级分流用例用）：connect 抛注入错误，其
/// 余契约方法空实现。
class _ThrowingConnectTransport implements OBDTransport {
  _ThrowingConnectTransport(this.error);

  final Object error;

  @override
  Future<void> connect() async => throw error;

  @override
  Future<void> send(List<int> bytes) async {}

  @override
  Stream<Uint8List> get byteStream => const Stream.empty();

  @override
  Future<void> disconnect() async {}
}
