// 停车倒计时实时活动的启停/对账执行体（仅 iOS 16.2+ 生效，staleDate
// 需要 16.2，见 ADR 0012 决定 7 的修订）。
//
// 属于 Runner target，被 SceneDelegate 的 lunio/native_live_activities
// 通道调用；Dart 侧桥接在 lib/core/platform/native_live_activities.dart。
// ActivityKit 的活动由主 App 进程创建、系统托管展示（Widget Extension
// 只负责画），所以启动/更新/结束都在这里做。
//
// 静默降级约定（ADR 0012 决定 6）：用户在系统设置里关了本 App 的实时
// 活动、活动数量到上限等场景下 request 会抛错——统一 catch 后以 false
// 回调，Dart 侧不弹提示、不报错，降级为"只有通知"。
import ActivityKit
import Foundation

@available(iOS 16.2, *)
enum ParkingCountdownActivityController {
  /// 启动（重建）停车实时活动。先结束同类型旧活动、确认收场后再启新
  /// 的——保存新目标时间 = 换内容不换位，避免重建瞬间同屏两张卡。
  /// 结束后在主线程回调是否启动成功。
  static func start(
    startedAt: Date,
    endsAt: Date,
    completion: @escaping (Bool) -> Void
  ) {
    stopAll {
      request(
        startedAt: startedAt,
        endsAt: endsAt,
        completion: completion
      )
    }
  }

  /// 把进行中的活动切到"已超时"正计时形态（到点时由 App 侧感知调用：
  /// 前台来自停车卡片时钟的边界触发，回前台来自对账，ADR 0012 决定 5）。
  /// 更新后在主线程回调是否成功；没有活动在跑时回调 false。
  static func markExpired(completion: @escaping (Bool) -> Void) {
    guard let activity = currentActivity() else {
      completion(false)
      return
    }
    let content = ActivityContent(
      state: ParkingCountdownAttributes.ContentState(expired: true),
      staleDate: nil
    )
    Task {
      await activity.update(content)
      // completion 就是 FlutterResult，必须回主线程：Task 无 actor 隔离，
      // await 恢复后落在全局并发执行器上（与 stopAll 的
      // group.notify(queue: .main) 同一纪律）。
      DispatchQueue.main.async {
        completion(true)
      }
    }
  }

  /// 结束本 App 全部停车实时活动，**全部确认撤场后**才回调（真机反馈：
  /// fire-and-forget 的 end 在 App 随即退后台时可能没跑完，卡在岛上等
  /// 下次对账才撤——Dart 侧 await 返回时必须已经撤干净）。
  static func stopAll(completion: @escaping () -> Void) {
    let existing = Activity<ParkingCountdownAttributes>.activities
    guard !existing.isEmpty else {
      completion()
      return
    }
    let group = DispatchGroup()
    for activity in existing {
      group.enter()
      Task {
        await activity.end(nil, dismissalPolicy: .immediate)
        group.leave()
      }
    }
    group.notify(queue: .main, execute: completion)
  }

  /// 当前活动的状态快照（Dart 侧对账三态的数据来源）：
  /// running = 是否有活动在跑；expired = 是否已切正计时形态；
  /// endsAtMs = 活动记录的到点时刻（毫秒时间戳，活动在跑才有）。
  static func status(completion: @escaping ([String: Any]) -> Void) {
    guard let activity = currentActivity() else {
      completion(["running": false])
      return
    }
    completion([
      "running": true,
      "expired": activity.content.state.expired,
      "endsAtMs": activity.attributes.endsAt.timeIntervalSince1970 * 1000,
    ])
  }

  /// 实际发起启动。request 同步抛错（实时活动被系统关闭 / 超上限等），
  /// catch 后按静默降级约定回调 false。
  private static func request(
    startedAt: Date,
    endsAt: Date,
    completion: @escaping (Bool) -> Void
  ) {
    let attributes = ParkingCountdownAttributes(
      startedAt: startedAt,
      endsAt: endsAt
    )
    let content = ActivityContent(
      state: ParkingCountdownAttributes.ContentState(expired: false),
      staleDate: endsAt
    )
    do {
      _ = try Activity.request(
        attributes: attributes,
        content: content,
        pushType: nil
      )
      completion(true)
    } catch {
      completion(false)
    }
  }

  /// 取当前在跑的停车活动（同一时刻至多一个：启动前会先清场）。
  private static func currentActivity() -> Activity<
    ParkingCountdownAttributes
  >? {
    Activity<ParkingCountdownAttributes>.activities.first
  }
}
