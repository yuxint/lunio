// ELM327 解析纯函数模块（ADR 0020）：组帧缓冲、响应行提取、多 ECU
// 按请求 PID 匹配、PID 公式枚举解析、hex 原文提取。不依赖 transport
// 与 UI，直接单测（图表刻度先例）。
//
// ≈ Java 的静态工具类：无实例状态的部分是纯函数；[ObdFrameAssembler]
// 是唯一带状态的小类（组帧缓冲），语义等同 IO 层分帧器。
//
// 协议事实全部来自实车日志 docs/car_obd_link/data/IOS-Vlink.txt 的
// 摘录（209ms 分片双通知、三 ECU 并发、NO DATA、独立提示符帧、多行
// 帧编号），测试按语料摘录构造。
import 'dart:convert';
import 'dart:typed_data';

import '../../../domain/entities/diagnostics_parse_type.dart';

/// 指令规整：大写 + 去全部空白。ELM327 把空白当可忽略分隔符（实车
/// 日志里 `ATSP 7` 与 `ATRV` 两种形态都通过），发送与匹配用同一份
/// 规整（diagnostics_probe.dart：发送前规整是会话决策体的职责）。
String normalizeObdCommand(String raw) {
  return raw.toUpperCase().replaceAll(RegExp(r'\s+'), '');
}

/// 组帧缓冲：字节累加到提示符（`>`，0x3E）提交完整帧（latin1 1:1
/// 字节↔字符，适配器输出是 ASCII 文本）。
///
/// 独立 `>` 提示符帧（`\r>` 单独一次通知、甚至裸 `>`）不丢不粘：`>`
/// 只负责切帧，提示符前后的字节各归各的帧。
class ObdFrameAssembler {
  final List<int> _buffer = [];

  /// 喂入新到的字节块，返回本次到齐的完整帧文本（可能 0/1/多帧——
  /// 012F 语料：`41 2F 60 \r` 与 `\r>` 间隔 209ms 两次通知才凑齐一帧）。
  List<String> push(List<int> chunk) {
    _buffer.addAll(chunk);
    final frames = <String>[];
    var start = 0;
    for (var i = 0; i < _buffer.length; i++) {
      if (_buffer[i] == 0x3E) {
        frames.add(latin1.decode(
          Uint8List.fromList(_buffer.sublist(start, i)),
          allowInvalid: true,
        ));
        start = i + 1;
      }
    }
    _buffer.removeRange(0, start);
    return frames;
  }

  /// 缓冲里尚未组帧的残余字节（超时诊断与测试断言用）。
  bool get hasPendingBytes => _buffer.isNotEmpty;

  /// 清空缓冲（超时后的去同步防护：迟到碎片整体丢弃，见会话控制器
  /// `_request` 的超时分支）。
  void clear() {
    _buffer.clear();
  }
}

/// 从完整帧文本提取响应行清单：按 CR 拆行、去空行，再防御性去回显
/// （ATE0 生效后适配器不发命令副本，但 ATD 等会复位回显，语料 19:31:53
/// 的 `0103` 响应即含回显）。[sentCommand] 传发送时的规整指令文本。
List<String> obdFrameLines(String frameText, {required String sentCommand}) {
  var lines = frameText
      .split('\r')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
  if (lines.isNotEmpty &&
      normalizeObdCommand(lines.first) ==
          normalizeObdCommand(sentCommand)) {
    lines = lines.sublist(1);
  }
  return lines;
}

/// 单条检测点一轮读取的解析结果（票 04 验收：NO DATA/ERROR 映射"无
/// 数据"语义值）。无数据是合法结果不是异常，页面对应行级灰态。
sealed class ObdReading {
  const ObdReading();

  /// 页面展示文本。无数据固定"无数据"；有数据按解析类型给规范展示。
  String get display;
}

/// 有数据。
final class ObdValue extends ObdReading {
  const ObdValue({required this.display, this.percent, this.celsius});

  @override
  final String display;

  /// 油量百分比（仅 fuelLevel 解析类型有值），0–100 保留精度供页面
  /// 估算升数 = 百分比 × 油箱容积（story 10/11）。
  final double? percent;

  /// 温度 ℃（仅 coolantTemp 解析类型有值）。
  final int? celsius;
}

/// 无数据（NO DATA / CAN ERROR 等错误行、响应不匹配、超时）。
final class ObdNoData extends ObdReading {
  const ObdNoData(this.reason);

  /// 原因短语（NO DATA / 响应不匹配 / 超时），页面灰态不展示它，
  /// 供日志与测试判别。
  final String reason;

  @override
  String get display => '无数据';
}

/// 适配器错误行关键词（整行匹配，大小写不敏感）：命中即"无数据"。
/// 语料只有 NO DATA；其余是 ELM327 标准错误响应（CAN ERROR/BUS
/// ERROR/STOPPED/UNABLE TO CONNECT/ERROR/`?`）。
const List<String> obdErrorKeywords = [
  'NO DATA',
  'CAN ERROR',
  'BUS ERROR',
  'STOPPED',
  'UNABLE TO CONNECT',
  'ERROR',
  '?',
];

/// 判断响应行是否错误关键词行。
bool isObdErrorLine(String line) {
  final upper = line.toUpperCase();
  return obdErrorKeywords.any((keyword) => upper == keyword);
}

/// 按请求指令匹配目标响应行（多 ECU 并发响应按 PID 取目标帧，ADR 0020
/// 决定 3）。返回 null = 没有匹配行（AT 指令没有 PID 语义，恒 null——
/// AT 响应文本直接整体解析）。
String? matchResponseLine(List<String> lines, String normalizedCommand) {
  final requestBytes = _requestPidBytes(normalizedCommand);
  if (requestBytes == null) {
    return null;
  }
  final (service, pid) = requestBytes;
  for (final line in lines) {
    final bytes = extractHexBytes(line);
    if (bytes.length >= 2 &&
        bytes[0] == (service | 0x40) &&
        bytes[1] == pid) {
      return line;
    }
  }
  return null;
}

/// 从指令文本取（service, pid）两字节：非 hex 指令（AT*）返回 null。
/// 只取前 4 个 hex 字符（012F → 01/2F；227029 → 22/70，首两字节即
/// 响应匹配键，余下字节不参与匹配）。
(int, int)? _requestPidBytes(String normalizedCommand) {
  final hex = RegExp(r'^[0-9A-F]{4,}$');
  if (!hex.hasMatch(normalizedCommand)) {
    return null;
  }
  final service = int.parse(normalizedCommand.substring(0, 2), radix: 16);
  final pid = int.parse(normalizedCommand.substring(2, 4), radix: 16);
  return (service, pid);
}

/// 从一行文本提取 hex 字节序列：按空白拆 token，取合法两位 hex（多行
/// 帧编号 `0:`–`8:` 与杂散字符自动跳过）。
List<int> extractHexBytes(String line) {
  final bytes = <int>[];
  for (final token in line.toUpperCase().split(RegExp(r'\s+'))) {
    if (token.length == 2 && RegExp(r'^[0-9A-F]{2}$').hasMatch(token)) {
      bytes.add(int.parse(token, radix: 16));
    }
  }
  return bytes;
}

/// 主解析入口：完整帧文本 + 规整指令 + 解析类型 → [ObdReading]。
///
/// 判定顺序：错误关键词行（整行）→ 公式类按 PID 匹配取数据字节 →
/// 电压文本 → 原始 hex。多 ECU 部分应答（一行 NO DATA + 一行数据）时
/// PID 匹配仍能取到值——单点失败不连坐的解析侧保障。
ObdReading parseProbeResponse({
  required String command,
  required DiagnosticsParseType parseType,
  required String frameText,
}) {
  final lines = obdFrameLines(frameText, sentCommand: command);
  // 错误关键词整行命中 = 无数据（语料：`NO DATA\r\r>`）。
  final errorLine = lines.where(isObdErrorLine).toList();
  if (errorLine.isNotEmpty && errorLine.length == lines.length) {
    return ObdNoData('响应为错误行：${errorLine.first}');
  }
  final matched = matchResponseLine(lines, command);
  switch (parseType) {
    case DiagnosticsParseType.fuelLevel:
      final a = _firstDataByte(matched);
      if (a == null) {
        return ObdNoData(_noDataReason(matched, command));
      }
      // 油量 = A × 100 / 255（实测 41 2F 60 → 96×100/255 = 37.6471%）。
      final percent = a * 100 / 255;
      return ObdValue(
        display: '${percent.toStringAsFixed(1)}%',
        percent: percent,
      );
    case DiagnosticsParseType.coolantTemp:
      final a = _firstDataByte(matched);
      if (a == null) {
        return ObdNoData(_noDataReason(matched, command));
      }
      // 水温 = A − 40 ℃（Mode 01 PID 0x05 标准公式）。
      final celsius = a - 40;
      return ObdValue(display: '$celsius℃', celsius: celsius);
    case DiagnosticsParseType.rpm:
      final data = _dataBytes(matched);
      if (data == null || data.length < 2) {
        return ObdNoData(_noDataReason(matched, command));
      }
      // 转速 = (A×256+B)/4 rpm（Mode 01 PID 0x0C）。
      final rpm = ((data[0] << 8) | data[1]) / 4;
      return ObdValue(display: '${rpm.toStringAsFixed(0)} rpm');
    case DiagnosticsParseType.speed:
      final a = _firstDataByte(matched);
      if (a == null) {
        return ObdNoData(_noDataReason(matched, command));
      }
      // 车速 = A km/h（Mode 01 PID 0x0D）。
      return ObdValue(display: '$a km/h');
    case DiagnosticsParseType.intakeTemp:
      final a = _firstDataByte(matched);
      if (a == null) {
        return ObdNoData(_noDataReason(matched, command));
      }
      // 进气温度 = A − 40 ℃（Mode 01 PID 0x0F）。
      return ObdValue(display: '${a - 40}℃');
    case DiagnosticsParseType.mapPressure:
      final a = _firstDataByte(matched);
      if (a == null) {
        return ObdNoData(_noDataReason(matched, command));
      }
      // 进气歧管绝对压力 = A kPa（Mode 01 PID 0x0B）。
      return ObdValue(display: '$a kPa');
    case DiagnosticsParseType.throttlePercent:
      final a = _firstDataByte(matched);
      if (a == null) {
        return ObdNoData(_noDataReason(matched, command));
      }
      // 节气门 = A × 100 / 255 %（Mode 01 PID 0x11）。
      return ObdValue(display: '${(a * 100 / 255).toStringAsFixed(1)}%');
    case DiagnosticsParseType.engineLoad:
      final a = _firstDataByte(matched);
      if (a == null) {
        return ObdNoData(_noDataReason(matched, command));
      }
      // 发动机负荷 = A × 100 / 255 %（Mode 01 PID 0x04）。
      return ObdValue(display: '${(a * 100 / 255).toStringAsFixed(1)}%');
    case DiagnosticsParseType.moduleVoltage:
      final data = _dataBytes(matched);
      if (data == null || data.length < 2) {
        return ObdNoData(_noDataReason(matched, command));
      }
      // 控制模块电压 = (A×256+B)/1000 V（Mode 01 PID 0x42）。
      final volts = ((data[0] << 8) | data[1]) / 1000;
      return ObdValue(display: '${volts.toStringAsFixed(2)}V');
    case DiagnosticsParseType.voltageText:
      // 电压文本：ATRV 响应即文本（语料 `11.2V\r\r>`），回显已去，整
      // 文本直接展示。
      if (lines.isEmpty) {
        return ObdNoData('空响应');
      }
      return ObdValue(display: lines.join(' '));
    case DiagnosticsParseType.rawHex:
      // 原始 hex 兜底（story 24"响应原文照显"）：回显剥除后的行全文
      // 照显——hex 形态（多 ECU 各行、多行帧编号 `0:`–`8:`）与文本形
      // 态（ATRV 的 `11.2V`）都忠实展示，不做 hex token 过滤。
      if (lines.isEmpty) {
        return ObdNoData('空响应');
      }
      return ObdValue(display: lines.join(' '));
  }
}

/// 公式类从 PID 匹配行取数据字节（跳过 service+pid 两字节）；无匹配行
/// 或不足两字节返回 null。
List<int>? _dataBytes(String? matched) {
  if (matched == null) {
    return null;
  }
  final bytes = extractHexBytes(matched);
  if (bytes.length < 2) {
    return null;
  }
  return bytes.sublist(2);
}

/// 单字节公式取首个数据字节 A；无匹配行或缺数据字节返回 null。
int? _firstDataByte(String? matched) {
  final data = _dataBytes(matched);
  return data == null || data.isEmpty ? null : data.first;
}

/// 公式类无数据的原因短语：无匹配行 vs 匹配行缺数据字节。
String _noDataReason(String? matched, String command) {
  return matched == null ? '无 $command 响应行' : '响应缺数据字节';
}
