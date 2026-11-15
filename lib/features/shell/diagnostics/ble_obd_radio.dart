// OBD 无线电面的 flutter_blue_plus 实现（ADR 0024）：端口与插件之间的
// 唯一 adapter。本文件与 ble_obd_platform_errors.dart 是仅有的两个
// import flutter_blue_plus 的文件——状态机与端口对插件零依赖。
//
// 职责边界（ADR 0024 决定 2）：只做调用翻译与类型映射，不做业务决策。
// License.nonprofit、continuousUpdates、withRemoteIds、withoutResponse
// 等插件细节在此固定；门禁窗口、扫描归属、建链释放、UUID 匹配、先订阅
// 后开通知的顺序全部在 ble_obd_link.dart。
//
// 错误口径（ADR 0024 决定 3 + Q12 共识）：操作类错误能把权限拒绝翻译成
// 可辨识异常就翻译，其余原样上抛；流错误原样透传，由上方的
// mapBleObdLinkFailure 兜底网统一分类——文案路径与重构前一致。
//
// ≈ Java 的驱动实现：把厂商 SDK 的 API 与类型翻译成 SPI 端口；换插件
// 只改本文件，端口与状态机不动。
import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'ble_obd_errors.dart';
import 'ble_obd_platform_errors.dart';
import 'obd_radio.dart';

/// 执行一次插件操作：可辨识的权限拒绝翻译成 [BleObdTransportException]，
/// 其余异常原样上抛（保留原始堆栈）。
Future<T> _translate<T>(Future<T> Function() action) async {
  try {
    return await action();
  } catch (e) {
    final denied = bleObdPermissionDeniedError(e);
    if (denied != null) {
      throw denied;
    }
    rethrow;
  }
}

/// 蓝牙适配器状态映射（本域枚举与插件枚举一一对应）。
RadioAdapterState _mapAdapterState(BluetoothAdapterState state) {
  return switch (state) {
    BluetoothAdapterState.on => RadioAdapterState.on,
    BluetoothAdapterState.off => RadioAdapterState.off,
    BluetoothAdapterState.unauthorized => RadioAdapterState.unauthorized,
    BluetoothAdapterState.unavailable => RadioAdapterState.unavailable,
    BluetoothAdapterState.unknown => RadioAdapterState.unknown,
    BluetoothAdapterState.turningOn => RadioAdapterState.turningOn,
    BluetoothAdapterState.turningOff => RadioAdapterState.turningOff,
  };
}

/// 设备连接状态映射：本域只分两态，中间态归 disconnected（建链前的回放
/// 由上方 _established 旗判定，不会误报链路丢失）。
RadioConnectionState _mapConnectionState(BluetoothConnectionState state) {
  return state == BluetoothConnectionState.connected
      ? RadioConnectionState.connected
      : RadioConnectionState.disconnected;
}

/// flutter_blue_plus 实现的 OBD 无线电面。无自有状态（扫描归属与订阅
/// 生命周期归上方 adapter），可安全共享单例（obdRadioProvider）。
class FlutterBluePlusObdRadio implements ObdRadio {
  @override
  Future<bool> get isSupported => _translate(() => FlutterBluePlus.isSupported);

  @override
  Stream<RadioAdapterState> get adapterState =>
      FlutterBluePlus.adapterState.map(_mapAdapterState);

  @override
  Stream<List<RadioScanResult>> get scanResults =>
      FlutterBluePlus.onScanResults.map(
        (results) => [
          for (final result in results)
            RadioScanResult(
              id: result.device.remoteId.str,
              name: result.advertisementData.advName,
              rssi: result.rssi,
              device: _FlutterBluePlusRadioDevice(result.device),
            ),
        ],
      );

  @override
  Future<void> startScan() =>
      _translate(() => FlutterBluePlus.startScan(continuousUpdates: true));

  @override
  Future<void> startDirectedScan(String deviceId) =>
      _translate(() => FlutterBluePlus.startScan(withRemoteIds: [deviceId]));

  @override
  Future<void> stopScan() => _translate(FlutterBluePlus.stopScan);
}

/// [RadioDevice] 的插件实现（一次扫描结果一个包装；句柄即底层
/// BluetoothDevice，不按 id 二次查找）。
class _FlutterBluePlusRadioDevice implements RadioDevice {
  _FlutterBluePlusRadioDevice(this._device);

  final BluetoothDevice _device;

  @override
  Future<void> connect({required Duration timeout}) => _translate(
        () => _device.connect(
          license: License.nonprofit,
          timeout: timeout,
        ),
      );

  @override
  Future<void> disconnect({required Duration timeout}) =>
      // FBP 的 disconnect 超时是秒（connect 才是 Duration）；取整秒传递。
      _device.disconnect(timeout: timeout.inSeconds);

  @override
  Stream<RadioConnectionState> get connectionState =>
      _device.connectionState.map(_mapConnectionState);

  @override
  Future<List<RadioService>> discoverServices() async {
    final services = await _translate(_device.discoverServices);
    return [
      for (final service in services)
        RadioService(
          uuid: service.uuid.str128,
          characteristics: [
            for (final characteristic in service.characteristics)
              _FlutterBluePlusRadioCharacteristic(characteristic),
          ],
        ),
    ];
  }
}

/// [RadioCharacteristic] 的插件实现：值流直接转发（订阅即监听插件通知
/// 流），带响应写在此固定（ADR 0020 决定的实测形态）。
class _FlutterBluePlusRadioCharacteristic implements RadioCharacteristic {
  _FlutterBluePlusRadioCharacteristic(this._characteristic);

  final BluetoothCharacteristic _characteristic;

  @override
  String get uuid => _characteristic.uuid.str128;

  @override
  Stream<List<int>> get onValueReceived => _characteristic.onValueReceived;

  @override
  Future<void> setNotifyValue(bool enabled) =>
      _translate(() => _characteristic.setNotifyValue(enabled));

  @override
  Future<void> write(List<int> bytes) => _translate(
        () => _characteristic.write(bytes, withoutResponse: false),
      );
}
