// 通知同步守卫：通知域防竞态协议的"状态与票"唯一拥有者。
// ≈ Spring 里一个极小的并发工具 Bean：只回答一个问题——"手里这轮同步
// 还作数吗"，不编排任何业务动作。
//
// 在 App 中的位置：notification_sync_controller.dart（读票方）与
// notification_coordinator.dart（写状态方）共用；代数 provider 原在
// app/providers.dart，2026-09-25 随守卫收编迁入本文件（与油价域 provider
// 收进 fuel_prices.dart 同款先例）。
//
// 四层防竞态协议的语义单一事实来源（调用方不再各自手抄）：
//  1. 同步代数（CONTEXT.md「同步代数」）：破坏性写库（恢复备份/清空数据/
//     删车）前后各 bump 一次，持票方比对开工时的快照，不一致即放弃（R8）；
//  2. 写库中间态旗（CONTEXT.md「写库中间态」）：破坏性写库事务进行中为
//     真——Drift 流查询与写库共用同一连接，此刻能看到未提交的半成品数据
//     （记录已插入、关联还没挂上之类），拿它算出的到期清单是假的。票直接
//     判无效，宁可丢弃本次同步、等事务提交后由 provider 失效触发的最终
//     一轮补判（2026-09-24 恢复备份弹假到期弹窗事故）；
//  3. disposed（读票方注入）：壳层销毁后一切在途任务放弃（R13）；
//  4. 重入与 pending 重跑（R3）：不属于"作数"判断，仍由同步控制器自己的
//     _GuardedOp 私有 harness 承担，不进本模块。
//
// 顺序保证：begin/settle 都"先升代数、后动旗"，于是"旗已关、代数仍旧"
// 的观察窗口不存在——持旧票的同步任务要么被旗拦住（写库进行中），要么被
// 代数拦住（写库已收尾）。失败回滚时 settle 照常执行：作废写库期间启动
// 的同步任务对回滚后的数据重算一轮，无害。
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 通知同步代数（≈ 乐观锁的版本号）：恢复备份/清空数据时 bump()，持票方
/// 比对开工时的快照，不一致即放弃——用于作废"用旧数据排通知"的竞态
/// （R8）。parking_countdown 保存链路同样用它防错排。用 provider 而非
/// 全局变量，保证所有读取方走同一容器。
final notificationSyncGenerationProvider =
    NotifierProvider<NotificationSyncGeneration, int>(
      NotificationSyncGeneration.new,
    );

/// 代数 Notifier：state 从 0 起，bump() 自增。
class NotificationSyncGeneration extends Notifier<int> {
  @override
  int build() => 0;

  /// 代数 +1（作废全部在途通知同步任务）。
  void bump() => state = state + 1;
}

/// 守卫模块的装配入口。协调器（唯一写者）与同步控制器（读票方）都经
/// 同一 provider 取实例，保证旗与代数只有一份。
final notificationSyncGuardProvider = Provider<NotificationSyncGuard>((ref) {
  return NotificationSyncGuard(ref: ref);
});

/// 通知同步守卫：代数与写库中间态旗的唯一拥有者，票的发牌点。
///
/// 写入面只有 [beginDataReset] / [settleDataReset] 一对，仅供协调器的
/// run* 收尾模板调用（破坏性写库前后各一次，见协调器注释）；其余全部
/// 只读。
class NotificationSyncGuard {
  NotificationSyncGuard({required this.ref});

  final Ref ref;

  bool _dataResetInFlight = false;

  /// 破坏性写库进行中为真（测试断言与同步入口早退读这个）。
  bool get isDataResetInFlight => _dataResetInFlight;

  /// 破坏性写库开工：升代数（作废写库前已在途的同步任务）+ 置旗。
  void beginDataReset() {
    _bumpGeneration();
    _dataResetInFlight = true;
  }

  /// 破坏性写库收尾（finally 语义，失败回滚同样执行）：先升代数（作废
  /// 写库进行中才启动的任务——它们开工时读到的已是上次 bump 后的代数，
  /// 只有这次 bump 能被交付前比对查出来）再关旗。
  void settleDataReset() {
    _bumpGeneration();
    _dataResetInFlight = false;
  }

  /// 发一张同步票：快照当前代数，可选注入"调用方是否已销毁"。
  /// 协调器侧（无 disposed 概念）不传 [isDisposed]。
  SyncRun acquire({bool Function()? isDisposed}) {
    return SyncRun._(
      this,
      ref.read(notificationSyncGenerationProvider),
      isDisposed,
    );
  }

  void _bumpGeneration() {
    ref.read(notificationSyncGenerationProvider.notifier).bump();
  }

  int get _currentGeneration => ref.read(notificationSyncGenerationProvider);
}

/// 一轮同步的有效性票（纯值对象）：开工时快照，之后每个不可逆副作用
/// （排通知、弹弹窗、写抑制偏好）之前问一次 [isValid]。
///
/// isValid = 未 disposed（若注入）&& 无写库中间态旗 && 代数未变。三个
/// 事实合成一个谓词是有意的：检查点只有一句话要回答，票的 interface 就
/// 该只有这一句。
class SyncRun {
  SyncRun._(this._guard, this._generation, this._isDisposed);

  final NotificationSyncGuard _guard;
  final int _generation;
  final bool Function()? _isDisposed;

  /// 这轮还作数吗：假了就整轮放弃，等下一轮用最新数据补判。
  bool get isValid =>
      !(_isDisposed?.call() ?? false) &&
      !_guard.isDataResetInFlight &&
      _guard._currentGeneration == _generation;
}
