// OBD 扫描器契约（2026-11-15 从 ble_obd_transport.dart 拆出）：扫描结果
// 流 + 适配器门禁 + 启停的唯一契约，v1 两个 adapter——BLE 真实现
// `BleObdScanner`（ble_obd_link.dart）与测试替身 FakeObdScanner。与
// obd_transport.dart 同一先例：契约留 obd_*.dart，BLE 实现在 ble_*.dart。
//
// ≈ Java 的接口（Scanner 端口）：连接编排依赖本契约，不依赖
// flutter_blue_plus 门面；换扫描实现不改编排与扫描 sheet。
import 'dart:async';

import 'ble_scan_entries.dart';

/// 设备扫描器接缝（诊断连接编排的数据源）。
abstract class ObdScanner {
  /// 扫描结果流（每次发射 = 当前全量清单按首见定序整备；发射节奏由
  /// 实现合并至 ≤1Hz，新设备立即发射；连接编排订阅它刷新扫描状态，
  /// 扫描 sheet 只渲染编排状态）。
  Stream<List<BleObdScanEntry>> get results;

  /// 适配器门禁（支持/授权/开关）：连接编排在打开扫描前先调用它，
  /// 门禁失败状态条渲染文案、不落扫描（story 8）。权限拒绝抛
  /// `BleObdTransportException`。
  Future<void> ensureReady();

  /// 开始扫描（已扫中幂等）。适配器门禁失败抛
  /// `BleObdTransportException`。
  Future<void> start();

  /// 停止扫描（幂等，释放订阅与适配器扫描）。起始窗口内调用只置停扫
  /// 旗，start 在检查点自行清理（不会扫出无人消费的结果）。
  Future<void> stop();
}
