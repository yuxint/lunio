// 加满预估档位列表的滚动定位决策体控制器（ADR 0002 滚动定档，2026-10-01
// 收编）：加油页「档位」交互全部决策的唯一实现。
//
// 职责：
//   1. 三向换算：已存档位(%) ↔ 列表下标 ↔ 滚动偏移(px)——行高经构造注入
//      （与列表 itemExtent/吸附物理共用同一常量），档位表取
//      FuelRules.allTierPercents（100%→0% 每 2% 一档共 51 档）；
//   2. 停稳定档落库：ScrollEnd 时第一行档位经注入的 saveBaseline 落库
//      （动作层 saveFuelBaseline，ADR 0007；仓库同值 no-op，重复停稳
//      零开销）；
//   3. 外部档位变化的重定位决策（换车后旧值→真值、恢复备份、error→data）：
//      与当前第一行同值（自己停稳写库的回读）不动作；正在拖动/惯性滑行
//      不抢位置（本轮手势停稳后会写库覆盖）；其余静默 jumpTo 重定位；
//   4. 默认档位 50%：无存档按它定位；返回图标的滚回目标偏移与置灰判定。
//
// 在 App 中的位置：只被 fuel_page.dart 的 _TierListCard 使用。
// ≈ Java Web 里表单页抽出来的 BackingBean（同 RecordFormController /
// RecordCostFormController / AddCarWizardController / FuelRecordFormController
// 四个先例）：持有交互状态与决策，widget 只做渲染并把事件转接进来；事件
// 方法只改状态不触发重建，返回第一行下标是否变化，widget 据此 setState。
//
// 与两道既有 seam 的边界：
//   - ADR 0007 动作层：落库不在本类——经注入的 saveBaseline 闭包调用
//     （内部走 saveFuelBaseline），失败 toast 留在闭包实现里（异常穿透
//     惯例，反馈归调用方）；
//   - shared/scroll_snap.dart 吸附物理：物理负责把手势停点对齐整行边界，
//     本类只在 ScrollEnd 消费已对齐的偏移（不能在 ScrollEnd 里再
//     animateTo，见 scroll_snap.dart 文件头）。
// 滚动真值（偏移、是否滚动中、静默跳转执行）经 [FuelTierListViewport]
// 注入——ScrollController 由 widget 持有（不挂视口读不到偏移），本类
// 不碰 BuildContext、不依赖 ref。
import '../../../domain/rules/fuel_rules.dart';

/// 档位列表滚动真值的注入点：控制器对滚动位置的全部读写都经这里。
/// 实现在 widget 侧（转发给它持有的 ScrollController）；单测注入假实现。
class FuelTierListViewport {
  const FuelTierListViewport({
    required this.offset,
    required this.isScrolling,
    required this.jumpTo,
  });

  /// 当前滚动偏移（px）。仅在列表已挂载（会收到滚动通知）后调用。
  final double Function() offset;

  /// 是否正在拖动/惯性滑行。实现方约定：视口未挂载（ScrollController
  /// 的 hasClients 为 false）也返回 true——读不了也跳不了，外部档位变化
  /// 静默放过等下一拍（等价原 State 里 hasClients 的独立守卫分支）。
  final bool Function() isScrolling;

  /// 静默跳转到目标偏移（外部档位变化重定位用，无动画；会连带派发一串
  /// 滚动通知，其 ScrollEnd 走停稳落库——落到重定位目标档即 provider
  /// 刚给的值，仓库同值 no-op，无副作用）。
  final void Function(double offset) jumpTo;
}

/// 档位列表控制器（职责与边界见文件头）。
///
/// 接口约定：事件方法（onScrollUpdate / onScrollEnd / onSavedPercentChanged）
/// 只改状态并经注入闭包与外界交互，不触发重建——返回第一行下标是否变化，
/// widget 据此决定 setState。渲染所需的派生状态经 firstIndex /
/// currentPercent / isAtDefault / backToDefaultOffset 暴露。
class FuelTierListController {
  FuelTierListController({
    required this.rowExtent,
    required this.viewport,
    required this.saveBaseline,
    int? savedPercent,
  }) : _savedPercent = savedPercent,
       _firstIndex = indexForPercent(savedPercent),
       // 初始定位（构造）不落库：只有滚动停稳才物化一行（ADR 0002 更新节）。
       initialOffset = indexForPercent(savedPercent) * rowExtent;

  /// 一行的固定高度（px）：偏移换算的步长。与列表 itemExtent/吸附物理
  /// 共用同一常量，由 widget 传入（先例：RowSnapScrollPhysics 收 rowExtent
  /// 参数、不自定义常量）。
  final double rowExtent;

  /// 滚动真值注入点（见 [FuelTierListViewport]）。
  final FuelTierListViewport viewport;

  /// 落库动作注入点：参数 = 停稳档位(%)。实现走动作层 saveFuelBaseline，
  /// 失败反馈（toast）留在实现里，异常不进决策体。
  final Future<void> Function(int percent) saveBaseline;

  /// 构造时的初始滚动偏移：已存档位（无存档 = 默认 50%）在第一行。
  /// widget 用它建 ScrollController（initialScrollOffset）。
  final double initialOffset;

  /// 默认档位（%）：无存档的定位档、返回图标的滚回目标（ADR 0002）。
  static const int defaultPercent = 50;

  /// 全量档位表（下标 0 = 100%，每档 -[FuelRules.percentStep]；widget
  /// 渲染行另有同一来源的引用，单一事实源是 FuelRules）。
  static final List<int> _tiers = FuelRules.allTierPercents;

  /// 默认档位在全量档位表里的下标。
  static final int _defaultIndex =
      (100 - defaultPercent) ~/ FuelRules.percentStep;

  /// 当前第一行下标（滚动跟随更新；行高亮与返回按钮态的基准）。
  int _firstIndex;

  /// 上次所见的已存档位（onSavedPercentChanged 的去重基准）。
  int? _savedPercent;

  /// 当前第一行下标（渲染高亮用）。
  int get firstIndex => _firstIndex;

  /// 当前第一行对应的档位百分比（滚动停稳后落库的就是它）。
  int get currentPercent => _tiers[_firstIndex];

  /// 是否停在默认 50%（返回图标的置灰条件）。
  bool get isAtDefault => currentPercent == defaultPercent;

  /// 返回图标滚回默认 50% 的目标偏移（animateTo 的时长/曲线是 UI 决策，
  /// 执行留 widget）。
  double get backToDefaultOffset => _defaultIndex * rowExtent;

  /// 已存档位 → 列表下标：null = 默认 50%；奇数等非档位值就近取整
  /// （容错老数据）；越界夹回首尾档。
  static int indexForPercent(int? percent) {
    final value = percent ?? defaultPercent;
    return ((100 - value) / FuelRules.percentStep)
        .round()
        .clamp(0, _tiers.length - 1);
  }

  /// 滚动偏移 → 第一行下标（吸附物理停稳后偏移已在整行边界；越界夹回）。
  int indexFromOffset(double offset) {
    return (offset / rowExtent).round().clamp(0, _tiers.length - 1);
  }

  /// 滚动进行中（widget 转发 ScrollUpdate）：跟随更新第一行下标。
  /// 返回下标是否变化（widget 据此 setState 重绘高亮与返回按钮态）。
  bool onScrollUpdate() => _syncFirstIndexFromOffset();

  /// 滚动停稳（widget 转发 ScrollEnd）：吸附物理已把偏移对齐整行边界，
  /// 更新第一行下标并按当前档位落库——无存档时停稳含 50% 也物化一行
  /// （ADR 0002 更新节）；初始定位不走这里，不落库。
  bool onScrollEnd() {
    final changed = _syncFirstIndexFromOffset();
    // 不 await：失败 toast 在注入闭包内消化，控制器不等落库结果。
    saveBaseline(currentPercent);
    return changed;
  }

  /// 外部已存档位变化（widget didUpdateWidget 转发：换车后旧值→真值、
  /// 恢复备份、error→data）。决策：与上次所见同值不动作；换算后与当前
  /// 第一行同值（自己停稳写库的回读）不动作；正在拖动/惯性滑行不抢位置
  /// （本轮手势停稳后会写库覆盖）；其余静默 jumpTo 重定位。
  /// 返回是否发生了重定位（widget 据此 setState 更新高亮）。
  bool onSavedPercentChanged(int? percent) {
    if (percent == _savedPercent) {
      return false;
    }
    _savedPercent = percent;
    final target = indexForPercent(percent);
    if (target == _firstIndex || viewport.isScrolling()) {
      return false;
    }
    viewport.jumpTo(target * rowExtent);
    _firstIndex = target;
    return true;
  }

  /// 按滚动真值同步第一行下标；返回是否变化。
  bool _syncFirstIndexFromOffset() {
    final index = indexFromOffset(viewport.offset());
    if (index == _firstIndex) {
      return false;
    }
    _firstIndex = index;
    return true;
  }
}
