// 加满预估档位列表控制器（FuelTierListController）的单元测试。
//
// 直接打控制器接口（不用 pump widget），锁死从档位列表 State 收编出来的
// 全部决策（2026-10-01，换算/定档/重定位归控制器、滚动执行与渲染归
// widget）：
//  - 三向换算：已存档位 ↔ 列表下标 ↔ 滚动偏移（无存档默认 50%、奇数
//    就近取整容错老数据、越界夹回首尾档）；
//  - 停稳定档：ScrollEnd 把第一行档位经注入闭包落库（ScrollUpdate 只
//    跟随不落库；初始定位不落库；无存档停稳含 50% 也物化一行，
//    ADR 0002 更新节）；
//  - 外部档位变化：静默 jumpTo 重定位（换车后旧值→真值、恢复备份、
//    error→data）；
//  - 不抢位置/不动作的三类守卫：拖动/惯性滑行中不重定位（本轮手势
//    停稳后写库覆盖）；与当前第一行同值的回读（自己停稳写库）不动作；
//    与上次所见同值不动作；
//  - 返回 50%：滚回目标偏移与置灰判定。
//
// 滚动行为的 widget 侧回归（真实拖动手势 + 吸附物理末速度投射）在
// test/widget/fuel_test.dart，这里不重复。
import 'package:flutter_test/flutter_test.dart';
import 'package:lunio/features/shell/fuel/fuel_tier_list_controller.dart';

/// 测试夹具：假滚动真值（偏移/占线态可拨动，jumpTo 记账并同步偏移）+
/// 落库记账。行高与 fuel_page 的 _kTierRowExtent 同值（44），档位步长
/// 取 FuelRules 事实（2% 一档共 51 档）。
class TierHarness {
  TierHarness({int? savedPercent}) {
    controller = FuelTierListController(
      rowExtent: rowExtent,
      savedPercent: savedPercent,
      viewport: FuelTierListViewport(
        offset: () => offset,
        isScrolling: () => scrolling,
        // 真实 jumpTo 会把偏移置为目标值并派发滚动通知，假实现同步
        // 偏移供后续读取，通知派发不在本层模拟（widget 测试覆盖）。
        jumpTo: (value) {
          jumps.add(value);
          offset = value;
        },
      ),
      saveBaseline: (percent) async => savedBaselines.add(percent),
    );
  }

  /// 行高（与 fuel_page 的 _kTierRowExtent 同值）。
  static const double rowExtent = 44;

  late final FuelTierListController controller;

  /// 假滚动真值：当前偏移（px）与是否正在拖动/惯性滑行。
  double offset = 0;
  bool scrolling = false;

  /// 静默重定位记账（每次 jumpTo 的目标偏移）。
  final List<double> jumps = [];

  /// 落库记账（每次停稳定档的档位值）。
  final List<int> savedBaselines = [];

  /// 把假偏移拨到某档位所在行（等价真实滚轮停在该档第一行）。
  void scrollToPercent(int percent) {
    offset = FuelTierListController.indexForPercent(percent) * rowExtent;
  }
}

void main() {
  test('no saved tier positions at default 50 percent without persisting', () {
    final harness = TierHarness();

    // 无存档按默认 50% 定位：下标 25、偏移 25 × 44 = 1100。
    expect(harness.controller.currentPercent, 50);
    expect(harness.controller.firstIndex, 25);
    expect(harness.controller.initialOffset, 25 * TierHarness.rowExtent);
    expect(harness.controller.isAtDefault, isTrue);
    // 初始定位不落库（ADR 0002：只有滚动停稳才物化一行）。
    expect(harness.savedBaselines, isEmpty);
    expect(harness.jumps, isEmpty);
  });

  test('saved tier positions its row at top on construction', () {
    final harness = TierHarness(savedPercent: 42);

    // 42% → 下标 (100-42)/2 = 29，初始偏移 29 × 44。
    expect(harness.controller.currentPercent, 42);
    expect(harness.controller.initialOffset, 29 * TierHarness.rowExtent);
    expect(harness.controller.isAtDefault, isFalse);
  });

  test('percent to index rounds odd values and clamps out of range', () {
    // 奇数 43 就近取整：(100-43)/2 = 28.5 → round 半数远离零 → 29（42%）。
    expect(FuelTierListController.indexForPercent(43), 29);
    // 越界夹回首尾档（容错老数据/异常值）。
    expect(FuelTierListController.indexForPercent(200), 0); // → 100%
    expect(FuelTierListController.indexForPercent(-4), 50); // → 0%

    final harness = TierHarness();
    // 偏移 ↔ 下标：整行边界直接换算，越界夹回。
    expect(harness.controller.indexFromOffset(29 * TierHarness.rowExtent), 29);
    expect(harness.controller.indexFromOffset(-99), 0);
    expect(harness.controller.indexFromOffset(9999), 50);
  });

  test('scroll update follows first row without persisting', () {
    final harness = TierHarness();
    harness.scrollToPercent(42);

    // 滚动过程中只跟随第一行（下标变化 → true，widget 才 setState）。
    expect(harness.controller.onScrollUpdate(), isTrue);
    expect(harness.controller.currentPercent, 42);
    // 不落库：写库时机是停稳（ScrollEnd），不是每一帧。
    expect(harness.savedBaselines, isEmpty);
    // 同档内细碎偏移不再变化 → false（widget 不必重绘）。
    expect(harness.controller.onScrollUpdate(), isFalse);
  });

  test('scroll settle persists the settled tier', () {
    final harness = TierHarness();
    harness.scrollToPercent(42);
    harness.controller.onScrollEnd();

    // 停稳即定档落库：42% 经注入闭包出仓。
    expect(harness.savedBaselines, [42]);

    // 无存档停稳含 50% 也物化一行（ADR 0002 更新节）。
    final fresh = TierHarness();
    fresh.scrollToPercent(50);
    fresh.controller.onScrollEnd();
    expect(fresh.savedBaselines, [50]);
  });

  test('external tier change silently repositions', () {
    final harness = TierHarness(savedPercent: 42);

    // 外部档位变化（换车后旧值→真值、恢复备份）：静默 jumpTo 到新档
    // 第一行（58% → 下标 21 → 偏移 21 × 44），返回 true 让 widget 重绘。
    expect(harness.controller.onSavedPercentChanged(58), isTrue);
    expect(harness.jumps, [21 * TierHarness.rowExtent]);
    expect(harness.controller.currentPercent, 58);
  });

  test('external tier change while scrolling does not steal position', () {
    final harness = TierHarness(savedPercent: 42);

    // 用户正在拖动/惯性滑行：外部档位变化不抢位置——本轮手势停稳后会
    // 写库覆盖。
    harness.scrolling = true;
    expect(harness.controller.onSavedPercentChanged(58), isFalse);
    expect(harness.jumps, isEmpty);
    expect(harness.controller.currentPercent, 42);

    // 手势停稳：落的是用户停的档（64%），不是被拦下的外部值。
    harness.scrolling = false;
    harness.scrollToPercent(64);
    harness.controller.onScrollEnd();
    expect(harness.savedBaselines, [64]);
  });

  test('read-back of own persisted tier does not act', () {
    final harness = TierHarness();

    // 停稳 42% 落库 → provider 失效回读出新值 42。
    harness.scrollToPercent(42);
    harness.controller.onScrollEnd();
    expect(harness.savedBaselines, [42]);

    // 回读值与当前第一行同值：不 jump、不重定位（State 与
    // ScrollController 保持存活，连续滚动手势不被打断）。
    expect(harness.controller.onSavedPercentChanged(42), isFalse);
    expect(harness.jumps, isEmpty);
    expect(harness.controller.currentPercent, 42);

    // 与上次所见同值再来一拍（provider 再通知）：同样不动作。
    expect(harness.controller.onSavedPercentChanged(42), isFalse);
    expect(harness.jumps, isEmpty);
  });

  test('same-value external change on construction value does not act', () {
    // 构造时已见 42%：didUpdateWidget 再传 42%（值未变化分支）不动作。
    final harness = TierHarness(savedPercent: 42);
    expect(harness.controller.onSavedPercentChanged(42), isFalse);
    expect(harness.jumps, isEmpty);
  });

  test('back to default exposes target offset and disabled flag', () {
    final harness = TierHarness(savedPercent: 42);

    // 返回图标的目标偏移 = 默认 50%（下标 25）所在行；未停默认档不置灰。
    expect(harness.controller.backToDefaultOffset, 25 * TierHarness.rowExtent);
    expect(harness.controller.isAtDefault, isFalse);

    // 滚回 50% 停稳后置灰（onPressed 传 null 的判定）。
    harness.scrollToPercent(50);
    harness.controller.onScrollUpdate();
    expect(harness.controller.isAtDefault, isTrue);
  });
}
