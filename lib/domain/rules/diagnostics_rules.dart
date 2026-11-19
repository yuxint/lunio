// 车辆诊断的业务规则（≈ Java 的计算/校验工具类，纯函数可测试）。
//
// 诊断信息卡染色口径（2026-11-17 拍板，ADR 0029；水温 2026-11-18 修订）：
// - 水温（用户拍板「最佳=绿、向外浮动黄、再浮动红」模型）：<50 红
//   （冷启动磨损窗口）→ 50-80 黄（升温中）→ 80-100 绿（最佳工作
//   状态；一般汽油机最佳 85-95、本田 L15 社区共识 88-100，本车实测
//   86/95℃）→ 100-105 黄（风扇启动区间缓冲）→ >105 红（真过热）。
// - 电压（ATRV 电瓶电压口径）：<11.5 红（严重亏电）→ 11.5~14.8 绿
//   （静置 12.4~12.6、充电 13.8~14.4 落绿区）→ >14.8 红（过充）。
// - 燃油修正（染色基准 = LTFT 长期修正，STFT 秒级抖动不做基准）：
//   ±10% 内绿 → ±10~15% 黄 → 超 ±15% 红（老化信号，ECU ±25% 左右设码）。
// - 油量卡不染色。
// 「冷启动 → 最佳工作状态」判读由水温卡承担（灰→黄→绿→红）；燃油修正
// 卡定位 = 燃烧系统健康度（LTFT 缓变趋势），不承担冷启动判别（冷车
// 开环修正冻结）。
//
// 2026-11-17 拍板：油量卡删「可用 X 升」估算展示（ADR 0022 修订节），
// estimateFuel/estimateFuelLiters/FuelEstimate 随展示删除——012F 百分
// 比是诊断侧唯一展示口径；总容积字段保留（加满预估档位列表用）。
//
// 协议解析不在这里——解析纯函数在 features/shell/diagnostics/
// elm327_parser.dart（依赖 DiagnosticsParseType 实体，归诊断域模块）。

/// 诊断信息卡读数色档（页面映射 LunioStatusTone）。
enum DiagnosticsReadingTone {
  /// 正常（绿）。
  normal,

  /// 警告（黄）。
  warning,

  /// 危险（红）。
  danger,
}

class DiagnosticsRules {
  DiagnosticsRules._();

  /// 水温色档（2026-11-18 用户拍板五段）：<50 红（冷启动磨损窗口）→
  /// 50-80 黄（升温中）→ 80-100 绿（最佳工作状态）→ 100-105 黄（风扇
  /// 启动区间缓冲）→ >105 红（真过热）。
  static DiagnosticsReadingTone coolantTempTone(int celsius) {
    if (celsius < 50) {
      return DiagnosticsReadingTone.danger;
    }
    if (celsius < 80) {
      return DiagnosticsReadingTone.warning;
    }
    if (celsius <= 100) {
      return DiagnosticsReadingTone.normal;
    }
    if (celsius <= 105) {
      return DiagnosticsReadingTone.warning;
    }
    return DiagnosticsReadingTone.danger;
  }

  /// 电压色档（ATRV 电瓶电压口径）：<11.5 红（严重亏电）→ 11.5~14.8
  /// 绿（静置 12.4~12.6、充电 13.8~14.4 落绿区）→ >14.8 红（过充/
  /// 调压器故障）。
  static DiagnosticsReadingTone batteryVoltageTone(double volts) {
    if (volts < 11.5) {
      return DiagnosticsReadingTone.danger;
    }
    if (volts <= 14.8) {
      return DiagnosticsReadingTone.normal;
    }
    return DiagnosticsReadingTone.danger;
  }

  /// CVT 油温色档（2026-11-18 用户拍板五段，与水温同「绿区浮动」模
  /// 型）：<60 红 / 60-75 黄 / 75-95 绿（CVT 油液最佳润滑区间 70-90、
  /// 本田城市工况常见 80-100）/ 95-115 黄 / >115 红（过热保护 ~120
  /// 之前）。2026-11-18 实测热车怠速 104℃ 落黄。
  static DiagnosticsReadingTone cvtOilTempTone(int celsius) {
    if (celsius < 60) {
      return DiagnosticsReadingTone.danger;
    }
    if (celsius < 75) {
      return DiagnosticsReadingTone.warning;
    }
    if (celsius <= 95) {
      return DiagnosticsReadingTone.normal;
    }
    if (celsius <= 115) {
      return DiagnosticsReadingTone.warning;
    }
    return DiagnosticsReadingTone.danger;
  }

  /// 燃油修正色档（染色基准 = LTFT）：±10% 内绿（健康）→ ±10~15% 黄
  /// → 超 ±15% 红（老化信号，ECU ±25% 左右设码）。
  static DiagnosticsReadingTone fuelTrimTone(double percent) {
    final abs = percent.abs();
    if (abs <= 10) {
      return DiagnosticsReadingTone.normal;
    }
    if (abs <= 15) {
      return DiagnosticsReadingTone.warning;
    }
    return DiagnosticsReadingTone.danger;
  }

  /// 从读数 display 文本解析数值（2026-11-19 拍板「回退染色」修复）：
  /// celsius/volts 不持久化，进程重开/重连前显示库回退值时染色依据缺
  /// 失落 ink 黑（深审确认的观感缺陷）。display 格式受解析器控制、格式
  /// 稳定（'95℃'/'11.2V'），从文本解析数值即可恢复染色依据；解析失败
  /// （null）返回 null、调用方不染兜底。
  static double? parseDisplayNumber(String display, String unit) {
    final text = display.trim();
    if (!text.endsWith(unit)) {
      return null;
    }
    final numberPart = text.substring(0, text.length - unit.length).trim();
    return double.tryParse(numberPart);
  }
}
