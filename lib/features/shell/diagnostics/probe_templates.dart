// 检测点推荐模板（ADR 0023 第一批）：标准 Mode 01 常用量，选中即回填
// 名称/指令/解析类型；用户仍可改。指令与公式见 DiagnosticsParseType。
import '../../../domain/entities/diagnostics_parse_type.dart';

/// 一条推荐模板：名称 + 标准 PID 指令 + 解析类型。
class DiagnosticsProbeTemplate {
  const DiagnosticsProbeTemplate({
    required this.name,
    required this.command,
    required this.parseType,
  });

  final String name;
  final String command;
  final DiagnosticsParseType parseType;
}

/// 第一批 6 项（2026-11-15 拍板）：转速/车速/进气温度/节气门/发动机
/// 负荷/控制模块电压。油轨压力、燃油修正、氧传感器等放第二批。
const List<DiagnosticsProbeTemplate> diagnosticsProbeTemplates = [
  DiagnosticsProbeTemplate(
    name: '转速',
    command: '010C',
    parseType: DiagnosticsParseType.rpm,
  ),
  DiagnosticsProbeTemplate(
    name: '车速',
    command: '010D',
    parseType: DiagnosticsParseType.speed,
  ),
  DiagnosticsProbeTemplate(
    name: '进气压力',
    command: '010B',
    parseType: DiagnosticsParseType.mapPressure,
  ),
  DiagnosticsProbeTemplate(
    name: '节气门',
    command: '0111',
    parseType: DiagnosticsParseType.throttlePercent,
  ),
  DiagnosticsProbeTemplate(
    name: '发动机负荷',
    command: '0104',
    parseType: DiagnosticsParseType.engineLoad,
  ),
  DiagnosticsProbeTemplate(
    name: '控制模块电压',
    command: '0142',
    parseType: DiagnosticsParseType.moduleVoltage,
  ),
];