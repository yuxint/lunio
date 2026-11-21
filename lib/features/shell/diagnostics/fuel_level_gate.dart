// 油量读数门限（2026-11-20 起，2026-11-21 二次修订定稿）：把 `012F` 的
// 晃动挡在信息卡之外，原始日志照记。
//
// 背景（语料 docs/car_obd_link/data/）：`012F` 是「油量输入」，即浮子
// 看到的液面高度，不是存量。实测同一会话里 11 秒内 7%↔44%、18 秒内
// 23%→61%——47L 箱上 37 个点 ≈ 17 升，「11 秒多出 17 升」物理上不成立，
// 只能是加减速/转弯/坡度把液面推向一侧后被浮子读到。
//
// 判据（2026-11-21 用户拍板「连续采样几次、在多少浮动范围内就更新」）：
//  1. 保留最近 [windowSize] 拍原始值；
//  2. 窗口内最大值−最小值 ≤ [spreadPercent] 个点（液面已稳定）；且
//  3. 三拍**严格全在卡片现值的一侧**（全大于或全小于）才移动卡片，
//     移动目标 = 窗口中位数。
//
// 第 3 条是二次修订加的（用户指出「行驶时油量还上涨」）：只看中位数
// 与卡片的大小，混合窗口也能推动卡片——11-21 早 40/43/42 的中位数是
// 42，卡片就从 40 涨到 42，而那一拍窗口里明摆着有一个 40。要求三拍
// 同侧后，混合窗口一律保持，方向性错误被堵死。
//
// 为什么不用「只降不升」：那会引入单边偏差——一次被高估的停车姿态
// （液面偏向传感器）会把卡片钉在高位，之后只能往下走，再也回不来；
// 反过来低估值也永远纠不上去。同侧判据是双向对称的，没有这个坑。
//
// 历史（同一条参数的演化，供追溯）：11-20 首版是「偏离基准 + 同向连拍
// 3 拍 + 跨度 ≤8」，被晃动的下降沿击穿（43 之后的 34/22/23 连拍同向，
// 把卡片锁到 23%）；11-21 上午改成纯窗口中位数，被混合窗口推动上涨；
// 本版在窗口内加「同侧」约束。
//
// 参数取 3 拍 / 5 个点：默认 60 秒一拍，3 拍 = 3 分钟；真实油耗率上限
// 约 0.2%/min（60km/h 巡航 ≈ 9%/h），3 分钟内合法变化不超过 1 个点，
// 而浮子晃动实测 10–40 个点——5 点落在两者之间。
//
// ≈ Java 里的一个带状态 Filter（不是纯函数）：跨采样保存窗口。不带
// Flutter 依赖，可直接单测。
import 'dart:math';

class FuelLevelGate {
  FuelLevelGate({this.windowSize = 3, this.spreadPercent = 5});

  /// 判定窗口的拍数（默认 3 拍）。
  final int windowSize;

  /// 窗口内允许的极差（百分点，默认 5）。
  final double spreadPercent;

  double? _accepted;

  /// 最近 [windowSize] 拍原始值（左旧右新）。
  final List<double> _window = [];

  /// 卡片当前采用的值（null = 尚未采纳过任何值）。
  double? get acceptedPercent => _accepted;

  /// 窗口当前样本数（门限拒绝时写日志用）。
  int get windowSampleCount => _window.length;

  /// 窗口当前极差；样本不足 2 拍时为 null（门限拒绝时写日志用）。
  double? get windowSpan {
    if (_window.length < 2) {
      return null;
    }
    return _window.reduce(max) - _window.reduce(min);
  }

  /// 用已知的最后读数播种（库里存的 lastPercent）。已采纳过则忽略。
  /// 播种的意义：连上后前三拍还没凑齐时，卡片显示的是它而不是空白。
  void seed(double? percent) {
    if (_accepted != null || percent == null) {
      return;
    }
    _accepted = percent;
  }

  /// 手动刷新直显：把卡片直接定到这一拍的原始值，并清空窗口重来。
  ///
  /// 用户拍板（2026-11-21）：「手动点刷新，读到多少卡片就显示多少」——
  /// 手动是一等的主观动作，不做平滑。清窗口是为了让随后的自动轮询从
  /// 新基准重新积累证据，而不是拿旧样本把刚显示的值顶回去。
  void override(double percent) {
    _accepted = percent;
    _window.clear();
  }

  /// 判定一拍读数：返回放行的值；null = 本拍丢弃（卡片保持现值）。
  ///
  /// 放行值取窗口中位数而不是最新值——窗口里若有一个边缘值，中位数
  /// 不会被它带偏。
  double? admit(double percent) {
    _window.add(percent);
    while (_window.length > windowSize) {
      _window.removeAt(0);
    }
    final accepted = _accepted;
    if (accepted == null) {
      // 冷启动首拍（库里也没有最后读数）：直接采纳并开始积窗，否则卡片
      // 要空等到窗口凑满。
      _accepted = percent;
      return percent;
    }
    if (_window.length < windowSize || windowSpan! > spreadPercent) {
      return null;
    }
    if (_window.every((value) => value == accepted)) {
      // 三拍与卡片完全一致：没有可移动的量，也不算拒绝（不写门限日志）。
      return accepted;
    }
    final allAbove = _window.every((value) => value > accepted);
    final allBelow = _window.every((value) => value < accepted);
    if (!allAbove && !allBelow) {
      // 三拍跨在卡片两侧 = 液面还在晃，方向都定不下来。
      return null;
    }
    final sorted = [..._window]..sort();
    final middle = sorted.length ~/ 2;
    final median = sorted.length.isOdd
        ? sorted[middle]
        : (sorted[middle - 1] + sorted[middle]) / 2;
    _accepted = median;
    return median;
  }
}
