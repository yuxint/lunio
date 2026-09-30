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
//  - 执行中又有新触发 → 置 pending，本轮结束后用最新数据重跑一轮；
//  - _disposed 检查：await 之后确认控制器还活着才继续。
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
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

  /// 快照写入是否在执行中（防并发重入）。
  bool _writing = false;

  /// 执行中又有新触发时置 true：本轮结束后用最新数据重跑一轮。
  bool _pending = false;

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
  /// 内容有变化才经原生桥写入。
  Future<void> syncSnapshot() async {
    if (_writing || _disposed) {
      _pending = !_disposed;
      return;
    }
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
    _writing = true;
    try {
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
      _writing = false;
      if (_pending && !_disposed) {
        _pending = false;
        await syncSnapshot();
      }
    }
  }
}
