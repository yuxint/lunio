# ADR 0013：保养提醒概览桌面小组件走 App Group 快照 + 预生成时间线

日期：2026-09-16
状态：已接受

## 背景

用户需求：不打开 App 也能看到车况——对应 iOS 的桌面小组件（Home Screen Widget / WidgetKit）。仓库现状：iOS 已有 Widget Extension target（停车实时活动，ADR 0012）但桌面小组件是空白；全工程没有 entitlements 与 App Group；没有任何深链接线；Android 无任何桌面小组件实现。数据侧，提醒行组装已有单一出口（`buildReminderRows` + 空态分类 `classifyReminderRows`，reminder_rows.dart），"界面看到的"可以直接投影成小组件数据。

WidgetKit 的机制约束（拷问时已对齐认知）：渲染发生在系统拉起的独立扩展进程，App 死活无关；刷新靠"预生成时间线 + 预算制重载"（约每天 40~70 次，时机系统说了算），App **无法**在未来某个精确时刻唤醒自己（与 ADR 0012 决定 5 同款限制）；扩展进程读不到 App 沙盒，必须经 App Group 共享存储拿数据。

## 决定

1. **内容定位**：保养提醒概览——当前应用车辆最紧急的 top3 保养项目 + 到期概览一句话 + 车名（中尺寸）；小尺寸渲染 4 行、中尺寸渲染 3 行。停车倒计时不上桌面（实时活动已覆盖锁屏/灵动岛/通知中心常驻，桌面刷新做不到走秒，放上去是更差的重复品）；油价卡与快捷操作不做。只做 iOS，**Android 本轮零改动**（沿 ADR 0012 双端不对齐先例）。
2. **数据通道**：App 内用纯函数 `buildWidgetSnapshotJson`（widget_snapshot.dart）组装快照 JSON，经 `lunio/native_widgets` 通道写入 App Group UserDefaults（`group.com.example.lunio`）并调 `WidgetCenter.reloadAllTimelines`。**小组件只渲染快照、不做任何业务计算**——连徽章/概览文案都在 App 内算好；契约带 `schemaVersion: 1`，版本不符整体丢弃渲染占位（与备份契约同思路）。快照口径 = 当前应用车辆 + 有效今天（手动日期 ?? 系统今天），与提醒页完全一致（拍板 Q4/Q5）。
3. **预生成窗口（拍板 Q6）**：快照自带未来 14 天逐日条目（每天用 `buildReminderRows` 以 day+N 重算一遍）。系统在本地午夜自动换页，"还剩 N 天"不打开 App 也每天翻页；窗口内状态跨档到点自动变色，窗口外跨档等下次打开 App 重写。桌面小组件的定位明确为"上次打开 App 时的车况快照 + 按日翻页"，不是实时仪表。
4. **快照写点（拍板 Q10-5）**：不进保存动作层——新建 `WidgetSnapshotController`（AppShell initState 挂载，`listenManual` 4 个数据上游，模式同 NotificationSyncController）监听触发。相同内容不重写；写入失败不记账、下个触发点重试；冷启首拍顺带自愈陈旧快照；动作层 14 个函数零改动。
5. **工程结构（拍板 Q9/Q10）**：新 Widget Extension target **LunioWidgetsExtension**（部署目标 16.2，原生实现不引第三方插件，照 0012 先例）；共享 Swift 文件 `LunioWidgetSnapshotStore.swift`（存取门面 + Codable 契约模型）以显式 target membership 同时编进 Runner 与扩展（照 ParkingCountdownAttributes.swift 共享先例）；Runner 与扩展各自新增 entitlements 挂 App Group（全工程首批 entitlements）。**点击小组件不接深链**（拍板 Q7）：不带 widgetURL，系统默认唤起 App 落默认页；URL scheme 基建留给后续增强（顺路惠及通知点击）。
6. **视觉**：跟随系统深浅色（背景 systemBackground），normal/warning/danger 语义色用 LunioTokens success/warning/danger 色值常量副本（0012 五轮先例）；布局对齐产品紧凑偏好，无说明性小字。空态三态（无车/无记录/无项目）复用 `classifyReminderRows` 分类口径，渲染引导文案；无快照/契约不符渲染"打开 Lunio 同步车况"占位。
7. **时间线策略**：条目锚定各日本地午夜，锚点早于今天的陈旧条目跳过；预生成窗口耗尽停在最后一条已知数据，半天兜底重试（约 2 次/天，远低于系统预算）；iOS 17+ 用 `containerBackground` 声明容器背景（系统强制），16.x 走系统默认。

## 后果

- Runner 首次引入 entitlements 与 App Group：真机自动签名多一个 capability，正常开发者账号无感；个人免费账号会因 App Group 受限装不上，发布前需确认账号支持。
- bundle id 仍是占位符 `com.example.lunio`，App Group 名跟着走——上架改 bundle id 时，两个 entitlements 与 `LunioWidgetSnapshotStore.appGroupId` 要一起改。
- 快照是最终一致性：App 被杀后数据变化不反映到桌面（拍板接受）；手动日期改到未来时条目锚点后移，锚点到达前桌面停留旧数据，属手动日期的固有语义。
- 第二个 Widget Extension target 的构建/签名维护成本（ADR 0012 已记录同类成本，工程有心理预期）。
- Android 用户没有桌面小组件（本轮拍板）；以后若做 Android AppWidget，快照 JSON 契约可直接复用，通道换成平台对应实现即可。
- 操作手册新增 §6.5；CONTEXT.md 新增"桌面小组件"词条组（2026-09-16）。

## 备选方案

- **home_widget 等第三方插件**：锁死通道与存储形态，且仓库约定不随意引新框架（0012 同款否决理由）。
- **复用 ParkingCountdownExtension 加 WidgetBundle**：省一个 target，但"保养小组件住在叫 ParkingCountdown 的扩展里"名实不符；改名 target 同样是 xcodeproj 手术。选择独立 target，领域清晰、互不牵连。
- **快照存共享文件而非 UserDefaults**：无收益，KV 够用且免文件句柄管理。
- **扩展进程自算进度**：扩展拿不到 Drift 库与偏好门面，且违背"只渲染快照"的单一出口，业务逻辑跨进程重复。
- **Configuration Intent 长按选车**：第一版砍掉（拍板 Q4），与 App 内"当前应用车辆"心智一致；留作后续增强。
- **只写当天一份快照不预生成**：天数冻结到下次打开 App 才走，违背最低新鲜度预期（拍板 Q6 否决）。
- **深链到提醒页并定位项目**：无深链基建，从零建 scheme 只为省一次点击不划算（拍板 Q7）。

## 修订

- 2026-09-16 初稿（拷问定稿 Q1-Q10 全部拍板后成文）。
- **2026-09-16 二轮（真机视觉反馈）**：决定 1 的行布局修订——小尺寸从"最紧急 1 行 + 详情"改为 **top3 紧凑列表**（名称 + 百分比 + 徽章，无详情文案，腾空间多显示项目）；中尺寸从单行三栏改为**两行式**（第一行名称/百分比/徽章，第二行详情独占一行超长截断），解决长短不一的详情把各列牵得错位的问题。纯渲染改动，快照契约不变（top3 本就带 3 行）。同日三轮：行详情按轴到期表达（`dueDetailText`：时间到期说时间、里程到期说里程、都到期都说），修正"时间超期却显示里程剩余"的错位。
- **2026-09-16 四轮（HTML 原型拍板 M3+S2）**：两档布局按原型定稿重写——中尺寸改**色块状态卡**（top3，每项一张浅色状态底卡：warning/danger 用语义色 12% 透明度、正常用系统灰，卡内两行名称/百分比/徽章 + 详情）；小尺寸改**密集 top4**（概览 + 4 行单行均分剩余高度）。快照契约随之从 top3 扩到 **top4**（`widgetSnapshotMaxRows` 3→4），两档视图各自按容量截断（中 3 / 小 4）。淘汰变体（M1 满铺两行式、M2 密集单行、S1 满铺、S3 大字概览）的探索原型见当次会话记录，未入库。
- **2026-09-16 五轮（底色反馈）**：中尺寸去掉色块底色（应用户反馈），保留 M3 的两行卡式排版与均分布局；`softBackground` 辅助随之删除。
