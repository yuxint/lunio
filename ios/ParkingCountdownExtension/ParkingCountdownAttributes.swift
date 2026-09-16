// 停车倒计时实时活动的静态属性定义（ActivityAttributes）。
//
// 本文件同时编进两个 target（pbxproj 里两条 Sources 引用指向同一份
// 源文件）：Runner（主 App）用它启动/更新活动；ParkingCountdownExtension
// （Widget Extension）用它画活动 UI。两侧各编译一份、互不通信——启动
// 活动时由系统把 attributes 快照交给扩展进程展示，≈ 跨进程共享一份
// 不可变值对象。
//
// 与 Java 类比：attributes ≈ 活动的"主键 + 固定字段"（启动后不可变），
// ContentState ≈ 可变状态字段（只有它能被 update 改写）。
import ActivityKit
import Foundation

/// 停车倒计时实时活动。同一时刻至多一个活动在跑：启动前先结束同类型
/// 旧活动（见 ParkingCountdownActivityController.start）。
@available(iOS 16.2, *)
struct ParkingCountdownAttributes: ActivityAttributes {
  /// 可更新状态只有一个开关位（ADR 0012 决定 3/5：卡片全部"实时"效果
  /// 由系统组件自动走时，App 唯一的更新动作是到点时翻转这个位——
  /// App 在前台由停车卡片时钟感知，不在前台由回前台对账兜底）。
  struct ContentState: Codable & Hashable {
    /// false = 倒计时中（显示剩余时间）；true = 已超时（显示"停车时长"
    /// 正计时，与 App 内卡片同一起点 = 入场时刻，状态转红）。
    var expired: Bool
  }

  /// 入场时刻（倒计时起点，进度条 100% 起点——剩余递减语义）。
  var startedAt: Date

  /// 到点时刻（进度条走空到 0% 的时刻）。启动时的 staleDate 也取它：
  /// 到点后系统自动把锁屏卡片置灰为"已到期"样式，无需 App 推送。
  var endsAt: Date
}
