// OBD 运行时装配（票 05）：诊断页消费的两条 provider 接缝。与
// providers.dart 的关系同油价域先例（fuel_prices.dart）：域内运行时
// 装配不进全局 provider 总入口，依赖单向（providers.dart 不 import
// 本文件，页面与测试直接消费）。
//
// ≈ Java 的 @Configuration 装配类：transport ≈ 连接工厂 Bean，会话
// 工厂 ≈ 每次调用 new 一个有状态 Service 实例（会话是一次性对象）。
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'elm327_session.dart';
import 'mock_obd_transport.dart';
import 'obd_transport.dart';

/// OBD 传输层 provider：诊断页经会话工厂消费。票 05 装配 Mock 实现
/// （语料演示表 + 真实延时，模拟器可完整演示一轮完整读取）；票 07
/// 引入 BLE 后替换本 provider 的装配体（协议层与页面零改动，ADR 0020
/// 传输层抽象的意义所在）。
///
/// 测试（widget/诊断页用例）整体覆盖本 provider 注入可控 Mock 实例。
final obdTransportProvider = Provider<OBDTransport>((ref) {
  return MockObdTransport(responses: mockObdCorpusDemoResponses());
});

/// OBD 会话工厂 provider：页面每次连接（首连/重连）经它新建
/// [Elm327Session]（会话是一次性对象，重连 = 新实例）。默认装配生产
/// 定时（单条响应超时 5s / 轮间隔 3s，真机联调再定）；测试覆盖本
/// provider 注入短定时与固定时钟，零/短等待驱动状态机、无 pending
/// timer 残留。
final obdSessionFactoryProvider = Provider<Elm327Session Function()>((ref) {
  final transport = ref.watch(obdTransportProvider);
  return () => Elm327Session(transport: transport);
});
