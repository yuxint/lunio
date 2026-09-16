// 停车倒计时实时活动（iOS Live Activity / 灵动岛）的原生桥。
//
// iOS 16.2+ 由 SceneDelegate.swift 的 lunio/native_live_activities 通道
// 实现（执行体 ParkingCountdownActivityController）；其他平台、低版本、
// 系统实时活动开关关闭等场景一律静默返回"未启用"（false / null），调用
// 方按 ADR 0012 决定 6 降级为"只有通知"，不提示、不报错。
//
// 桥只负责传话：什么时候启/停/对账的编排规则在通知协调器
// （notification_coordinator.dart）。
//
// 与 native_notification_settings 的静态方法风格不同，这里是普通可
// 实例化类（通道可注入）：协调器的测试用假子类覆盖方法即可驱动对账
// 各路径，不必 mock 方法通道。
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 实时活动的系统侧状态快照（对账三态的数据来源）。
class LiveActivitySnapshot {
  const LiveActivitySnapshot({
    required this.running,
    required this.expired,
    this.endsAt,
  });

  /// 是否有本 App 的停车实时活动在跑。
  final bool running;

  /// 活动是否已切到"已超时"正计时形态。
  final bool expired;

  /// 活动记录的到点时刻（毫秒精度；无活动时 null）。
  final DateTime? endsAt;
}

class NativeLiveActivities {
  NativeLiveActivities({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('lunio/native_live_activities');

  final MethodChannel _channel;

  /// 实时活动是 iOS 专属能力：其他平台所有方法自禁用（≈ 接口返回
  /// "不支持"），调用方无需感知平台差异。
  bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  /// 启动/重建停车实时活动（原生侧先结束同类型旧活动再启新的）。
  /// 返回是否启动成功；非 iOS、系统开关关闭、达活动数量上限等返回
  /// false（不抛异常）。
  Future<bool> start({
    required DateTime startedAt,
    required DateTime endsAt,
  }) async {
    if (!_supported) {
      return false;
    }
    try {
      return await _channel.invokeMethod<bool>('start', {
            'startedAtMs': startedAt.millisecondsSinceEpoch.toDouble(),
            'endsAtMs': endsAt.millisecondsSinceEpoch.toDouble(),
          }) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      // 通道尚未随 scene 生命周期装配好（启动早期）时等同"未启用"。
      return false;
    }
  }

  /// 把进行中的活动切到"已超时"正计时形态（到点对账用）。返回是否更新
  /// 成功；无活动在跑时返回 false。
  Future<bool> markExpired() async {
    if (!_supported) {
      return false;
    }
    try {
      return await _channel.invokeMethod<bool>('markExpired') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// 结束全部停车实时活动。任何平台都安全（无活动 = 无操作）。
  Future<bool> stop() async {
    if (!_supported) {
      return false;
    }
    try {
      return await _channel.invokeMethod<bool>('stop') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// 查询活动状态快照；非 iOS / 通道不可用时返回 null（对账据此跳过）。
  Future<LiveActivitySnapshot?> status() async {
    if (!_supported) {
      return null;
    }
    try {
      final raw = await _channel.invokeMethod<Object?>('status');
      if (raw is! Map<Object?, Object?> || raw['running'] != true) {
        return const LiveActivitySnapshot(running: false, expired: false);
      }
      final endsAtMs = raw['endsAtMs'];
      return LiveActivitySnapshot(
        running: true,
        expired: raw['expired'] == true,
        endsAt: endsAtMs is num
            ? DateTime.fromMillisecondsSinceEpoch(endsAtMs.toInt())
            : null,
      );
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}
