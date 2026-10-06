// 桌面小组件快照同步控制器：把"提醒数据变化 → 重写小组件快照"从
// 业务链路里独立出来的轻量协调器（≈ Spring 的一个监听器 @Component，
// 生命周期挂在主壳层 State 上，ADR 0013）。
//
// 与 NotificationSyncController 的分工：那边管"通知域"（重排系统通知、
// 弹应用内提醒），这边管"桌面呈现"——两边都 watch 同一组数据上游，
// 互不依赖、互不触发。放监听器而不是塞进保存动作层（ADR 0007）的
// 理由：快照重写是所有数据写点的统一下游，逐个函数收尾要记 14 处，
// 监听器一处收齐，动作层零改动；冷启动首拍顺带自愈陈旧快照。
//
// 触发方式：start() 对应用车辆数据束 ref.listenManual
// （fireImmediately: true，车/项目/记录/生效今天四件套一并触发），
// 数据一变（或首拍就绪）就组装快照并经原生桥写入。loading 中的上游
// 当"未就绪"跳过，等就绪那一拍补写。
//
// 防重复/防竞态（比通知同步简单——快照写入幂等、无弹窗无权限链）：
//  - 相同 JSON 不重写（跨零点失效等触发不产生重复 I/O）；
//  - 执行中又有新触发不丢弃：置 pending，本轮结束后用最新数据重跑
//    一轮——重入防护经 reminders 域共享模块 guarded_op.dart 的 GuardedOp
//    （2026-10-06 起与通知同步控制器同一份实现，不再手抄标志位）；
//  - _disposed 检查：await 之后确认控制器还活着才继续。
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import 'guarded_op.dart';
import 'widget_snapshot.dart';

/// 快照同步控制器。由 AppShell 的 State 创建/销毁（同
/// NotificationSyncController 的接线方式）。
class WidgetSnapshotController {
  WidgetSnapshotController({required this.ref, required this.isAlive});

  /// 主壳层的 WidgetRef（读 provider、listenManual）。
  final WidgetRef ref;

  /// 主壳层是否仍挂载（mounted 的回调版）。
  final bool Function() isAlive;

  /// listenManual 订阅句柄（dispose 时统一关闭）。
  final List<ProviderSubscription> _subscriptions = [];

  /// 上次写入的快照 JSON（相同内容不重写）。
  String? _lastJson;

  /// 快照写入的重入防护（R3 同款）：执行中来了新触发不丢弃，本轮
  /// finally 里重跑一轮 [syncSnapshot]——重新读数据束重组件比对，内容
  /// 没变自然不写；重跑动作即"用最新数据重同步快照"。disposed 后不记
  /// pending、不重跑（协议语义见 guarded_op.dart 文件头）。
  late final GuardedOp _write = GuardedOp(
    isDisposed: () => _disposed,
    onRerun: () => syncSnapshot(),
  );

  /// 控制器是否已销毁。
  bool _disposed = false;

  /// 启动：订阅应用车辆数据束（providers.dart 的 appliedCarBoardProvider，
  /// 车/项目/记录/生效今天四件套，2026-10-01 起四路由它一并触发），
  /// 任何变化（含首拍）都触发 [syncSnapshot]。AppShell initState 调用。
  void start() {
    _subscriptions.add(
      ref.listenManual(
        appliedCarBoardProvider,
        (_, _) => syncSnapshot(),
        fireImmediately: true,
      ),
    );
  }

  /// 销毁：AppShell dispose 调用。关闭订阅；置 _disposed 后所有在途
  /// 写入在下一个 await 检查点自动放弃。
  void dispose() {
    _disposed = true;
    for (final subscription in _subscriptions) {
      subscription.close();
    }
    _subscriptions.clear();
  }

  /// 同步入口：数据束（车/项目/记录/生效今天四件套）未就绪就跳过
  /// （等就绪那一拍的 listenManual 再补）；数据就绪后组装快照，
  /// 内容有变化才经原生桥写入。入口先拦 disposed 再领重入票（GuardedOp
  /// 的 isDisposed 只管 pending 记账与重跑决策，不 busy 时销毁与否都
  /// 放行——是否继续由本方法自定），整个执行体包 try/finally 保证
  /// 早退路径也配对 exit。
  Future<void> syncSnapshot() async {
    if (_disposed || !_write.enter()) {
      return;
    }
    try {
      final board = ref
          .read(appliedCarBoardProvider)
          .maybeWhen(data: (value) => value, orElse: () => null);
      if (board == null) {
        return;
      }
      // 车辆为 null（还没建车）是合法输入：快照按 noCar 空态组装。
      final json = buildWidgetSnapshotJson(
        car: board.car,
        items: board.items,
        records: board.records,
        today: board.today,
      );
      if (json == _lastJson) {
        return;
      }
      final delivered = await ref
          .read(nativeWidgetsProvider)
          .updateSnapshot(json);
      if (_disposed) {
        return;
      }
      // 送达才记账：失败（非 iOS/系统侧异常）不缓存，下个触发点重试。
      if (delivered) {
        _lastJson = json;
      }
    } finally {
      // 执行中来过新触发（被置 pending）时，这里用最新数据重跑一轮
      // （重跑轮自身的重入仍由同一实例把守）。
      _write.exit();
    }
  }
}
