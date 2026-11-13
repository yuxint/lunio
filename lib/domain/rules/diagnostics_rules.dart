// 车辆诊断的业务规则（≈ Java 的计算/校验工具类，纯函数可测试）。
//
// 当前只有展示侧计算：油量卡升数估算（票 05）。协议解析不在这里——
// 解析纯函数在 features/shell/diagnostics/elm327_parser.dart（依赖
// DiagnosticsParseType 实体，归诊断域模块）；本文件只收"与车有关"
// 的业务判断（油箱容积在 Car 上），供页面与后续票复用。
class DiagnosticsRules {
  DiagnosticsRules._();

  /// 油量卡升数估算（spec story 10/11）：百分比 × 油箱容积 = 估算升数，
  /// 页面保留 1 位小数展示（"≈ 20.7 升"）。容积未填返回 null——页面
  /// 只显示百分比、不显示估算、也不提示去填（story 11：不误导）。
  static double? estimateFuelLiters(
      double percent, double? tankCapacityLiters) {
    if (tankCapacityLiters == null) {
      return null;
    }
    return percent / 100 * tankCapacityLiters;
  }
}
