// 车辆诊断的业务规则（≈ Java 的计算/校验工具类，纯函数可测试）。
//
// 当前只有展示侧计算：油量卡升数估算（票 05）。协议解析不在这里——
// 解析纯函数在 features/shell/diagnostics/elm327_parser.dart（依赖
// DiagnosticsParseType 实体，归诊断域模块）；本文件只收"与车有关"
// 的业务判断（油箱容积在 Car 上），供页面与后续票复用。
/// 双油量估算结果（ADR 0022）。[reserveLiters]/[totalLiters] 为 null =
/// 总容积未填（或小于可用容积的脏数据），页面只显示可用油量。
class FuelEstimate {
  const FuelEstimate({
    required this.usableLiters,
    this.reserveLiters,
    this.totalLiters,
  });

  /// 日常可用油量 = 仪表% × 可用容积。
  final double usableLiters;

  /// 储备油量 = 总容积 − 可用容积。
  final double? reserveLiters;

  /// 估算总油量 = 储备油量 + 可用油量。
  final double? totalLiters;
}

class DiagnosticsRules {
  DiagnosticsRules._();

  /// 油量卡升数估算（spec story 10/11）：百分比 × 可用容积 = 可用油量，
  /// 页面保留 1 位小数展示。容积未填返回 null——页面只显示百分比、
  /// 不显示估算、也不提示去填（story 11：不误导）。
  static double? estimateFuelLiters(
      double percent, double? tankCapacityLiters) {
    if (tankCapacityLiters == null) {
      return null;
    }
    return percent / 100 * tankCapacityLiters;
  }

  /// 双油量估算（ADR 0022）：可用油量 + 储备/总油量一次算齐。
  /// [tankCapacityLiters] = 加满可加油量；[totalTankCapacityLiters] =
  /// 官方总容积。总容积未填或小于可用容积时只返回可用油量（脏数据不
  /// 造负数储备）。浮子百分比是位置不是体积，结果都是估算。
  static FuelEstimate? estimateFuel({
    required double percent,
    double? tankCapacityLiters,
    double? totalTankCapacityLiters,
  }) {
    final usable = estimateFuelLiters(percent, tankCapacityLiters);
    if (usable == null) {
      return null;
    }
    final total = totalTankCapacityLiters;
    if (total == null || total < tankCapacityLiters!) {
      return FuelEstimate(usableLiters: usable);
    }
    final reserve = total - tankCapacityLiters;
    return FuelEstimate(
      usableLiters: usable,
      reserveLiters: reserve,
      totalLiters: reserve + usable,
    );
  }
}
