# Lunio UI 操作手册（操作 ↔ 代码对照）

> 版本：2026-09-25 · 基于 schemaVersion 3 / 备份 schemaVersion 3 代码快照（项目费用见 docs/adr/0010，数据层按域拆分见 docs/adr/0008，油价域 provider 收拢见 5.10，加油记录应付/实付模型与 v3 就地重定义见 docs/adr/0015，取代 0014 的模型部分；备份/清空收编动作层见 docs/adr/0007 修订节）
>
> **用途**：某个操作步骤出了问题，从本手册查到"这个操作经过哪些代码、改了哪些数据"，快速定位到文件和函数。
>
> **锚点约定**：引用格式为 `文件路径 : 行号 → 函数/类名`。代码改动后行号会漂移，**以"文件 + 函数名"为主锚点**，行号仅辅助；只改函数内部实现时通常无需更新本手册，改了流程/入口/数据写点才必须同步维护。
>
> **读法提示**（Java 背景）：`Repository` ≈ Service+DAO；`Provider` ≈ Spring Bean；`ref.invalidate` ≈ 缓存逐出。多数写操作的固定模式是：**UI 事件 → 动作层（shell_actions）写库 + invalidate → FutureProvider 重新查库 → UI 自动刷新**。少数旁路不走动作层：停车倒计时保存是 `parking_countdown.dart` 本地函数（1.4）。（备份导出/恢复/清空原是旁路，2026-09-25 起收编走动作层"备份与数据重置"分节，见 5.3/5.4/5.5；油价手填价重置原是旁路，2026-09-09 起已收编走 `saveFuelManualPrice`。）

数据层按域拆成仓库家族（ADR 0008）：**主仓库** `LunioRepository`（车辆/项目/记录核心域）、`BuiltInCatalogRepository`（车型目录+bootstrap）、`FuelRepository`（加油域）、`BackupRepository`（备份/恢复/清空）、`LunioPreferences`（偏好门面，全部偏好 key 与编解码的唯一出口）。各域在 providers.dart 装配（例外：油价域 provider——省份/油品/手填价/数据源/油价控制器/生效链——在 `lib/features/shell/fuel/fuel_prices.dart`，2026-09-13 收拢，依赖单向：providers.dart 不再 import 它）；偏好写入后的缓存逐出走偏好纪元（ADR 0017，见下文"缓存失效入口"）；表插入路径共享 `entity_row_codec.dart` 的 Companion 构造。

---

## 目录

- [0. 通用模式速览](#0-通用模式速览)
- [1. 冷启动与首次进入](#1-冷启动与首次进入)
- [2. 提醒页（/reminders）](#2-提醒页reminders)
- [3. 应用内提醒弹窗（snooze / ack）](#3-应用内提醒弹窗snooze--ack)
- [4. 记录页（/records）](#4-记录页records)
- [5. 我的页（/me）](#5-我的页me)
- [6. 主壳层与通知同步引擎](#6-主壳层与通知同步引擎)
- [7. 数据与偏好速查表](#7-数据与偏好速查表)
- [8. 手册维护规则](#8-手册维护规则)

---

## 0. 通用模式速览

**一次写操作的完整链路**（以保存保养记录为例）：

```
用户点"保存记录"
  → records_page.dart → MaintenanceRecordFormState._submit()     # 载荷校验+构造在 RecordFormController.submitPayload（record_form_controller.dart）
  → onSubmit 闭包（showMaintenanceRecordFormSheet 内）
  → shell_actions.dart → saveMaintenanceRecord(ref, ...)         # 动作层（ADR 0007）
      ├→ repository.saveMaintenanceRecordWithItemUpdates()       # 事务：校验+写库
      └→ invalidateVehicleProviders(ref)                         # 逐出缓存
  → appliedCarRecordsProvider 等重算 → AppShell build → UI 刷新
```

**保存动作层**（`lib/features/shell/shared/shell_actions.dart`，ADR 0007）：每个业务变更一个具名函数，内部固定编排"写库 → 失效对应 provider 家族 →（需要时）组合通知协调器"；只收 `WidgetRef`，不弹确认框、不 pop、不 toast，异常穿透给表单的行内错误机制。**新增保存路径时进动作层加函数，不要在 UI 里手排失效序列。**（2026-09-25 起，编辑表单 sheet 的"关 sheet + toast"反馈薄壳收进表单运行时 `showLunioFormSheet`，见下一条；动作层本身不变。）

**表单 sheet 运行时**（`lib/features/shell/shared/form_sheet.dart`，ADR 0016）：编辑表单类 sheet 一律经 `showLunioFormSheet` 打开，不再手写 `showLunioModalSheet`+`PrototypeSheetFrame`+pop/toast——① `load` 预装载（失败 friendlyError toast、sheet 不出现，装载结果经入口闭包局部变量在 load/guard/builder 间共享）；② `guard` 领域守卫（非空文案 → info toast 拦截，如"请先新增车辆"）；③ 键盘 inset 由运行时经 sheet 自己的 context 读取；④ 提交 = `FormSheetHandle.submit`（re-entrant；失败行内错误留场，成功 pop + successMessage toast，`resultOnSubmit` 透传；加车向导第一步用 `run` 不关场）；⑤ 所有 pop 归运行时（`close({toast, tone})` 承接取消/删除/查重"去编辑"/去系统设置）。表单 State 经把手读 `saving`/`errorText`（原 `LunioFormSubmit` mixin 已删除）；错误行 `LunioInlineMessage` 的渲染留在表单侧。模块级专测 `test/widget/form_sheet_test.dart`。

**保存成功反馈**：所有落库保存（保养记录/车辆新增编辑/保养项目/通知设置/手动日期/手填油价）成功关 sheet 后，统一在外层页面 context 弹轻量 toast"已保存"（`showStatusOverlay`，1.6s 自动消失，modal_feedback.dart）。2026-09-25 起这个"关 sheet + toast"薄壳由表单运行时统一执行（ADR 0016），个别无 toast 的入口（停车倒计时、草稿项目表单）以 `successMessage: null` 表达。

**数字输入键盘**：所有只填数字的输入框统一数字键盘——整数字段用 `TextInputType.numberWithOptions()`（免费时长/保养里程/费用外的里程/项目周期数字行），金额类带小数用 `numberWithOptions(decimal: true)`（费用/油箱容积）。

**底部弹窗关闭与键盘**：所有底部 sheet（`showLunioModalSheet`，modal_feedback.dart）的关闭/键盘行为统一由共享原语处理，页面不单独实现——① 下拉整块跟手：内容滚到顶部后继续下拉，sheet 跟手移动，松手超过 1/4 弹窗高度（矮弹窗按 80px 下限）或下滑够快即关闭，否则弹回；内容可滚时走内部出界滚动通知（`_SheetDragDismiss` 通知通道），内容收缩不满一屏时走外层手势（`canDrag=false` 时内部无识别器，出界通知不存在，Flutter 行为）。② 点弹窗内非输入框区域：只收键盘不关弹窗（`_LunioModalContent` 的 onTap unfocus，数字/全键盘一致）。③ 点弹窗外暗色遮罩区按弹层类型分两档（2026-09-12 产品决策）：**编辑表单类**（有取消/确认按钮的表单 sheet：记录表单、添加/编辑车辆、项目表单两版、停车倒计时、快捷更新里程、手动日期、手填油价、通知设置（2026-09-25 归一，原先可点遮罩关闭是漂移），一律走 `showLunioFormSheet`（ADR 0016），`barrierDismissible=false` 是运行时固定行为）点遮罩、下滑、系统返回键（`PopScope` canPop=false）都关不掉，只能走取消/确认按钮，防止误关丢已输入内容；**选择器/只读 sheet**（车型选择、日期选择、项目多选、省份/油品选择、停车时长滚轮、记录详情、项目管理、切换车辆）保持点遮罩与下滑直接关闭，无未保存确认。

**sheet 高度上限**：`PrototypeSheetFrame` 限制 sheet 最大高度 = 屏幕高度 − 顶部安全区 − 底部预留（max(安全区, 键盘高度)，2026-09-12）：长表单顶到状态栏下沿为止，标题永不与状态栏时钟重叠，超出内容走内部滚动；矮弹窗贴内容不变；键盘弹出时上限随键盘高度同步收缩。

**sheet 键盘抬升**：键盘高度（`bottomInset`）垫在 sheet 容器**外侧**（`PrototypeSheetFrame` 返回 `Padding(bottom: bottomInset)`）：键盘弹出时 sheet 底边整体抬到键盘顶边、表面悬在键盘上方，滚动视口完整可见，点击底部输入框由 Flutter 焦点滚动滚入可见区；无键盘时外侧垫 0，sheet 照旧贴住屏幕底边不悬空。底部安全区（Home 横条）补在内容内侧、只补键盘没盖住的差额，总预留恒为 max(安全区, 键盘高度) 不叠加（2026-09-12 修复：此前键盘预留垫在滚动内容内部，长表单触顶高度上限后视口下半截仍被键盘盖住，编辑记录底部费用框点了看不见；抬升初版把安全区也垫外侧，无键盘时底部悬空一条缝，均已修）。配套约束：`bottomInset` 必须取 sheet 自己的 builder context（`MediaQuery.of(sheetContext)`，随键盘实时更新）；误用外层页面 context 会在 sheet 构建时定格为 0（records_page 曾踩，2026-09-12 修复）。**2026-09-25 起编辑表单 sheet 的 bottomInset 由表单运行时 `showLunioFormSheet` 统一读取（ADR 0016），调用方不再裸写 MediaQuery。**

**缓存失效入口**（`lib/app/providers.dart`）。ADR 0007 后主要调用方是保存动作层（shell_actions.dart）与通知协调器，UI 不再手排。2026-09-26 起偏好类缓存失效改**偏好纪元**模型（ADR 0017）——`preferencesEpochProvider` 是偏好表数据的版本号（与通知同步代数同构），写完库 bump 一次，所有 watch 纪元的 provider 自动重查，无名单可漏：

| 入口 | 失效内容 | 谁在调 |
|---|---|---|
| 偏好纪元 bump（ADR 0017） | 全部偏好表派生 provider（开发者模式/手动日期/生效日期/主题/通知设置/加油开关/当前车加油预测设置/省份/油品/手填价/油价控制器，共 11 个，分布在 providers.dart 与 fuel_prices.dart，各自 build 里 watch 纪元） | 动作层偏好类函数与加油省份/油品/手填价函数、通知协调器（权限回写与通知设置） |
| `invalidateVehicleProviders` | 车辆/车型/项目/记录（含按车记录 family）/加油记录 9 个 provider（车辆类家族维持手动失效） | 动作层车辆/项目/记录类函数 |
| `parkingCountdownProvider` 直失效 | 停车倒计时缓存（不走纪元——写点直失效自己模型，偏好写入不牵动停车卡） | 动作层 saveParkingCountdown / clearParkingCountdown |
| `invalidateAllAppDataProviders` | bootstrap + 停车倒计时直失效 + 车辆家族 + 偏好纪元 bump | 恢复备份 / 清空数据 |

**Provider 依赖图**（`lib/app/providers.dart`，文件头有注释版；仓库按域拆分后：目录/加油/备份/主仓库各自独立挂数据库，偏好类 provider 统一挂偏好门面；**油价域 provider 定义在 `lib/features/shell/fuel/fuel_prices.dart`**，这里只画在本文件的锚点）：

```text
appDatabaseProvider(:213)
  ├─→ lunioPreferencesProvider(:221) ─ 偏好门面（下述偏好类 provider 的数据源）
  │     ├─ developerModeProvider(:107) ─→ manualDatePreferenceProvider(:115) ─┐
  │     ├─ themeModePreferenceProvider(:130)                                 │
  │     ├─ notificationSettingsProvider(:138)                               ├─→ effectiveTodayProvider(:203)
  │     ├─ parkingCountdownProvider(:147)                                   │   （另一输入 appDateContextProvider(:101)）
  │     └─ 加油开关(:157)/当前车加油设置(:167)                              │
  │        （省份/油品/手填价在 fuel_prices.dart，watch 偏好门面 + 偏好纪元）│
  │     上述偏好类 provider（停车除外）均 watch preferencesEpochProvider(:84)
  │     ——写完库 bump 一次全体自动重查（ADR 0017，替代旧失效名单）
  ├─→ builtInCatalogRepositoryProvider(:226)
  │     └─→ defaultMaintenanceBootstrapProvider(:260)
  │           ├─→ vehicleModelsProvider(:268)（另挂目录仓库）
  │           └─→ carsProvider(:294)（另挂主仓库）
  │                 └─→ appliedCarProvider(:303)（另挂主仓库）
  │                       ├─→ appliedCarMaintenanceItemsProvider(:321)（另挂主仓库）
  │                       ├─→ appliedCarRecordsProvider(:342)（另挂主仓库）
  │                       └─→ appliedCarFuelRecordsProvider(:191)
  │                             （另挂加油仓库 family :183，ADR 0014）
  ├─→ fuelRepositoryProvider(:233)（另挂偏好门面）
  │     └─ fuel_prices.dart：手填价、油价控制器 FuelPriceController、
  │        生效链（effectiveFuelPrice/effectiveFuelForecast/predictedFuelPrice）
  ├─→ backupRepositoryProvider(:241)（另挂偏好门面）
  └─→ lunioRepositoryProvider(:250)（另挂偏好门面 + 加油仓库）
        └─→ recordsForCarProvider(:334)（按车记录 family——费用统计页
            当前应用车辆作用域，2026-09-20 起不再有"全部"合并）
```

---

## 1. 冷启动与首次进入

### 1.1 启动链路（App 进程启动 → 首帧）

| 步骤 | 代码位置 | 做了什么 |
|---|---|---|
| 1 | `lib/main.dart:20-37 → main()` | 初始化引擎绑定 → **await 通知服务初始化**（时区+插件，`:33`）→ `runApp(ProviderScope(LunioApp))` |
| 2 | `lib/core/notifications/lunio_notification_service.dart:78 → initialize()` | 时区数据库 + 本地时区（失败回退 Asia/Shanghai 并打日志，R34/R14）+ 插件初始化（iOS 不在此弹权限） |
| 3 | `lib/app/lunio_app.dart:31 → LunioApp.build` | watch 主题偏好 → `MaterialApp.router`，路由挂全局单例 `appRouter` |
| 4 | `lib/app/app_router.dart:26 → appRouter` | 平级入口路由 `/reminders` `/records` `/me` 各渲染 `AppShell(selectedIndex: n)`（`/fuel` 路由常驻，开关关闭时由 AppShell 重定向回 `/me`）；另有第一个不挂壳的 pushed 子页 `/cost-stats`（§4.5，不渲染 AppShell）；初始 `/reminders` |
| 5 | `lib/features/shell/app_shell.dart:34 → AppShell` | 主壳首帧 build：watch 全部 provider（此时数据库才真正打开） |

**注意**：数据库是**惰性**打开的——`appDatabaseProvider`（providers.dart:213）首次被 watch 时 `new AppDatabase()`，而 SQLite 文件连接由 Drift LazyDatabase 推迟到第一条 SQL（`lib/data/database/app_database.dart → _openConnection`，后台 isolate 打开 `lunio.sqlite`）。

### 1.2 首次进入（无任何数据）发生了什么

| 步骤 | 代码位置 | 做了什么 | 数据变化 |
|---|---|---|---|
| 1 | `lib/app/providers.dart:260 → defaultMaintenanceBootstrapProvider` | AppShell 首帧 watch 触发 `ensureBootstrapData()` | 见第 2 步 |
| 2 | `lib/data/repositories/built_in_catalog_repository.dart → BuiltInCatalogRepository.ensureBootstrapData()` → `_ensureVehicleModels` + `_ensureDefaultMaintenanceItems` | 从 asset `assets/data/catalog/`（templates.json + vehicles_a–z.json 字母分片）加载目录（**2026-09-01 动力类型改版后为 1675 条：懂车帝在售 1645 + 停售 30，车系名用懂车帝原名，每条带推荐动力类型；默认保养模板按动力类型分五组；同日起精简为每品牌最多 10 款热门车型，现共 1223 条**，见 ADR 0003），**按 catalogId 幂等对账**写入两张内置表 | `vehicle_models`、`vehicle_default_maintenance_items` 两表灌入/更新 |
| 3 | `lib/features/shell/reminders/reminder_page.dart:102 → EmptyVehicleCard` | appliedCarProvider 返回 null → 显示"还没有车辆"卡片 | 无 |
| 4 | `lib/features/shell/app_shell.dart:69-74 → NotificationSyncController` + `start()`（`reminders/notification_sync_controller.dart`，对 6 个数据 provider `listenManual` 且首拍即触发） | 系统通知开关为默认开 → 同步链对账系统真值并触发首启权限请求 | 见 1.3 |

**首启不会创建默认车辆**——必须用户手动走添加向导；车辆级保养项目也是添加车辆时才从模板复制。

### 1.3 首次通知权限请求

执行体在通知协调器（`reminders/notification_coordinator.dart → LunioNotificationCoordinator`），控制器只做防重入与签名重置：

| 步骤 | 代码位置 | 做了什么 | 数据变化 |
|---|---|---|---|
| 1 | `notification_sync_controller.dart → _ensureInitialSystemNotificationPermission`（防重入）→ `notification_coordinator.dart → ensureInitialSystemNotificationPermission` | 读偏好 `systemNotificationPermissionRequested` 分流 | — |
| 2a | 未请求过 → 协调器 `requestPermission` | 弹系统权限对话框（iOS/Android 13+） | 写 `systemNotificationPermissionRequested=true`；被拒时写 `systemNotificationsEnabled=false` 并失效偏好缓存 |
| 2b | 请求过 → 协调器 `reconcileSystemEnabled` 查系统真实开关 | 用户可能在系统设置改过，回写偏好保持一致（查询失败回退偏好值，R14） | 可能更新 `systemNotificationsEnabled` |
| 3 | 真的弹了请求（2a）→ 控制器清空签名 | 下帧触发系统通知首次全量重排 | — |

---

## 2. 提醒页（/reminders）

页面装配：`lib/features/shell/reminders/reminder_page.dart → ReminderPreviewPage`（页面本身无周期重建；停车倒计时卡片内部 1s Timer 自刷新秒级进度）。

### 2.1 当前车辆卡片（hero 卡）

| 用户看到 | 代码位置 | 数据来源 |
|---|---|---|
| 品牌/车型/上路日期/当前里程 | `reminder_page.dart:76-97 → LunioHeroCard` | `appliedCarProvider`（providers.dart:303）→ `repository.getAppliedCar()`（lunio_repository.dart:314，含偏好失效回退逻辑） |
| "到期概览"文案（超期 x / 到期 x / 全部正常） | `reminder_page.dart → reminderRows.when` + `reminder_rows.dart → dueOverviewText` | watch `reminderRowsProvider`（reminder_rows.dart：watch 车辆/项目/记录/今天四上游，英雄卡与列表共消费，数据变化只组装一遍）；loading"计算中"/error"加载失败"由页面 when 收口，文案函数只收就绪数据，空态经 `classifyReminderRows` 单一出口 |
| 右上角"更新里程"按钮 | `reminder_page.dart:80 → showQuickMileageUpdateSheet` | 快捷改里程 sheet，见 2.1.1 |
| 右上角"切换车辆"按钮（多车才显示） | `reminder_page.dart:69 → showVehicleSwitcher` | `vehicles.dart:430`，见 5.1.4 |

#### 2.1.1 快捷更新里程（hero 卡"更新里程"按钮）

| 步骤 | 代码位置 | 做了什么 | 数据变化 |
|---|---|---|---|
| 1 | `reminder_page.dart:165 → showQuickMileageUpdateSheet` | 弹表单 sheet（标题"更新里程"，副标题展示当前里程）；输入框（`LunioNumberField` 纯整数）**默认留空 + autofocus 自动弹数字键盘** | — |
| 2 | 留空提交 → 行内校验错误"请输入当前里程" | 不落库 | — |
| 3 | 新里程 ≤ 当前里程（**含相等**）提交 → 先弹确认框"里程未调高"（`showConfirmDialog`，非破坏性：确认键主色） | "仍要保存"强保继续；"取消"留在 sheet，库里不变 | — |
| 4 | 确认/直接保存 → `shell_actions.dart → updateCar`（动作层，ADR 0007） | copyWith 里程（sync 置 pendingUpdate，与编辑车辆表单同通道）→ 写库 → 失效车辆家族 → 关 sheet + toast"里程已更新" | `cars` 表该行 `current_mileage_km` |

> 快捷入口的"未调高确认框"只加在这一个入口；"我的 → 编辑车辆"表单仍允许任意改小（宽松规则待确认，见审查台账 R36）。

### 2.2 停车倒计时

**开始**：

| 步骤 | 代码位置 | 做了什么 | 数据变化 |
|---|---|---|---|
| 1 | `reminder_page.dart:103`（倒计时为 null 时按钮可用，进行中禁用）→ `parking_countdown.dart:586 → showParkingCountdownSheet` | 弹表单 sheet | — |
| 2 | `parking_countdown.dart → ParkingCountdownForm`（约 230 行起） | 入场时间（**点按钮此刻实时取系统时间，秒/毫秒截 0 默认整分**；时间轮可改时分秒，双向循环滚动）+ 免费时长（数字键盘输入框或 0.5/1/2 小时快捷 chip） | — |
| 3 | 提交 → `shell_actions.dart → saveParkingCountdown(ref, countdown)`（动作层，ADR 0007） | ① 写偏好（经偏好门面 `LunioPreferences.saveParkingCountdown`） ② 失效 ③ 通知尾巴委托协调器 `onParkingCountdownSaved`（`notification_coordinator.dart`）：**先取保存时刻**（预警门槛用它评估，弹窗停留不挤占剩余时长）→ **启动/重建 iOS 实时活动**（与系统通知开关无关；到点时刻已过则跳过，与通知调度同一静默口径）→ 若系统通知开 → 请求权限（被拒回写开关关）→ 调度前比对**通知同步代数**（保存期间发生恢复/清空则放弃）→ Android 精确闹钟 → 调度前再问一次同步票（精确闹钟弹窗停留期间发生恢复/清空同样放弃，2026-09-25 补齐）→ 调度通知。编排只收 `WidgetRef`，不依赖任何页面存活（表单 sheet 的关闭由表单自理） | ① `parkingCountdown` = JSON ② iOS 实时活动（见下方专节）③ 系统通知 id **9002**（Android 常驻 chronometer）+ **9001**（到点闹钟）+ **9003/9004**（剩 15/5 分钟预警，保存时剩余 ≥ 30 分钟才启用）；`systemNotificationPermissionRequested=true`；被拒时 `systemNotificationsEnabled=false` |
| 4 | `lunio_notification_service.dart → scheduleParkingCountdownNotification` | 先成组取消旧 9001~9004，再排新通知；**到点时刻已过则静默 return**；剩余 ≥ 30 分钟（按整分钟向上取整）才加排两条预警 | — |

**展示**：`parking_countdown.dart → ParkingCountdownCard`（ConsumerStatefulWidget）——进度规则在 `lib/domain/rules/parking_countdown_rules.dart`（剩余≤20% 黄、到期红转正计时）；颜色映射 `_parkingStatusColor`。**卡片内部 1s Timer 自刷新**（时钟走 `appDateContextProvider.readSystemNow()`，测试可注入），重建范围只有这张卡。

**结束**：卡片"结束"按钮 → `shell_actions.dart → clearParkingCountdown(ref)`（动作层，ADR 0007）→ 删偏好 key + 失效 + 通知收尾委托协调器 `onParkingCountdownCleared`（撤 iOS 实时活动 + 系统通知开着时取消 9001~9004）。

#### 2.2.1 iOS 实时活动（灵动岛，ADR 0012）

iOS 16.2+ 上停车倒计时另有系统托管的常驻实时卡片（锁屏 + 灵动岛 + 通知中心顶部），Android 零改动。链路：Dart 桥 `lib/core/platform/native_live_activities.dart`（非 iOS 自禁用）↔ SceneDelegate `lunio/native_live_activities` 通道 ↔ 执行体 `ios/Runner/ParkingCountdownActivityController.swift`；卡片 UI 在 Widget Extension target `ios/ParkingCountdownExtension/`；启停编排挂通知协调器。

| 事件 | 行为 |
|---|---|
| 保存倒计时 | 启动/重建活动（零更新渲染：剩余时间与进度条由系统组件自动走时，App 不推送任何更新；启动时设 `staleDate = 到点时刻`）。样式为"行式对照"（ADR 0012 三轮定稿）：青色图标 + 灰色文案 + 金黄计时 + 白色状态 + 蓝色剩余递减进度条 + 黑底锁屏 |
| 到点（App 在前台，提醒页可见） | 停车卡片秒时钟跨越到点的那一刻经动作层 `notifyParkingCountdownExpired` 调协调器，**即时**把活动切成"已超时"正计时（红色状态，计时从入场时刻起算 = App 内"停车时长"） |
| 到点（App 不在跑/不在提醒页） | 卡片停在 00:00；**锁屏卡由系统自动置灰（staleDate），灵动岛无置灰表现**；不自动切正计时——ActivityKit 无本地定时更新手段，由回前台/冷启动对账兜底（接受的折衷，ADR 0012 决定 5 及三轮修订） |
| 回前台 / 冷启动 / 偏好变化 | 协调器 `reconcileParkingLiveActivity` 对账三态（真值直读偏好表，不走 provider 快照——invalidate 旧值曾把刚启动的活动当"偏好无"误撤，见 ADR 0012 六轮）：偏好无+活动在 → 撤；偏好有+活动丢（重启/系统收回）→ 剩余为正才补启；都有但形态漂移 → 过期切正计时、到点时刻对不上则重建/撤 |
| 结束 / 清空数据 | 协调器撤活动（`onParkingCountdownCleared` / `runAllDataClear`）；原生侧确认全部撤场后才算返回，且启/停/翻转都包 `beginBackgroundTask` 后台保活（2026-09-16 真机修正：ActivityKit 握手是异步的，退后台即挂起会让开始不上岛、结束留残卡，见 ADR 0012 五轮修订） |
| 删车 / 恢复备份 / 关通知总开关 | 不动实时活动（倒计时全局不挂车、备份不含倒计时偏好；实时活动与通知是系统设置里两个独立开关） |
| iOS < 16.2 / 系统关实时活动 / 活动超上限 | 通道返回"未启用"，静默降级为"只有通知"，不提示不报错 |

> 实时活动卡片不放开始/结束钟点、不放车辆名；活动有系统寿命上限（约 8~12 小时），超长倒计时活动被系统收回后由对账补启兜底（剩余为正时）。已知问题：到点后与 App 内卡片一致不自动清除，须手动"结束"（R9）。

> 已知问题：到期后倒计时不自动清除（须手动结束才能开始新的，R9/R17）。恢复备份/清空数据后的 9001~9004 残留已修复（恢复保留停车偏好不动其通知；清空显式成组取消并撤实时活动，见 §5.4/§5.5）。

### 2.3 新增保养记录入口

`reminder_page.dart:101` → 记录表单（完整流程见 §4.2）。

### 2.4 保养提醒列表（"待关注项目"）

| 步骤 | 代码位置 | 做了什么 |
|---|---|---|
| 1 | `reminder_list.dart:21 → ReminderList` | 自取 `reminderRowsProvider`（不再由页面透传数据）：加载中 → 菊花；加载失败 → "加载失败：…"（车辆/项目/记录/今天四数据源合并成一个 provider，出错不再区分来源）；空态经 `classifyReminderRows` 单一出口：无任何记录 → "暂无保养记录"（产品约定：无记录不产生提醒）；无启用项目 → 引导去"我的"配置 |
| 2 | `reminder_rows.dart:88 → buildReminderRows` | 只取启用项目 → 逐项找最近记录（`RecordRules.latestRecordForItem`，domain 层；同项目同日唯一约束保证按日期可唯一定位，无"同日多条"并列）→ 调 **进度计算**（见下）→ 排序（状态→百分比→sortOrder）。通知侧 `maintenanceNotices` 复用同一函数 |
| 3 | `lib/domain/rules/maintenance_rules.dart:120 → progressForItem` | 里程维（当前里程−基线）/间隔、时间维（今天−基线日）/总天数，**双维取大**为展示进度；状态按项目阈值（默认 100 黄 / 125 红） |
| 4 | `reminder_list.dart:59 → ReminderRow` | 进度环（`ReminderProgressRingPainter`）+ 状态徽章 + 剩余里程/时间文案 |
| 5 | 点击行 → `reminder_list.dart:151 → showReminderRecordDetail` | 弹上次保养日期/里程 + 距上次时间/里程 sheet（距上次字段在 `buildReminderRows` 构造 `ReminderViewData` 时经 `RecordRules.daysSinceLast` / `kmSinceLast` 算好：基线记录 → 今天 / 当前里程；无记录或差值为负（补录乱序）已在 domain 折叠成 null，格式层只把 null 显示"—"） |

---

## 3. 应用内提醒弹窗（snooze / ack）

**触发时机**：通知同步控制器检测"应用内通知开 + 到期项变化/回到前台"（`reminders/notification_sync_controller.dart → _showDueInAppNotifications`）。

**中间态守卫（2026-09-24 新增；2026-09-25 收编进守卫模块）**：破坏性写库（恢复备份/清空数据/删除车辆，经协调器三个 run* 模板驱动守卫）的写库事务进行中，`syncFromProviders` 入口查守卫 `isDataResetInFlight` 旗直接丢弃（写库逐行插入会经 Drift 同连接流查询暴露未提交的半成品数据，拿它算提醒会得出"全部到期"的假结论——曾经的事故：恢复备份后弹出"已超 3 年 11 个月"的假到期弹窗）；弹窗展示前（保养/里程两处，与各自展示调用之间无 await）各问一次同步票 `run.isValid`（= 未销毁 && 无中间态旗 && 代数未变，见 6.3），封掉"检查开始后写库才开始/恰好结束"的窄窗。检查执行中来新请求由重入 harness 记 pending，本轮 finally 强制重跑（R3 同款），消除"弹窗开着时数据变化的那一拍被丢"整类问题。

| 步骤 | 代码位置 | 做了什么 | 数据变化 |
|---|---|---|---|
| 1 | `reminder_notifications.dart → maintenanceNotices` | 到期项收集（无记录直接空）；静默过滤走协调器 `isSilencedForInAppDialog`（"稍后提醒"期内或今天已"知道了"即跳过） | — |
| 2 | `reminder_dialogs.dart:26 → showMaintenanceReminderDialog` | 弹保养提醒框（逐项列出） | — |
| 3a | 点"知道了" | 返回 acknowledged，控制器经协调器 `acknowledgeMaintenanceItem` 逐项写当日 ack | `maintenanceInAppReminderAcknowledgedOn:<itemId>` = 今天（当天不再弹，系统通知照发） |
| 3b | 点"15 天内不再提醒" | 弹窗内 `onSnoozeAll` 经协调器 `snoozeMaintenanceItems` 写 snooze | `maintenanceReminderSnoozedUntil:<itemId>` = 今天+15 天（系统+应用内一起静默） |
| 4 | 有动作后 | 控制器清空两个签名并立即重跑 `syncFromProviders` | 系统通知按新 snooze 状态重排 |
| 5 | 里程更新弹窗同构 | `reminder_dialogs.dart:60 → showMileageUpdateReminderDialog`；是否到期判定 `reminder_notifications.dart → mileageUpdateReminderDue`（上次里程更新日 = car.sync.updatedAt + 按记录频率推断的间隔） | `mileageUpdateSnoozedUntil:<carId>` / `mileageUpdateInAppAcknowledgedOn:<carId>`（经协调器 `snoozeMileageUpdate` / `acknowledgeMileageUpdate` 写入） |
| 6 | 回到前台 | `app_shell.dart → didChangeAppLifecycleState` 转交 `controller.onAppResumed()` 清空应用内签名并重跑同步 | 强制重查（处理完离开再回来，到期会再弹） |

---

## 4. 记录页（/records）

页面装配：`lib/features/shell/records/records_page.dart → RecordsPreviewPage`（记录 provider 就绪前整页 LoadingPage/ErrorPage 占位，三页统一形态；就绪后 LunioPage.slivers：头部固定 + 列表懒加载）。空记录文案："暂无保养记录，可在提醒页点「新增保养记录」。"（真实入口指向提醒页）。

### 4.1 列表与筛选

| 用户操作 | 代码位置 | 做了什么 |
|---|---|---|
| 切换"按周期/按项目" | `records_page.dart:133`（LunioSegmentedControl） | `selectedMode` 0/1 |
| 年份/项目多选筛选 | `records_page.dart`（两个 `_FilterBar`，已回收为页面私有）+ `record_rows.dart`（口径规则） | `selectedYears`/`selectedItemIds` 集合仅由用户点击变更；渲染与过滤用派生集合（自动忽略已失效的年份/项目），下标映射、toggle 与有效性过滤收在 `record_rows.dart`（`validSelections`/`filterBarSelectionIndexes`/`toggleSetValue`） |
| 按周期视图 | `records_page.dart → RecordCycleCard`（SliverList.builder 逐条懒加载，ValueKey('record-<id>')） | 一条记录一张卡（日期+金额+里程+备注+项目 pills+编辑/删除）；**整卡可点 → 记录详情弹窗（§4.4，ADR 0010）** |
| 按项目视图 | `records_page.dart → RecordItemRowCard`（同样懒加载） | 记录×项目展开成行（行组装在 `record_rows.dart → buildRecordItemRows`：记录序×itemIds 序，项目已删的行 item 为 null、渲染兜底"未知项目"），可单独删某项；**整行可点 → 只看该项目的详情弹窗（§4.4）** |
| 列表空态 | `record_rows.dart → classifyRecordListState`（sealed 分类） | 优先级：无车 > 无任何记录 > 筛选无结果 > 有数据（两视图行各自备好）；空态文案是 UI 决策，留在 `records_page.dart` 渲染 |

### 4.2 新增 / 编辑保养记录（两步表单）

**入口**：提醒页"新增保养记录"按钮（reminder_page.dart:126）或记录卡"编辑" → `records_page.dart → showMaintenanceRecordFormSheet`。新增模式带同日查重拦截（步骤 0b：打开时/选完日期后，重复日期弹"返回/去编辑"，可直接转编辑同日已有记录）；第一步「下一步」另有里程单调性软提示（步骤 2a，新增与编辑都查）。**两步表单的状态机（字段、步进、校验、两个软提示决策、查重循环驱动）2026-09-26 起收在 `records/record_form_controller.dart → RecordFormController`（plain-Dart，弹窗/日期选择器实现经 `RecordFormUi` 注入、已有记录经快照 getter 注入、单测 `test/features/record_form_controller_test.dart` 含变异验证 3/3）；表单 widget 只渲染两步视图、转发事件并持有弹窗实现与文案。**

| 步骤 | 代码位置 | 做了什么 | 数据变化 |
|---|---|---|---|
| 0 | `showMaintenanceRecordFormSheet` 的 `load`+`guard`（ADR 0016） | 预装载车/项目/今天三个 provider（失败 friendlyError toast 不开壳）；无车或无可用项目 → 守卫文案 toast 拦截 | — |
| 0b | widget 首帧后 → `RecordFormController.formOpened`；选完日期后控制器 `_pickRecordDate → _checkDuplicateAndOfferEdit`（record_form_controller.dart；widget `_pickRecordDate` 只转发） | **同日查重拦截（2026-09-16 新增，仅新增模式，编辑模式不查；循环驱动 2026-09-26 收进控制器）**：`_findRecordOn` 经注入的记录快照 getter（`appliedCarRecordsProvider`）过滤同日期记录（{carId, date} 唯一约束最多一条；快照未就绪返回 null 跳过检查，保存时同日唯一校验兜底）。有记录 → `showConfirmDialog`"该日期已有保养记录"（按钮**返回/去编辑**；`showConfirmDialog` 的 `cancelLabel` 参数为此新增，默认仍"取消"；弹窗实现作为 `RecordFormUi.askDuplicate` 注入）：「去编辑」→ `RecordFormUi.exitToEdit` → `onExitToEdit` 回调（sheet 入口接线，经 `handle.close()` 关新增 sheet）、用外层 context 重开该记录的编辑 sheet；「返回」/点遮罩 → 控制器驱动 `_pickRecordDate` 自动重开日期选择器换日期（选择器实现作为 `RecordFormUi.pickDate` 注入），选完再查一轮，循环到选出无重复日期或去编辑退出。拦截始终发生在第一步，不会带着重复日期进入第二步。分支/循环单测在 `test/features/record_form_controller_test.dart`，接线 smoke（去编辑跳转、返回换日）在 `test/widget/records_test.dart` | — |
| 1 | `MaintenanceRecordForm`（:493 起）第一步 | 日期（范围=上路日期~今天+365）、里程（默认车辆当前里程）、费用（元输入）、备注、**详细模式开关（ADR 0010，默认简洁、不持久化；编辑带项目费用的记录自动开启，控制器构造 → detailMode）**、项目多选 chip；编辑态可见"已禁用但被选过"的项目（`RecordFormController.availableItems`） | — |
| 1a | 详细模式费用行（`_ItemCostRow`，勾选项目 chip 下方逐项展开） | 每个项目"材料费/工时费/项目费用"三个数字框。**自动算链**：材料、工时**任一非空**（未填侧按 0 求和；两格都 0 填 0.00；2026-09-12 修订，原规则要求两者都>0）→ 项目费用=两者之和；已填项目费用 → 总费用=合计。自动值可手改，**手改后不再自动覆盖**（清空=恢复自动；编辑记录打开时，存量项目费用≠材料+工时或存量总费用≠合计即视为已手改，避免预填的优惠价被自动算链冲掉）。算链、手改标记、费用草稿生命周期与提交清单收在 `records/record_cost_form_controller.dart → RecordCostFormController`（ADR 0010 唯一实现点，表单 State 只接线与重建；单测 `test/features/record_cost_form_controller_test.dart`）；**不一致纯提示**：项目费用≠材料+工时（任一非空时比，未填侧按 0；2026-09-12 同步修订）或总费用≠合计（有项目费用时）→ 该数字红字+框尾/行首黄色警告角标，不拦截保存（优惠等差异合法）。判定纯函数在 `record_rules.dart`（`itemCostMismatch`/`totalCostMismatch`/`sumItemCostCents`） | — |
| 1b | 行内"新增"项目 | `records_page.dart → _addMaintenanceItem` → 弹项目表单（§5.2.2）→ 重拉列表 → 控制器 `itemPoolRefreshed`（record_form_controller.dart）**diff 出新 id 自动勾选**（费用草稿随勾选集合同步） | 新项目已落库 |
| 2 | `RecordFormController.goToIntervalStep`（含 `_buildRecordDraft`，record_form_controller.dart）+ `_costForm.buildItemCosts()`；widget `_goToIntervalStep`（:743）只转发 | 控制器校验（里程非负/费用非负/至少一项；费用不一致**不做**校验）→ 构造记录草稿（含项目费用列表；全空草稿跳过；提交清单**原样交出原始三值**，"材料/工时有值但项目费用为空"由写 seam——关联行 companion 内置 `RecordRules.normalizeItemCost`——按材料+工时补齐，2026-09-20 数据不变量、2026-09-25 收编单点；正常交互下算链/打开回填已填好项目费用，绕过输入事件的路径由 seam 兜住；编辑打开时 `_backfillMissingCosts` 立即回填显示，所见即所得）→ 为每个选中项目建间隔输入草稿（草稿生命周期归控制器） | — |
| 2a | 控制器 `_findMileageConflict` → `RecordRules.conflictingMileageRecord`（domain 纯函数）；弹窗实现 `RecordFormUi.askMileageProceed` 注入 | **里程单调性软提示（2026-09-17 新增，新增与编辑都查——区别于步骤 0b 同日查重只查新增）**：草稿与该车全量记录构成"里程不随日期单调非降"（存在记录晚于草稿但里程更低，或早于草稿但里程更高；等里程不算冲突，同日跳过——同日由步骤 0b/唯一约束兜底；编辑经草稿自身 id 排除自己）→ `showConfirmDialog`"与已有记录不一致"（文案含参照记录日期+里程，按钮**仍要继续/返回修改**）：「仍要继续」→ 放行进第二步；「返回修改」/点遮罩 → 留在第一步改日期或里程。**纯提示不拦截保存、两分支都不写库**；记录快照未就绪跳过检查（保存时既有校验兜底）。规则单测（含变异验证）`test/domain/record_rules_test.dart`；分支流转（三态+编辑排除自身，变异 3/3 锁定）`test/features/record_form_controller_test.dart`；弹窗文案 smoke `test/widget/records_test.dart` | — |
| 3 | 第二步 `_buildIntervalStep`（:752） | 每个项目"按里程/按时间"间隔输入（预填当前值，可改，可返回上一步；间隔草稿持有权在控制器 `form.intervalDrafts`） | — |
| 4 | widget `_submit()`（:806）→ 控制器 `RecordFormController.submitPayload` → `records/record_interval_updates.dart → buildItemUpdates()` | 控制器把间隔草稿整理成待更新项目实体清单：正整数校验（规则收在 `MaintenanceRules.validateIntervals`，**与保养项目表单共用**，文案经 `intervalProblemText` 生成、带项目名前缀）；**有变化的项目**才生成 update 实体（注入时钟重建实体的 sync 元数据）。仍在第一步时先推进不自动提交（历史行为）。草稿类与清单生成收在 `record_interval_updates.dart`（单测 `test/features/record_interval_updates_test.dart`；校验规则单测在 `test/domain/maintenance_rules_test.dart`） | — |
| 5 | onSubmit（sheet 入口处）→ `shell_actions.dart → saveMaintenanceRecord`（动作层，ADR 0007） | 内部按 id 分流：新增 → `repository.saveMaintenanceRecordWithItemUpdates`（lunio_repository.dart:329）；编辑 → `updateMaintenanceRecordWithItemUpdates`(:345)。两个入口与基础版（不带间隔更新）共用私有写管线 `_writeRecord`（:365），四入口收敛后新增写库不变量只改这一处。**单事务**：项目归属校验 → 同日唯一校验（`_ensureRecordIsUnique`，**R4 收紧后同车同日只允许一条记录**，已有记录即抛"这辆车当天已有保养记录，请编辑原记录"，不再区分项目是否相同）→ 插/改主表+关联表（**费用三列按 itemId 从 `record.itemCosts` 取，`_insertRecordItemRowsInTransaction`**）→ 车辆里程只增同步 → 更新项目间隔；写完失效车辆家族 | `maintenance_records` + `maintenance_record_items`（含费用三列）；可能更新 `cars.current_mileage_km`、`maintenance_items` 间隔 |
| 6 | 提交成功关 sheet + toast"保养记录已保存"（表单运行时统一收口，ADR 0016） | 记录页/提醒页/通知签名全部刷新 | — |

### 4.3 删除记录

| 操作 | 代码位置 | 数据变化 |
|---|---|---|
| 按周期删整条 | `records_page.dart → deleteMaintenanceRecord` → 确认框 → `shell_actions.dart → removeMaintenanceRecord`（动作层：`repository.deleteMaintenanceRecord`，事务删主表+关联 + 失效） | 删 1 条记录 + N 条关联（含费用） |
| 按项目删单项 | `records_page.dart → deleteMaintenanceRecordItem` → 确认框（带项目名）→ `shell_actions.dart → removeMaintenanceRecordItem`（动作层：`repository.removeMaintenanceRecordItem`(:486)：**只剩这一项时连记录一起删**（返回 true），否则只删关联行 + 失效） | 删关联行（该项目的费用随行删除，总费用不动；或整条记录） |

### 4.4 记录详情弹窗（ADR 0010）

**入口**：按周期视图点记录卡任意位置（`RecordCycleCard` 内 `InkWell`）或按项目视图点项目行（`RecordItemRowCard`）→ `record_detail_sheet.dart → showRecordDetailSheet`（弹窗自取数据：自己 watch 该车**全量**记录与项目两个 provider，卡片不再透传 `carRecords`——按项目视图找"上一条"必须用未筛选列表、按年份筛选会把上一条筛掉，这条知识现在是弹窗内部的实现细节）。

| 视图 | 内容 | 展示规则 |
|---|---|---|
| 按周期（整条记录） | 标题"保养记录" + 副标题"整条记录总费用 ¥xx" + 日期/里程/总费用指标格 + 备注（有才显示）+ 项目费用清单（每勾选项目一行：项目名 + 项目费用，未填显示"—"，填了材料/工时的加小字"材料 xx / 工时 xx"） | 展示永远取存储值：单项目以项目费用为准、整条记录以总费用为准；不一致的项目费用/总费用加黄色警告角标，**不做读时修正** |
| 按项目（单项目） | 标题=项目名（无副标题）+ 日期/里程指标格 + 距上次时间/里程指标格 + 材料费/工时费一行（两者都未填整行不显示，只填一格另一格显示"—"）+ 项目费用格（保留不一致黄三角）。距上次参照点 = 该项目**上一条记录 → 本条**（`RecordRules.previousRecordForItem`：严格早于本条日期的最新一条，同车同日唯一保证可唯一定位；项目首条无上一条 → 两格都显示"—"） | 同上；差值经 `RecordRules.daysSinceLast` / `kmSinceLast` 计算，负值（补录乱序）/无上一条在 domain 折叠成 null，`formatters.dart → formatDaysSinceLast` / `formatKmSinceLast` 只把 null 显示"—" |

### 4.5 费用统计（今年保养/今年加油汇总行 + /cost-stats 统计页，2026-09-17 新增；2026-09-20 单车化 + 优惠分摊；2026-09-21 详情/钻取增强；2026-09-21 改版：条形占比、年度走势、其他段守恒；2026-09-22 新增加油费用卡，汇总行拆今年保养/今年加油，ADR 0015；2026-09-23 改版：走势改年度柱、加油卡删年度行改全历史月度柱；2026-09-24 原型选型改版：走势/加油改坐标系柱状图、占比改堆叠条+明细行、走势卡改名"保养费用"；同日第五轮：占比/加油卡头部一行化、柱色统一、超一屏滚动+滚动条、加油记录卡删展开收起改卡内滚动）

**纯读取聚合**：不动数据库、不走动作层（无写点）。聚合口径唯一实现在 `lib/features/shell/records/cost_stats.dart`（纯函数 `buildCostStats`，单测含变异验证 `test/features/cost_stats_test.dart`）：**总额/年度/月度用记录总费用（权威值）**，与项目费用合计不一致仍按总费用（ADR 0010 口径）；**项目计费值 = 项目费用**（没填即不参与，材料/工时不做读侧兜底——不变量由写 seam 单点保证：关联行 companion 内置 normalizeItemCost，2026-09-21 拍板删兜底分支、2026-09-25 写侧收编单点），按**项目名**聚合（清单外归"未知项目"），**全部项目列出不截断、按实付降序**；**年度走势**每年一点（= 该年总费用），跨度首条记录年 → 今年、无记录年补 0（不再有"近一年/近半年"窗口，也不再依赖 `addMonths`；其 floor 语义回归测试仍在 `test/domain/app_date_context_test.dart`；2026-09-24 起展示为坐标系年度柱状图、卡名改"保养费用"，见下表）。**优惠分摊（2026-09-20）**：记录级总优惠 = Σ项目费用 − 记录总费用（负差值 = 无优惠按 0；无项目费用记录 Σ=0 自然不参与），按各项目费用权重分摊（`allocateDiscount` 泛型最大余数法，分摊合计与总优惠严格相等、每项分摊 ≤ 项目费用），纯读时派生不改存储值。**其他段守恒（2026-09-21）**：其他段 = 简洁模式记录的全部费用 + 单条记录"总费用超出项目费用合计"的差额，**总费用 ≡ Σ项目实付 + 其他段** 恒成立（此前"总花费 ≠ 项目实付"的口径缺口即由这两类无归属费用造成）；词汇见 CONTEXT.md「费用统计与优惠」。**汇总指标**：保养次数（总/今年）、单次均价（=总费用÷次数）、月均（=总费用÷首条记录月到当月的自然月数，全程摊薄、不随任何图表联动）、上次保养（`lastRecordDate` → 距今天数）。

| 用户操作 | 代码位置 | 做了什么 |
|---|---|---|
| 记录页头部汇总行（**保养或加油任一非空即显示**）："今年保养 ¥x" + "今年加油 ¥y"（2026-09-22 由单一"今年费用"拆分；**两段按域各自显隐**——无加油记录不显示"今年加油"，无保养记录对称隐藏"今年保养"，不留 ¥0.00 占位） | `records_page.dart → _CostSummaryRow`（保养口径 `costCentsForYear`、加油口径 `fuelCostCentsForYear`（`fuel_cost_stats.dart`，实付优先）；加油记录 watch `appliedCarFuelRecordsProvider`，未就绪按 0；生效今天未就绪兜底系统日期） | 整行可点 → `context.push('/cost-stats')` |
| 我的页「数据与工具」首行"费用统计 → 查看" | `profile_page.dart`（`ProfileSettingRow`，onTap `context.push`） | 进同一统计页 |
| 统计页作用域（**永远当前应用车辆，2026-09-20 拍板移除"全部"/切车 chips**） | `cost_stats_page.dart → costStatsDataProvider`（**非 family**，watch `appliedCarProvider` + 按车 family；2026-09-22 起同源拉 `fuelRecordsForCarProvider` 供加油费用卡） | 应用车辆解析完成前整页 loading，解析失败走错误页兜底（带返回键）；当前车辆名在标题副字"当前车辆：XX"展示；无车 → "请先新增车辆"空态 |
| 加油费用卡（2026-09-22 新增，ADR 0015；`fuelRecords` 非空才渲染，**固定页面最后**；2026-09-23 删年度行——卡内无任何按年统计；2026-09-24 加坐标系样式，同日第五轮：头部一行化 + 删"N 笔"换月均 + 月柱间距加大） | 同页 `_FuelCostCard`（无内嵌 state；逐月聚合在 `fuel_cost_stats.dart` 纯函数 `fuelMonthlyCents(records, today)` → `FuelCostMonthPoint` 全历史序列，实付优先口径；卡头数字 `buildFuelCostStats(records, today)` 含月均） | 头部一行 = "总费用"标签 + 金额（15/w800，基线对齐）+ 右侧"月均 ¥y"（= 总费用 ÷ 首条加油记录月到当月的自然月数，全程摊薄，口径同保养月均；2026-09-22 二轮反馈"总加油"改名"总费用"——本卡作用域就是加油；"n 笔"第五轮删除）；月份图 = 首条加油月 → 当月**全历史连续月度柱**（共用的 `_AxesColumnChart`：**纵轴固定左侧**三条刻度 + 虚线网格线，柱顶标 `formatMoneyCents` 全格式金额、0 元月灰色基线桩不标金额、轴标签"26.9"式；记录晚于生效今天（手动日期异常）时序列终点顺延不丢钱） |
| 汇总指标行 | 同页 `_buildMetricsCard` | 保养次数（副字"今年 n 次"）/ 单次均价 / 月均（全程摊薄定值）/ 上次保养（"n 天前"，当天为"今天"），四块一行 |
| 项目占比（2026-09-24 C 方案改版：**100% 堆叠条 + 紧凑明细行**，替代每行条形轨道；同日第五轮：头部两行压成一行）→ 点项目行 → 项目档案 sheet | 同页 `_buildProjectCard` + `_shareRow` + `_stackColor` → `cost_item_history_sheet.dart → showCostItemHistorySheet`（`buildItemHistories` 聚合，按项目名映射） | 头部一行 = "总费用"标签 + 金额（15/w800，基线对齐）+ 右侧"累计优惠 ¥x"小字（无优惠整段省略；守恒锚点：各行相加 ≡ 总费用）；**堆叠条**：一条 14dp 高的满宽条按实付降序分段（主色透明度深→浅、"其他"段灰），分段宽度 = 实付占比，入场随 `_entrance` 从左往右长出；**明细行** = 色点 | 项目名（截断）| 百分比 | 省额 | 实付——三个数值列**固定槽右对齐**（百分比 34 / 省额 52 / 实付 64，无优惠行省槽留空；2026-09-24 用户点名要求竖向对齐），百分比 = 实付 ÷ 总费用取整；行带 `cost-pct/cost-amt-<项目名>` key 供对齐断言，堆叠段带 `cost-seg-<项目名>` key；实付降序、全部项目不截断；末尾"其他"段（仅有缺口时出现）= 简洁模式费用 + 总费用超出项目合计的差额，不可下钻。档案头：次数/单次均价（累计实付÷次数）/累计计费三格 + 副字累计实付（有优惠附省额）；逐次明细日期倒序（日期、里程、实付 + 优惠小字）。费用全空的记录不进档案 |
| 保养费用（2026-09-24 由"保养费用走势"改名并改 **A 方案坐标系年度柱状图**；同日第五轮：柱色统一、删今年高亮、图表行为与加油卡统一；≥2 条保养记录才展示，单年车多条记录也展示） | 同页 `_YearTrendCard` → 共用 `_AxesColumnChart`（`data.records.length >= 2` 门卫；数据复用 `stats.years` 年度聚合） | 每年一柱（= 该年总费用，无记录年灰桩补 0），柱色统一主色、无高亮（第五轮删"今年柱主色高亮"）；纵轴固定左侧三条刻度（0/半峰/峰，步进取整 ¥50→¥1 万档、峰刻度 ≥ 最大柱值）+ 横向虚线网格线（`_DashedLinePainter`）；柱顶标金额，柱体带 `cost-year-bar-<年>` key 供 widget 断言 |
| 统计页内容（柱形为 Widget 组装 + 网格线自绘虚线 painter；一次性入场动画 700ms，各卡共用同一 AnimationController；坐标系柱状图 `_AxesColumnChart` 行为统一——2026-09-24 第五轮：列基准宽 64、柱宽 16，放得下视口等分铺满无滚动条，放不下定宽横向滚动 + 底部常显 3dp 滚动条（与轴标签间距 6dp）+ 初始停最右且**停在整柱边界**（视口取整放下整数根柱、柱宽微调放大，滚动范围恒为柱宽整数倍——默认显示两缘都是完整的月/年，不露半根，同日复验反馈）+ **停稳吸附整柱**（`RowSnapScrollPhysics`，2026-09-24 二次复验补齐；纯手势层对齐不记录），纵轴不随滚动消失） | 同页 `_buildSummaryCard` / `_buildMetricsCard` / `_buildProjectCard` / `_YearTrendCard` / `_FuelCostCard` / `_AxesColumnChart` | 汇总卡（**总费用 + 今年保养，有加油记录追加"今年加油"第三栏**（2026-09-22 二轮反馈：无加油记录不显示该栏））→ 指标行 → 项目占比（堆叠条 + 明细行）→ **保养费用卡**（≥2 条记录）→ **加油费用卡（固定页面最后，`fuelRecords` 非空才渲染）**；保养+加油都无记录 → 空态卡，只有加油 → 保养区降一行"暂无保养记录"轻提示，无车 → "请先新增车辆" |
| 返回 | 顶部栏 leading 返回键（`context.pop`）+ iOS 右滑返回（默认转场天然支持） | — |

**路由与安全区**：`lib/app/app_router.dart:61 → /cost-stats` 是第一个**不挂主壳层的 pushed 子页**（不渲染 AppShell 无底部导航，页面自带 Scaffold；builder 默认 MaterialPage 转场）。`LunioPage`/`LunioTopBar`为此增加可选 `leading` 位；**安全区由 `LunioPage` 内置 `SafeArea` 统一提供（2026-09-20）**——tab 页壳层（app_shell.dart:162）已包一层、嵌套幂等零行为变化，pushed 子页不挂壳层也能天生拿到顶部安全区与底部手势条避让（此前 /cost-stats 标题顶进状态栏的根因即"壳层包 SafeArea 而 pushed 页没人包"）。`initialLocation` 支持 `--dart-define=LUNIO_INITIAL_ROUTE=...` 覆盖（仅模拟器截图/验收用，默认 `/reminders` 行为不变）。widget 测试 `test/widget/cost_stats_test.dart`（渲染/指标行/占比堆叠条与三列对齐/守恒/单条记录保养费用卡隐藏/单年双条展示/项目档案/优惠/加油卡坐标系月度柱与初始停最右/空态/两入口跳转/返回键/错误页兜底）。

---

## 5. 我的页（/me）

页面装配：`lib/features/shell/profile/profile_page.dart:27 → ProfilePreviewPage`（结构：我的车辆 / 数据与工具——首行「费用统计」进统计页（§4.5）/ 版本 footer）。

### 5.1 车辆管理

#### 5.1.1 添加车辆（两步向导）

**入口**：我的页"我的车辆 → 添加"（profile_page.dart:56）或提醒页/我的页空卡片"新增车辆" → `vehicles.dart:297 → showAddCarSheet`。

| 步骤 | 代码位置 | 做了什么 | 数据变化 |
|---|---|---|---|
| 1 | `showLunioFormSheet` 预装载 `vehicleModelsProvider` + `effectiveTodayProvider`（ADR 0016：装载失败 toast 不开壳；目录为空守卫 toast"暂无可选车型"） | 装载结果经闭包共享变量传给向导 | — |
| 2 | 第一步 `AddCarForm`（add_car_wizard.dart:41 起） | 选品牌车型（`VehicleModelPicker`（vehicle_model_picker.dart:58）→ 双列选择 sheet `:117 → VehicleModelPickerSheet`，支持搜索——过滤/品牌派生/生效品牌回退是三个纯函数；**列表外可"＋ 自定义输入…"手输品牌车型**，ADR 0003）、**动力类型五选一 chip 行**（`PowertrainPicker`，按目录推荐值预选，换车型时重置推荐、用户可改）、当前里程、上路日期、油箱容积（选填，升，1–999、最多四位小数，`FuelRules.validateTankCapacity` 校验） | — |
| 3 | "下一步" → `AddCarWizardController.submitCarDraft`（add_car_wizard.dart:611；widget 侧 `_handleCarDraft` :480 只做刷新与 sheet 标题同步） | 草稿状态机（plain-Dart 控制器，单测 test/features/add_car_wizard_controller_test.dart）：同车型同动力复用草稿不重查、换键重转、竞态防御（等待中换车丢弃过期结果/过期失败）。模板加载/缓存归 `defaultItemsTemplateProvider`（providers.dart，**按"品牌·车型·所选动力类型"record 键缓存的 family**，内置只读数据不失效）：仓库 `resolveDefaultItems`（built_in_catalog_repository.dart，解析唯一入口）→ `ensureBootstrapData()` + **车型专属模板优先**（`listDefaultItemsForVehicleModel`：品牌+车型命中目录条目、条目带 itemTemplate、所选动力类型=推荐值三者都满足才命中，目前仅思域→civicFuel 14 项，ADR 0004；不落库）→ 未命中 `listDefaultItemsForPowertrain`（**按车的动力类型取**）；加载失败退回第一步、行内错误可见 | 只读，无写库 |
| 4 | 第二步 `AddCarMaintenanceItemsStep`（maintenance_items.dart:29） | 默认项目草稿可编辑（草稿表单 `:803 → showDraftMaintenanceItemFormSheet`，纯内存）/启停/删除（均受"至少一个启用项"拦截）/"恢复"补回被删默认项（`:141 → showRestoreDefaultItemsSheet` 勾选式） | 纯内存 |
| 5 | "保存车辆" → `AddCarWizardState._submit`（add_car_wizard.dart:497，校验在控制器 `validateForSubmit`）→ onSubmit（sheet 入口处）→ `shell_actions.dart → createCar`（动作层，ADR 0007） | `repository.createCarWithMaintenanceItems`（lunio_repository.dart:224，**单事务**：校验至少一个启用项目+逐项 validate → 插车辆 → 逐条插项目 → **无应用车辆时把新车设为当前**）；写完失效车辆家族 | `cars` +1、`maintenance_items` +N、可能写 `appliedCarId` |
| 6 | 提交成功关 sheet + toast"车辆已保存"（表单运行时统一收口，ADR 0016） | 提醒页立即显示新车 | — |

#### 5.1.2 编辑车辆

车辆卡"编辑" → `vehicles.dart:362 → showEditCarSheet` → `AddCarForm` 编辑模式（**品牌车型与动力类型只读**——身份字段，ADR 0003）→ `shell_actions.dart → updateCar`（动作层：`repository.updateCar`（lunio_repository.dart:291，写里程/日期/油箱容积/sync）+ 失效车辆家族）→ 提交成功关 sheet + toast"车辆已保存"（表单运行时统一收口，ADR 0016）。⚠ 里程可改小（无回退限制）。油箱容积在此可随时补填/修改（加油预估用，ADR 0002）。

#### 5.1.3 删除车辆

车辆卡"删除" → `shell_actions.dart → deleteCar` → 确认框 → 协调器 `runCarDeletion`（`notification_coordinator.dart`：**guard.beginDataReset()**——先 bump() 通知同步代数作废在途任务，再置写库中间态旗（`isDataResetInFlight`，状态在守卫模块 `notification_sync_guard.dart`，见第 3 节），再执行 `repository.deleteCar`（lunio_repository.dart 主仓库，**事务级联**：记录关联→记录→项目→appliedCarId 偏好（仅当指向本车，经偏好门面）→加油预测行与加油记录（借道 `FuelRepository.deleteForCar`，ADR 0014）→车辆；删完按 AppliedCarRules 把应用车辆指向剩余第一辆，无剩余清空），删完 **取消保养/里程 8000/8900 系系统通知**。R1：同步控制器在无车时短路不走重排，删最后一辆车后旧调度无人清理，必须显式取消；非最后一辆车的场景取消后会随 invalidate 触发的重排恢复。停车 9001~9004 与车辆无关，不在此处理。删库失败（异常）时旧通知原样保留）→ invalidate。收尾统一走 **guard.settleDataReset()**（finally：**再 bump 一次代数**——作废写库进行中才启动的同步任务——再关中间态旗；失败回滚时同样执行，对回滚后数据重算一轮无害）。

#### 5.1.4 切换当前应用车辆

| 入口 | 代码位置 |
|---|---|
| 提醒页右上角"切换车辆" | `vehicles.dart → showVehicleSwitcher`（async：先 await 车辆列表与应用车辆，加载失败 toast"车辆加载失败"；sheet 列车，点非当前车确认） |
| 车辆卡"应用"按钮 | `profile_page.dart` → `shell_actions.dart → applyCar`（动作层：经偏好门面 `LunioPreferences.setAppliedCarId` 写 `appliedCarId` + 失效车辆家族） |

切换 sheet 里的选中卡片同走 `applyCar`。

### 5.2 保养项目管理

#### 5.2.1 打开项目 sheet

车辆卡"项目" → `maintenance_items.dart:365 → showMaintenanceItemsSheet`（car 为空时管当前应用车辆）。sheet 项目列表 watch `providers.dart → maintenanceItemsForCarProvider`（**按车 family**，加载/竞态/缓存由 Riverpod 接管；`appliedCarMaintenanceItemsProvider` 也是它的派生），增删改经动作层失效车辆家族（含 family 整族失效）后列表自动重算，sheet 无本地刷新通道；重载中/重载失败保留旧列表（滚动位置不丢），失败时列表下方红条提示。

#### 5.2.2 各操作

| 操作 | 代码位置 | 数据变化 |
|---|---|---|
| 新增项目 | 卡片区"新增" → `:764 → showMaintenanceItemFormSheet`（表单：名称+里程/时间开关行+间隔，数字键盘；间隔正整数校验走 `MaintenanceRules.validateIntervals`，**与记录表单第二步共用**，文案经 `intervalProblemText` 生成、无项目名前缀）→ `shell_actions.dart → saveMaintenanceItem`（动作层，内部按 id 分流 `repository.saveMaintenanceItem`（lunio_repository.dart:516））→ 成功 toast"保养项目已保存" | `maintenance_items` +1 |
| 编辑项目 | 卡片"编辑" → 同上表单 → 同上动作层函数（`repository.updateMaintenanceItem`（:556）；停用态先过"至少一个启用"校验）→ 成功 toast"保养项目已保存" | 更新该行 |
| 启停项目 | 卡片"已启用/已禁用"按钮 → `:832 → toggleMaintenanceItem` → `shell_actions.dart → setMaintenanceItemEnabled`（动作层：`repository.setMaintenanceItemEnabled`（:590）+ 失效） | 更新 enabled |
| 删除项目 | 卡片"删除" → 确认框 → `:848 → deleteMaintenanceItem` → `shell_actions.dart → removeMaintenanceItem`（动作层：`repository.deleteMaintenanceItem`（:626，**有历史记录直接抛错**拒绝删除）+ 失效） | 删该行（或报错 toast） |

> "恢复默认"只存在于**添加向导草稿**内；已保存车辆没有该功能。

### 5.3 备份导出

我的页"备份数据" → `profile_page.dart → _exportBackup`（反馈薄壳）→ `shell_actions.dart → exportBackup`（动作层"备份与数据重置"分节，2026-09-25 自 settings_data.dart 收编）：

1. `backupRepository.exportBackupJson`——仓库内先 `exportBackupPayload`（4 张业务表 + 加油设置 + 加油记录全量读（不含偏好/停车倒计时/油价缓存/目录），schemaVersion 固定 3（v2 条目含记录的项目费用 `itemCosts`，ADR 0010；v3 增加油记录数组 `fuelRecords`——条目为 ADR 0015 应付/实付结构 {carId, date, grade, unitPriceCents, payableCents, actualCents, volumeLiters, sync}，容积恢复时由实体按应付÷单价重算）再 `BackupCodec().encode` 手写 JSON 序列化（编码收在 data 层，codec 不再出 data 层）；
2. `NativeFiles.exportJsonFile`（lib/core/platform/native_files.dart）——MethodChannel `lunio/native_files` → Android `MainActivity.kt`（ACTION_CREATE_DOCUMENT）/ iOS `SceneDelegate.swift`（临时文件+UIExporter）弹系统保存框，文件名 `lunio-backup-yyyyMMdd-HHmmss.json`（生成在动作层私有 `_backupFilename`）；
3. 返回值语义（动作层三函数统一）：`Future<bool>`——true=已保存 / false=用户取消保存框（静默，无 overlay）/ 失败异常穿透；成功"备份完成"与失败 toast 在页面薄壳。

### 5.4 恢复备份

我的页"恢复数据" → `profile_page.dart → _restoreBackup`（反馈薄壳）→ `shell_actions.dart → restoreBackupFromFile`（动作层，2026-09-25 收编；**确认框在动作层内弹**——deleteCar 同款破坏性例外）：

1. 确认框（明示"先清空本地车辆、保养项目、保养记录，再写入备份数据。**主题、通知等偏好设置会保留**"）；取消确认框/取消选文件静默返回 false、无 overlay；
2. `NativeFiles.pickJsonFile` 选文件 → `backupRepository.decodeBackupJson`（解码收在 data 层；版本∉{1,2,3} 抛 UnsupportedError；**v1/v2 备份兼容导入**——缺 `itemCosts` 字段等于项目费用全空（ADR 0010）、缺 `fuelRecords` 字段等于无加油记录（ADR 0014），纯增量缺失按空读入；**含旧结构加油条目的 v3 备份解码即拒**（ADR 0015 v3 就地重定义，前提=屏蔽期无真实加油数据）；
3. 协调器 `runBackupRestore`（`notification_coordinator.dart`）**guard.beginDataReset()**——先 bump() 通知同步代数（守卫模块 `notification_sync_guard.dart` 的 `notificationSyncGenerationProvider`，作废同步控制器在途任务）并**置写库中间态旗**（`isDataResetInFlight`，同步入口在此期间丢弃一切触发，见第 3 节）再执行恢复；
4. `backupRepository.restoreBackupPayload`——事务外**两层预校验**：引用完整性（`_validateBackupReferences`，含加油预测/加油记录的 carId 存在性）+ 业务规则（`_validateBackupBusinessRules`：逐条 `item.validate()` / `RecordRules.validateRecord` / 加油预测与加油记录实体 `validate()`，含项目费用金额非负且 itemId 在记录项目集合内，篡改备份直接拒绝且不碰库）→ 单一大事务：`_clearRestorableDataInTransaction` **只清 6 张业务表（4 张主业务表 + 加油预测设置 + 加油记录）+ 按前缀清提醒抑制键（snooze/ack），偏好整体保留** → cars→items→records→fuelPredictions→fuelRecords 逐行插入（id 全换新雪花 id，旧→新映射；**项目费用按备份旧 itemId 查表、随关联行恢复，"材料/工时有值但项目费用为空"的旧备份条目由关联行 companion 内置 `RecordRules.normalizeItemCost` 按材料+工时补齐（写 seam 单点，2026-09-20 数据不变量、2026-09-25 收编），恢复不把违规数据带进新库；加油预测/加油记录 carId 同表重映射**）→ 应用车辆指向第一辆；任何一行失败整体回滚；
5. 恢复成功后模板在**旗还举着时执行屏障重算**（`refreshProviders` 闭包，2026-09-26 新增）：`invalidateAllAppDataProviders` 全量失效 + 逐个 await 通知同步控制器监听的 6 个 provider 的新 future 全部落定（`notificationSettings/appliedCar/appliedCarItems/appliedCarRecords/effectiveToday/parkingCountdown`；单读失败不拦收尾）——屏障期间一切同步触发被入口早退丢弃，settle 时数据必然已收敛，"部分 provider 新、部分旧"的混合快照在结构上读不到（2026-09-26 真机复现残余漏洞的修复：settle 后重算未落定时同步控制器读到混合快照、票有效，算出全部短间隔项目按无历史基线到期的假弹窗）；
6. 模板收尾：**guard.settleDataReset()**（finally：**再 bump 一次代数**作废写库期间启动的同步 + 关中间态旗；失败回滚同样执行）→ 取消旧数据残留的 8000/8900 系（停车 9001~9004 与 iOS 实时活动**都不动**——停车倒计时偏好保留且其通知/活动仍有效）；恢复失败（异常上抛）时不取消，旧通知原样保留；
7. 成功结局模板**强制补判一轮**（失效 `notificationSettingsProvider` 让同步控制器重发一拍）：屏障吞掉了窗口内全部重算触发，settle 后没有自然触发，系统通知重排与应用内弹窗检查由这一轮用收敛后的最终数据补跑；失败结局数据已回滚、签名与数据仍一致，不会出假弹窗也无需补判；
8. 失败分支（错误分类留页面薄壳）：唯一约束冲突 → 弹"本次恢复未写入任何数据"对话框（`formatters.isUniqueConstraintError` 文本识别是 ADR 0009 明文的驱动层兜底口径）；其他 → toast。

### 5.5 清空数据

我的页"清空数据" → `profile_page.dart → _clearAllData`（反馈薄壳）→ `shell_actions.dart → clearAllData`（动作层，2026-09-25 自 settings_data.dart 收编；**确认框在动作层内弹**，取消静默返回 false）→ 确认框（明示"默认车辆模型与默认保养项目目录会保留"）→ 协调器 `runAllDataClear`（`notification_coordinator.dart`：**guard.beginDataReset()**——先 bump() 通知同步代数 + 置写库中间态旗（见第 3 节）→ `backupRepository.clearAllData`（事务删 7 张表：4 张业务表 + 加油预测设置表 + 加油记录表 + 偏好表，ADR 0014）→ **guard.settleDataReset()** 收尾（再 bump + 关旗）→ **撤 iOS 实时活动** → 取消停车 9001~9004 与保养/里程 8000/8900 系系统通知——偏好已删，倒计时与通知开关都不复存在，残留通知与活动必须撤清；清库失败异常上抛、不撤不取消）→ invalidate 全量（bootstrap 重灌车型目录）→ 成功 overlay"已清空数据"（失败 toast，反馈薄壳在 profile_page）。

### 5.6 通知设置

我的页"通知提醒" → `settings_notifications.dart → showNotificationSettingsSheet`（2026-09-25 自 settings_data.dart 拆出）：

1. `showLunioFormSheet` 的 `load` 预装载 `notificationSettingsProvider.future`（装载失败 friendlyError toast 且不开壳，杜绝 loading 期默认值覆盖真实设置；ADR 0016）；
2. 装载中协调器 `reconcileSystemEnabled`（`notification_coordinator.dart`）向系统查真实开关并回写偏好（不一致才写；查询失败回退偏好值，R14）；
3. 表单：系统通知状态行（只读）+ "系统设置"跳转（`NativeNotificationSettings` → 原生设置页，跳转后 sheet 关闭）+ 应用内通知开关 + 到期重复频率三段（每周/每 2 周/每月）；
4. 保存 → `shell_actions.dart → saveNotificationSettings`（动作层：先协调器 `reconcileSystemEnabled` 对账系统真值，再经偏好门面 `LunioPreferences.saveNotificationSettings`（**一个事务内批量写 3 个偏好 key**），协调器内部失效偏好缓存）→ 提交成功关 sheet + toast"设置已保存"（表单运行时统一收口，ADR 0016）→ 同步控制器签名变化触发系统通知重排。

> 产品口径：保养到期提醒是 App 核心能力，**不提供用户关闭入口**（R5 确认；原 `maintenanceDueEnabled` 偏好已于 2026-08-29 移除）。

### 5.7 手动日期（开发者模式专属）

1. 开发者模式：版本 footer **连点 5 次** → `profile_page.dart:156 → _handleVersionTap` → `shell_actions.dart → setDeveloperModeEnabled`（动作层：写 `developerModeEnabled`，关闭时**连带清 `manualDateEnabled`/`manualDate`/`fuelPredictionEnabled`**——加油预测开关入口只在开发者模式可见）；
2. "手动日期"行 → `settings_manual_date.dart → showManualDateSheet`（2026-09-25 自 settings_data.dart 拆出）：开关+日期（1990~今天+10 年）→ `shell_actions.dart → saveManualDate`（动作层：写 `manualDateEnabled`/`manualDate` + bump 偏好纪元（ADR 0017））→ 提交成功关 sheet + toast"手动日期已保存"（表单运行时统一收口，ADR 0016）→ **`effectiveTodayProvider`（providers.dart:203）重算**，所有提醒进度/表单默认日期/通知签名里的 today 全部按新日期。

### 5.8 主题切换

我的页"主题模式"三段 → `settings_data.dart → ThemeModeSettingRow` → `shell_actions.dart → setThemeModePreference`（动作层）写偏好 `themeMode` → `themeModePreferenceProvider` 刷新 → `lunio_app.dart` MaterialApp.themeMode 生效（appRouter 单例保证不跳页）。

### 5.9 加油预测开关（开发者模式专属）

"手动日期"行下方的"加油预测"开关行 → `profile_page.dart → _FuelPredictionSettingRow`，切换写偏好 `fuelPredictionEnabled`（`profile_page.dart → _setFuelPredictionEnabled`）→ bump 偏好纪元 → **`fuelPredictionEnabledProvider`（providers.dart）重算**（ADR 0017） → `app_shell.dart` 底部导航实时插入/移除"加油"tab（无需重启 App）。关闭开发者模式时该偏好连带清掉（`_handleVersionTap`），加油 tab 随之消失；已填的加油数据保留。

### 5.10 加油页（/fuel，开发者开关打开时可见）

页面：`fuel/fuel_page.dart → FuelPreviewPage`，**标题与底部导航同名"加油"**（2026-09-17 从"加油预测"改名，新增加油记录流水后原名不准确，ADR 0014；开发者开关本身仍叫"加油预测"）。当前可见**三张卡**：油价卡 → 加满预估卡 → 加油记录卡（**记录卡于 2026-09-22 按 ADR 0015 重定义后重新挂载**，取代 2026-09-20 的入口注释隐藏）。数据规则（词汇表 CONTEXT.md / ADR 0001 / ADR 0002 / ADR 0006 / ADR 0015）：

1. **油价卡**：手填价优先于数据源价；"刷新" → `FuelPriceController.manualRefresh`（失败保留旧数据并 toast）；**价格行右侧动作按钮按状态切换（同一位置同一个按钮；价格文字与"— 元/升"占位价纯展示不可点）**：无手填价显示"手填"（主动作样式，唯一编辑入口）→ 点了 `showLunioFormSheet → _ManualPriceForm` 编辑油价（**输入框每次留空，不预填**；留空提交按校验错误"请输入价格"处理；装载/pop/toast 时序归表单运行时，ADR 0016），保存走 `shell_actions.dart → saveFuelManualPrice`（动作层：写 `fuelManualPrices` 偏好（按"省+油品"组合，`setFuelManualPrice`）+ bump 偏好纪元，ADR 0017）+ toast"手填油价已保存"；有手填价显示"重置"（弱化样式；**改手填价须先重置再重新手填**）→ 重置同样走动作层 `shell_actions.dart → saveFuelManualPrice`（pricePerLiter 传 null 删该组合键恢复数据源价 + bump 偏好纪元，ADR 0017；原旁路已于 2026-09-09 收编，ADR 0007 的例外消除）+ toast"已恢复数据源价"；**没拉到数据（无缓存/拉取失败/该省该油品无报价）时显示"— 元/升"占位价 + "暂无数据"胶囊，编辑同样走"手填"按钮**（油价获取中的加载态无按钮，不可点）。数据源是 `QiyouJiaFuelPriceSource`（qiyoujiage 网页宽松解析，**按当前省份抓详情页** `/hubei.shtml` 等，一次一省 + 调价预告，见 ADR 0006/0011；`fuelPriceSourceProvider` 在 `fuel/fuel_prices.dart`，注入可换源）。自动更新：AppShell/加油页 watch `fuelPriceControllerProvider`（`fuel/fuel_prices.dart`，缓存优先/新鲜期/换省守卫/自动拉取的编排都在它的 build），缓存距上次拉取 ≥10 个自然日或无缓存时静默拉取（缓存是**单省价表**：换省后缓存省份不匹配 → 油价卡按"暂无数据"展示、**不自动拉取，点"刷新"再拉新省**，用户决策 2026-09-12；价格里的省份守卫保证旧省缓存不透出），失败退回旧缓存。站点改版解析不到油价主体时抛 `FuelSourceException` → 控制器退回旧缓存；网络层已对字节流显式按 UTF-8 解码（该站响应头不带 charset），明文 http 在 iOS 走 ATS 例外域、Android 9+ 走 network security config 只对该域放行（见 ADR 0006）。
2. **预估下次油价块**（油价卡内，价格行下方）：标题"预估下次油价"（与"当前油价"同字号）；数值 = 生效价（手填优先）+ 调价预告变动中值（`FuelRules.predictedPricePerLiter`，先取整到分），价格旁带**涨跌箭头**（`Icons.trending_up`/`trending_down`，方向取预告 `trend`，与预估价的正负号同源；**红涨绿跌**复用语义 token：涨 `tokens.danger`、跌 `tokens.success`，见 DESIGN.md），右侧日期胶囊"X月X日调价"；展示样式与价格行一致（`_TagPill` 复用）。无预告/无基准价时显示"暂无调价预测"占位（无箭头），不算错误。**过期预告按无预告同占位**（调价日早于当前应用日期 `effectiveTodayProvider` 即过期，调价日当天仍有效；无年份预告按"离今天最近的同月日"定年，判定在 `FuelRules.isForecastExpired`，过滤统一走 `fuel/fuel_prices.dart → effectiveFuelForecastProvider`，ADR 0011 二轮修订）。
3. **省份/油品编辑**（并入油价卡，无独立设置区）：副标题"湖北 · 92#"两段各自可点（`_SettingHotspot`）→ 弹对应选择 sheet，单选即写偏好并关 sheet。省份用列表（`_SheetOptionList`，领域清单 `fuelProvinces` 31 项限高 320 可滚动、打开时定位到当前项；清单归属见 ADR 0001 附注）；油品固定 4 项，用一行胶囊单选（`_GradeChip`，sheet 贴内容收缩、无滚动无留白）。省份写 `fuelProvince`（默认湖北，偏好门面兜底），油品写 `fuelGrade`（默认 92#），写完 bump 偏好纪元（ADR 0017，偏好派生 provider 自动重算）。
4. **加满预估卡（滚动定档）**：表头四列"当前油量 / 可加油量 / 加满价格 / 调价后价格"（`_TierHeaderRow`，列宽比例与 `_TierRow` 一致）。全量档位列表（`FuelRules.allTierPercents`，100%→0% 每 2% 一档共 51 档），窗口可见 5 档、整表上下滚动，**右侧常显 3dp 滚动条**（2026-09-24 五轮复验补齐，与加油记录卡/费用统计图表同款；表头与行内容右缩进 12dp 给拇指让位、列对齐不受影响）；`RowSnapScrollPhysics`（2026-09-24 由本页私有类提升为 `shared/scroll_snap.dart` 共享，记录卡与统计图表同用）吸附整行边界（**按父物理自然弹道投射停点再取最近整行**，照搬官方 `FixedExtentScrollPhysics` 模式——快速甩动可连滚多档、慢速就近弹回，停点严格对齐整行），`ScrollEnd` 后第一行档位 = 剩余油量，经动作层 `shell_actions.dart → saveFuelBaseline`（ADR 0007，2026-09-25 收编，原 widget 直写+本地游标去重已删）写 `fuel_predictions`——仓库 `saveFuelPrediction` 同值 no-op（返回 false 即不失效 `appliedCarFuelPredictionProvider`），失败 toast「油量保存失败，请重试」留在本卡（默认 50%，初始定位不落库；无存档时停稳含 50% 也物化一行，见 ADR 0002 更新节）；进入页面定位到已存档位在第一行，换应用车辆/已存档位变化经 `ValueKey('车id:档位')` 强制重建 State 重定位（2026-09-25 修复换车残留旧车滚动位置；key 须带档位——`skipLoadingOnReload` 会让换车后首次重载先用旧车档位建 State）。右上角返回图标（置灰条件：已停在 50%）→ `animateTo` 滚回 50% 在第一行，停稳后写库。当前油量 = 档位/100 × 容积（`FuelRules.litersInTank`）；可加油量 =（100−档位）/100 × 容积（`FuelRules.litersToFill`）；加满价格 = 可加油量 × 生效价（`FuelRules.fullTankCostCents`，分存储）；调价后价格 = 可加油量 × 预估价（`fuel_prices.dart → predictedFuelPriceProvider`，无预告时显示"—"）；第一行档位高亮、无"（当前）"文字。
5. **油箱容积入口在车辆管理**：添加/编辑车辆表单填写（选填，见 5.1.1/5.1.2）；未填容积时加满预估卡显示引导"先在'我的 → 车辆管理'里填写油箱容积，才能估算加满金额"，不显示金额列表。
6. **加油记录卡**（`fuel/fuel_records_card.dart → FuelRecordsCard`，ADR 0015，2026-09-22 重定义）：
   - **摘要行**：`累计加油 ¥x · n 笔`，金额口径 = 实付优先、没填取应付（`FuelRecord.effectiveCostCents`）。
   - **记录行**：日期（ISO 紧凑形态）· 油品（92# 等）+ 金额（实付优先）；下行 `¥x.xx/升`，实付低于应付时带"省 ¥x"小字（实付 ≥ 应付不算省）。**行点按进编辑**（无冗余编辑图标）。列表倒序（最近优先）；超过 **5** 条收进固定 5 行高的**卡内滚动窗口**、右侧常显 3dp 滚动条（内容右缩进 12dp 给拇指让位，右对齐金额不与滚动条重叠；滚动停稳**吸附整行**——`RowSnapScrollPhysics` 纯手势对齐不记录；2026-09-24 第五轮：删除"展开全部/收起"按钮——展开后要滚到底才能收起的来回横跳没了，滚轮直接看全部）；不超过 5 条按实际行数自然排布、无滚动条；空态一行文案"还没有加油记录，点「记一笔」开始记录"。
   - **记一笔/编辑表单**（`showFuelRecordFormSheet`，新增与编辑共用一个 sheet）：五项字段——加油日期（`showSimpleDatePicker`，**上路日期起、上限今天，不能选未来**（2026-09-22 拍板，与保养记录同规则）；**无同日查重**——同车同日多箱合法）+ 油品（一行胶囊 92#/95#/98#/0#，**默认 92#**）+ 单价（`LunioNumberField` 元/升两位小数；**新增态且表单油品 = 油价卡油品时预填生效价**（手填价 > 数据源价，`showFuelRecordFormSheet` 里读 `effectiveFuelPriceProvider`），只在开表单时生效一次、切油品不重算，可改）+ 应付金额（必填，元两位小数）→ **箭头按钮（Icons.east，tooltip"同应付"）** → 实付金额（**选填**，点箭头一键回填应付值；留空 = 无优惠存 null）。校验：单价/应付必须大于 0、实付填了必须非负。保存提交生命周期走表单运行时把手 `FormSheetHandle`（ADR 0016）→ `shell_actions.dart → saveFuelRecord`（动作层按 id 分新增/编辑 + 整族失效，ADR 0007）→ toast"加油记录已保存"。容积 = 应付÷单价由实体构造时算好落库**预留**，页面任何地方不展示。
   - **删除**：只在编辑态出现（表单底部 danger 按钮）→ 确认框"删除加油记录"（确认框在调用方弹，动作经动作层 `removeFuelRecord`）→ toast"加油记录已删除"。
   - **不联动**：保存加油记录**不更新**车辆当前里程（保养记录是唯一写源）；加油记录不进保养费用统计（统计页另立加油费用卡，见 4.5）。满箱段油耗口径已随重定义删除（`FuelRules` 的段划分/均值函数与卡上油耗 UI 不复存在）。

---

## 6. 主壳层与通知同步引擎

### 6.1 底部导航

三个固定入口（提醒/记录/我的）+ 条件入口"加油"（`fuelPredictionEnabledProvider` 打开时显示，位于记录与我的之间；路由 /fuel 常驻，开关关闭时 AppShell 兜底重定向回 /me）。

`lib/features/shell/app_shell.dart → build`：三或四个 `_BottomNavItem`（加油项按 `fuelPredictionEnabledProvider` 插入），点击 → `dismissTransientUi`（收键盘/toast/snackbar，modal_feedback.dart）→ `context.go('/xx')` → NoTransitionPage 重建 AppShell（selectedIndex 由路由决定，语义 0=提醒 1=记录 2=加油 3=我的）。

### 6.2 生命周期与跨零点刷新

`app_shell.dart → didChangeAppLifecycleState`：resumed（回前台）转交 `_notificationSync.onAppResumed()`（清空应用内提醒签名并立即重跑同步，强制重查弹窗）+ 刷新 Android 导航 inset。Android 三键导航 inset 适配在 `_refreshAndroidSystemNavigationInset`（requestId+mounted 双检查）。

**跨零点静默刷新**：`_AppShellState._scheduleMidnightDateRefresh`（initState 启动）排一个对准下一个 00:00:00 的 Timer，触发时 `ref.invalidate(effectiveTodayProvider)`（"今天"是 FutureProvider 只算一次，跨零点不失效会让提醒页到期概览/待关注项目、"我的"页车龄停在昨天）→ 各 watch 方自动重建，通知同步控制器监听该 provider 静默重排系统通知 → 重新排次日零点。App 在后台时 Timer 挂起，回前台瞬间补触发。手动日期开启时重算结果不变，无害。dispose 取消 Timer。

### 6.3 系统通知同步引擎（核心机制）

**位置**：`lib/features/shell/reminders/notification_sync_controller.dart → NotificationSyncController`（AppShell 的 initState 创建并 `start()`，dispose 关闭；build 只渲染，无同步副作用）。

**触发**：`start()` 对 6 个 provider（通知设置/应用车辆/项目/记录/生效今天/停车倒计时）`ref.listenManual(..., fireImmediately: true)`——任何一个变化（含首拍）都调 `syncFromProviders`。

```
provider 变化 / 首拍 / 回前台（onAppResumed）
  → syncFromProviders：写库中间态旗为真直接丢弃（守卫模块
    isDataResetInFlight，见第 3 节）；否则读
    6 个 provider 当前值（loading 中当 null，数据齐才继续）
  → 拼"系统通知签名" = 重复频率 + 停车倒计时摘要 + 全量数据签名
      （reminder_notifications.dart → reminderNotificationDataSignature：
       车辆/项目/记录全部相关字段 + today 拼成一个大字符串）
  → 签名 != 上次记录？
      是 → 记录新签名 → _applySystemNotificationSchedule
             ├─ 执行中又有新签名 → 置 pending，本轮 finally 置空签名
             │   并用最新数据重跑一轮（不丢更新，R3）
             ├─ 开关关 → cancelLunioNotifications（全取消）
             ├─ 协调器 ensureSystemNotificationsSchedulable（查系统开关、
             │   必要时补请求/回写偏好，仍不可用则回写关并取消）
             ├─ buildScheduledNotifications（reminder_notifications.dart）
             │    ├─ 到期项目（"稍后提醒"过滤，经协调器静默读）≥1 → 汇总通知 id 8000
             │    └─ 里程更新到期且未"稍后提醒" → id 8900（9:05 错峰）
             └─ Android 申请精确闹钟 → reschedule 前再问一次同步票 isValid
                  → rescheduleNotifications（lunio_notification_service.dart：
                     先精确取消 16 个在用 id（8000-8007/8900-8907，R10 收紧），
                     再每条通知排 8 次重复，
                     避开停车到点时刻 ±5 分钟步进错峰；月/日步进按日历字段
                     计算（R34：月末钳制 + 不做 24 小时累加））
      否 → 什么都不做
```

**防竞态四层**（状态与票的单一事实来源：`reminders/notification_sync_guard.dart → NotificationSyncGuard`，2026-09-25 收编；协调器是唯一写者，同步控制器与协调器读票）：① 同步代数（`notificationSyncGenerationProvider`，已随守卫收编迁出 providers.dart；删车/恢复/清空由协调器 run* 模板经 guard.begin/settle 在写库前后各 bump 一次——前者作废写库前已在途的任务，后者作废写库进行中才启动的任务）；② 中间态守卫（破坏性写库事务进行中，`syncFromProviders` 入口查守卫 `isDataResetInFlight` 旗直接丢弃、弹窗展示前再复查，见第 3 节）；③ 执行中 pending 重跑（不丢更新，系统通知与应用内弹窗两条路径都有，控制器私有 `_GuardedOp`）；④ `_disposed` 检查（控制器随主壳层销毁后所有 await 检查点放弃）。①②④ 合成一张同步票 **SyncRun**：各异步任务开工时 `guard.acquire()` 领票（可注入 disposed），每个不可逆副作用（排通知/弹窗）之前问一次 `run.isValid`（= 未销毁 && 无旗 && 代数未变）——检查点不再手抄协议（CONTEXT.md 词汇：**同步守卫**）。

> 通知域协议（权限真值对账、删车/恢复/清空的通知清扫、"稍后提醒/知道了"静默读写）的执行体集中在 `reminders/notification_coordinator.dart → LunioNotificationCoordinator`（CONTEXT.md 词汇：**通知协调器**）；控制器保留被动监听外壳，停车倒计时的通知尾巴由协调器 `onParkingCountdownSaved/Cleared` 承接。

**一句话：任何数据/偏好变化 → provider 变更 → listenManual 回调 → 签名 diff → 全量重排系统通知。**

### 6.4 系统通知 id 分配表

| id 段 | 用途 | channel |
|---|---|---|
| 8000-8007 | 保养到期汇总通知（8 次重复） | lunio_maintenance_due_heads_up |
| 8900-8907 | 里程更新提醒（9:05 起，8 次重复） | lunio_mileage_update_heads_up |
| 9001 | 停车到点闹钟 | lunio_parking_due_heads_up（alarm，显示名"Lunio 停车提醒"） |
| 9002 | Android 停车进行中常驻通知（chronometer 倒计时，到点自毁） | lunio_parking_ongoing |
| 9003 | 停车预警：剩 15 分钟（保存时剩余 ≥ 30 分钟才排） | lunio_parking_due_heads_up（alarm） |
| 9004 | 停车预警：剩 5 分钟（同上，与 9003 成对） | lunio_parking_due_heads_up（alarm） |

> iOS 停车实时活动（ADR 0012）不走通知 id 体系：活动由 ActivityKit 管理、系统托管展示，见 §2.2.1。

### 6.5 桌面小组件快照同步（iOS，ADR 0013）

保养提醒桌面小组件（`LunioWidgetsExtension`：小/中两档，小=概览+top4 密集单行、中=车名+概览+top3 两行项目行）只渲染快照、不做计算。快照链路：

```
数据变化（记保养/改项目/改里程/切车/手动日期/跨零点…）
  → 4 个数据上游 provider 重算
  → WidgetSnapshotController（widget_snapshot_controller.dart，AppShell initState 挂载，
     listenManual fireImmediately 监听，模式同 §6.3 通知同步）
      ├─ 任一上游 loading → 跳过，等就绪那一拍补写
      ├─ buildWidgetSnapshotJson（widget_snapshot.dart 纯函数）：
      │    当前应用车辆 + 有效今天 → top4 行 + 概览 + 空态（复用 reminder_rows
      │    组装/分类单一出口）+ 未来 14 天逐日条目（预生成窗口，逐日重算）
      │    （行详情按轴到期表达：哪轴到期说哪轴、都到期都说，未到期回退
      │     里程优先的剩余行——ReminderViewData.dueDetailText）
      ├─ 内容与上次相同 → 不重写；写入失败 → 不记账，下个触发点重试
      └─ lunio/native_widgets 通道 → LunioWidgetSnapshotStore.save
           （App Group `group.com.example.lunio` 的 UserDefaults）+ reloadAllTimelines
```

小组件扩展侧（`MaintenanceOverviewWidget.swift`）：快照条目 → 各日本地午夜时间轴，系统到点自动换页（App 不在也翻页）；窗口耗尽停在最后一条、半天兜底重试；无快照/契约版本不符（`schemaVersion` ≠ 1）渲染"打开 Lunio 同步车况"占位；空态三态渲染引导文案。点击小组件经 `widgetURL`（`lunio:///reminders`，2026-09-16 接入）唤起 App：冷启落默认首屏（提醒页），热启经 Flutter scene delegate 转发给 go_router 跳回提醒页。

**改快照 JSON 契约**：`widgetSnapshotSchemaVersion` +1 → 同步 Swift 侧 `LunioWidgetSnapshot` 模型 → 两端测试同改；快照 key/存取只在 `LunioWidgetSnapshotStore.swift`，App Group 标识跟 bundle id 走（改 bundle id 时两个 entitlements + `appGroupId` 常量一起改）。

**一句话：任何提醒数据变化 → provider 变更 → 监听器自动重写 App Group 快照并请求系统刷新；业务动作层（§0）对此零感知。**

---

## 7. 数据与偏好速查表

### 7.1 数据库表（schemaVersion = 2，`lib/data/database/app_database.dart`）

| 表 | 内容 | 关键唯一约束 |
|---|---|---|
| cars | 车辆（含油箱容积；含动力类型，默认 fuel） | {brand, model, roadDate} |
| vehicle_models | 内置车型目录（bootstrap 灌入，含推荐动力类型 template） | {catalogId}, {brand, model} |
| vehicle_default_maintenance_items | 默认项目模板，**按动力类型分组**（五组共 46 项，bootstrap 灌入） | {catalogId}, {powertrainType, itemName} |
| maintenance_items | 车辆保养项目 | {carsId, name}；普通索引 cars_id |
| maintenance_records | 保养记录主表 | **{carId, date}（一天一条）**；普通索引 car_id |
| maintenance_record_items | 记录-项目关联 + **项目费用三列**（材料/工时/项目费用，单位分可空，ADR 0010） | {carId, date, itemId}；普通索引 maintenance_record_id |
| app_preferences | 偏好 KV | {key} |
| fuel_predictions | 加油预测设置（剩余油量=基准档，容积在 cars） | {carId} |

### 7.2 偏好 key 清单（app_preferences 表；key 常量与编解码的唯一出口：`lib/data/preferences/app_preferences.dart → LunioPreferences`）

| key | 含义 | 写入点 |
|---|---|---|
| `appliedCarId` | 当前应用车辆 id | applyCar / getAppliedCar 回退 / 删车 / 恢复备份（恢复只替换业务数据，偏好保留） |
| `themeMode` | light/dark/system | 主题切换 |
| `systemNotificationsEnabled` | 系统通知开关 | 通知协调器（reconcile 回写 / saveNotificationSettings / 被拒回写） |
| `systemNotificationPermissionRequested` | 是否请求过权限 | 通知协调器 requestPermission |
| `inAppNotificationsEnabled` | 应用内弹窗开关 | 通知协调器 saveNotificationSettings |
| `maintenanceDueRepeat` | 到期重复频率 | 通知协调器 saveNotificationSettings |
| `developerModeEnabled` | 开发者模式 | 动作层 setDeveloperModeEnabled（入口：版本连点） |
| `manualDateEnabled` / `manualDate` | 手动日期 | 动作层 saveManualDate（手动日期 sheet / 关开发者模式连带） |
| `parkingCountdown` | 停车倒计时 JSON（**不进备份**） | 停车保存/结束 |
| `fuelPredictionEnabled` | 加油预测功能开关 | 动作层 setFuelPredictionEnabled / 关开发者模式连带清除 |
| `fuelProvince` | 加油预测省份（默认湖北，**进备份**） | 加油页省份 sheet / 恢复备份 |
| `fuelGrade` | 加油预测油品 code（**进备份**） | 加油页油品分段 / 恢复备份 |
| `fuelPriceCache` | 油价缓存 JSON（当前省价表 + 调价预告，**不进备份**；ADR 0011） | FuelPriceController 拉取成功 |
| `fuelManualPrices` | 手填油价 JSON（**不进备份**） | 加油页手填/清除手填 |
| `maintenanceReminderSnoozedUntil:<itemId>` | 保养项 snooze 截止日 | 通知协调器 snoozeMaintenanceItems（应用内弹窗调用） |
| `maintenanceInAppReminderAcknowledgedOn:<itemId>` | 保养项当日 ack | 通知协调器 acknowledgeMaintenanceItem |
| `mileageUpdateSnoozedUntil:<carId>` | 里程提醒 snooze | 通知协调器 snoozeMileageUpdate |
| `mileageUpdateInAppAcknowledgedOn:<carId>` | 里程提醒当日 ack | 通知协调器 acknowledgeMileageUpdate |

### 7.3 原生桥（MethodChannel）

| channel | Dart 侧 | 原生侧 |
|---|---|---|
| `lunio/native_files` | core/platform/native_files.dart | Android MainActivity.kt / iOS SceneDelegate.swift |
| `lunio/native_notification_settings` | core/platform/native_notification_settings.dart | 同上 |
| `lunio/native_system_ui` | core/platform/native_system_ui.dart | 仅 Android（iOS 返回 null 容错） |

---

## 8. 手册维护规则

1. **何时必须更新本手册**：改动涉及以下任一项——
   - 页面入口/操作步骤增删（新增按钮、改交互流程）；
   - 数据写点变化（新增偏好 key、改表结构、改 Repository 写方法的事务范围）；
   - 通知行为变化（id 分配、调度/取消时机、channel）；
   - Provider 依赖关系调整（新增/改名/改失效入口）。
2. **如何更新**：以"文件 + 函数名"为主锚点修正描述；行号尽量同步（`rg -n "函数名" 路径` 一查即得）。只改函数内部实现、不改流程时无需更新。
3. **关联文档**：视觉/token 改动同步 `DESIGN.md`；数据库结构改动同步 `docs/migration/current-database-schema.md`；已知问题与修复状态见 `docs/code-review-report.md`（修复后请把对应条目标记为已修复并注明版本）。
