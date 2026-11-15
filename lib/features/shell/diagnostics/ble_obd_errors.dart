// BLE 链路错误分类（2026-11-15 从 ble_obd_transport.dart 拆出）：可辨识
// 异常 + 状态条文案单一出口 + 平台异常映射。扫描器 adapter、传输层
// adapter、诊断连接编排与扫描 sheet 共用本模块；错误文案按 kind 唯一映
// 射（throw 点不重复写字符串）。
//
// ≈ Java 的自定义异常族 + 错误码表：kind ≈ ErrorCode，statusCopy ≈
// 错误码对应的用户文案；平台异常（PlatformException /
// FlutterBluePlusException）在此翻译成可辨识类别。
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

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
  /// 引导修系统状态、不落扫描 sheet（诊断连接编排按它分流）。
  bool get isGateError =>
      this == BleObdLinkErrorKind.adapterOff ||
      this == BleObdLinkErrorKind.adapterUnavailable ||
      this == BleObdLinkErrorKind.permissionDenied;
}

/// BLE 链路可辨识异常（错误文案单一出口）。会话控制器把它当普通传输
/// 层异常透传（Disconnected 事件 cause / connect() 重抛的 wrap cause），
/// 连接编排按 kind 翻译状态条文案与降级分支。
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
