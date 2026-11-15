// BLE 链路错误分类（2026-11-15 从 ble_obd_transport.dart 拆出）：可辨识
// 异常 + 状态条文案单一出口。扫描器 adapter、传输层 adapter、诊断连接
// 编排与扫描 sheet 共用本模块；错误文案按 kind 唯一映射（throw 点不重
// 复写字符串）。
//
// 平台异常识别（权限文本嗅探、fallback 包装）在 ble_obd_platform_errors.
// dart——本文件保持零 flutter_blue_plus 依赖（ADR 0024），可被纯 Dart
// 测试与状态机文件直接 import。
//
// ≈ Java 的自定义异常族 + 错误码表：kind ≈ ErrorCode，statusCopy ≈
// 错误码对应的用户文案。
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
