// OBD 传输层接口（ADR 0020 决定 1）：字节流收发语义的唯一契约，v1 两个
// 实现——BLE（票 07 真机）与 Mock（模拟器演示/单测）。协议层与页面只
// 认本接口；未来 WiFi/TCP 通道走新实现，协议层不动。
//
// ≈ Java 的 java.net.Socket 抽象：connect 建链、OutputStream 写、
// InputStream 读、close 断开；字节流语义对上层屏蔽 BLE 通知分片细节
// （分片组装归解析模块的组帧缓冲）。
//
// 通道降级守卫（guardedChannelCall）不适用本接口：BLE 会话是有状态长
// 连接，不是轻功能方法通道（ADR 0020 背景节）。
import 'dart:typed_data';

/// OBD 传输层接口：连接、发指令字节、收响应字节流、断开。
///
/// 字节流契约（实车语料）：指令 = ASCII 文本 + CR（0x0D）结尾；响应
/// 以一次/多次通知分片到达，按 `>` 组帧缓冲归解析模块。上层（会话
/// 控制器）保证严格串行：上一条等 `>`（或超时）才发下一条。
abstract class OBDTransport {
  /// 建立链路。BLE 实现含扫描/连接/发现服务/订阅通知；Mock 无操作。
  /// 失败抛异常（会话控制器翻译成可辨识的会话错误）。
  Future<void> connect();

  /// 写指令字节（规整指令 + CR）。失败抛异常。返回后响应字节经
  /// [byteStream] 陆续到达。
  Future<void> send(List<int> bytes);

  /// 响应字节流（BLE 通知分片逐块到达）。断连经流 error/done 上抛。
  Stream<Uint8List> get byteStream;

  /// 断开链路并释放底层资源。幂等。
  Future<void> disconnect();
}
