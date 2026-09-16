// 停车倒计时实时活动的 UI：锁屏卡片 + 灵动岛（行式对照风格，样式 A，
// 2026-09-15 用户从三套 PROTOTYPE 变体中拍板定稿）。
//
// 属于 ParkingCountdownExtension target，纯 SwiftUI。所有"实时"效果
// （倒计时数字跳动、进度条走动）都由系统组件自动驱动（Text / ProgressView
// 的 timerInterval 系列构造器），本进程不跑任何定时器、不接收任何更新
// 推送——即 ADR 0012 的"零更新渲染"。App 侧唯一的形态控制是到点时
// 翻转 expired（切"停车时长"正计时 + 状态转红；App 在前台由卡片时钟
// 感知，不在前台由回前台对账兜底）。
//
// 布局口径（ADR 0012 决定 4 + 定稿修订）：锁屏与灵动岛展开态同构——
// 主行三层 ZStack：最左 P 图标 + 文案（"免费时长"，到点后变红字
// "已停时长"——即 App 内"停车时长"正计时的口径），计时数字由
// multilineTextAlignment 画在行正中（金黄），最右状态（"停车中"，到
// 点后变红字"已超时"）；下方一行剩余递减进度条（到点走空 0%，左右
// 留出岛圆角安全边距）；不放开始/结束钟点，不放车辆名。到点正计时
// 从入场时刻起算，与 App 内"停车时长"数值一致。配色借鉴 live_island
// 示例：青色图标 + 金黄计时 + 蓝色进度条 + 黑底锁屏。
import ActivityKit
import SwiftUI
import WidgetKit

/// Widget Extension 入口：本扩展只承载停车倒计时一种实时活动。
@main
struct ParkingCountdownWidgetBundle: WidgetBundle {
  var body: some Widget {
    ParkingCountdownActivityWidget()
  }
}

/// 停车倒计时活动的锁屏卡片与灵动岛呈现配置。
struct ParkingCountdownActivityWidget: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: ParkingCountdownAttributes.self) { context in
      // 锁屏 / 通知中心卡片（黑底，无灵动岛硬件的设备只呈现这一处）。
      // 主行与灵动岛展开态同构：最左 P 图标 + 文案，时间居中，最右
      // 状态；下方一行剩余进度条。
      VStack(spacing: 12) {
        MainRow(
          attributes: context.attributes,
          state: context.state,
          timeFont: .title.bold(),
          secondaryFont: .subheadline
        )
        ParkingProgressBar(
          attributes: context.attributes,
          color: .blue,
          height: 8
        )
        .padding(.horizontal, 8)
      }
      .padding(16)
      .activityBackgroundTint(Color.black.opacity(0.8))
    } dynamicIsland: { context in
      DynamicIsland {
        // 展开态整行收进 bottom 区：leading/center/trailing 三个区域
        // 各自有宽度与对齐规则（文案被截、状态折行、时间偏位，真机
        // 反馈样式乱），自定义 HStack 才能按"图标+文案 | 时间 | 状态"
        // 精确排布。
        DynamicIslandExpandedRegion(.bottom) {
          VStack(spacing: 10) {
            MainRow(
              attributes: context.attributes,
              state: context.state,
              timeFont: .title3.bold()
            )
            ParkingProgressBar(
              attributes: context.attributes,
              color: .blue,
              height: 6
            )
            .padding(.horizontal, 12)
          }
          .padding(.top, 6)
        }
      } compactLeading: {
        Image(systemName: "parkingsign.circle.fill")
          .foregroundStyle(.cyan)
      } compactTrailing: {
        RemainingTimeText(
          attributes: context.attributes,
          state: context.state
        )
        .font(.caption2.monospacedDigit())
        .foregroundStyle(.yellow)
        .frame(width: 40)
      } minimal: {
        Image(systemName: "parkingsign.circle.fill")
          .foregroundStyle(.cyan)
      }
    }
  }
}

// MARK: - 共用部件

/// 主行（锁屏与灵动岛展开态同构）：最左 P 图标 + 文案，时间居中，
/// 最右状态。
///
/// 必须用三层 ZStack 而不是 HStack：计时 Text 是贪婪布局、且会按最
/// 大可能表示预留宽框、数字靠左画在框内——HStack（含定宽框）里时间
/// 永远偏左、还会挤压文案截断（真机截图确认）。分层后时间层独占整
/// 行、由 `multilineTextAlignment(.center)` 让系统把数字画在行中心，
/// 文案/状态两层各自贴边浮在两侧，互不挤压。
private struct MainRow: View {
  let attributes: ParkingCountdownAttributes
  let state: ParkingCountdownAttributes.ContentState
  let timeFont: Font
  var secondaryFont: Font = .caption

  var body: some View {
    ZStack {
      RemainingTimeText(attributes: attributes, state: state)
        .font(timeFont)
        .monospacedDigit()
        .foregroundStyle(.yellow)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)

      HStack(spacing: 6) {
        Image(systemName: "parkingsign.circle.fill")
          .foregroundStyle(.cyan)
        Text(state.expired ? "已停时长" : "免费时长")
          .font(secondaryFont)
          .foregroundStyle(
            state.expired ? ParkingThemeColors.danger : .gray
          )
      }
      .lineLimit(1)
      .frame(maxWidth: .infinity, alignment: .leading)

      Text(state.expired ? "已超时" : "停车中")
        .font(secondaryFont)
        .foregroundStyle(
          state.expired ? ParkingThemeColors.danger : .white
        )
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
  }
}

/// 剩余/正计时文本。两种形态都是系统自动走时的 Text(timerInterval:)：
/// 倒计时到 0 自动停在 00:00；超时形态从入场时刻起算总时长（App 内
/// 卡片"停车时长"同口径，两侧数值一致）。本视图会按最大可能表示预留
/// 宽度、数字靠左画在预留框内，居中交给调用方处理——主行走 MainRow
/// 的三层 ZStack 方案，灵动岛紧凑尾位（compactTrailing）用定宽框。
private struct RemainingTimeText: View {
  let attributes: ParkingCountdownAttributes
  let state: ParkingCountdownAttributes.ContentState

  var body: some View {
    if state.expired {
      Text(
        timerInterval: attributes.startedAt...Date.distantFuture,
        countsDown: false
      )
    } else {
      Text(
        timerInterval: attributes.startedAt...attributes.endsAt,
        countsDown: true
      )
    }
  }
}

/// 剩余递减进度条：从满条向 0% 自动走空（100% → 0% = 到点时刻），
/// 到点后停在空条——"剩余"语义与 App 内进度环方向一致。label /
/// currentValueLabel 显式留空——timerInterval 构造器默认会在两端画
/// 时间刻度，不符合"只留一根条"的设计。
private struct ParkingProgressBar: View {
  let attributes: ParkingCountdownAttributes
  let color: Color
  let height: CGFloat

  var body: some View {
    ProgressView(
      timerInterval: attributes.startedAt...attributes.endsAt,
      countsDown: true,
      label: { EmptyView() },
      currentValueLabel: { EmptyView() }
    )
    .progressViewStyle(.linear)
    .tint(color)
    .frame(height: height)
  }
}

/// 到点警示红（DESIGN.md LunioTokens danger 0xffef4444 的按值副本，
/// 扩展进程拿不到 Flutter 主题——改 token 时两处一起改）。
private enum ParkingThemeColors {
  static let danger = Color(red: 0xef / 255, green: 0x44 / 255, blue: 0x44 / 255)
}
