// 车辆诊断的业务规则（≈ Java 的计算/校验工具类，纯函数可测试）。
//
// 诊断信息卡染色口径（2026-11-17 拍板，ADR 0029）：
// - 水温：<70 灰（冷车，非警告）→ 70-85 黄（未达最佳）→ 85-100 绿
//   （最佳工作状态）→ >100 红（过热）。本车热车怠速实测 95℃（0167
//   A 传感器），「>92 红」会让正常热车常亮红，绿区上限定 100。
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

/// 诊断信息卡读数色档（页面映射 LunioStatusTone）。muted = 冷车灰档
/// （未达工作温度，非警告）。
enum DiagnosticsReadingTone {
  /// 正常（绿）。
  normal,

  /// 警告（黄）。
  warning,

  /// 危险（红）。
  danger,

  /// 冷车灰档（水温 <70℃，未达工作温度；非警告）。
  muted,
}

class DiagnosticsRules {
  DiagnosticsRules._();

  /// 水温色档：<70 灰（冷车）→ 70-85 黄（未达最佳）→ 85-100 绿（最佳
  /// 工作状态）→ >100 红（过热）。
  static DiagnosticsReadingTone coolantTempTone(int celsius) {
    if (celsius < 70) {
      return DiagnosticsReadingTone.muted;
    }
    if (celsius < 85) {
      return DiagnosticsReadingTone.warning;
    }
    if (celsius <= 100) {
      return DiagnosticsReadingTone.normal;
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
}
