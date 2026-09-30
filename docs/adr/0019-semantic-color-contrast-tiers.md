# ADR 0019：语义三色浅色主题改对比度档，深色与小组件同步

日期：2026-09-29
状态：已接受（用户拍板"基调不变、具体色值由 agent 设计"；全仓色值扫描后确定改动面）

## 背景

现行语义三色（绿 #22c55e / 黄 #f59e0b / 红 #ef4444，Tailwind 500 档）是图形级取值：做状态徽章的小号文字（10.5-13px / w800）时，在各自浅色 soft 底（#dcfce7 / #fef3c7 / #ffe2e2）上的对比度约 2.1 / 2.0 / 3.6 : 1，低于 WCAG AA 文字级 4.5:1，小字发虚。2026-09-29 提醒页重设计（ADR 0018）把语义色用在量规填充与百分比数字上，小号文字用色密度进一步提高，借此机会统一校正。

用户约束：**红绿黄的语义基调不能变**（绿=正常、黄=到期、红=超期/破坏性，加油价红涨绿跌例外不变），具体色值由 agent 设计。

## 决定

1. **浅色主题三值加深到 700 档**（`lunio_tokens.dart` light）：
   - success `#22c55e` → **`#15803d`**（soft 底 #dcfce7 不变）
   - warning `#f59e0b` → **`#b45309`**（soft 底 #fef3c7 不变）
   - danger `#ef4444` → **`#dc2626`**（soft 底 #ffe2e2 不变）
   三个新值与其 soft 底的对比度全部 ≥4.5:1，色相不变、只加深度。
2. **深色主题不动**：dark 的三值（亮色档）在深底上的对比度已 7:1+，加深反而伤；六个 soft 底浅深两套都不动。
3. **iOS 扩展常量副本同步**（扩展进程读不到 Flutter 主题，ADR 0012 先例）：
   - `LunioWidgetsExtension/MaintenanceOverviewWidget.swift` `LunioStatusColor`（桌面小组件状态色块）
   - `ParkingCountdownExtension/ParkingCountdownLiveActivity.swift` `ParkingThemeColors.danger`（灵动岛到点警示红）
4. 消费点全部走 token/常量副本，无需改调用方：`lib/` 内除 token 文件外零硬编码语义色（全仓扫描确认）；测试锁值断言 4 处（records_test ×3、app_shell_test ×1）同步换 `0xffdc2626`。
5. 改语义色值时必须同步的三处清单：token light 三值 + 上述两个 Swift 常量副本（AGENTS.md 已登记）。

## 后果

- 浅色主题下徽章/百分比/删除按钮等小号文字全部达到 AA 对比度；视觉上黄从艳黄变琥珀棕、绿变沉稳——可读性换鲜艳度的取舍（黄色系无两全解，用户接受）。
- 桌面小组件与灵动岛跟 App 内颜色保持一致；快照 JSON 契约不带颜色，无 schemaVersion 变化。
- DESIGN.md frontmatter 与 Colors 章节同步更新 hex 引用。
- 真机视觉验收待用户（模拟器构建受运行时/SDK 错配限制）。

## 备选方案

- **黄色拆双 token**（文字用 #b45309、图形用 #d97706）：对比度与鲜艳度兼得，但 token 面翻倍、调用方要逐处选档，收益不抵复杂度；若日后嫌琥珀棕太沉可再拆。
- **只改文字用色、图形保持 500 档**：同上需要拆 token 且量规填充（图形）与百分比数字（文字）同色并排，拆开后反而不同步。
- **深色主题同步加深**：深底亮字已是高对比，加深无收益，不动。
