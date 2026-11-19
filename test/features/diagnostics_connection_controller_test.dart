// 诊断连接编排 controller 单测（C1）：直连/扫描分流、门禁与失败回填、
// 取消与重连、最后读数合并与落库。全部经注入接缝驱动（会话工厂 + 门闩
// 延时 + 假扫描器 + 闭包记忆/落库），零真实等待、零 widget。
//
// 时序配方同 diagnostics fixture：Mock 分片延时走 chunkGate（放行 = 在途
// 指令的响应到达），会话延时走 timeGate（响应超时竞速/轮询拍，未放行
// 即挂起——测试按需逐条放行，避免轮询空转）。
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lunio/domain/entities/diagnostics_parse_type.dart';
import 'package:lunio/domain/entities/diagnostics_probe.dart';
import 'package:lunio/features/shell/diagnostics/ble_obd_errors.dart';
import 'package:lunio/features/shell/diagnostics/ble_scan_entries.dart';
import 'package:lunio/features/shell/diagnostics/diagnostics_connection_controller.dart';
import 'package:lunio/features/shell/diagnostics/elm327_parser.dart'
    show ObdNoData, ObdReading, ObdValue;
import 'package:lunio/features/shell/diagnostics/elm327_session.dart';
import 'package:lunio/features/shell/diagnostics/mock_obd_transport.dart';
import 'package:lunio/features/shell/diagnostics/obd_session_log.dart';
import 'package:lunio/features/shell/diagnostics/obd_transport.dart';

import '../helpers/diagnostics_fixture.dart';

/// 建链即抛的传输层桩（会话级/BLE 失败分流用）。
class _ThrowingTransport implements OBDTransport {
  _ThrowingTransport(this.error);

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

/// 建链挂起的传输层桩（连接中关 sheet 取消在途连接用）。
class _HangingConnectTransport implements OBDTransport {
  final release = Completer<void>();
  int disconnectCalls = 0;

  @override
  Future<void> connect() async {
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

/// 会话日志收尾用假件：只记账 onSessionEnd 调用（问题 1 用例）。
class _RecordingSink implements ObdSessionLogSink {
  _RecordingSink(this.ends);

  final List<(DateTime, String?)> ends;

  @override
  void onSessionStart(DateTime at, {String? deviceId, bool mock = false}) {}

  @override
  void onProbeReading(
    DiagnosticsProbe probe,
    ObdReading reading,
    DateTime at,
  ) {}

  @override
  void onSessionEnd(DateTime at, {String? reason}) {
    ends.add((at, reason));
  }

  @override
  void onVerificationLog(String log, DateTime at) {}

  @override
  String? get currentRecordingFileName => null;
}

DiagnosticsProbe _probe(
  int id,
  String command,
  DiagnosticsParseType parseType, {
  bool enabled = true,
  String? lastValue,
  double? lastPercent,
  DateTime? lastReadingAt,
}) {
  return DiagnosticsProbe(
    id: id,
    carId: 1,
    name: 'P$id',
    command: command,
    parseType: parseType,
    enabled: enabled,
    lastValue: lastValue,
    lastPercent: lastPercent,
    lastReadingAt: lastReadingAt,
  );
}

/// 控制器测试装具：可控会话工厂 + 假扫描器 + 记忆/落库捕获 + UI 动作计数。
class _Harness {
  _Harness({
    Object? connectError,
    this.rememberedId,
    bool mockLink = false,
    Map<String, MockObdScript>? responses,
    OBDTransport? transportOverride,
    ObdSessionLogSink? sessionLogSink,
  }) {
    mock = MockObdTransport(
      responses: responses ?? rigStandardResponses(),
      delay: (d) => chunkGate.gate(d),
    );
    controller = DiagnosticsConnectionController(
      sessionFactory: (deviceId) {
        deviceIds.add(deviceId);
        return Elm327Session(
          transport: transportFactory?.call(deviceIds.length) ??
              transportOverride ??
              (connectError == null ? mock : _ThrowingTransport(connectError)),
          now: () => fixedNow,
          delay: (d) => timeGate.gate(d),
          responseTimeout: const Duration(milliseconds: 300),
        );
      },
      scanner: scanner,
      readDeviceId: () async => rememberedId,
      rememberDevice: (id) async => remembered.add(id),
      saveReading: (probeId, {required value, percent, required at}) async {
        saved.add((probeId, value, percent, at));
      },
      mockLink: mockLink,
      sessionLogSink: sessionLogSink,
    );
    // ADR 0027：UI 接缝与 ECU 里程回调改为挂载式接缝（App 级控制器，
    // 页面 initState 挂载、dispose 摘除）；测试装具构造后立即挂上。
    controller.attachUi(
      DiagnosticsConnectionUi(
        openScanSheet: () => openCalls++,
        closeScanSheet: () => closeCalls++,
      ),
    );
    controller.setOdometerSyncHandler(odometerReadings.add);
    addTearDown(controller.dispose);
  }

  /// ECU 里程同步接缝捕获（ADR 0026 用例）。
  final odometerReadings = <ObdValue>[];

  final FakeObdScanner scanner = FakeObdScanner();
  final RigGate chunkGate = RigGate();
  final RigGate timeGate = RigGate();
  final DateTime fixedNow = DateTime(2026, 5, 19, 14, 30, 0);
  late final MockObdTransport mock;
  late final DiagnosticsConnectionController controller;

  /// 设备记忆当前值（用例可改：null = 无记忆首用）。
  String? rememberedId;

  /// 按尝试序号（1 起）给传输层（多会话竞态用例用；null = 统一用
  /// transportOverride / connectError / 默认 Mock）。
  OBDTransport Function(int attempt)? transportFactory;

  /// 会话工厂收到的设备标识（按序）。
  final deviceIds = <String>[];

  /// rememberDevice 调用记录。
  final remembered = <String>[];

  /// saveReading 调用记录：(probeId, value, percent, at)。
  final saved = <(int, String, double?, DateTime)>[];

  int openCalls = 0;
  int closeCalls = 0;

  Future<void> pump() => pumpEventQueue();

  /// 发出 command 并逐拍放行 chunk 门闩（connect 的 AT 序列 = 4 条 +
  /// ECU 握手 0100，共 5 条）。
  Future<void> driveChunks(int count) async {
    for (var i = 0; i < count; i++) {
      await pump();
      chunkGate.completeAll();
      await pump();
    }
  }

  /// 直连（记忆命中）到已连接：放行 4 条 AT 序列 + ECU 握手后等
  /// Connected 事件落地。
  Future<void> connectDirect() async {
    unawaited(controller.start());
    await driveChunks(5);
    await pump();
  }

  /// 无记忆首用：等门禁 + 开 sheet + 启动扫描。
  Future<void> startScanning() async {
    unawaited(controller.start());
    await pump();
  }

  /// 把设备推给扫描 sheet 并点选。
  Future<void> pick(BleObdScanEntry entry) async {
    scanner.emit([entry]);
    await pump();
    controller.pickDevice(entry);
    await pump();
  }
}

BleObdScanEntry _entry(String id) =>
    BleObdScanEntry(id: id, name: 'OBD-$id', rssi: -40);

void main() {
  group('直连与相位', () {
    test('有记忆直连：工厂收设备标识、进入已连接、不开扫描', () async {
      final h = _Harness(rememberedId: 'dev-1');
      await h.connectDirect();

      expect(h.deviceIds, ['dev-1']);
      expect(h.controller.state.phase, DiagnosticsConnectionPhase.connected);
      expect(h.openCalls, 0);
      expect(h.scanner.gateCalls, 0);
    });

    test('无记忆：门禁后开扫描 sheet，进入扫描中', () async {
      final h = _Harness(rememberedId: null);
      await h.startScanning();

      expect(h.scanner.gateCalls, 1);
      expect(h.scanner.startCalls, 1);
      expect(h.openCalls, 1);
      expect(h.controller.state.phase, DiagnosticsConnectionPhase.scanning);
    });

    test('首用门禁失败：状态条文案、不开 sheet', () async {
      final h = _Harness(rememberedId: null);
      h.scanner.gateError = const BleObdTransportException(
        BleObdLinkErrorKind.permissionDenied,
      );
      await h.startScanning();

      expect(h.openCalls, 0);
      expect(h.scanner.startCalls, 0);
      expect(
        h.controller.state.phase,
        DiagnosticsConnectionPhase.disconnected,
      );
      expect(
        h.controller.state.statusError,
        const BleObdTransportException(
          BleObdLinkErrorKind.permissionDenied,
        ).statusCopy,
      );
    });

    test('扫描启动门禁失败：关 sheet、状态条文案', () async {
      final h = _Harness(rememberedId: null);
      h.scanner.startError = const BleObdTransportException(
        BleObdLinkErrorKind.permissionDenied,
      );
      await h.startScanning();
      await h.pump();

      expect(h.openCalls, 1);
      expect(h.closeCalls, 1);
      expect(h.controller.state.phase, DiagnosticsConnectionPhase.disconnected);
      expect(h.controller.state.statusError, contains('蓝牙权限未授权'));
    });

    test('已连接手动断开：落未连接、设备记忆不动', () async {
      final h = _Harness(rememberedId: 'dev-1');
      await h.connectDirect();

      await h.controller.disconnectManually();
      await h.pump();

      expect(h.controller.state.phase, DiagnosticsConnectionPhase.idle);
      expect(h.controller.state.statusError, isNull);
      expect(h.mock.disconnectCalls, 1);
      expect(h.remembered, isEmpty);
    });

    test('直连失败（设备未扫到）：自动落扫描 sheet', () async {
      final h = _Harness(
        rememberedId: 'dev-1',
        connectError: const BleObdTransportException(
          BleObdLinkErrorKind.deviceNotFound,
        ),
      );
      unawaited(h.controller.start());
      await h.pump();
      await h.pump();

      expect(h.openCalls, 1);
      expect(h.scanner.gateCalls, 1);
      expect(h.controller.state.phase, DiagnosticsConnectionPhase.scanning);
    });

    test('直连门禁失败（权限）：状态条文案、不落扫描', () async {
      final h = _Harness(
        rememberedId: 'dev-1',
        connectError: const BleObdTransportException(
          BleObdLinkErrorKind.permissionDenied,
        ),
      );
      unawaited(h.controller.start());
      await h.pump();
      await h.pump();

      expect(h.openCalls, 0);
      expect(
        h.controller.state.phase,
        DiagnosticsConnectionPhase.disconnected,
      );
      expect(h.controller.state.statusError, contains('蓝牙权限未授权'));
    });
  });

  group('扫描点选', () {
    test('点选成功：停扫、写记忆、关 sheet、已连接', () async {
      final h = _Harness(rememberedId: null);
      await h.startScanning();

      await h.pick(_entry('dev-A'));
      await h.driveChunks(5);
      await h.pump();

      expect(h.deviceIds, ['dev-A']);
      expect(h.scanner.stopCalls, greaterThanOrEqualTo(1));
      expect(h.remembered, ['dev-A']);
      expect(h.closeCalls, 1);
      expect(h.controller.state.phase, DiagnosticsConnectionPhase.connected);
    });

    test('点选失败（设备未扫到）：回填行态、恢复扫描、sheet 不关', () async {
      final h = _Harness(
        rememberedId: null,
        connectError: const BleObdTransportException(
          BleObdLinkErrorKind.deviceNotFound,
        ),
      );
      await h.startScanning();

      await h.pick(_entry('dev-A'));
      await h.pump();

      expect(h.closeCalls, 0);
      expect(h.controller.state.phase, DiagnosticsConnectionPhase.scanning);
      expect(h.controller.state.scan.connectingId, isNull);
      expect(
        h.controller.state.scan.hint,
        const BleObdTransportException(
          BleObdLinkErrorKind.deviceNotFound,
        ).statusCopy,
      );
      expect(h.scanner.startCalls, 2);
    });

    test('点选会话级失败（AT 超时）：同样回填恢复扫描', () async {
      final h = _Harness(
        rememberedId: null,
        connectError: StateError('chip silent'),
      );
      await h.startScanning();

      await h.pick(_entry('dev-A'));
      await h.pump();

      expect(h.closeCalls, 0);
      expect(h.controller.state.phase, DiagnosticsConnectionPhase.scanning);
      expect(h.controller.state.scan.connectingId, isNull);
      expect(h.controller.state.scan.hint, 'AT 初始化序列失败');
      expect(h.scanner.startCalls, 2);
    });

    test('连接中关 sheet = 取消本次连接（迟到的建链不改写相位）', () async {
      final hanging = _HangingConnectTransport();
      final h = _Harness(rememberedId: null, transportOverride: hanging);
      await h.startScanning();
      await h.pick(_entry('dev-A'));
      expect(h.controller.state.phase, DiagnosticsConnectionPhase.connecting);

      h.controller.onScanSheetDismissed();
      await h.pump();

      expect(h.controller.state.phase, DiagnosticsConnectionPhase.idle);
      expect(h.controller.state.statusError, isNull);
      expect(hanging.disconnectCalls, 1);

      // 迟到的建链恢复：尝试已被代数作废，相位不被改写。
      hanging.release.complete();
      await h.pump();
      expect(h.controller.state.phase, DiagnosticsConnectionPhase.idle);
    });

    test('取消后旧尝试的迟到失败不改写新连接相位', () async {
      final hanging = _HangingConnectTransport();
      final h = _Harness(rememberedId: null);
      h.transportFactory = (attempt) => attempt == 1 ? hanging : h.mock;

      // 第一次尝试：挂起在建链上，然后关 sheet 取消。
      await h.startScanning();
      await h.pick(_entry('dev-A'));
      expect(h.controller.state.phase, DiagnosticsConnectionPhase.connecting);
      h.controller.onScanSheetDismissed();
      await h.pump();
      expect(h.controller.state.phase, DiagnosticsConnectionPhase.idle);

      // 第二次尝试：重开扫描并连上 B。
      unawaited(h.controller.openScan());
      await h.pump();
      await h.pick(_entry('dev-B'));
      await h.driveChunks(5);
      await h.pump();
      expect(h.controller.state.phase, DiagnosticsConnectionPhase.connected);
      final connectedSession = h.controller.session;

      // 放行第一次尝试的迟到建链：尝试代数已作废，不得改写 B 的相位。
      hanging.release.complete();
      await h.pump();
      await h.pump();
      expect(h.controller.state.phase, DiagnosticsConnectionPhase.connected);
      expect(h.controller.session, same(connectedSession));
    });

    test('取消回未连接，选择设备再入口重开扫描', () async {
      final h = _Harness(rememberedId: null);
      await h.startScanning();
      h.controller.onScanSheetDismissed();
      await h.pump();
      expect(h.controller.state.phase, DiagnosticsConnectionPhase.idle);

      unawaited(h.controller.openScan());
      await h.pump();

      expect(h.controller.state.phase, DiagnosticsConnectionPhase.scanning);
      expect(h.openCalls, 2);
      expect(h.scanner.startCalls, 2);
    });
  });

  group('最后读数与落库', () {
    test('有效读数写库、无数据不写、实时优先与持久化回退', () async {
      final h = _Harness(rememberedId: 'dev-1');
      final fuel = _probe(1, '012F', DiagnosticsParseType.fuelLevel);
      final coolant = _probe(2, '0167', DiagnosticsParseType.coolantTempAux);
      final volt = _probe(
        3,
        'ATRV',
        DiagnosticsParseType.voltageText,
        enabled: false,
      );
      h.controller.setProbes([fuel, coolant, volt]);
      await h.connectDirect();
      // 一轮只发两个启用项（电压停用）：两拍响应。
      await h.driveChunks(2);

      expect(h.controller.state.readings[1]?.reading.display, '38%');
      expect(h.controller.state.readings[2]?.reading.display, '95℃');
      expect(h.controller.state.readings.containsKey(3), isFalse);
      expect(h.mock.sentCommands, isNot(contains('ATRV')));
      expect(h.saved.map((row) => row.$1), unorderedEquals([1, 2]));
      expect(h.saved.first.$4, h.fixedNow);

      // 实时优先：同 id 的持久化旧值不覆盖实时值。
      final persistedFuel = _probe(
        1,
        '012F',
        DiagnosticsParseType.fuelLevel,
        lastValue: '1.0%',
        lastPercent: 1,
        lastReadingAt: h.fixedNow.subtract(const Duration(days: 1)),
      );
      expect(h.controller.readingFor(persistedFuel)?.reading.display, '38%');

      // 持久化回退：无实时读数的行用最后有效值（油量百分比一并恢复）。
      final fallback = _probe(
        99,
        '012F',
        DiagnosticsParseType.fuelLevel,
        lastValue: '50.0%',
        lastPercent: 50,
        lastReadingAt: h.fixedNow.subtract(const Duration(days: 1)),
      );
      final snapshot = h.controller.readingFor(fallback);
      expect(snapshot?.reading.display, '50.0%');
      expect((snapshot?.reading as ObdValue?)?.percent, 50);
    });

    test('ECU 里程读数经接缝回调（ADR 0026）：kilometers 66068，无数据不回调', () async {
      final h = _Harness(
        rememberedId: 'dev-1',
        responses: {
          ...rigStandardResponses(),
          '01A6': rigResp('41 A6 00 0A 14 C8 \r\r>'),
        },
      );
      h.controller.setProbes([
        _probe(4, '01A6', DiagnosticsParseType.odometer),
      ]);
      await h.connectDirect();
      await h.driveChunks(1);

      expect(h.controller.state.readings[4]?.reading.display, '66,068 km');
      expect(h.odometerReadings, hasLength(1));
      expect(h.odometerReadings.single.kilometers, 66068);
      expect(h.saved.single.$1, 4);
    });

    test('无数据读数不写库、不覆盖旧值（内存照显无数据）', () async {
      final h = _Harness(
        rememberedId: 'dev-1',
        responses: {
          ...rigStandardResponses(),
          '012F': rigResp('NO DATA\r\r>'),
        },
      );
      h.controller.setProbes([
        _probe(1, '012F', DiagnosticsParseType.fuelLevel),
      ]);
      await h.connectDirect();
      await h.driveChunks(1);

      expect(h.controller.state.readings[1]?.reading, isA<ObdNoData>());
      expect(h.saved, isEmpty);
    });
  });
  group('快速连接与作用域（ADR 0027）', () {
    test('快速连接有记忆：直连成功、不开扫描', () async {
      final h = _Harness(rememberedId: 'dev-1');
      unawaited(h.controller.connectRemembered());
      await h.driveChunks(5);
      await h.pump();

      expect(h.deviceIds, ['dev-1']);
      expect(h.controller.state.phase, DiagnosticsConnectionPhase.connected);
      expect(h.openCalls, 0);
    });

    test('快速连接失败（设备未扫到）：不落扫描、落断开错误文案', () async {
      final h = _Harness(
        rememberedId: 'dev-1',
        connectError: const BleObdTransportException(
          BleObdLinkErrorKind.deviceNotFound,
        ),
      );
      final ok = await h.controller.connectRemembered();
      await h.pump();

      expect(ok, isFalse);
      expect(h.controller.state.phase, DiagnosticsConnectionPhase.disconnected);
      expect(h.controller.state.statusError, isNotNull);
      expect(h.openCalls, 0);
    });

    test('快速连接门禁失败（蓝牙关）：不落扫描、状态条文案', () async {
      final h = _Harness(
        rememberedId: 'dev-1',
        connectError: const BleObdTransportException(
          BleObdLinkErrorKind.adapterOff,
        ),
      );
      final ok = await h.controller.connectRemembered();
      await h.pump();

      expect(ok, isFalse);
    });

    test('快速连接无记忆：静默 false，无任何扫描动作', () async {
      final h = _Harness(rememberedId: null);
      final ok = await h.controller.connectRemembered();
      await h.pump();

      expect(ok, isFalse);
      expect(
        h.controller.state.phase,
        DiagnosticsConnectionPhase.idle,
      );
    });

    test('start 的 connected 守卫：已连接再调不重连（诊断页复用连接）', () async {
      final h = _Harness(rememberedId: 'dev-1');
      await h.connectDirect();
      await h.connectDirect();

      expect(h.deviceIds, ['dev-1']);
      expect(h.controller.state.phase, DiagnosticsConnectionPhase.connected);
    });

    test('作用域换防：诊断页全量清单、退回提醒页只轮询核心两条', () async {
      final h = _Harness(rememberedId: 'dev-1');
      final fuel = _probe(1, '012F', DiagnosticsParseType.fuelLevel);
      final coolant = _probe(2, '0167', DiagnosticsParseType.coolantTempAux);
      final volt = _probe(3, 'ATRV', DiagnosticsParseType.voltageText);
      h.controller.setProbes([fuel, coolant, volt]);
      h.controller.setBackgroundProbes([fuel, coolant]);
      h.controller.setDiagnosticsScope(true);
      await h.connectDirect();
      await h.driveChunks(3);

      expect(
        h.mock.sentCommands,
        containsAll(['012F', '0167', 'ATRV']),
      );

      final consumed = h.mock.sentCommands.length;
      h.controller.setDiagnosticsScope(false);
      // 倒计时每秒一拍（timeGate 门闩 = 一拍）：放行满 30 拍跨过刷新
      // 间隔，核心两条到期发指令、电压不到期不发（ADR 0027 换防）。
      for (var i = 0; i < 35; i++) {
        h.timeGate.completeAll();
        await h.pump();
      }
      await h.driveChunks(2);

      final tail = h.mock.sentCommands.skip(consumed).toList();
      expect(tail, containsAll(['012F', '0167']));
      expect(tail, isNot(contains('ATRV')));
    });
  });
  group('会话日志收尾（2026-11-18 深审修复，问题 1）', () {
    test('手动断开写收尾行（事件路径收不到 dispose 触发的断开事件）', () async {
      final ends = <(DateTime, String?)>[];
      final harness = _Harness(
        rememberedId: 'dev-1',
        sessionLogSink: _RecordingSink(ends),
      );
      await harness.connectDirect();
      await harness.controller.disconnectManually();
      await harness.pump();
      expect(ends, hasLength(1));
      expect(ends.single.$2, '手动断开');
    });

    test('链路自发掉线走事件路径写收尾，不与 teardown 路径互斥', () async {
      final ends = <(DateTime, String?)>[];
      final harness = _Harness(
        rememberedId: 'dev-1',
        sessionLogSink: _RecordingSink(ends),
      );
      await harness.connectDirect();
      harness.mock.injectError(StateError('链路丢失'));
      await harness.pump();
      expect(ends, hasLength(1));
      expect(ends.single.$2, contains('链路丢失'));
    });
  });


}
