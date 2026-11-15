// OBD BLE 链路 adapter（票 07，ADR 0020 / 0024）：把 OBD 无线电面
// （obd_radio.dart）翻译成两个上层契约——
//   - BleObdScanner → ObdScanner（扫描清单数据源）；
//   - BleObdTransport → OBDTransport（字节流收发）。
//
// 2026-11-15 接缝重构（ADR 0024）：本文件不再 import flutter_blue_plus；
// 插件面由 FlutterBluePlusObdRadio 承担（ble_obd_radio.dart）。所有业务
// 决策留在这一侧，adapter 只做调用转发：
//   - 适配器门禁（支持/授权/开关三查 + unknown 等待窗口）；
//   - 扫描归属代数（进程级扫描资源的令牌收尾）；
//   - 起始窗口停扫、半开清理、单次设备断开；
//   - 定向扫描/建链窗口、UUID 匹配、先订阅后开通知；
//   - 链路丢失监视与 _established 旗；
//   - 错误兜底（能分类的类型化，未分类原样透传）。
//
// ≈ Java 的有状态适配器层：本类 ≈ 协议适配器（含状态机与竞态收尾），
// obd_radio.dart ≈ SPI 端口，ble_obd_radio.dart ≈ 厂商驱动。
import 'dart:async';
import 'dart:typed_data';

import 'ble_obd_errors.dart';
import 'ble_obd_platform_errors.dart';
import 'ble_scan_entries.dart';
import 'obd_radio.dart';
import 'obd_scanner.dart';
import 'obd_transport.dart';

/// GATT 通道 UUID（docs/car_obd_link/ 实测事实：厂商借用 SIG 16-bit 编
/// 号做串口透传，按 UUID 判断不按名称判断）：服务 18F0；通知 2AF0；写
/// 入 2AF1（带响应写，ADR 0020 决定 2）。
class BleObdUuids {
  BleObdUuids._();

  /// 服务 UUID（完整 128-bit 小写形态，与 `Guid.str128` 输出可比）。
  static const service = '000018f0-0000-1000-8000-00805f9b34fb';

  /// 通知 characteristic UUID（订阅它收响应字节）。
  static const notify = '00002af0-0000-1000-8000-00805f9b34fb';

  /// 写入 characteristic UUID（带响应写指令字节）。
  static const write = '00002af1-0000-1000-8000-00805f9b34fb';
}

/// 授权弹窗等待窗口（unknown 停留超时按不支持处理；构造可注入）。
const _defaultAdapterStateWindow = Duration(seconds: 10);

/// 适配器门禁：支持/授权/开关三查，通过才放行扫描与建链。蓝牙 API 首
/// 次调用触发系统权限弹窗（iOS），授权态在弹窗期间停在 unknown——给
/// 足弹窗窗口再判，超时按不支持处理（story 8 文案兜底）。
Future<void> _ensureAdapterReady(ObdRadio radio, Duration window) async {
  if (!await radio.isSupported) {
    throw const BleObdTransportException(
      BleObdLinkErrorKind.adapterUnavailable,
    );
  }
  // 手订阅 + 超时竞速（不用 firstWhere.timeout）：超时后 firstWhere 的
  // 底层订阅仍挂在广播流上等一个永不消费的状态值，重复门禁会叠加残留。
  final stateCompleter = Completer<RadioAdapterState>();
  final stateSub = radio.adapterState.listen(
    (state) {
      if (state != RadioAdapterState.unknown && !stateCompleter.isCompleted) {
        stateCompleter.complete(state);
      }
    },
    onError: (Object error) {
      if (!stateCompleter.isCompleted) {
        stateCompleter.completeError(error);
      }
    },
  );
  RadioAdapterState state;
  try {
    state = await stateCompleter.future.timeout(window);
  } on TimeoutException {
    throw const BleObdTransportException(
      BleObdLinkErrorKind.adapterUnavailable,
    );
  } catch (e) {
    throw mapBleObdLinkFailure(
      e,
      fallback: BleObdLinkErrorKind.adapterUnavailable,
    );
  } finally {
    // 订阅取消的完成时机与假异步环境（fakeAsync）耦合，不等待；取消本身
    // 同步生效，之后不再投递（会话 teardown 同手法）。
    unawaited(stateSub.cancel());
  }
  switch (state) {
    case RadioAdapterState.on:
      return;
    case RadioAdapterState.unauthorized:
      throw const BleObdTransportException(
        BleObdLinkErrorKind.permissionDenied,
      );
    case RadioAdapterState.unavailable:
      throw const BleObdTransportException(
        BleObdLinkErrorKind.adapterUnavailable,
      );
    case RadioAdapterState.off:
    case RadioAdapterState.turningOn:
    case RadioAdapterState.turningOff:
      throw const BleObdTransportException(BleObdLinkErrorKind.adapterOff);
    case RadioAdapterState.unknown:
      throw const BleObdTransportException(
        BleObdLinkErrorKind.adapterUnavailable,
      );
  }
}

/// 停扫尽力而为（适配器可能已关；吞错不影响调用方语义）。
Future<void> _stopScanBestEffort(ObdRadio radio) async {
  try {
    await radio.stopScan();
  } catch (_) {
    // 停扫失败不影响取消/收尾语义。
  }
}

/// 全局扫描归属代数：底层扫描是进程级单例资源。每次开始扫描领新令牌；
/// 收尾只在令牌仍是最新时停扫，避免旧流程的 finally 停掉后来者（重试/
/// 重新扫描）启动的扫描。
int _scanEpoch = 0;

int _beginScan() => ++_scanEpoch;

bool _ownsScan(int token) => token == _scanEpoch;

Future<void> _stopScanIfOwned(ObdRadio radio, int token) async {
  if (!_ownsScan(token)) {
    return;
  }
  await _stopScanBestEffort(radio);
}

/// BLE 扫描器 adapter（flutter_blue_plus 无线电面 → [ObdScanner]）。
class BleObdScanner implements ObdScanner {
  BleObdScanner({
    required this.radio,
    this.adapterStateWindow = _defaultAdapterStateWindow,
    this.coalesceInterval = ScanEntryCoalescer.defaultInterval,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// 无线电面（生产 = FlutterBluePlusObdRadio；测试 = 假 radio）。
  final ObdRadio radio;

  /// 门禁 unknown 等待窗口（默认 10 秒；测试可注入）。
  final Duration adapterStateWindow;

  /// 扫描清单合并窗口（默认 1 秒；测试可注入）。
  final Duration coalesceInterval;

  /// 合并器时钟（注入以便零真实时间测试）。
  final DateTime Function() _now;

  final _entries = StreamController<List<BleObdScanEntry>>.broadcast();
  StreamSubscription<List<RadioScanResult>>? _resultsSub;
  bool _scanning = false;
  bool _starting = false;

  /// 清单合并器（首见定序 + ≤1Hz 发射节奏，2026-11-15 拍板）。
  late final ScanEntryCoalescer _coalescer = ScanEntryCoalescer(
    emit: _entries.add,
    interval: coalesceInterval,
    now: _now,
  );

  /// 合并器的节拍器（1Hz 补发尾拍；扫描会话内存在，停扫即撤）。
  Timer? _coalesceTimer;

  /// 起始窗口内的停扫请求（stop 在 start 尚未置 _scanning 时置旗，
  /// start 在每个检查点自行清理并退出）。
  bool _stopRequested = false;

  @override
  Stream<List<BleObdScanEntry>> get results => _entries.stream;

  @override
  Future<void> ensureReady() => _ensureAdapterReady(radio, adapterStateWindow);

  @override
  Future<void> start() async {
    if (_scanning || _starting) {
      return;
    }
    _starting = true;
    _stopRequested = false;
    int? scanToken;
    try {
      await _ensureAdapterReady(radio, adapterStateWindow);
      if (_stopRequested) {
        return;
      }
      // 新扫描会话：定序与节流窗口复位（恢复扫描至多重排一次，
      // 2026-11-15 拍板），节拍器随会话起停。
      _coalescer.reset();
      _coalesceTimer?.cancel();
      _coalesceTimer = Timer.periodic(
        _coalescer.interval,
        (_) => _coalescer.flushIfDue(),
      );
      // 先订阅再 startScan（无线电面惯例：结果流是全量快照、不回放，
      // 启动后才发；先听后启动不丢首拍）。清单整备走合并器（过滤空名
      // + 首见定序 + 节流，单一出口）。
      _resultsSub = radio.scanResults.listen(
        (results) {
          _coalescer.accept([
            for (final result in results)
              BleObdScanEntry(
                id: result.id,
                name: result.name,
                rssi: result.rssi,
              ),
          ]);
        },
        onError: _entries.addError,
      );
      if (_stopRequested) {
        await _cancelScanResources();
        return;
      }
      // 令牌在真正 startScan 前领取：归属与实际扫描启动同一时刻。
      scanToken = _beginScan();
      await radio.startScan();
      if (_stopRequested) {
        await _cancelScanResources(scanToken);
        return;
      }
      _scanning = true;
    } catch (e) {
      // 半开清理：startScan 抛错（门禁后意外失败）时订阅与底层扫描都
      // 撤干净，否则订阅泄漏、重试 start 会重复发射。
      await _cancelScanResources(scanToken);
      final denied = bleObdPermissionDeniedError(e);
      if (denied != null) {
        throw denied;
      }
      rethrow;
    } finally {
      _starting = false;
    }
  }

  @override
  Future<void> stop() async {
    _stopRequested = true;
    if (!_scanning) {
      return;
    }
    _scanning = false;
    // 停扫领新令牌：任何更早的扫描持有者（已取消的直连定位等）之后
    // 的收尾都不得再停掉本次停扫之后的扫描。
    await _cancelScanResources(_beginScan());
  }

  /// 撤订阅 + 撤节拍器 + 停底层扫描（start 的失败/取消路径与 stop 共
  /// 用）；只在令牌仍是最新扫描持有者时停扫（全局扫描资源归属见
  /// [_scanEpoch]）。订阅取消不等待完成（假异步环境耦合，取消同步生效）。
  Future<void> _cancelScanResources([int? scanToken]) async {
    _coalesceTimer?.cancel();
    _coalesceTimer = null;
    unawaited(_resultsSub?.cancel());
    _resultsSub = null;
    if (scanToken != null) {
      await _stopScanIfOwned(radio, scanToken);
    }
  }
}

/// BLE 传输层 adapter（[OBDTransport] 实现，票 07 真机链路）。一次会话
/// 一个实例（会话是一次性对象）；构造收目标设备标识（设备记忆/扫描选
/// 中的平台设备标识），connect 六步建链。
class BleObdTransport implements OBDTransport {
  BleObdTransport({
    required this.radio,
    required this._deviceId,
    this.adapterStateWindow = _defaultAdapterStateWindow,
    this.directConnectScanWindow = defaultDirectConnectScanWindow,
    this.connectWindow = defaultConnectWindow,
  });

  /// 无线电面（生产 = FlutterBluePlusObdRadio；测试 = 假 radio）。
  final ObdRadio radio;

  final String _deviceId;

  /// 门禁 unknown 等待窗口（默认 10 秒；测试可注入）。
  final Duration adapterStateWindow;

  /// 定向扫描窗口（直连第一步按设备标识过滤扫描定位设备；iOS 按标识
  /// 直连要求设备在系统缓存里，先扫到再连最稳）。真机联调可再调。
  final Duration directConnectScanWindow;

  /// 建链窗口（传给插件的 connect 超时；收窄到 15 秒给状态条更快反馈，
  /// FBP 默认 35 秒太久）。
  final Duration connectWindow;

  /// 默认定向扫描窗口。
  static const defaultDirectConnectScanWindow = Duration(seconds: 8);

  /// 默认建链窗口。
  static const defaultConnectWindow = Duration(seconds: 15);

  /// 断开指令的超时（尽力而为，不阻塞收尾）。
  static const _disconnectTimeout = Duration(seconds: 5);

  /// 建链后的设备/通道引用（send 与 disconnect 都经它们）。
  RadioDevice? _device;
  RadioCharacteristic? _writeChar;

  /// 通知字节订阅 + 断连监视订阅（disconnect 时退订）。
  StreamSubscription<List<int>>? _notifySub;
  StreamSubscription<RadioConnectionState>? _connSub;

  /// 已主动释放旗（防自己的 disconnect 触发断连监视误报链路丢失）。
  bool _released = false;

  /// 设备断开指令只发一次的旗：disconnect 与 connect 的释放复检都会
  /// 经 [_releaseLink]，第二次若再断开，可能把用户随后重连到同一适配
  /// 器的新链路断掉。
  bool _disconnectIssued = false;

  /// 建链完成旗（connectionState 流首值回放"已断开"，建链前的断连事
  /// 件一律忽略——订阅提前到建链前收掉窗口缝，旗防回放误报）。
  bool _established = false;

  /// 响应字节流（BLE 通知分片逐块到达；链路丢失经 error 上抛）。
  final _bytes = StreamController<Uint8List>.broadcast();

  @override
  Stream<Uint8List> get byteStream => _bytes.stream;

  @override
  Future<void> connect() async {
    await _ensureAdapterReady(radio, adapterStateWindow);
    _throwIfReleased();
    final device = await _locateDevice();
    _throwIfReleased();
    _device = device;
    // 断连监视订阅提前到建链前（建链成功到订阅之间的断连不再漏报）；
    // 流首值回放"已断开"由 _established 旗挡掉，建链前的真实断连（连
    // 接尝试中失败）走建链失败语义不误报链路丢失。
    _connSub = device.connectionState.listen((state) {
      if (state == RadioConnectionState.disconnected &&
          _established &&
          !_released) {
        _bytes.addError(
          const BleObdTransportException(BleObdLinkErrorKind.linkLost),
        );
      }
    });
    try {
      await _establish(device);
    } catch (_) {
      // 建链途中被 disconnect 释放：迟到的订阅/连接要当场收掉（否则
      // 新连接与订阅无人持有、永久泄漏）。
      if (_released) {
        await _releaseLink(device);
      }
      rethrow;
    }
    if (_released) {
      // 建链成功但释放旗已置：会话已先行断开，不再交付连接。
      await _releaseLink(device);
      throw const BleObdTransportException(
        BleObdLinkErrorKind.connectFailed,
        '连接已取消',
      );
    }
    _established = true;
  }

  /// 释放后安全退出（每个 await 后复检；页面退出/取消连接的竞态窗）。
  void _throwIfReleased() {
    if (_released) {
      throw const BleObdTransportException(
        BleObdLinkErrorKind.connectFailed,
        '连接已取消',
      );
    }
  }

  /// 直连第一步：定向扫描定位目标设备。
  Future<RadioDevice> _locateDevice() async {
    final scanToken = _beginScan();
    StreamSubscription<List<RadioScanResult>>? resultsSub;
    try {
      await radio.startDirectedScan(_deviceId);
      // 手订阅 + 超时竞速（不用 firstWhere.timeout）：超时后 firstWhere
      // 的底层订阅仍挂在广播流上等一个永不消费的匹配结果，下次扫描会
      // 重复收到旧尝试的事件。订阅在 finally 统一取消。
      final found = Completer<RadioDevice>();
      resultsSub = radio.scanResults.listen(
        (results) {
          if (found.isCompleted) {
            return;
          }
          for (final result in results) {
            if (result.id == _deviceId) {
              found.complete(result.device);
              return;
            }
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          if (!found.isCompleted) {
            found.completeError(error, stackTrace);
          }
        },
        cancelOnError: true,
      );
      try {
        return await found.future.timeout(directConnectScanWindow);
      } on TimeoutException {
        throw BleObdTransportException(
          BleObdLinkErrorKind.deviceNotFound,
        );
      }
    } catch (e) {
      // Android 权限拒绝在 startScan 时才出现（平台异常按消息识别，
      // 见 ble_obd_platform_errors.dart 的权限映射）。
      throw mapBleObdLinkFailure(
        e,
        fallback: BleObdLinkErrorKind.connectFailed,
      );
    } finally {
      // 取消不等待完成（假异步环境耦合，取消同步生效）。
      unawaited(resultsSub?.cancel());
      // 旧尝试只在仍持有扫描归属时停扫，不打断后来者（重试/重新扫描）。
      await _stopScanIfOwned(radio, scanToken);
    }
  }

  /// 直连第二~四步：建链 → 发现服务 → 订阅通知。GATT 形态缺失抛
  /// serviceMissing，权限拒绝归 permissionDenied，其余失败归
  /// connectFailed。每个 await 后复检释放旗：中途 disconnect 时当场
  /// 退出，由 connect 的清理分支收掉半成品连接。
  Future<void> _establish(RadioDevice device) async {
    try {
      await device.connect(timeout: connectWindow);
      _throwIfReleased();
      final services = await device.discoverServices();
      _throwIfReleased();
      final service = _findService(services);
      final notifyChar = _findChar(service, BleObdUuids.notify);
      final writeChar = _findChar(service, BleObdUuids.write);
      if (notifyChar == null || writeChar == null) {
        throw const BleObdTransportException(
          BleObdLinkErrorKind.serviceMissing,
        );
      }
      // 先订阅字节流再开通知，通知早到不丢字节（与会话"先听后连"同
      // 一手法）。释放后迟到的通知直接丢弃（不再向已关闭的会话投递）。
      _notifySub = notifyChar.onValueReceived.listen(
        (bytes) {
          if (_released) {
            return;
          }
          _bytes.add(Uint8List.fromList(bytes));
        },
        onError: (Object error) {
          if (_released) {
            return;
          }
          _bytes.addError(error);
        },
      );
      await notifyChar.setNotifyValue(true);
      _throwIfReleased();
      _writeChar = writeChar;
    } on BleObdTransportException {
      rethrow;
    } catch (e) {
      throw mapBleObdLinkFailure(
        e,
        fallback: BleObdLinkErrorKind.connectFailed,
      );
    }
  }

  /// 服务按 UUID 定位（全小写 128-bit 形态比较；找不到抛
  /// serviceMissing）。
  RadioService _findService(List<RadioService> services) {
    for (final service in services) {
      if (service.uuid == BleObdUuids.service) {
        return service;
      }
    }
    throw const BleObdTransportException(
      BleObdLinkErrorKind.serviceMissing,
    );
  }

  /// characteristic 按 UUID 定位（找不到返回 null，调用方归类
  /// serviceMissing）。
  RadioCharacteristic? _findChar(RadioService service, String uuid) {
    for (final char in service.characteristics) {
      if (char.uuid == uuid) {
        return char;
      }
    }
    return null;
  }

  @override
  Future<void> send(List<int> bytes) async {
    final writeChar = _writeChar;
    if (writeChar == null) {
      throw StateError('BleObdTransport 未连接，不能发送');
    }
    // 带响应写（ADR 0020 决定 2，实测成功形态）。链路死亡时写超时抛
    // 错 → 会话侧"发送失败" → 链路丢失语义。
    await writeChar.write(bytes);
  }

  /// 断开并释放（幂等）：置释放旗 → 退订断连监视（防自己的断开误报
  /// 链路丢失）→ 退订通知 → 断开设备（尽力而为：设备可能已消失）。
  /// 在途 connect 的迟到建链由 connect 的释放复检分支收尾
  ///（[_releaseLink]），不会留下无人持有的连接与订阅。
  @override
  Future<void> disconnect() async {
    if (_released) {
      return;
    }
    _released = true;
    final device = _device;
    if (device == null) {
      // 尚未定位到设备：只收已有订阅（建链途中的迟到资源由 connect
      // 的释放复检清理）。取消不等待完成（假异步环境耦合，取消同步生效）。
      unawaited(_connSub?.cancel());
      _connSub = null;
      unawaited(_notifySub?.cancel());
      _notifySub = null;
      return;
    }
    await _releaseLink(device);
  }

  /// 释放一条（半成品或已建成的）链路：退订两个订阅、清写通道与设备
  /// 引用、断开设备（整个实例生命周期只发一次断开指令）。disconnect
  /// 与 connect 的释放复检共用。取消不等待完成（假异步环境耦合，取消
  /// 同步生效）。
  Future<void> _releaseLink(RadioDevice device) async {
    unawaited(_connSub?.cancel());
    _connSub = null;
    unawaited(_notifySub?.cancel());
    _notifySub = null;
    _writeChar = null;
    _established = false;
    if (identical(_device, device)) {
      _device = null;
    }
    if (_disconnectIssued) {
      return;
    }
    _disconnectIssued = true;
    try {
      await device.disconnect(timeout: _disconnectTimeout);
    } catch (_) {
      // 断开尽力而为。
    }
  }
}
