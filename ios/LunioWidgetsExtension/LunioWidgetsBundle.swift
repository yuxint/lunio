// LunioWidgetsExtension 的入口 WidgetBundle（ADR 0013）。
//
// 本扩展只承载保养提醒概览桌面小组件；停车倒计时实时活动在
// ParkingCountdownExtension（两扩展互不牵连，见 docs/adr/0013）。
// 之后新增桌面小组件往 body 里加即可。
import WidgetKit
import SwiftUI

@main
struct LunioWidgetsBundle: WidgetBundle {
    var body: some Widget {
        MaintenanceOverviewWidget()
    }
}
