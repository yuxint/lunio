// OBD 无线电面（GLOSSARY 词条，ADR 0024）：诊断域对手机蓝牙能力的最小
// 抽象面。适配器状态、扫描、设备建链/服务发现、通知订阅与写入是它与
// flutter_blue_plus 之间的全部契约；门禁分流、扫描归属、建链释放等业务
// 决策都在本层之上（ble_obd_link.dart），不在 adapter 里。
//
// 版本约定（2026-11-15，ADR 0024）：
//   - 跨本层只用自有类型——测试不 import flutter_blue_plus；
//   - 状态流（adapterState / connectionState）订阅即回放当前值，与 FBP
//     语义一致（建链前回放 disconnected 由上方 _established 旗判定）；
//   - 扫描结果流是全量快照、不回放：调用方先订阅再启动扫描；
//   - 插件细节（License.nonprofit、continuousUpdates、withRemoteIds、
//     withoutResponse）在 FBP adapter 内固定，不进本层。
//
// ≈ Java 的 SPI 端口：BleObdScanner / BleObdTransport 依赖本接口，不依
// 赖插件门面；生产 adapter 是 FlutterBluePlusObdRadio，测试 adapter 是
// test/helpers/fake_obd_radio.dart。这不是产品扩展点——未来换传输通道
// 走 OBDTransport 新实现（ADR 0020），不在这里加实现。
import 'dart:async';

/// 蓝牙适配器状态（与系统/插件状态一一对应；门禁按它分流）。
enum RadioAdapterState {
  on,
  off,
  unauthorized,
  unavailable,
  unknown,
  turningOn,
  turningOff,
}

/// 设备连接状态（本域只消费 connected / disconnected；connecting 等中间
/// 态由 adapter 归并为 disconnected，建链前的断连回放由上方旗挡掉）。
enum RadioConnectionState { connected, disconnected }

/// 一条扫描结果：扫描清单只消费 [id]/[name]/[rssi]；定向建链用 [device]
/// 句柄（不按 id 重新查找，避免插件侧缓存语义差异）。
class RadioScanResult {
  const RadioScanResult({
    required this.id,
    required this.name,
    required this.rssi,
    required this.device,
  });

  /// 平台设备标识（iOS = CBPeripheral identifier UUID；Android = MAC）。
  final String id;

  /// 广播名（可能为空；空名过滤在扫描清单合并函数，单一出口）。
  final String name;

  /// 信号强度 dBm（越大越近）。
  final int rssi;

  /// 设备句柄（建链/服务发现入口）。
  final RadioDevice device;
}

/// 一个 GATT 服务（uuid 为全小写 128-bit 形态，与 UUID 匹配口径一致）。
class RadioService {
  const RadioService({required this.uuid, required this.characteristics});

  final String uuid;
  final List<RadioCharacteristic> characteristics;
}

/// 一个 GATT characteristic（诊断域只用「值流 / 开通知 / 写入」三面）。
abstract class RadioCharacteristic {
  /// 全小写 128-bit 形态。
  String get uuid;

  /// 通知值流（字节块原样到达；组帧归解析器）。
  Stream<List<int>> get onValueReceived;

  /// 开关通知（订阅 [onValueReceived] 之后调用，早到字节不丢）。
  Future<void> setNotifyValue(bool enabled);

  /// 写入指令字节（带响应写由 adapter 固定）。
  Future<void> write(List<int> bytes);
}

/// 一台 BLE 设备（建链、连接状态、服务发现）。
abstract class RadioDevice {
  /// 建链（超时窗口由调用方传入，adapter 不再二次收窄）。
  Future<void> connect({required Duration timeout});

  /// 断开并释放（幂等由调用方保证；adapter 尽力而为）。
  Future<void> disconnect({required Duration timeout});

  /// 连接状态流（订阅即回放当前值）。
  Stream<RadioConnectionState> get connectionState;

  /// 发现服务与 characteristic（一次性返回全量）。
  Future<List<RadioService>> discoverServices();
}

/// OBD 无线电面（职责与版本约定见文件头）。
abstract class ObdRadio {
  /// 本机是否支持蓝牙（门禁第一查）。
  Future<bool> get isSupported;

  /// 适配器状态流（订阅即回放当前值）。
  Stream<RadioAdapterState> get adapterState;

  /// 扫描结果流（全量快照；每次发射 = 当前附近设备，不回放）。
  Stream<List<RadioScanResult>> get scanResults;

  /// 启动持续扫描（RSSI 持续刷新；插件 flag 由 adapter 固定）。
  Future<void> startScan();

  /// 按设备标识定向扫描（直连定位用；找到后调用方自行 stopScan）。
  Future<void> startDirectedScan(String deviceId);

  /// 停止扫描（幂等；尽力而为的吞错由调用方决定）。
  Future<void> stopScan();
}
