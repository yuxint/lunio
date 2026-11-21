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
/// 012F 走 209ms 双通知分片、内置探针一轮的实车数值（油量 0x60 =
/// 37.6%、水温 0167 = 95℃（41 67 03 87 83，A 传感器）、电压 0142 =
/// 12.43V（2026-11-20 换源；ATRV 保留作调试终端手发演示）、
/// 燃油修正 0106 = −1.6% / 0107 = 0%，11-12 实测口径），
/// 内置七条全在演示语料里（油量/水温/电压/燃油修正两条/CVT 油温/
/// 里程表），外加 CVT 探针切头应答（2026-11-19 深审修复：轮询链路
/// 按 probe.header 按需 ATSH 切头，演示语料缺应答会让 CVT 卡每轮多
/// 两次静默超时、永远无数据）。ECU 握手 0100 摘自一键检测日志真实帧
///（三 ECU 并发响应）。
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
    // 燃油修正（2026-11-17 拍板转正）：本车 11-12 实测口径。
    // 0106 A=0x7E → (126−128)×100/128 = −1.6%；0107 A=0x80 → 0%。
    '0106': instant('41 06 7E \r\r>'),
    '0107': instant('41 07 80 \r\r>'),
    // ECU 握手探测（ADR 0029）：三 ECU 并发响应，摘自一键检测日志。
    '0100': instant(
      '41 00 90 18 80 11 \r41 00 B6 3C A8 13 \r41 00 90 18 80 03\r\r>',
    ),
    '01A6': instant('41 A6 00 0A 14 C8 \r\r>'),
    // 电压（2026-11-20 内置口径换 0142）：三 ECU 各回一行，首行
    // 0x308E = 12.43V（11-19 07:58 一键检测日志原帧）。ATRV 留着给
    // 调试终端手发演示（不再进内置轮询）。
    '0142': instant('41 42 30 8E \r41 42 2F F8 \r41 42 30 1D\r\r>'),
    'ATRV': instant('11.2V\r\r>'),
    // CVT 探针切头应答（2026-11-19 深审修复）：222301 须 ATSH DA1EF1
    // 物理寻址，轮询链路按需切头；帧摘自 11-19 实车日志（热车怠速
    // 0x74 → 76℃，黄档）。
    'ATSHDA1EF1': instant('OK\r\r>'),
    'ATSHDB33F1': instant('OK\r\r>'),
    '222301': instant(
      '027 \r'
      '0: 62 23 01 9E 48 AF \r'
      '1: 38 11 00 00 05 47 04 \r'
      '2: 8F 02 CB 19 00 00 13 \r'
      '3: 00 00 00 82 00 2B 00 \r'
      '4: 66 30 74 7B 00 00 42 \r'
      '5: 00 00 FF FF 00 55 55\r\r>',
    ),
  };
}
