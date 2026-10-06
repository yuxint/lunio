// 重入防护小模块：一组"执行中标志 + pending 重跑"的协议实现（R3 丢
// 更新修复语义的单一事实来源，2026-10-06 从通知同步控制器的私有
// _GuardedOp 收编为 reminders 域共享模块）。≈ Java 并发里一个极小的
// 协作工具类——语义上接近"tryAcquire 失败就登记、release 时若有登记
// 就补跑一轮"的单槽门闩，只是全部跑在 Dart 单线程事件循环上、无锁，
// 重入只可能发生在 await 挂起点之后。
//
// 在 App 中的位置：reminders 域内两个异步协调器共用——通知同步控制器
// （notification_sync_controller.dart：系统通知重排、应用内弹窗检查两
// 条路径各一实例）与桌面小组件快照控制器（widget_snapshot_controller.dart：
// 快照写入一实例；此前手抄 _writing/_pending 标志位、语义要人肉与注释
// 核对，正是收编动机）。第三个需要"执行中来了新请求不丢弃、本轮结束
// 用最新数据重跑"的异步协调器出现时直接复用本模块，不再手抄标志位。
//
// 与通知同步守卫（notification_sync_guard.dart）的边界：那边管"这轮还
// 作数吗"（同步代数 + 写库中间态旗 + disposed，合成一张 SyncRun 票），
// 这边只管"执行中来新请求怎么办"（记 pending、本轮结束重跑）——两层
// 协议有意分开（守卫模块文件头第 4 层说明），本模块不进守卫模块。
//
// isDisposed 的职责边界（防第三消费者踩坑）：只参与"记不记 pending"与
// "重不重跑"两个决策；enter() 在不 busy 时无论销毁与否都放行（返回
// true），"本轮要不要继续执行"的销毁检查归调用方——通知侧在守卫票
// run.isValid，快照侧在入口与 await 后自检。

/// 重入保护（R3 语义）：执行中又来新请求时不丢弃，记 pending；本轮
/// [exit]（finally 配对调用）时若来过新请求且未销毁，用最新数据强制
/// 重跑一轮（重跑动作由 [onRerun] 定义——调用方各自清自己的签名/重读
/// 数据）。销毁后不再记 pending、不再重跑。
///
/// 用法骨架（enter 返回 false 直接返回；执行体整体包 try/finally——
/// 早退路径也要走 exit 复位 busy，否则防护永久卡死）：
/// ```dart
/// if (_disposed || !_op.enter()) return;
/// try {
///   ... // 异步执行体，不可逆副作用前自行做销毁/作数检查
/// } finally {
///   _op.exit();
/// }
/// ```
class GuardedOp {
  GuardedOp({required this.isDisposed, required this.onRerun});

  /// 调用方是否已销毁：注入谓词而非存 bool——dispose 发生在持有点上，
  /// 记 pending / 重跑前各问一次最新值。职责边界见文件头。
  final bool Function() isDisposed;

  /// pending 重跑动作：本轮 [exit] 时来过新请求则同步调用一次，调用方
  /// 在此用最新数据重跑（通常先清自己的签名/记账再触发入口）。返回值
  /// 语义上忽略（fire-and-forget），重跑轮自身的重入仍由本实例把守。
  final void Function() onRerun;

  bool _busy = false;
  bool _pending = false;

  /// 开始一轮：已在执行中则记 pending（销毁后不记）并返回 false，调用
  /// 方直接返回；空闲则置 busy 并返回 true。
  bool enter() {
    if (_busy) {
      _pending = !isDisposed();
      return false;
    }
    _busy = true;
    return true;
  }

  /// 结束一轮（配对 finally 调用）：执行中标志复位；期间来过新请求且
  /// 未销毁则清 pending 并强制重跑一轮。
  void exit() {
    _busy = false;
    if (_pending && !isDisposed()) {
      _pending = false;
      onRerun();
    }
  }
}
