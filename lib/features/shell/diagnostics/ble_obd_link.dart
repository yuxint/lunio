// OBD BLE 链路适配器（票 07，ADR 0020）：flutter_blue_plus 2.3.x 胶水层。
// 把 BLE 会话六步（适配器门禁 → 定向扫描定位设备 → 建链 → 发现服务 →
// 订阅通知 → 挂断连监视）翻译成 OBDTransport 的字节流契约，协议层与会
// 话控制器零改动（传输层抽象的意义所在）。
//
// 2026-11-15 按概念拆分后本文件只留 FBP 胶水：适配器门禁、扫描归属代
// 数、扫描器 adapter 与传输层 adapter（两者共享门禁与扫描归属，同住一
// 处）。错误分类在 ble_obd_errors.dart、扫描清单协议在
// ble_scan_entries.dart、契约在 obd_scanner.dart / obd_transport.dart。
//
// ≈ Java 的 JSch/serial 通信工具类：connect ≈ 六步建链（含握手前检
// 查），send ≈ OutputStream.write，byteStream ≈ InputStream 事件流，
// disconnect ≈ close；BLE 的通知分片细节对上层屏蔽（分片组装归解析模
// 块的组帧缓冲）。
//
// flutter_blue_plus 2.x 许可口径：商业用途付费、个人/非营利用途免费，
// connect 需显式传 License.nonprofit——本应用单人自用，落在免费档
// （pubspec 注释同口径）。
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'ble_obd_errors.dart';
import 'ble_scan_entries.dart';
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

/// 适配器门禁：支持/授权/开关三查，通过才放行扫描与建链。蓝牙 API 首
/// 次调用触发系统权限弹窗（iOS），授权态在弹窗期间停在 unknown——给
/// 足弹窗窗口再判，超时按不支持处理（story 8 文案兜底）。
Future<void> _ensureAdapterReady() async {
  if (!await FlutterBluePlus.isSupported) {
    throw const BleObdTransportException(
      BleObdLinkErrorKind.adapterUnavailable,
    );
  }
  // 手订阅 + 超时竞速（不用 firstWhere.timeout）：超时后 firstWhere 的
  // 底层订阅仍挂在广播流上等一个永不消费的状态值，重复门禁会叠加残留。
  final stateCompleter = Completer<BluetoothAdapterState>();
  final stateSub = FlutterBluePlus.adapterState.listen(
    (state) {
      if (state != BluetoothAdapterState.unknown &&
          !stateCompleter.isCompleted) {
        stateCompleter.complete(state);
      }
    },
    onError: (Object error) {
      if (!stateCompleter.isCompleted) {
        stateCompleter.completeError(error);
      }
    },
  );
  BluetoothAdapterState state;
  try {
    state = await stateCompleter.future.timeout(_adapterStateWindow);
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
    await stateSub.cancel();
  }
  switch (state) {
    case BluetoothAdapterState.on:
      return;
    case BluetoothAdapterState.unauthorized:
      throw const BleObdTransportException(
        BleObdLinkErrorKind.permissionDenied,
      );
    case BluetoothAdapterState.unavailable:
      throw const BleObdTransportException(
        BleObdLinkErrorKind.adapterUnavailable,
      );
    case BluetoothAdapterState.off:
    case BluetoothAdapterState.turningOn:
    case BluetoothAdapterState.turningOff:
      throw const BleObdTransportException(BleObdLinkErrorKind.adapterOff);
    case BluetoothAdapterState.unknown:
      throw const BleObdTransportException(
        BleObdLinkErrorKind.adapterUnavailable,
      );
  }
}

/// 授权弹窗等待窗口（unknown 停留超时按不支持处理）。
const _adapterStateWindow = Duration(seconds: 10);

/// 停扫尽力而为（适配器可能已关；吞错不影响调用方语义）。
Future<void> _stopScanBestEffort() async {
  try {
    await FlutterBluePlus.stopScan();
  } catch (_) {
    // 停扫失败不影响取消/收尾语义。
  }
}

/// 全局扫描归属代数：flutter_blue_plus 的扫描是进程级单例资源。每次
/// 开始扫描领新令牌；收尾只在令牌仍是最新时停扫，避免旧流程的
/// finally 停掉后来者（重试/重新扫描）启动的扫描。
int _scanEpoch = 0;

int _beginScan() => ++_scanEpoch;

bool _ownsScan(int token) => token == _scanEpoch;

Future<void> _stopScanIfOwned(int token) async {
  if (!_ownsScan(token)) {
    return;
  }
  await _stopScanBestEffort();
}

/// 真扫描器（flutter_blue_plus 门面胶水）。
class BleObdScanner implements ObdScanner {
  final _entries = StreamController<List<BleObdScanEntry>>.broadcast();
  StreamSubscription<List<ScanResult>>? _resultsSub;
  bool _scanning = false;
  bool _starting = false;

  /// 清单合并器（首见定序 + ≤1Hz 发射节奏，2026-11-15 拍板）。
  late final ScanEntryCoalescer _coalescer = ScanEntryCoalescer(
    emit: _entries.add,
  );

  /// 合并器的节拍器（1Hz 补发尾拍；扫描会话内存在，停扫即撤）。
  Timer? _coalesceTimer;

  /// 起始窗口内的停扫请求（stop 在 start 尚未置 _scanning 时置旗，
  /// start 在每个检查点自行清理并退出）。
  bool _stopRequested = false;

  @override
  Stream<List<BleObdScanEntry>> get results => _entries.stream;

  @override
  Future<void> ensureReady() => _ensureAdapterReady();

  @override
  Future<void> start() async {
    if (_scanning || _starting) {
      return;
    }
    _starting = true;
    _stopRequested = false;
    int? scanToken;
    try {
      await _ensureAdapterReady();
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
      // 先订阅再 startScan（FBP 惯例：onScanResults 拿到的是全量清单，
      // 启动后才发；先听后启动不丢首拍）。清单整备走合并器（过滤空名
      // + 首见定序 + 节流，单一出口）。
      _resultsSub = FlutterBluePlus.onScanResults.listen(
        (results) {
          _coalescer.accept([
            for (final result in results)
              BleObdScanEntry(
                id: result.device.remoteId.str,
                name: result.advertisementData.advName,
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
      // continuousUpdates：默认节流只报新设备，开着才持续刷新 RSSI
      //（列表排序依据）；removeIfGone 不开——离开范围的设备保留在列
      // 表里，避免"扫到过又消失"闪烁。令牌在真正 startScan 前领取：
      // 归属与实际扫描启动同一时刻。
      scanToken = _beginScan();
      await FlutterBluePlus.startScan(continuousUpdates: true);
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
  /// [_scanEpoch]）。
  Future<void> _cancelScanResources([int? scanToken]) async {
    _coalesceTimer?.cancel();
    _coalesceTimer = null;
    await _resultsSub?.cancel();
    _resultsSub = null;
    if (scanToken != null) {
      await _stopScanIfOwned(scanToken);
    }
  }
}

/// BLE 传输层（[OBDTransport] 实现，票 07 真机链路）。一次会话一个实
/// 例（会话是一次性对象）；构造收目标设备标识（设备记忆/扫描选中的平
/// 台设备标识），connect 六步建链。
class BleObdTransport implements OBDTransport {
  BleObdTransport({required this._deviceId});

  final String _deviceId;

  /// 建链后的设备/通道引用（send 与 disconnect 都经它们）。
  BluetoothDevice? _device;
  BluetoothCharacteristic? _writeChar;

  /// 通知字节订阅 + 断连监视订阅（disconnect 时退订）。
  StreamSubscription<List<int>>? _notifySub;
  StreamSubscription<BluetoothConnectionState>? _connSub;

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

  /// 定向扫描窗口（直连第一步按设备标识过滤扫描定位设备；iOS 按标识
  /// 直连要求设备在系统缓存里，先扫到再连最稳）。真机联调可再调。
  static const directConnectScanWindow = Duration(seconds: 8);

  /// 建链窗口（FBP connect 的超时参数，收窄到 15 秒给状态条更快反馈；
  /// FBP 默认 35 秒太久）。
  static const connectWindow = Duration(seconds: 15);

  @override
  Stream<Uint8List> get byteStream => _bytes.stream;

  @override
  Future<void> connect() async {
    await _ensureAdapterReady();
    _throwIfReleased();
    final device = await _locateDevice();
    _throwIfReleased();
    _device = device;
    // 断连监视订阅提前到建链前（建链成功到订阅之间的断连不再漏报）；
    // 流首值回放"已断开"由 _established 旗挡掉，建链前的真实断连（连
    // 接尝试中失败）走建链失败语义不误报链路丢失。
    _connSub = device.connectionState.listen((state) {
      if (state == BluetoothConnectionState.disconnected &&
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
  Future<BluetoothDevice> _locateDevice() async {
    final scanToken = _beginScan();
    StreamSubscription<List<ScanResult>>? resultsSub;
    try {
      await FlutterBluePlus.startScan(withRemoteIds: [_deviceId]);
      // 手订阅 + 超时竞速（不用 firstWhere.timeout）：超时后 firstWhere
      // 的底层订阅仍挂在广播流上等一个永不消费的匹配结果，下次扫描会
      // 重复收到旧尝试的事件。订阅在 finally 统一取消。
      final found = Completer<BluetoothDevice>();
      resultsSub = FlutterBluePlus.onScanResults.listen(
        (results) {
          if (found.isCompleted) {
            return;
          }
          for (final result in results) {
            if (result.device.remoteId.str == _deviceId) {
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
      // 见 ble_obd_errors.dart 的权限映射）。
      throw mapBleObdLinkFailure(
        e,
        fallback: BleObdLinkErrorKind.connectFailed,
      );
    } finally {
      await resultsSub?.cancel();
      // 旧尝试只在仍持有扫描归属时停扫，不打断后来者（重试/重新扫描）。
      await _stopScanIfOwned(scanToken);
    }
  }

  /// 直连第二~四步：建链 → 发现服务 → 订阅通知。GATT 形态缺失抛
  /// serviceMissing，权限拒绝归 permissionDenied，其余失败归
  /// connectFailed。每个 await 后复检释放旗：中途 disconnect 时当场
  /// 退出，由 connect 的清理分支收掉半成品连接。
  Future<void> _establish(BluetoothDevice device) async {
    try {
      await device.connect(
        license: License.nonprofit,
        timeout: connectWindow,
      );
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

  /// 服务按 UUID 定位（str128 全小写 128-bit 形态比较；找不到抛
  /// serviceMissing）。
  BluetoothService _findService(List<BluetoothService> services) {
    for (final service in services) {
      if (service.uuid.str128 == BleObdUuids.service) {
        return service;
      }
    }
    throw const BleObdTransportException(
      BleObdLinkErrorKind.serviceMissing,
    );
  }

  /// characteristic 按 UUID 定位（找不到返回 null，调用方归类
  /// serviceMissing）。
  BluetoothCharacteristic? _findChar(
    BluetoothService service,
    String uuid,
  ) {
    for (final char in service.characteristics) {
      if (char.uuid.str128 == uuid) {
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
    await writeChar.write(bytes, withoutResponse: false);
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
      // 的释放复检清理）。
      await _connSub?.cancel();
      _connSub = null;
      await _notifySub?.cancel();
      _notifySub = null;
      return;
    }
    await _releaseLink(device);
  }

  /// 释放一条（半成品或已建成的）链路：退订两个订阅、清写通道与设备
  /// 引用、断开设备（整个实例生命周期只发一次断开指令）。disconnect
  /// 与 connect 的释放复检共用。
  Future<void> _releaseLink(BluetoothDevice device) async {
    await _connSub?.cancel();
    _connSub = null;
    await _notifySub?.cancel();
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
      await device.disconnect(timeout: 5);
    } catch (_) {
      // 断开尽力而为。
    }
  }
}
