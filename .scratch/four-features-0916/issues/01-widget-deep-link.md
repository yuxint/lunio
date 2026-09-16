# 01 — 小组件点击深链

**Spec:** `.scratch/four-features-0916/spec.md`

**What to build:** 车主点击桌面小组件（小/中两档与空态）后，App 直接落在提醒页——冷启保持现状（默认首屏本就是提醒页），热启（上次停在别的 tab）经 URL 跳回提醒页。这推翻 ADR 0013「第一版不接深链」的拍板。

**Blocked by:** None — can start immediately.

**Status:** ready-for-human（实现完成；仅剩真机点小组件最终验收，见 Comments）

- [x] iOS Info.plist 注册 URL scheme `lunio`（CFBundleURLTypes，此前没有）
- [x] 小组件根视图一处 `widgetURL` 覆盖两档尺寸与空态；URL 必须是 `lunio:///reminders` 形态（go_router 只匹配 path，`lunio://reminders` 的 path 为空会匹配失败）
- [x] Dart 路由零改动；现有 widget 测试全绿（它们隐式覆盖冷启落提醒页）；另新增 2 个深链用例（三斜杠热启跳回提醒页 / 双斜杠匹配失败变异锁定），391 全绿
- [ ] 模拟器 `xcrun simctl openurl booted "lunio:///reminders"` 热启验证跳到提醒页 —— **被本机环境挡住**：SDK 26.2 vs 运行时 26.3.1 错配复发（9-16 上午"已修复"状态失效），xcodebuild 拒绝配置模拟器构建请求；替代验证 = swiftc 类型检查扩展源码零错误 + 导航通道级 widget 测试覆盖同一链路
- [x] ADR 0013 追加修订记录；小组件 Swift 文件头注释、AGENTS.md、CONTEXT.md、operations-manual 共 4 处「不接深链」表述同步
- [x] `flutter analyze` 通过

## Comments

- 2026-09-16 实现：Info.plist 加 CFBundleURLTypes（URLName 用 `$(PRODUCT_BUNDLE_IDENTIFIER)`，scheme 字面量 `lunio`）；`MaintenanceOverviewView.body` 根视图一处 `.widgetURL(URL(string: "lunio:///reminders"))`；ADR 0013 六轮修订；Dart 生产代码零改动。
- 模拟器验证被环境挡住的细节：`xcodebuild -showdestinations` 能列出 iPhone 17 Pro Max（OS 26.3.1），但任何 `-showBuildSettings`/build 请求对 `generic/platform=iOS Simulator` 与具体设备 id 都报 exit 64（Apple 规则：运行时版本 > SDK 版本的运行时不参与构建）。修复选项（用户决定）：装 iOS 26.2 模拟器运行时匹配现有 SDK，或换带 iOS 26.3 SDK 的 Xcode。Info.plist 结构经 `plutil -lint` + CFBundleURLTypes 提取校验；Swift 改动经 `swiftc -typecheck -application-extension`（iphonesimulator26.2 SDK）零错误。
- 遗留人工验收：真机长按桌面 → 添加「保养提醒」小组件 → 确认 App 在记录/我的页时点小组件直接跳回提醒页（此步同时验收 widgetURL 生效与扩展进程渲染，本机无模拟器可绕）。
