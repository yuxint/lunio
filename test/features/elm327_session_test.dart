// ELM327 会话决策体单测（票 04）：喂字节、收事件，只测外部行为。
// 延时走注入接缝（_DelayGate），零真实等待；事件经 StreamQueue 按
// 序消费，断言确定性来自事件流的先进先出。
//
// 覆盖：AT 序列逐条发等 >（ATSP 7 必发）、初始化超时上抛可辨识错误、
// 一轮串行全部启用项、单条超时映射行级无数据不阻塞后续、停轮/断开
// 可中断、链路丢失、dispose 释放。
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lunio/domain/entities/diagnostics_parse_type.dart';
import 'package:lunio/domain/entities/diagnostics_probe.dart';
import 'package:lunio/features/shell/diagnostics/elm327_parser.dart';
import 'package:lunio/features/shell/diagnostics/elm327_session.dart';
import 'package:lunio/features/shell/diagnostics/mock_obd_transport.dart';

/// 注入延时接缝：记录每次请求的时长并挂起，测试按序放行（completeAt）
/// 或整体放行（completeAll）。会话侧 responseTimeout/pollInterval 与
/// Mock 分片延时共用同一形态，可精确驱动超时竞速。
class _DelayGate {
  final requests = <Duration>[];
  final _completers = <Completer<void>>[];

  Future<void> gate(Duration d) {
    requests.add(d);
    final completer = Completer<void>();
    _completers.add(completer);
    return completer.future;
  }

  void completeAt(int index) => _completers[index].complete();

  void completeAll() {
    for (final completer in _completers) {
      if (!completer.isCompleted) {
        completer.complete();
      }
    }
  }
}

/// 事件队列：订阅会话事件流按序取用（StreamQueue 的最小替代，免引
/// package:async）。流关闭后 pending 的 next 以 StateError 收场。
class _EventQueue {
  final _buffered = <Elm327SessionEvent>[];
  final _waiters = <Completer<Elm327SessionEvent>>[];

  _EventQueue(Elm327Session session) {
    session.events.listen(
      (event) {
        if (_waiters.isNotEmpty) {
          _waiters.removeAt(0).complete(event);
        } else {
          _buffered.add(event);
        }
      },
      onDone: () {
        for (final waiter in _waiters) {
          waiter.completeError(StateError('事件流已关闭'));
        }
      },
    );
  }

  /// 取下一个事件（先缓冲后挂起）。
  Future<Elm327SessionEvent> next() {
    if (_buffered.isNotEmpty) {
      return Future.value(_buffered.removeAt(0));
    }
    final waiter = Completer<Elm327SessionEvent>();
    _waiters.add(waiter);
    return waiter.future;
  }
}

/// 即时应答脚本（零延时单块）。
MockObdScript resp(String text) => MockObdScript(
      chunks: [latin1.encode(text)],
      firstChunkDelay: Duration.zero,
      chunkGap: Duration.zero,
    );

DiagnosticsProbe makeProbe(
  int id,
  String command,
  DiagnosticsParseType parseType,
) {
  return DiagnosticsProbe(
    id: id,
    name: 'P$id',
    command: command,
    parseType: parseType,
  );
}

void main() {
  group('connect：AT 序列', () {
    test('逐条发等 >，ATSP 7 必发不省略（语料序列）', () async {
      final gate = _DelayGate();
      final mock = MockObdTransport(
        responses: mockObdCorpusDemoResponses(),
        delay: (_) async {},
      );
      final session = Elm327Session(transport: mock, delay: gate.gate);
      await session.connect();
      expect(session.state, Elm327SessionState.connected);
      expect(mock.sentCommands, ['ATZ', 'ATE0', 'ATL0', 'ATSP7']);
    });

    test('初始化超时：上抛 Elm327SessionException + 断开事件 + 终态', () async {
      final gate = _DelayGate();
      // ATZ 无声（不应答）→ 走响应超时。
      final mock = MockObdTransport(
        responses: {'ATZ': const MockObdScript.silent()},
        delay: (_) async {},
      );
      final session = Elm327Session(transport: mock, delay: gate.gate);
      final queue = _EventQueue(session);
      final connectFuture = session.connect();
      // 第一个延时请求 = ATZ 的响应超时竞速；放行它。
      while (gate.requests.isEmpty) {
        await pumpEventQueue();
      }
      gate.completeAt(0);
      Object? caught;
      try {
        await connectFuture;
      } catch (e) {
        caught = e;
      }
      expect(caught, isA<Elm327SessionException>());
      expect(session.state, Elm327SessionState.disconnected);
      final event = await queue.next();
      expect(event, isA<Elm327Disconnected>());
      await session.dispose();
    });
  });

  group('轮询编排', () {
    test('一轮串行读全部启用项，轮间停 pollInterval', () async {
      final gate = _DelayGate();
      final mock = MockObdTransport(
        responses: mockObdCorpusDemoResponses(),
        delay: (_) async {},
      );
      final session = Elm327Session(transport: mock, delay: gate.gate);
      final queue = _EventQueue(session);
      await session.connect();
      expect(await queue.next(), isA<Elm327Connected>());
      session.startPolling(enabledProbes: () => [
        makeProbe(1, '012F', DiagnosticsParseType.fuelLevel),
        makeProbe(2, '0105', DiagnosticsParseType.coolantTemp),
        makeProbe(3, 'ATRV', DiagnosticsParseType.voltageText),
      ]);
      final first = await queue.next() as Elm327ProbeReading;
      final second = await queue.next() as Elm327ProbeReading;
      final third = await queue.next() as Elm327ProbeReading;
      // 一轮按序：油量 → 水温 → 电压（实车数值）。
      expect(first.probeId, 1);
      expect((first.reading as ObdValue).display, '37.6%');
      expect(second.probeId, 2);
      expect((second.reading as ObdValue).display, '90℃');
      expect(third.probeId, 3);
      expect((third.reading as ObdValue).display, '11.2V');
      // 串行发送次序 = AT 序列 + 一轮启用项。
      expect(
        mock.sentCommands,
        ['ATZ', 'ATE0', 'ATL0', 'ATSP7', '012F', '0105', 'ATRV'],
      );
      // 轮间停 pollInterval：第 8 个延时请求 = 轮间延时（前 7 个是各
      // 指令的响应超时竞速，时长 5s）。
      expect(gate.requests.length, 8);
      expect(gate.requests.last, const Duration(seconds: 3));
      await session.dispose();
    });

    test('单条超时映射行级无数据、不阻塞后续', () async {
      final gate = _DelayGate();
      final mock = MockObdTransport(
        responses: {
          'ATZ': resp('\r\rELM327 v2.3\r\r>'),
          'ATE0': resp('OK\r\r>'),
          'ATL0': resp('OK\r\r>'),
          'ATSP7': resp('OK\r\r>'),
          '019D': const MockObdScript.silent(),
          '0105': resp('41 05 82 \r\r>'),
        },
        delay: (_) async {},
      );
      final session = Elm327Session(transport: mock, delay: gate.gate);
      final queue = _EventQueue(session);
      await session.connect();
      expect(await queue.next(), isA<Elm327Connected>());
      session.startPolling(enabledProbes: () => [
        makeProbe(7, '019D', DiagnosticsParseType.rawHex),
        makeProbe(8, '0105', DiagnosticsParseType.coolantTemp),
      ]);
      // 放行 019D 的响应超时（第 5 个延时请求）。
      while (gate.requests.length < 5) {
        await pumpEventQueue();
      }
      gate.completeAt(4);
      final first = await queue.next() as Elm327ProbeReading;
      expect(first.probeId, 7);
      expect(first.reading, isA<ObdNoData>());
      final second = await queue.next() as Elm327ProbeReading;
      expect(second.probeId, 8);
      expect((second.reading as ObdValue).display, '90℃');
      await session.dispose();
    });

    test('停轮检查点退出、不再发下一轮', () async {
      final gate = _DelayGate();
      final mock = MockObdTransport(
        responses: mockObdCorpusDemoResponses(),
        delay: (_) async {},
      );
      final session = Elm327Session(transport: mock, delay: gate.gate);
      final queue = _EventQueue(session);
      await session.connect();
      expect(await queue.next(), isA<Elm327Connected>());
      session.startPolling(
        enabledProbes: () => [
          makeProbe(1, '012F', DiagnosticsParseType.fuelLevel),
        ],
      );
      final reading = await queue.next() as Elm327ProbeReading;
      expect((reading.reading as ObdValue).display, '37.6%');
      // 读数事件后循环停在轮间延时（第 6 个延时请求）。
      while (gate.requests.length < 6) {
        await pumpEventQueue();
      }
      session.stopPolling();
      gate.completeAt(5);
      await pumpEventQueue();
      // 检查点退出：不再发下一轮（变异目标：删轮末检查点 → 此断言失败）。
      expect(mock.sentCommands.length, 5);
      await session.dispose();
    });
  });

  group('断开与链路丢失', () {
    test('disconnect 中断在途请求、事件与终态一致', () async {
      final gate = _DelayGate();
      final mockDelay = _DelayGate();
      // 012F 分片首块延时挂起 → 在途请求停在路上。
      final mock = MockObdTransport(
        responses: {
          'ATZ': resp('\r\rELM327 v2.3\r\r>'),
          'ATE0': resp('OK\r\r>'),
          'ATL0': resp('OK\r\r>'),
          'ATSP7': resp('OK\r\r>'),
          '012F': MockObdScript(
            chunks: [latin1.encode('41 2F 60 \r'), latin1.encode('\r>')],
            firstChunkDelay: const Duration(milliseconds: 209),
            chunkGap: Duration.zero,
          ),
        },
        // 零延时直接放行（AT 序列即时应答），非零延时挂起等待放行。
        delay: (d) => d > Duration.zero ? mockDelay.gate(d) : Future.value(),
      );
      final session = Elm327Session(transport: mock, delay: gate.gate);
      final queue = _EventQueue(session);
      await session.connect();
      expect(await queue.next(), isA<Elm327Connected>());
      session.startPolling(
        enabledProbes: () => [
          makeProbe(1, '012F', DiagnosticsParseType.fuelLevel),
        ],
      );
      // 等在途请求上路（mock 分片延时已挂起）。
      while (mockDelay.requests.isEmpty) {
        await pumpEventQueue();
      }
      session.disconnect();
      final event = await queue.next() as Elm327Disconnected;
      expect(event.cause, isA<Elm327SessionException>());
      expect(session.state, Elm327SessionState.disconnected);
      // 轮询已退出：之后泵事件队列不再产生新发送。
      await pumpEventQueue();
      expect(mock.sentCommands, ['ATZ', 'ATE0', 'ATL0', 'ATSP7', '012F']);
      await session.dispose();
    });

    test('字节流 error → 断开事件 + 终态', () async {
      final gate = _DelayGate();
      final mock = MockObdTransport(
        responses: mockObdCorpusDemoResponses(),
        delay: (_) async {},
      );
      final session = Elm327Session(transport: mock, delay: gate.gate);
      final queue = _EventQueue(session);
      await session.connect();
      expect(await queue.next(), isA<Elm327Connected>());
      mock.injectError(StateError('蓝牙断连'));
      final event = await queue.next() as Elm327Disconnected;
      expect(event.cause, isA<StateError>());
      expect(session.state, Elm327SessionState.disconnected);
      await session.dispose();
    });

    test('dispose 后事件流关闭（离开页面不泄漏订阅）', () async {
      final gate = _DelayGate();
      final mock = MockObdTransport(
        responses: mockObdCorpusDemoResponses(),
        delay: (_) async {},
      );
      final session = Elm327Session(transport: mock, delay: gate.gate);
      await session.connect();
      final done = Completer<void>();
      session.events.listen((_) {}, onDone: done.complete);
      await session.dispose();
      await done.future.timeout(const Duration(seconds: 1));
      expect(session.state, Elm327SessionState.disconnected);
    });

    test('迟到的空白提示符帧不打断在途请求（防读数错位）', () async {
      final gate = _DelayGate();
      final mock = MockObdTransport(
        responses: {
          'ATZ': resp('OK\r\r>'),
          'ATE0': resp('OK\r\r>'),
          'ATL0': resp('OK\r\r>'),
          'ATSP7': resp('OK\r\r>'),
          '012F': const MockObdScript.silent(),
        },
        delay: (_) async {},
      );
      final session = Elm327Session(transport: mock, delay: gate.gate);
      final queue = _EventQueue(session);
      await session.connect();
      expect(await queue.next(), isA<Elm327Connected>());
      session.startPolling(
        enabledProbes: () => [
          makeProbe(1, '012F', DiagnosticsParseType.fuelLevel),
        ],
      );
      // 012F 在途（无声脚本）：第 5 个门 = 它的响应超时。
      while (gate.requests.length < 5) {
        await pumpEventQueue();
      }
      // 在途窗口注入迟到的纯提示符碎片：过滤后不入队，在途请求继续等
      // 真超时（变异对照：去掉空白帧过滤 → 在途等待者被空帧打断、
      // reason 变'无 012F 响应行'，此处红）。
      mock.injectBytes(latin1.encode('\r>'));
      await pumpEventQueue();
      await pumpEventQueue();
      gate.completeAt(4);
      final first = await queue.next() as Elm327ProbeReading;
      expect((first.reading as ObdNoData).reason, '超时');
      await session.dispose();
    });
  });
}
