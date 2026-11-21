// ELM327 会话决策体单测（票 04）：喂字节、收事件，只测外部行为。
// 延时走注入接缝（_DelayGate），零真实等待；事件经 StreamQueue 按
// 序消费，断言确定性来自事件流的先进先出。
//
// 覆盖：AT 序列逐条发等 >（ATSP 7 必发）、初始化超时上抛可辨识错误、
// 一轮串行全部启用项、单条超时映射行级无数据不阻塞后续、停轮/断开
// 可中断、链路丢失、dispose 释放。
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lunio/domain/entities/diagnostics_parse_type.dart';
import 'package:lunio/domain/entities/diagnostics_probe.dart';
import 'package:lunio/features/shell/diagnostics/elm327_parser.dart';
import 'package:lunio/features/shell/diagnostics/elm327_session.dart';
import 'package:lunio/features/shell/diagnostics/mock_obd_transport.dart';
import 'package:lunio/features/shell/diagnostics/obd_transport.dart';

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

/// 建链挂起的传输层桩：connect 停到用例放行，期间可被 dispose 打断。
class _HangingConnectTransport implements OBDTransport {
  final started = Completer<void>();
  final release = Completer<void>();
  int disconnectCalls = 0;

  @override
  Future<void> connect() async {
    started.complete();
    await release.future;
  }

  @override
  Future<void> send(List<int> bytes) async {}

  @override
  Stream<Uint8List> get byteStream => const Stream.empty();

  @override
  Future<void> disconnect() async {
    disconnectCalls++;
  }
}

/// 写挂起的传输层桩（BLE 半开链路形态）：指定指令的 send 永不返回，
/// 其余指令转发给内部 Mock（响应字节照常经同一条字节流到达）。
class _HangingSendTransport implements OBDTransport {
  _HangingSendTransport({required this.inner, required this.hangOn});

  final MockObdTransport inner;
  final String hangOn;

  @override
  Future<void> connect() => inner.connect();

  @override
  Future<void> send(List<int> bytes) {
    final command = latin1.decode(bytes).trim();
    if (command == hangOn) {
      return Completer<void>().future;
    }
    return inner.send(bytes);
  }

  @override
  Stream<Uint8List> get byteStream => inner.byteStream;

  @override
  Future<void> disconnect() => inner.disconnect();
}

/// 响应帧先到、写回调随后永久挂起的传输层桩（半开链路极窄时序）：
/// 指定指令先注入完整应答帧，再让 send 永不返回。
class _FrameBeforeSendReturnsTransport implements OBDTransport {
  _FrameBeforeSendReturnsTransport({required this.inner, required this.holdOn});

  final MockObdTransport inner;
  final String holdOn;

  @override
  Future<void> connect() => inner.connect();

  @override
  Future<void> send(List<int> bytes) async {
    final command = latin1.decode(bytes).trim();
    if (command == holdOn) {
      inner.injectBytes(latin1.encode('41 2F 60 \r\r>'));
      await Completer<void>().future;
    }
    return inner.send(bytes);
  }

  @override
  Stream<Uint8List> get byteStream => inner.byteStream;

  @override
  Future<void> disconnect() => inner.disconnect();
}

DiagnosticsProbe makeProbe(
  int id,
  String command,
  DiagnosticsParseType parseType,
) {
  return DiagnosticsProbe(
    id: id,
    carId: 1,
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
      expect(mock.sentCommands, ['ATZ', 'ATE0', 'ATL0', 'ATSP7', '0100']);
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

    test('ECU 握手失败：AT 序列成功但 0100 全 NO DATA → 可辨识错误 + 断开', () async {
      final gate = _DelayGate();
      // AT 序列应答正常，0100 回 NO DATA（点火 OFF 总线休眠形态）。
      final mock = MockObdTransport(
        responses: {
          'ATZ': resp('\r\rELM327 v2.3\r\r>'),
          'ATE0': resp('OK\r\r>'),
          'ATL0': resp('OK\r\r>'),
          'ATSP7': resp('OK\r\r>'),
          '0100': resp('NO DATA\r\r>'),
        },
        delay: (_) async {},
      );
      final session = Elm327Session(transport: mock, delay: gate.gate);
      final queue = _EventQueue(session);
      final connectFuture = session.connect();
      connectFuture.ignore();
      final event = await queue.next();
      expect(event, isA<Elm327Disconnected>());
      expect(session.state, Elm327SessionState.disconnected);
      Object? caught;
      try {
        await connectFuture;
      } catch (e) {
        caught = e;
      }
      expect(caught, isA<Elm327EcuUnreachableException>());
      expect(
        (caught as Elm327SessionException).message,
        '适配器已连上，但 ECU 无响应（检查点火开关）',
      );
      expect(mock.sentCommands, ['ATZ', 'ATE0', 'ATL0', 'ATSP7', '0100']);
      await session.dispose();
    });

    test('ECU 握手过程行击穿守卫：SEARCHING... + UNABLE TO CONNECT 也判无响应', () async {
      final gate = _DelayGate();
      // 过程行 + 错误行混合：负向 lines.every(isObdErrorLine) 会被非错
      // 误的过程行击穿（误判 connected），正向判定（有非错误行才算）
      // 拦住——2026-11-18 深审边缘项回归守卫。
      final mock = MockObdTransport(
        responses: {
          'ATZ': resp('\r\rELM327 v2.3\r\r>'),
          'ATE0': resp('OK\r\r>'),
          'ATL0': resp('ECU not detected\r\r>'),
          'ATSP7': resp('OK\r\r>'),
          '0100': resp('SEARCHING...\rUNABLE TO CONNECT\r\r>'),
        },
        delay: (_) async {},
      );
      final session = Elm327Session(transport: mock, delay: gate.gate);
      final queue = _EventQueue(session);
      final connectFuture = session.connect();
      connectFuture.ignore();
      final event = await queue.next();
      expect(event, isA<Elm327Disconnected>());
      expect(session.state, Elm327SessionState.disconnected);
      Object? caught;
      try {
        await connectFuture;
      } catch (e) {
        caught = e;
      }
      expect(caught, isA<Elm327EcuUnreachableException>());
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
        makeProbe(2, '0167', DiagnosticsParseType.coolantTempAux),
        makeProbe(3, 'ATRV', DiagnosticsParseType.voltageText),
      ]);
      final first = await queue.next() as Elm327ProbeReading;
      final second = await queue.next() as Elm327ProbeReading;
      final third = await queue.next() as Elm327ProbeReading;
      // 一轮按序：油量 → 水温 → 电压（实车数值）。
      expect(first.probeId, 1);
      expect((first.reading as ObdValue).display, '38%');
      expect(second.probeId, 2);
      expect((second.reading as ObdValue).display, '95℃');
      expect(third.probeId, 3);
      expect((third.reading as ObdValue).display, '11.2V');
      // 串行发送次序 = AT 序列 + 一轮启用项。
      expect(
        mock.sentCommands,
        ['ATZ', 'ATE0', 'ATL0', 'ATSP7', '0100', '012F', '0167', 'ATRV'],
      );
      // 轮间停 1 秒调度拍（ADR 0023）：第 9 个延时请求 = 轮末一拍
      // （前 8 个是各指令的响应超时竞速，时长 5s；间隔取实体默认 60s，
      // 倒计时按拍递减）。
      expect(gate.requests.length, 9);
      expect(gate.requests.last, Elm327Session.pollTick);
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
          '0100': resp('41 00 90 18 80 11 \r41 00 B6 3C A8 13 \r41 00 90 18 80 03\r\r>'),
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
      // 放行 019D 的响应超时（第 6 个延时请求；第 5 个 = ECU 握手）。
      while (gate.requests.length < 6) {
        await pumpEventQueue();
      }
      gate.completeAt(5);
      final first = await queue.next() as Elm327ProbeReading;
      expect(first.probeId, 7);
      expect(first.reading, isA<ObdNoData>());
      final second = await queue.next() as Elm327ProbeReading;
      expect(second.probeId, 8);
      expect((second.reading as ObdValue).display, '90℃');
      await session.dispose();
    });

    test('send 挂起时超时仍收尾：行级无数据、串行槽释放、暂停不锁死', () async {
      final gate = _DelayGate();
      final inner = MockObdTransport(
        responses: mockObdCorpusDemoResponses(),
        delay: (_) async {},
      );
      final transport = _HangingSendTransport(inner: inner, hangOn: '012F');
      final session = Elm327Session(
        transport: transport,
        // 暂停轮询的 50ms 睡眠直接放行（只驱动超时与轮间拍门闩）。
        delay: (d) => d == const Duration(milliseconds: 50)
            ? Future<void>.value()
            : gate.gate(d),
      );
      final queue = _EventQueue(session);
      await session.connect();
      expect(await queue.next(), isA<Elm327Connected>());
      session.startPolling(enabledProbes: () => [
        makeProbe(1, '012F', DiagnosticsParseType.fuelLevel),
      ]);
      // 012F 的 send 永不返回：第 6 个门 = 它的响应超时竞速（第 5 个 = ECU 握手）。
      while (gate.requests.length < 6) {
        await pumpEventQueue();
      }
      // 旧实现：超时错误被 completer.future.ignore() 吞掉、_frameWaiter
      // 永占 —— pausePolling 死等、后续请求全部「串行违规」。
      final pause = session.pausePolling();
      gate.completeAt(5);
      await pause.timeout(const Duration(seconds: 1));
      final reading =
          await queue.next().timeout(const Duration(seconds: 1))
              as Elm327ProbeReading;
      expect(reading.probeId, 1);
      expect((reading.reading as ObdNoData).reason, '超时');
      // 串行槽已释放：原始命令可发（旧实现这里抛「串行违规」）。
      final frame = await session.sendRawCommand('ATRV');
      expect(frame, contains('11.2V'));
      await session.dispose();
    });

    test('帧先到而 send 挂起：请求照常完成、串行槽不占死', () async {
      final gate = _DelayGate();
      final inner = MockObdTransport(
        responses: mockObdCorpusDemoResponses(),
        delay: (_) async {},
      );
      final transport = _FrameBeforeSendReturnsTransport(
        inner: inner,
        holdOn: '012F',
      );
      final session = Elm327Session(transport: transport, delay: gate.gate);
      final queue = _EventQueue(session);
      await session.connect();
      expect(await queue.next(), isA<Elm327Connected>());
      session.startPolling(enabledProbes: () => [
        makeProbe(1, '012F', DiagnosticsParseType.fuelLevel),
      ]);
      // 帧先到即证明写入已送达：不等到挂死的 send，本条请求直接完成
      //（旧实现 sendPhase 只在 completer 报错时才收尾，此处会死锁）。
      final reading =
          await queue.next().timeout(const Duration(seconds: 1))
              as Elm327ProbeReading;
      expect(reading.probeId, 1);
      expect((reading.reading as ObdValue).display, '38%');
      // 串行槽已释放：原始命令可发。
      final frame = await session.sendRawCommand('ATRV');
      expect(frame, contains('11.2V'));
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
      expect((reading.reading as ObdValue).display, '38%');
      // 读数事件后循环停在轮间延时（第 7 个延时请求）。
      while (gate.requests.length < 7) {
        await pumpEventQueue();
      }
      session.stopPolling();
      gate.completeAt(6);
      await pumpEventQueue();
      // 检查点退出：不再发下一轮（变异目标：删轮末检查点 → 此断言失败）。
      expect(mock.sentCommands.length, 6);
      await session.dispose();
    });

    test('手动刷新立即补跑一轮（不动自动间隔）', () async {
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
      final first = await queue.next() as Elm327ProbeReading;
      expect(first.probeId, 1);
      // 等循环进入 1 秒调度拍（一拍 = pollTick）。
      while (!gate.requests.contains(Elm327Session.pollTick)) {
        await pumpEventQueue();
      }
      session.requestImmediatePoll();
      final second = await queue.next() as Elm327ProbeReading;
      expect(second.probeId, 1);
      expect(
        mock.sentCommands.where((command) => command == '012F'),
        hasLength(2),
      );
      await session.dispose();
    });

    test('暂停后原始命令独占链路，恢复后继续轮询', () async {
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
      final first = await queue.next() as Elm327ProbeReading;
      expect(first.probeId, 1);
      while (!gate.requests.contains(Elm327Session.pollTick)) {
        await pumpEventQueue();
      }
      await session.pausePolling();
      final frame = await session.sendRawCommand('ATRV');
      expect(frame, contains('11.2V'));
      expect(
        mock.sentCommands.where((command) => command == '012F'),
        hasLength(1),
        reason: '暂停期间不再自动轮询',
      );
      session.resumePolling();
      session.requestImmediatePoll();
      final second = await queue.next() as Elm327ProbeReading;
      expect(second.probeId, 1);
      expect(
        mock.sentCommands.where((command) => command == '012F'),
        hasLength(2),
      );
      await session.dispose();
    });
  });

  group('轮询 header 切换（2026-11-18 深审修复，问题 3）', () {
    test('带 header 探针先 ATSH 切头再发指令；无 header 探针切回默认头', () async {
      final gate = _DelayGate();
      final mock = MockObdTransport(
        responses: {
          'ATZ': resp('\r\rELM327 v2.3\r\r>'),
          'ATE0': resp('OK\r\r>'),
          'ATL0': resp('OK\r\r>'),
          'ATSP7': resp('OK\r\r>'),
          '0100': resp('41 00 90 18 80 11\r\r>'),
          'ATSHDA1EF1': resp('OK\r\r>'),
          'ATSHDB33F1': resp('OK\r\r>'),
          '012F': resp('41 2F 60 \r\r>'),
        },
        delay: (_) async {},
      );
      final session = Elm327Session(transport: mock, delay: gate.gate);
      await session.connect();
      final cvt = DiagnosticsProbe(
        id: 1,
        carId: 1,
        name: 'CVT',
        command: '012F',
        parseType: DiagnosticsParseType.fuelLevel,
        header: 'ATSH DA1EF1',
      );
      final plain = DiagnosticsProbe(
        id: 2,
        carId: 1,
        name: 'Plain',
        command: '012F',
        parseType: DiagnosticsParseType.fuelLevel,
      );
      session.startPolling(enabledProbes: () => [cvt, plain]);
      // 等一轮完成（两条 + 两次 ATSH = 4 条命令）。
      while (mock.sentCommands.length < 9) {
        await pumpEventQueue();
      }
      expect(mock.sentCommands.sublist(5), [
        'ATSHDA1EF1',
        '012F',
        'ATSHDB33F1',
        '012F',
      ]);
      session.stopPolling();
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
          '0100': resp('41 00 90 18 80 11 \r41 00 B6 3C A8 13 \r41 00 90 18 80 03\r\r>'),
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
      expect(mock.sentCommands, ['ATZ', 'ATE0', 'ATL0', 'ATSP7', '0100', '012F']);
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

    test('建链期间 dispose：不投递连接事件、释放后正常收尾', () async {
      final transport = _HangingConnectTransport();
      final session = Elm327Session(transport: transport);
      final events = <Elm327SessionEvent>[];
      final done = Completer<void>();
      session.events.listen(events.add, onDone: done.complete);
      final connecting = session.connect();
      await transport.started.future;
      await session.dispose();
      // dispose 先行：迟到建链必须立即失败退出，不得再标 connected、
      // 不得再投递任何事件（旧实现会先发 Disconnected，并在关闭流后
      // add 连接事件时抛 StateError）。1 秒上限同时排除真实超时兜底
      //（默认 responseTimeout 5 秒）造成的假通过。
      transport.release.complete();
      await expectLater(
        connecting.timeout(const Duration(seconds: 1)),
        throwsA(isA<Elm327SessionException>()),
      );
      await done.future.timeout(const Duration(seconds: 1));
      expect(events, isEmpty);
      expect(session.state, Elm327SessionState.disconnected);
      expect(transport.disconnectCalls, greaterThanOrEqualTo(1));
    });

    test('迟到的空白提示符帧不打断在途请求（防读数错位）', () async {
      final gate = _DelayGate();
      final mock = MockObdTransport(
        responses: {
          'ATZ': resp('OK\r\r>'),
          'ATE0': resp('OK\r\r>'),
          'ATL0': resp('OK\r\r>'),
          'ATSP7': resp('OK\r\r>'),
          '0100': resp('41 00 90 18 80 11 \r41 00 B6 3C A8 13 \r41 00 90 18 80 03\r\r>'),
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
      // 012F 在途（无声脚本）：第 6 个门 = 它的响应超时（第 5 个 = ECU 握手）。
      while (gate.requests.length < 6) {
        await pumpEventQueue();
      }
      // 在途窗口注入迟到的纯提示符碎片：过滤后不入队，在途请求继续等
      // 真超时（变异对照：去掉空白帧过滤 → 在途等待者被空帧打断、
      // reason 变'无 012F 响应行'，此处红）。
      mock.injectBytes(latin1.encode('\r>'));
      await pumpEventQueue();
      await pumpEventQueue();
      gate.completeAt(5);
      final first = await queue.next() as Elm327ProbeReading;
      expect((first.reading as ObdNoData).reason, '超时');
      await session.dispose();
    });
  });
}
