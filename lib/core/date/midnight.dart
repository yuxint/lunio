// 「生效今天」的零点调度纯函数（ADR 0025）：provider 自刷新的时长计算。
//
// 放在 core/date：只依赖本地日历算术，不碰 Flutter 与 Riverpod，可直接
// 单测。语义 =「下一个本地零点 − now」。整点零点返回整天而不是 0——零
// 时长定时器会立刻触发，形成自旋。
//
// ≈ Java 的 Duration.between(now, LocalDate.now().plusDays(1).atStartOfDay())。
Duration untilNextMidnight(DateTime now) {
  // 本地日历归一化（DateTime 构造自动跨月/跨年进位），不是 24 小时累加。
  final nextMidnight = DateTime(now.year, now.month, now.day + 1);
  return nextMidnight.difference(now);
}
