// BLE 平台异常识别（2026-11-15，ADR 0024）：把 flutter_blue_plus /
// Flutter 平台的异常翻译成可辨识的 BLE 链路错误类别。收敛在本文件（与
// ble_obd_radio.dart 是仅有的两个 import flutter_blue_plus 的文件）：
//   - 权限拒绝按消息识别（Android 运行时在 startScan/connect 才请求权限，
//     拒绝以 PlatformException 返回）；
//   - 其余异常按调用点 fallback 包装（fallback 选择留在调用方——门禁=
//     adapterUnavailable、扫描/建链=connectFailed，文案路径不变）。
//
// ≈ Java 的异常翻译器：底层抛框架异常，本层按错误码表翻成业务可辨识
// 类别；错误文案在 ble_obd_errors.dart 的 statusCopy 单一出口。
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'ble_obd_errors.dart';

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
/// （调用方按自己的兜底类别包装）。
BleObdTransportException? bleObdPermissionDeniedError(Object error) {
  if (error is BleObdTransportException) {
    return error.kind == BleObdLinkErrorKind.permissionDenied ? error : null;
  }
  if (!_hasPermissionDeniedText(error)) {
    return null;
  }
  return BleObdTransportException(BleObdLinkErrorKind.permissionDenied, error);
}

/// 建链/扫描异常 → 可辨识 BLE 链路错误（权限拒绝优先，其余归 fallback）。
BleObdTransportException mapBleObdLinkFailure(
  Object error, {
  required BleObdLinkErrorKind fallback,
}) {
  if (error is BleObdTransportException) {
    return error;
  }
  return bleObdPermissionDeniedError(error) ??
      BleObdTransportException(fallback, error);
}
