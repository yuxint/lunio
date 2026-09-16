// 小组件快照共享存取与契约模型（ADR 0013）。
//
// 本文件以显式 target membership 同时编进 Runner 与 LunioWidgetsExtension
// 两个 target（照 ParkingCountdownAttributes.swift 的共享先例）：Runner
// 侧经 lunio/native_widgets 通道写入快照，扩展侧渲染时读取——App Group
// 是两侧唯一的共享存储（App 进程与小组件进程互不可见各自的沙盒）。
//
// 契约对齐 Dart 侧 widget_snapshot.dart 的 buildWidgetSnapshotJson；
// 字段语义与版本演进规则见该文件与 docs/adr/0013。
// Java 类比：一份共享 DTO + 一个基于 App Group 的简单 KV 存取门面。
import Foundation

enum LunioWidgetSnapshotStore {
    /// App Group 标识（与 Runner / LunioWidgetsExtension 两个 target 的
    /// entitlements 对齐）。suite 名跟 bundle id 走：上架换 bundle id 时
    /// 这里和两个 entitlements 要一起改。
    static let appGroupId = "group.com.example.lunio"

    /// 快照在 UserDefaults 里的 key。
    static let snapshotKey = "maintenance_overview_snapshot"

    /// 本构建支持的快照契约版本（对齐 Dart 侧 widgetSnapshotSchemaVersion）。
    /// 版本不符（App 降级装回旧版后扩展还新、或反之）整体丢弃渲染占位。
    static let supportedSchemaVersion = 1

    /// 覆写快照 JSON。写入失败（App Group 未配置等）返回 false，Dart 侧
    /// 据此静默降级——桌面小组件缺失不影响 App 功能。
    @discardableResult
    static func save(json: String) -> Bool {
        guard let defaults = UserDefaults(suiteName: appGroupId) else {
            return false
        }
        defaults.set(json, forKey: snapshotKey)
        return true
    }

    /// 读取快照 JSON；无快照、App Group 不可用返回 nil。
    static func loadJSON() -> String? {
        guard let defaults = UserDefaults(suiteName: appGroupId) else {
            return nil
        }
        return defaults.string(forKey: snapshotKey)
    }
}

/// 快照 JSON 的 Swift 侧模型（Codable）。与 Dart 契约一一对应：未知字段
/// 忽略、缺字段解码失败 → 调用方按"无快照"渲染占位。
struct LunioWidgetSnapshot: Codable {
    let schemaVersion: Int

    /// 当前应用车辆的展示名（"品牌 车型"）；无车为 nil。
    let carName: String?

    /// 车辆当前里程；无车为 nil。
    let mileageKm: Int?

    /// 空态键：noCar / noRecords / noItems / nil（有数据）。非 nil 时
    /// entries 必为空，小组件据此渲染引导文案。
    let emptyState: String?

    /// 预生成窗口内的逐日条目（见 CONTEXT.md"预生成窗口"）。
    let entries: [DayEntry]

    struct DayEntry: Codable {
        /// 本条目生效的本地日（yyyy-MM-dd，锚定 App 内有效"今天"）。
        let date: String

        /// 到期概览文案（如"超期 1 / 到期 2"、"全部正常"），与 App 内
        /// 英雄卡同一组装出口。
        let overview: String

        /// 最紧急的前几个项目行（已按 App 内提醒列表排序截断）。
        let items: [Item]
    }

    struct Item: Codable {
        let name: String

        /// 状态键：normal / warning / danger（渲染成语义色）。
        let status: String

        /// 徽章文案：正常 / 到期 / 超期。
        let badge: String

        /// 进度展示文案（如"96%"）。
        let percentText: String

        /// 详情行文案（里程/时间剩余，与提醒页详情弹窗同源）。
        let detail: String
    }

    /// 解码当前契约版本的快照；JSON 缺失、损坏或版本不符返回 nil。
    static func decodeCurrent(json: String?) -> LunioWidgetSnapshot? {
        guard let json, let data = json.data(using: .utf8),
              let snapshot = try? JSONDecoder().decode(
                  LunioWidgetSnapshot.self, from: data
              ),
              snapshot.schemaVersion == LunioWidgetSnapshotStore.supportedSchemaVersion
        else {
            return nil
        }
        return snapshot
    }
}
