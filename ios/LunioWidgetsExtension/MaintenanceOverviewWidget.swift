// 保养提醒概览桌面小组件（ADR 0013）：时间线组装 + 小/中两档渲染。
//
// 数据来源只有 App Group 里的快照（LunioWidgetSnapshotStore）：本进程
// 读不到 App 的数据库与偏好，快照是唯一数据——这里不做任何业务计算，
// 只做"快照条目 → 本地午夜时间轴"的映射与纯渲染。预生成窗口内的
// 条目由系统到点自动换页（App 不在也翻页），窗口耗尽停在最后一条
// 已知数据等 App 重写。
//
// 视觉约定：跟随系统深浅色（背景 systemBackground / 文字语义灰阶），
// 状态语义色是 DESIGN.md LunioTokens 的常量副本（照实时活动 ADR 0012
// 五轮先例）；布局对齐产品紧凑偏好——不放说明性小字。
// 点击小组件经 widgetURL（lunio:///reminders，scheme 注册在 Runner 的
// Info.plist）唤起 App 落提醒页——冷启默认首屏本就是提醒页，深链实际
// 补的是热启回跳（2026-09-16 修订，推翻 ADR 0013 初版"不接深链"）。
import WidgetKit
import SwiftUI

// MARK: - 时间线

struct MaintenanceEntry: TimelineEntry {
    /// 本条目开始展示的时刻（对应快照条目的本地午夜）。
    let date: Date

    /// 解码成功的快照；无快照 / 契约版本不符为 nil。
    let snapshot: LunioWidgetSnapshot?

    /// 本条目应渲染的日数据；无快照或空态（entries 为空）时 nil。
    let day: LunioWidgetSnapshot.DayEntry?
}

struct MaintenanceOverviewProvider: TimelineProvider {
    func placeholder(in context: Context) -> MaintenanceEntry {
        Self.sampleEntry(date: Date())
    }

    /// 小组件图库预览：优先真实快照，没有就渲染样本。
    func getSnapshot(in context: Context, completion: @escaping (MaintenanceEntry) -> Void) {
        completion(currentEntry() ?? Self.sampleEntry(date: Date()))
    }

    /// 时间线组装：快照条目 → 本地午夜条目，锚点早于今天的（陈旧快照）
    /// 跳过；窗口耗尽停在最后一条已知数据、半天兜底重试（数据本身要
    /// 等 App 重写，重试只为跟随系统节流的低成本轮询）。
    func getTimeline(in context: Context, completion: @escaping (Timeline<MaintenanceEntry>) -> Void) {
        let calendar = Calendar.current
        let now = Date()
        guard let snapshot = LunioWidgetSnapshot.decodeCurrent(
            json: LunioWidgetSnapshotStore.loadJSON()
        ) else {
            completion(Timeline(
                entries: [MaintenanceEntry(date: now, snapshot: nil, day: nil)],
                policy: .after(Self.retryDate(now: now, calendar: calendar))
            ))
            return
        }
        let startOfToday = calendar.startOfDay(for: now)
        let applicable = snapshot.entries.compactMap { day -> MaintenanceEntry? in
            guard let date = Self.localMidnight(day.date, calendar: calendar),
                  date >= startOfToday else {
                return nil
            }
            return MaintenanceEntry(date: date, snapshot: snapshot, day: day)
        }
        if applicable.isEmpty {
            completion(Timeline(
                entries: [MaintenanceEntry(date: now, snapshot: snapshot, day: snapshot.entries.last)],
                policy: .after(Self.retryDate(now: now, calendar: calendar))
            ))
            return
        }
        // 窗口内按日翻页；最后一条走完后系统再次询问（.atEnd），那时
        // applicable 已为空，自动落入上面的"窗口耗尽"分支。
        completion(Timeline(entries: applicable, policy: .atEnd))
    }

    // ---- 工具 ----

    /// 当前时刻应展示的条目（getSnapshot 用）：第一个今天及以后的条目，
    /// 没有则退回最后一条；整份无条目时 day 为 nil（视图按空态渲染）。
    private func currentEntry() -> MaintenanceEntry? {
        guard let snapshot = LunioWidgetSnapshot.decodeCurrent(
            json: LunioWidgetSnapshotStore.loadJSON()
        ) else {
            return nil
        }
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        let applicable = snapshot.entries.compactMap { day -> MaintenanceEntry? in
            guard let date = Self.localMidnight(day.date, calendar: calendar),
                  date >= startOfToday else {
                return nil
            }
            return MaintenanceEntry(date: date, snapshot: snapshot, day: day)
        }
        if let first = applicable.first {
            return first
        }
        return MaintenanceEntry(date: Date(), snapshot: snapshot, day: snapshot.entries.last)
    }

    private static func sampleEntry(date: Date) -> MaintenanceEntry {
        let sample = LunioWidgetSnapshot(
            schemaVersion: LunioWidgetSnapshotStore.supportedSchemaVersion,
            carName: "丰田 卡罗拉",
            mileageKm: 32500,
            emptyState: nil,
            entries: [
                .init(
                    date: "2026-09-16",
                    overview: "超期 1 / 到期 1",
                    items: [
                        .init(
                            name: "刹车油", status: "danger", badge: "超期",
                            percentText: "104%", detail: "时间：已超 5天"
                        ),
                        .init(
                            name: "机油", status: "warning", badge: "到期",
                            percentText: "96%", detail: "里程：距离下次约 800公里"
                        ),
                    ]
                )
            ]
        )
        return MaintenanceEntry(date: date, snapshot: sample, day: sample.entries.first)
    }

    /// 兜底重试时刻：半天后（预算制下约耗 2 次/天，远低于系统配额）。
    private static func retryDate(now: Date, calendar: Calendar) -> Date {
        calendar.date(byAdding: .hour, value: 12, to: now) ?? now.addingTimeInterval(43_200)
    }

    /// 解析 yyyy-MM-dd 为本地午夜时刻（快照日期格式见 widget_snapshot.dart）。
    private static func localMidnight(_ text: String, calendar: Calendar) -> Date? {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else {
            return nil
        }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}

// MARK: - 小组件声明

struct MaintenanceOverviewWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MaintenanceOverview", provider: MaintenanceOverviewProvider()) { entry in
            MaintenanceOverviewView(entry: entry)
        }
        .configurationDisplayName("保养提醒")
        .description("当前车辆最紧急的保养项目，不打开 App 也能看到车况")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - 视图

struct MaintenanceOverviewView: View {
    @Environment(\.widgetFamily) private var family
    let entry: MaintenanceEntry

    var body: some View {
        Group {
            if let day = entry.day {
                if family == .systemSmall {
                    SmallOverviewView(day: day)
                } else {
                    MediumOverviewView(carName: entry.snapshot?.carName, day: day)
                }
            } else {
                EmptyHintView(emptyState: entry.snapshot?.emptyState)
            }
        }
        // 深链落提醒页的链路与修订出处见文件头；这里挂根视图一处，
        // 小/中两档与空态全覆盖。URL 必须保持 lunio:///reminders 三斜杠
        // 形态——go_router 只匹配 path，简化成双斜杠会匹配失败。
        .widgetURL(URL(string: "lunio:///reminders"))
        .modifier(WidgetContainerBackground())
    }
}

/// iOS 17 起必须显式声明容器背景（系统据此管理全屏/待机模式边距）；
/// 16.x 不声明即走系统默认背景与边距。
struct WidgetContainerBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            content.containerBackground(for: .widget) {
                Color(uiColor: .systemBackground)
            }
        } else {
            content
        }
    }
}

/// 小尺寸：概览一行 + top4 密集单行（名称 + 百分比 + 徽章，无详情；
/// 2026-09-16 原型拍板 S2——4 行均分剩余高度，把上下空白吃掉）。
private struct SmallOverviewView: View {
    let day: LunioWidgetSnapshot.DayEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(day.overview)
                // 2026-09-24 二轮提档：小组件是远距离一瞥的表面，数字档
                // 全面上调（9→10→11），最小不低于 11。
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(day.overviewColor)
                .lineLimit(1)
            ForEach(Array(day.items.prefix(4).enumerated()), id: \.offset) { _, item in
                HStack(spacing: 3) {
                    Text(item.name)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 3)
                    Text(item.percentText)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(item.badge)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(LunioStatusColor.color(for: item.status))
                }
                // 每行均分剩余高度，行数不足 4 时也不留成块空白。
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
    }
}

/// 中尺寸：概览头部 + top3 两行项目行（2026-09-16 原型拍板 M3，同日
/// 反馈去掉色块底色）——每个项目两行：名称/百分比/徽章 + 详情，
/// 卡片间距保留、无底色。
private struct MediumOverviewView: View {
    let carName: String?
    let day: LunioWidgetSnapshot.DayEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(carName ?? "保养提醒")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(day.overview)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(day.overviewColor)
                    .lineLimit(1)
            }
            .padding(.bottom, 6)
            ForEach(Array(day.items.prefix(3).enumerated()), id: \.offset) { _, item in
                // 2026-09-24 对齐修正：右侧百分比/状态徽章与左侧"名称 +
                // 详情"两行整体垂直居中（原来挂在名称行上，两行内容头
                // 重脚轻不协调）。
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.name)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                        Text(item.detail)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Text(item.percentText)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(item.badge)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(LunioStatusColor.color(for: item.status))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .frame(maxWidth: .infinity, alignment: .leading)
                // 卡片在头部之下均分剩余高度（上下贴边、中间等距）。
                .frame(maxHeight: .infinity, alignment: .center)
            }
        }
    }
}

/// 概览文案着色：取最紧急一行（首行）的状态色——有超期/到期一眼可见。
private extension LunioWidgetSnapshot.DayEntry {
    var overviewColor: Color {
        items.first.map { LunioStatusColor.color(for: $0.status) } ?? .secondary
    }
}

/// 空态 / 无快照：图标 + 一句话引导（文案对应快照 emptyState 键）。
private struct EmptyHintView: View {
    /// 快照里的空态键；nil 表示无快照（还没打开过 App 或版本不符）。
    let emptyState: String?

    private var title: String {
        switch emptyState {
        case "noCar":
            return "还没有车辆"
        case "noRecords":
            return "还没有保养记录"
        case "noItems":
            return "还没有保养项目"
        default:
            return "打开 Lunio 同步车况"
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "wrench.and.screwdriver")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
            Text("打开 App 查看详情")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 语义色常量副本

/// 状态键 → 语义色。色值是 DESIGN.md LunioTokens success/warning/danger
/// 的常量副本（浅深主题同值），扩展进程读不到 Flutter 主题——照实时
/// 活动 ADR 0012 五轮的先例。
enum LunioStatusColor {
    static func color(for status: String) -> Color {
        switch status {
        case "warning":
            // #F59E0B（到期/黄）
            return Color(red: 245 / 255, green: 158 / 255, blue: 11 / 255)
        case "danger":
            // #EF4444（超期/红）
            return Color(red: 239 / 255, green: 68 / 255, blue: 68 / 255)
        default:
            // #22C55E（正常/绿）
            return Color(red: 34 / 255, green: 197 / 255, blue: 94 / 255)
        }
    }
}
