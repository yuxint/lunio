// OBD 运行时装配（票 05 建缝，票 07 换 BLE 装配体）：诊断页消费的三条
// provider 接缝。与 providers.dart 的关系同油价域先例（fuel_prices.dart）：
// 域内运行时装配不进全局 provider 总入口，依赖单向（providers.dart 不
// import 本文件，页面与测试直接消费）。
//
// ≈ Java 的 @Configuration 装配类：transport 工厂 ≈ 每次调用 new 一个
// 有状态 Service 实例（会话/传输层都是一次性对象）；scanner ≈ 单例
// Bean。
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ble_obd_transport.dart';
import 'elm327_session.dart';
import 'mock_obd_transport.dart';

/// 诊断链路 mock 回退开关（dart-define）：`--dart-define=LUNIO_OBD_MOCK=true`
/// 时整条链路回退票 05 语料演示 Mock（模拟器无蓝牙，视觉验收用）；默
/// 认装配 BLE 真链路（真机验收走真机验收清单）。
const obdMockLink = bool.fromEnvironment('LUNIO_OBD_MOCK');

/// OBD 会话工厂 provider：页面每次连接（首连/重连/扫描点选）经它新建
/// [Elm327Session]（会话与传输层都是一次性对象，重连 = 新实例）。
/// [ObdSessionFactory] 收目标设备标识——BLE 装配按它绑定传输层；mock
/// 装配忽略它（语料演示不认设备）。测试覆盖本 provider 注入门闩夹具
///（diagnostics_fixture.dart），零真实定时器。
typedef ObdSessionFactory = Elm327Session Function(String deviceId);

final obdSessionFactoryProvider = Provider<ObdSessionFactory>((ref) {
  if (obdMockLink) {
    return (deviceId) => Elm327Session(
          transport: MockObdTransport(responses: mockObdCorpusDemoResponses()),
        );
  }
  return (deviceId) =>
      Elm327Session(transport: BleObdTransport(deviceId: deviceId));
});

/// OBD 设备扫描器 provider：诊断页扫描选择 sheet 的数据源接缝。测试
/// 覆盖本 provider 注入受控假扫描器（transport 接缝同手法）。
final obdScannerProvider = Provider<ObdScanner>((ref) => BleObdScanner());
