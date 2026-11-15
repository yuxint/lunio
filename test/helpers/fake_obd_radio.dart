// 假 OBD 无线电面（ADR 0024 决定 6）：adapter 测试的受控替身。
//
// 与真实现（FlutterBluePlusObdRadio）对齐的语义：
//   - adapterState / connectionState 订阅即回放当前值；
//   - scanResults 全量快照、不回放（调用方先订阅再 start）；
//   - 所有调用进共享事件日志（跨对象顺序断言，例如「先订阅后 startScan」
//     与「先订阅后开通知」）；
//   - 门闩（Completer）控制建链/服务发现的挂起点，零真实等待。
//
// 不做通用脚本 DSL：每个用例按需设字段、放门闩、推事件。
import 'dart:async';

import 'package:lunio/features/shell/diagnostics/ble_obd_link.dart'
    show BleObdUuids;
import 'package:lunio/features/shell/diagnostics/obd_radio.dart';

/// 假 radio：扫描面 + 适配器状态 + 设备仓。
class FakeObdRadio implements ObdRadio {
  FakeObdRadio({this.supported = true});

  /// isSupported 返回值。
  bool supported;

  /// isSupported 抛错（null = 正常返回 [supported]）。
  Object? isSupportedError;

  /// 跨对象调用事件日志（按发生顺序追加）。
  final List<String> events = [];

  final _adapterStates = StreamController<RadioAdapterState>.broadcast();
  RadioAdapterState _currentAdapterState = RadioAdapterState.unknown;

  late final StreamController<List<RadioScanResult>> _scanResults =
      StreamController<List<RadioScanResult>>.broadcast(
    onListen: () => events.add('listenScanResults'),
    onCancel: () => events.add('cancelScanResults'),
  );

  final Map<String, FakeRadioDevice> _devices = {};

  int startScanCalls = 0;
  final List<String> directedScanIds = [];
  int stopScanCalls = 0;

  /// startScan 抛出的错误（null = 正常）。
  Object? startScanError;

  /// startDirectedScan 抛出的错误（null = 正常）。
  Object? startDirectedScanError;

  @override
  Future<bool> get isSupported async {
    if (isSupportedError != null) {
      throw isSupportedError!;
    }
    return supported;
  }

  @override
  Stream<RadioAdapterState> get adapterState => _replay(
        () => _currentAdapterState,
        _adapterStates.stream,
      );

  @override
  Stream<List<RadioScanResult>> get scanResults => _scanResults.stream;

  @override
  Future<void> startScan() async {
    events.add('startScan');
    startScanCalls++;
    if (startScanError != null) {
      throw startScanError!;
    }
  }

  @override
  Future<void> startDirectedScan(String deviceId) async {
    events.add('startDirectedScan:$deviceId');
    directedScanIds.add(deviceId);
    if (startDirectedScanError != null) {
      throw startDirectedScanError!;
    }
  }

  @override
  Future<void> stopScan() async {
    events.add('stopScan');
    stopScanCalls++;
  }

  /// 推一个适配器状态（同时更新回放当前值）。
  void emitAdapterState(RadioAdapterState state) {
    _currentAdapterState = state;
    _adapterStates.add(state);
  }

  /// 推一个适配器状态流错误（门禁错误路径）。
  void emitAdapterError(Object error) {
    _adapterStates.addError(error);
  }

  /// 推一批扫描结果（全量快照）。
  void emitScanResults(List<RadioScanResult> results) {
    _scanResults.add(results);
  }

  /// 取/建设备（扫描结果与建链共用同一句柄）。
  FakeRadioDevice device(String id) =>
      _devices.putIfAbsent(id, () => FakeRadioDevice(id: id, events: events));

  /// 便捷构造扫描结果（自动注册设备）。
  RadioScanResult scanResultFor(
    String id, {
    String name = 'IOS-Vlink',
    int rssi = -40,
  }) =>
      RadioScanResult(
        id: id,
        name: name,
        rssi: rssi,
        device: device(id),
      );

  /// 回放当前值 + 后续广播（与 FBP 的状态流语义一致）。
  Stream<T> _replay<T>(T Function() current, Stream<T> updates) {
    final controller = StreamController<T>();
    controller.add(current());
    final sub = updates.listen(
      controller.add,
      onError: controller.addError,
    );
    controller.onCancel = sub.cancel;
    return controller.stream;
  }
}

/// 假设备：建链/服务发现/连接状态/断连。
class FakeRadioDevice implements RadioDevice {
  FakeRadioDevice({required this.id, required this.events});

  final String id;
  final List<String> events;

  final _connectionStates =
      StreamController<RadioConnectionState>.broadcast();
  RadioConnectionState _currentConnectionState =
      RadioConnectionState.disconnected;

  int connectCalls = 0;
  int discoverCalls = 0;
  int disconnectCalls = 0;

  /// 建链门闩（非 null = connect 挂起直到 complete）。
  Completer<void>? connectGate;

  /// 发现服务门闩。
  Completer<void>? discoverGate;

  /// 建链抛出的错误。
  Object? connectError;

  /// 发现服务抛出的错误。
  Object? discoverError;

  /// discoverServices 返回的服务表。
  List<RadioService> services = const [];

  @override
  Stream<RadioConnectionState> get connectionState {
    final controller = StreamController<RadioConnectionState>();
    controller.add(_currentConnectionState);
    final sub = _connectionStates.stream.listen(
      controller.add,
      onError: controller.addError,
    );
    controller.onCancel = sub.cancel;
    return controller.stream;
  }

  @override
  Future<void> connect({required Duration timeout}) async {
    events.add('connect:$id');
    connectCalls++;
    final gate = connectGate;
    if (gate != null) {
      await gate.future;
    }
    if (connectError != null) {
      throw connectError!;
    }
    setConnectionState(RadioConnectionState.connected);
  }

  @override
  Future<void> disconnect({required Duration timeout}) async {
    events.add('disconnect:$id');
    disconnectCalls++;
    setConnectionState(RadioConnectionState.disconnected);
  }

  @override
  Future<List<RadioService>> discoverServices() async {
    events.add('discover:$id');
    discoverCalls++;
    final gate = discoverGate;
    if (gate != null) {
      await gate.future;
    }
    if (discoverError != null) {
      throw discoverError!;
    }
    return services;
  }

  /// 推连接状态（链路丢失/回放模拟）。
  void setConnectionState(RadioConnectionState state) {
    _currentConnectionState = state;
    _connectionStates.add(state);
  }
}

/// 假 characteristic：值流订阅计数、开通知顺序、写入捕获。
class FakeRadioCharacteristic implements RadioCharacteristic {
  FakeRadioCharacteristic({required this.uuid, required this.events});

  @override
  final String uuid;

  final List<String> events;

  late final StreamController<List<int>> _values =
      StreamController<List<int>>.broadcast(
    onListen: () => events.add('subscribe:$uuid'),
    onCancel: () => events.add('unsubscribe:$uuid'),
  );

  bool notifyEnabled = false;
  int setNotifyCalls = 0;
  Object? setNotifyError;

  /// 开通知门闩（非 null = setNotifyValue 挂起直到 complete）。
  Completer<void>? setNotifyGate;

  /// 写入捕获（字节原样）。
  final List<List<int>> writes = [];
  Object? writeError;

  @override
  Stream<List<int>> get onValueReceived => _values.stream;

  @override
  Future<void> setNotifyValue(bool enabled) async {
    events.add('setNotify:$uuid:$enabled');
    setNotifyCalls++;
    final gate = setNotifyGate;
    if (gate != null) {
      await gate.future;
    }
    if (setNotifyError != null) {
      throw setNotifyError!;
    }
    notifyEnabled = enabled;
  }

  @override
  Future<void> write(List<int> bytes) async {
    events.add('write:$uuid');
    writes.add(bytes);
    if (writeError != null) {
      throw writeError!;
    }
  }

  /// 推一条通知值。
  void emitValue(List<int> bytes) {
    _values.add(bytes);
  }
}

/// 标准 OBD GATT 夹具：18F0 服务 + 2AF0 通知 + 2AF1 写入。
class FakeObdGatt {
  FakeObdGatt._(this.notify, this.write);

  factory FakeObdGatt.standard(List<String> events) => FakeObdGatt._(
        FakeRadioCharacteristic(uuid: BleObdUuids.notify, events: events),
        FakeRadioCharacteristic(uuid: BleObdUuids.write, events: events),
      );

  final FakeRadioCharacteristic notify;
  final FakeRadioCharacteristic write;

  /// 可直接赋给 FakeRadioDevice.services。
  List<RadioService> get services => [
        RadioService(
          uuid: BleObdUuids.service,
          characteristics: [notify, write],
        ),
      ];
}
