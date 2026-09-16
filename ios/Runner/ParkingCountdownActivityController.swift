// 停车倒计时实时活动的启停/对账执行体（仅 iOS 16.2+ 生效，staleDate
// 需要 16.2，见 ADR 0012 决定 7 的修订）。
//
// 属于 Runner target，被 SceneDelegate 的 lunio/native_live_activities
// 通道调用；Dart 侧桥接在 lib/core/platform/native_live_activities.dart。
// ActivityKit 的活动由主 App 进程创建、系统托管展示（Widget Extension
// 只负责画），所以启动/更新/结束都在这里做。
//
// 后台保活纪律（2026-09-16 真机调试后确立）：request/end/update 的同步
// 返回 ≠ 与系统守护进程的异步握手完成，App 随即退后台会被挂起、握手
// 半路夭折。启停/翻转一律经 runKeptAlive 包进 beginBackgroundTask 保活
// 执行。保活只对"已经在跑"的工作有效、做不到定时唤醒，所以后台到点
// 翻转仍靠回前台对账兜底（ADR 0012 决定 5 不变）。
//
// 静默降级约定（ADR 0012 决定 6）：用户在系统设置里关了本 App 的实时
// 活动、活动数量到上限等场景下 request 会抛错——统一 catch 后以 false
// 回调，Dart 侧不弹提示、不报错，降级为"只有通知"。
import ActivityKit
import Foundation
import UIKit

@available(iOS 16.2, *)
enum ParkingCountdownActivityController {
  /// 启动（重建）停车实时活动：先结束同类型旧活动、确认收场后再启
  /// 新的——保存新目标时间 = 换内容不换位，避免重建瞬间同屏两张卡。
  /// 整条"清场 + 重建"链包在后台保活里执行，完成后在主线程回调是否
  /// 启动成功（点完立即回桌面也不至于握手半路夭折、活动没建成）。
  static func start(
    startedAt: Date,
    endsAt: Date,
    completion: @escaping (Bool) -> Void
  ) {
    runKeptAlive("parking-live-activity-start", completion) { settle in
      stopActivities {
        request(
          startedAt: startedAt,
          endsAt: endsAt,
          completion: settle
        )
      }
    }
  }

  /// 把进行中的活动切到"已超时"正计时形态（到点时由 App 侧感知调用：
  /// 前台来自停车卡片时钟的边界触发，回前台来自对账，ADR 0012 决定 5）。
  /// 更新后在主线程回调是否成功；没有活动在跑时回调 false。
  static func markExpired(completion: @escaping (Bool) -> Void) {
    runKeptAlive("parking-live-activity-expire", completion) { settle in
      guard let activity = currentActivity() else {
        settle(false)
        return
      }
      let content = ActivityContent(
        state: ParkingCountdownAttributes.ContentState(expired: true),
        staleDate: nil
      )
      Task {
        await activity.update(content)
        // settle 内部统一主线程排队回包（Task 无 actor 隔离，await 恢复
        // 后落在全局并发执行器上），FlutterResult 的主线程纪律由它满足。
        settle(true)
      }
    }
  }

  /// 结束本 App 全部停车实时活动，**全部确认撤场后**才回调（真机反馈：
  /// 随即退后台时无保活的 end 会半路夭折，残卡卡在岛上等下次对账才撤
  /// ——除确认收场外，现在叠加后台保活，见 runKeptAlive）。
  static func stopAll(completion: @escaping () -> Void) {
    // 撤场动作本身没有布尔语义（通道侧恒回 true），settle 的取值只是
    // 保活收场的载体，completion 不消费它。
    runKeptAlive("parking-live-activity-stop", { _ in completion() }) { settle in
      stopActivities { settle(false) }
    }
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

  /// 在系统授予的后台运行时间里执行工作：进入时申请后台保活，工作完成
  /// 或保活到期都经 settle 收场——completion 恰好回一次（到期时工作没
  /// 跑完按 false 回包，与"未启用/未完成静默降级"同口径），收场同时
  /// endBackgroundTask（要求主线程，expiration 回调线程系统没承诺，
  /// settle 统一主线程排队，顺带满足 FlutterResult 的主线程纪律）。
  private static func runKeptAlive(
    _ name: String,
    _ completion: @escaping (Bool) -> Void,
    work: @escaping (@escaping (Bool) -> Void) -> Void
  ) {
    var task = UIBackgroundTaskIdentifier.invalid
    var settled = false
    let settle: (Bool) -> Void = { value in
      DispatchQueue.main.async {
        guard !settled else {
          return
        }
        settled = true
        completion(value)
        if task != .invalid {
          UIApplication.shared.endBackgroundTask(task)
          task = .invalid
        }
      }
    }
    // 通道分发已在主线程，task/settled 的读写都在 main queue 串行发生，
    // 无并发写。
    task = UIApplication.shared.beginBackgroundTask(withName: name) {
      settle(false)
    }
    work(settle)
  }

  /// 实际撤场（无保活）：全部活动确认 end 后回调。start（外层已保活）
  /// 与 stopAll（自带保活）共用的底层动作。
  private static func stopActivities(completion: @escaping () -> Void) {
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
