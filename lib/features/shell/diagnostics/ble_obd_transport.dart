// OBD 传输层 BLE 实现（票 07，ADR 0020）：flutter_blue_plus 2.3.x 胶水
// 层。把 BLE 会话六步（适配器门禁 → 定向扫描定位设备 → 建链 → 发现服
// 务 → 订阅通知 → 挂断连监视）翻译成 OBDTransport 的字节流契约，协议
// 层与会话控制器零改动（传输层抽象的意义所在）。
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

import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

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

/// BLE 链路错误类别（异常的可辨识分类；状态条文案单一出口见
/// [BleObdTransportException.statusCopy]）。
enum BleObdLinkErrorKind {
  /// 设备不支持蓝牙（模拟器/无蓝牙主机）。
  adapterUnavailable,

  /// 蓝牙权限拒绝（iOS 首次弹窗拒绝 / Android 运行时权限拒绝）。
  permissionDenied,

  /// 蓝牙未开启。
  adapterOff,

  /// 定向扫描窗口内未发现目标设备（适配器断电/离开范围）。
  deviceNotFound,

  /// 建链或通道订阅失败（建链超时、服务发现失败等）。
  connectFailed,

  /// GATT 通道形态缺失（18F0/2AF0/2AF1 缺一，适配器固件异常）。
  serviceMissing,

  /// 链路丢失（连接后适配器断电/走远，经断连监视上抛）。
  linkLost;

  /// 门禁类（蓝牙关/不支持/权限）：扫描也扫不出结果，状态条渲染文案
  /// 引导修系统状态、不落扫描 sheet（诊断页连接流程按它分流）。
  bool get isGateError =>
      this == BleObdLinkErrorKind.adapterOff ||
      this == BleObdLinkErrorKind.adapterUnavailable ||
      this == BleObdLinkErrorKind.permissionDenied;
}

/// BLE 链路可辨识异常（错误文案单一出口）。会话控制器把它当普通传输
/// 层异常透传（Disconnected 事件 cause / connect() 重抛的 wrap cause），
/// 页面按 kind 翻译状态条文案与降级分支。
class BleObdTransportException implements Exception {
  const BleObdTransportException(this.kind, [this.cause]);

  final BleObdLinkErrorKind kind;
  final Object? cause;

  /// 状态条错误文案（story 8：权限拒绝/蓝牙未开有明确提示）。文案按
  /// kind 唯一映射，throw 点不重复写字符串。
  String get statusCopy => switch (kind) {
        BleObdLinkErrorKind.adapterUnavailable =>
          '蓝牙不可用：本设备不支持蓝牙，无法连接适配器',
        BleObdLinkErrorKind.permissionDenied =>
          '蓝牙权限未授权：请在系统设置 > Lunio 中允许蓝牙',
        BleObdLinkErrorKind.adapterOff => '蓝牙未开启：请打开蓝牙后重试',
        BleObdLinkErrorKind.deviceNotFound =>
          '未找到适配器：请确认适配器已插车（车辆通电）并靠近手机',
        BleObdLinkErrorKind.connectFailed => '适配器连接失败：请重试',
        BleObdLinkErrorKind.serviceMissing =>
          '适配器通道异常：请重启适配器后重试',
        BleObdLinkErrorKind.linkLost => '连接已断开',
      };

  @override
  String toString() => 'BleObdTransportException: ${kind.name}'
      '${cause == null ? '' : ' ($cause)'}';
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
  final state = await FlutterBluePlus.adapterState
      .firstWhere((state) => state != BluetoothAdapterState.unknown)
      .timeout(_adapterStateWindow);
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

/// 平台异常是否表示 Android 运行时蓝牙权限被拒。Android 端
/// flutter_blue_plus 的 adapterState 查询不申请权限（权限在 startScan/
/// connect 时才请求），拒绝以 PlatformException 返回，消息形如
/// "Permission android.permission.BLUETOOTH_SCAN required to scan
/// devices"（API 30 及以下为 ACCESS_FINE_LOCATION）。这里按消息识别，
/// 统一归 [BleObdLinkErrorKind.permissionDenied]。
bool _hasPermissionDeniedText(Object error) {
  final errorText = switch (error) {
    PlatformException(:final message) => message ?? '',
    FlutterBluePlusException(:final description) => description ?? '',
    _ => error.toString(),
  };
  final text = errorText.toLowerCase();
  return text.contains('permission') &&
      (text.contains('bluetooth') ||
          text.contains('access_fine_location') ||
          text.contains('access_coarse_location'));
}

/// 权限拒绝的平台异常 → 可辨识的 permissionDenied；其他异常返回 null
///（调用方按自己的兜底类别包装）。
BleObdTransportException? _permissionDeniedError(Object error) {
  if (error is BleObdTransportException) {
    return error.kind == BleObdLinkErrorKind.permissionDenied ? error : null;
  }
  if (!_hasPermissionDeniedText(error)) {
    return null;
  }
  return BleObdTransportException(BleObdLinkErrorKind.permissionDenied, error);
}

/// 建链/扫描异常 → 可辨识 BLE 链路错误（权限拒绝优先，其余归 fallback）。
BleObdTransportException _mapLinkFailure(
  Object error, {
  required BleObdLinkErrorKind fallback,
}) {
  if (error is BleObdTransportException) {
    return error;
  }
  return _permissionDeniedError(error) ??
      BleObdTransportException(fallback, error);
}

/// 一台扫描到的 BLE 设备（扫描列表行数据）。
class BleObdScanEntry {
  const BleObdScanEntry({
    required this.id,
    required this.name,
    required this.rssi,
  });

  /// 平台设备标识（iOS = CBPeripheral identifier UUID；Android = MAC），
  /// 设备记忆偏好与定向扫描都用它。
  final String id;

  /// 广播名（可能为空串，UI 显"未命名设备"）。
  final String name;

  /// 信号强度 dBm（越大越近；列表按它降序）。
  final int rssi;
}

/// 设备扫描器接缝（诊断页扫描选择 sheet 的数据源）。抽象出来是为了
/// widget 测试可注入受控假扫描器——真扫描器碰 flutter_blue_plus 静态
/// 门面，单测不可控（transport 接缝同手法）。
abstract class ObdScanner {
  /// 扫描结果流（每次发射 = 当前全量清单按信号强度降序；sheet 订阅
  /// 它刷新列表）。
  Stream<List<BleObdScanEntry>> get results;

  /// 适配器门禁（支持/授权/开关）：页面在打开扫描 sheet 前先调用它，
  /// 门禁失败状态条渲染文案、不落扫描（story 8）。权限拒绝抛
  /// [BleObdTransportException]。
  Future<void> ensureReady();

  /// 开始扫描（已扫中幂等）。适配器门禁失败抛
  /// [BleObdTransportException]。
  Future<void> start();

  /// 停止扫描（幂等，释放订阅与适配器扫描）。起始窗口内调用只置停扫
  /// 旗，start 在检查点自行清理（不会扫出无人消费的结果）。
  Future<void> stop();

}

/// 真扫描器（flutter_blue_plus 门面胶水）。
class BleObdScanner implements ObdScanner {
  final _entries = StreamController<List<BleObdScanEntry>>.broadcast();
  StreamSubscription<List<ScanResult>>? _resultsSub;
  bool _scanning = false;
  bool _starting = false;

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
    try {
      await _ensureAdapterReady();
      if (_stopRequested) {
        return;
      }
      // 先订阅再 startScan（FBP 惯例：onScanResults 只在扫描中发射，
      // 启动后才发；先听后启动不丢首拍）。不过滤设备名——story 5 全
      // 部显示，选中靠用户点选。
      _resultsSub = FlutterBluePlus.onScanResults.listen(
        (results) {
          final entries = [
            for (final result in results)
              BleObdScanEntry(
                id: result.device.remoteId.str,
                name: result.advertisementData.advName,
                rssi: result.rssi,
              ),
          ]..sort((a, b) => b.rssi.compareTo(a.rssi));
          _entries.add(entries);
        },
        onError: _entries.addError,
      );
      if (_stopRequested) {
        await _cancelScanResources();
        return;
      }
      // continuousUpdates：默认节流只报新设备，开着才持续刷新 RSSI
      //（列表排序依据）；removeIfGone 不开——离开范围的设备保留在列
      // 表里，避免"扫到过又消失"闪烁。
      await FlutterBluePlus.startScan(continuousUpdates: true);
      if (_stopRequested) {
        await _cancelScanResources();
        return;
      }
      _scanning = true;
    } catch (e) {
      // 半开清理：startScan 抛错（门禁后意外失败）时订阅与底层扫描都
      // 撤干净，否则订阅泄漏、重试 start 会重复发射。
      await _cancelScanResources();
      final denied = _permissionDeniedError(e);
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
    await _cancelScanResources();
  }

  /// 撤订阅 + 停底层扫描（start 的失败/取消路径与 stop 共用）。
  Future<void> _cancelScanResources() async {
    await _resultsSub?.cancel();
    _resultsSub = null;
    await _stopScanBestEffort();
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
    try {
      await FlutterBluePlus.startScan(withRemoteIds: [_deviceId]);
      // 不传 FBP timeout：窗口归本类持有（单一定时归属），finally 停扫。
      final match = await FlutterBluePlus.onScanResults
          .firstWhere(
            (results) =>
                results.any((r) => r.device.remoteId.str == _deviceId),
          )
          .timeout(directConnectScanWindow);
      return match
          .firstWhere((r) => r.device.remoteId.str == _deviceId)
          .device;
    } on TimeoutException {
      throw BleObdTransportException(
        BleObdLinkErrorKind.deviceNotFound,
      );
    } catch (e) {
      // Android 权限拒绝在 startScan 时才出现（见 _hasPermissionDeniedText）。
      throw _mapLinkFailure(
        e,
        fallback: BleObdLinkErrorKind.connectFailed,
      );
    } finally {
      try {
        await FlutterBluePlus.stopScan();
      } catch (_) {
        // 停扫尽力而为。
      }
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
      throw _mapLinkFailure(
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
  /// 引用、尽力断开设备。disconnect 与 connect 的释放复检共用。
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
    try {
      await device.disconnect(timeout: 5);
    } catch (_) {
      // 断开尽力而为。
    }
  }
}
