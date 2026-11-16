// OBD 传输层 Mock 实现（ADR 0020）：可编程响应脚本驱动，模拟器演示
// 与单测共用。不做设备发现，connect 无操作。
//
// ≈ Java 单测里的内嵌假服务器：按规整指令文本查表应答，支持分片推
// 送（语料 209ms 双通知形态）、不应答（超时路径）、发送即抛（链路
// 错误路径）。
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'elm327_parser.dart' show normalizeObdCommand;
import 'obd_transport.dart';

/// 一条指令的应答脚本（[MockObdTransport.responses] 的值）。
/// [chunks] 是通知分片字节（latin1 文本编码）；发送后先等
/// [firstChunkDelay] 再推首块、块间等 [chunkGap]（默认 209ms 对齐
/// 语料形态）。[error] 非 null = 发送即抛（链路错误路径）。
class MockObdScript {
  const MockObdScript({
    required this.chunks,
    this.firstChunkDelay = const Duration(milliseconds: 50),
    this.chunkGap = const Duration(milliseconds: 209),
    this.error,
  });

  final List<List<int>> chunks;
  final Duration firstChunkDelay;
  final Duration chunkGap;

  /// 发送即抛的错误（null = 正常应答脚本）。
  /// 不应答脚本：send 正常返回、无字节到达（会话侧走超时路径）。
  const MockObdScript.silent()
      : chunks = const [],
        firstChunkDelay = Duration.zero,
        chunkGap = Duration.zero,
        error = null;
  final Object? error;
}

/// Mock 传输层：按规整指令文本查 [responses] 应答；未命中 = 不应答
/// （走超时路径）。
class MockObdTransport implements OBDTransport {
  MockObdTransport({required this.responses, this.delay = _realDelay});

  /// 脚本表：key = 规整指令文本（normalizeObdCommand 后）。
  final Map<String, MockObdScript> responses;


  /// 延时接缝（会话控制器与单测共用一份假延时，单测零真实等待）。
  final Future<void> Function(Duration) delay;

  static Future<void> _realDelay(Duration d) => Future<void>.delayed(d);

  final _bytes = StreamController<Uint8List>.broadcast();
  bool _connected = false;

  /// 已发送的规整指令记录（按序全加；测试断言 AT 序列与轮询编排用，
  /// 模拟器演示调试用）。
  final sentCommands = <String>[];

  /// disconnect() 调用次数（测试断言"离开页面断开会话"用——页面
  /// dispose 链路最终会调到这里，计数是可观察出口）。
  int disconnectCalls = 0;

  @override
  Future<void> connect() async {
    _connected = true;
  }

  @override
  Future<void> send(List<int> bytes) async {
    if (!_connected) {
      throw StateError('MockObdTransport not connected');
    }
    final text = latin1.decode(bytes);
    final stripped =
        text.endsWith('\r') ? text.substring(0, text.length - 1) : text;
    final command = normalizeObdCommand(stripped);
    sentCommands.add(command);
    final script = responses[command] ?? const MockObdScript.silent();
    if (script.error != null) {
      throw script.error!;
    }
    for (var i = 0; i < script.chunks.length; i++) {
      if (i == 0) {
        await delay(script.firstChunkDelay);
      } else {
        await delay(script.chunkGap);
      }
      _bytes.add(Uint8List.fromList(script.chunks[i]));
    }
  }

  /// 未发送指令直接注字节：测试超时清缓冲后迟到碎片（纯提示符帧）等
  /// 形态用（防读数错位测试消费）。
  void injectBytes(List<int> bytes) {
    _bytes.add(Uint8List.fromList(bytes));
  }

  /// 向字节流注入 error（断连/链路错误路径测试用）。
  void injectError(Object error) {
    _bytes.addError(error);
  }

  @override
  Stream<Uint8List> get byteStream => _bytes.stream;

  @override
  Future<void> disconnect() async {
    _connected = false;
    disconnectCalls++;
  }
}

/// 语料对齐的演示脚本表（票 05 模拟器演示用）：key = 规整指令文本。
/// 形态全部取自实车日志：ATZ 横幅无回显、ATE0 自带最后一次回显、
/// 012F 走 209ms 双通知分片、内置三条一轮的实车数值（油量 0x60 =
/// 37.6%、水温 0167 = 95℃（41 67 03 87 83，A 传感器）、电压 11.2V），
/// 外加模板里程表 01A6（66,068 km，ADR 0026 两档演示用；不在内置
/// 三条里、默认不轮询，启用模板探针后才有消费者）。
Map<String, MockObdScript> mockObdCorpusDemoResponses() {
  List<int> chunk(String text) => latin1.encode(text);
  MockObdScript instant(String text) => MockObdScript(
        chunks: [chunk(text)],
        firstChunkDelay: Duration.zero,
        chunkGap: Duration.zero,
      );
  return {
    'ATZ': instant('\r\rELM327 v2.3\r\r>'),
    'ATE0': MockObdScript(
      chunks: [chunk('ATE0\r'), chunk('OK\r\r>')],
      firstChunkDelay: Duration.zero,
      chunkGap: Duration.zero,
    ),
    'ATL0': instant('OK\r\r>'),
    'ATSP7': instant('OK\r\r>'),
    '012F': MockObdScript(chunks: [chunk('41 2F 60 \r'), chunk('\r>')]),
    '0167': instant('41 67 03 87 83 \r\r>'),
    '01A6': instant('41 A6 00 0A 14 C8 \r\r>'),
    'ATRV': instant('11.2V\r\r>'),
  };
}
