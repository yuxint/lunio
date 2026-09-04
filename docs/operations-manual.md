# Lunio UI 操作手册（操作 ↔ 代码对照）

> 版本：2026-09-03 · 基于 schemaVersion 1 / 备份 schemaVersion 1 代码快照（同日数据层按域拆分，见 docs/adr/0008）
>
> **用途**：某个操作步骤出了问题，从本手册查到"这个操作经过哪些代码、改了哪些数据"，快速定位到文件和函数。
>
> **锚点约定**：引用格式为 `文件路径 : 行号 → 函数/类名`。代码改动后行号会漂移，**以"文件 + 函数名"为主锚点**，行号仅辅助；只改函数内部实现时通常无需更新本手册，改了流程/入口/数据写点才必须同步维护。
>
> **读法提示**（Java 背景）：`Repository` ≈ Service+DAO；`Provider` ≈ Spring Bean；`ref.invalidate` ≈ 缓存逐出。所有写操作的固定模式是：**UI 事件 → 动作层（shell_actions）写库 + invalidate → FutureProvider 重新查库 → UI 自动刷新**。

数据层按域拆成仓库家族（ADR 0008）：**主仓库** `LunioRepository`（车辆/项目/记录核心域）、`BuiltInCatalogRepository`（车型目录+bootstrap）、`FuelRepository`（加油域）、`BackupRepository`（备份/恢复/清空）、`LunioPreferences`（偏好门面，全部偏好 key 与编解码的唯一出口）。各域在 providers.dart 装配；表插入路径共享 `entity_row_codec.dart` 的 Companion 构造。

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
  → records_page.dart → MaintenanceRecordFormState._submit()     # UI 校验+构造实体
  → onSubmit 闭包（showMaintenanceRecordFormSheet 内）
  → shell_actions.dart → saveMaintenanceRecord(ref, ...)         # 动作层（ADR 0007）
      ├→ repository.saveMaintenanceRecordWithItemUpdates()       # 事务：校验+写库
      └→ invalidateVehicleProviders(ref)                         # 逐出缓存
  → appliedCarRecordsProvider 等重算 → AppShell build → UI 刷新
```

**保存动作层**（`lib/features/shell/shared/shell_actions.dart`，ADR 0007）：每个业务变更一个具名函数，内部固定编排"写库 → 失效对应 provider 家族 →（需要时）组合通知协调器"；只收 `WidgetRef`，不弹确认框、不 pop、不 toast，异常穿透给表单的行内错误机制。UI 侧只剩三行反馈薄壳：pop 用 sheet 的 context（`sheetContext.mounted` 检查）、toast 用打开 sheet 前的外层 context（`context.mounted` 检查）。**新增保存路径时进动作层加函数，不要在 UI 里手排失效序列。**

**保存成功反馈**：所有落库保存（保养记录/车辆新增编辑/保养项目/通知设置/手动日期/手填油价）成功关 sheet 后，统一在外层页面 context 弹轻量 toast"已保存"（`showStatusOverlay`，1.6s 自动消失，modal_feedback.dart）。

**数字输入键盘**：所有只填数字的输入框统一数字键盘——整数字段用 `TextInputType.numberWithOptions()`（免费时长/保养里程/费用外的里程/项目周期数字行），金额类带小数用 `numberWithOptions(decimal: true)`（费用/油箱容积）。

**底部弹窗关闭与键盘**：所有底部 sheet（`showLunioModalSheet`，modal_feedback.dart）的关闭/键盘行为统一由共享原语处理，页面不单独实现——① 下拉整块跟手：内容滚到顶部后继续下拉，sheet 跟手移动，松手超过 1/4 弹窗高度（矮弹窗按 80px 下限）或下滑够快即关闭，否则弹回；内容可滚时走内部出界滚动通知（`_SheetDragDismiss` 通知通道），内容收缩不满一屏时走外层手势（`canDrag=false` 时内部无识别器，出界通知不存在，Flutter 行为）。② 点弹窗内非输入框区域：只收键盘不关弹窗（`_LunioModalContent` 的 onTap unfocus，数字/全键盘一致）。③ 点弹窗外暗色遮罩区：直接关闭整个弹窗，无未保存确认（产品决策，与下滑关闭一致）。

**三大缓存失效入口**（`lib/app/providers.dart:205-230`）。ADR 0007 后主要调用方是保存动作层（shell_actions.dart）与通知协调器，UI 不再手排：

| 函数 | 失效内容 | 谁在调 |
|---|---|---|
| `invalidateVehicleProviders` (:205) | 车辆/车型/项目/记录 5 个 provider | 动作层车辆/项目/记录类函数 |
| `invalidatePreferenceProviders` (:214) | 开发者模式/手动日期/生效日期/主题/通知设置 | 动作层偏好类函数、通知协调器（WithRef 版） |
| `invalidateAllAppDataProviders` (:224) | 上述全部 + bootstrap + 停车倒计时 | 恢复备份 / 清空数据 |

**Provider 依赖图**（`lib/app/providers.dart`，文件头有注释版）：

```
appDatabaseProvider(:136) ─→ lunioRepositoryProvider(:144)
    ├─ developerModeProvider(:58) ─→ manualDatePreferenceProvider(:67) ─┐
    ├─ themeModePreferenceProvider(:86)                                 ├─→ effectiveTodayProvider(:127)
    ├─ notificationSettingsProvider(:99)                                │
    ├─ parkingCountdownProvider(:120)                                   │
    └─ defaultMaintenanceBootstrapProvider(:150)                        │
         ├─→ vehicleModelsProvider(:156)                                │
         └─→ carsProvider(:164) ─→ appliedCarProvider(:173)             │
                                   ├─→ appliedCarMaintenanceItemsProvider
                                   └─→ appliedCarRecordsProvider
```

---

## 1. 冷启动与首次进入

### 1.1 启动链路（App 进程启动 → 首帧）

| 步骤 | 代码位置 | 做了什么 |
|---|---|---|
| 1 | `lib/main.dart:20-37 → main()` | 初始化引擎绑定 → **await 通知服务初始化**（时区+插件，`:33`）→ `runApp(ProviderScope(LunioApp))` |
| 2 | `lib/core/notifications/lunio_notification_service.dart:78 → initialize()` | 时区数据库 + 本地时区（失败回退 Asia/Shanghai 并打日志，R34/R14）+ 插件初始化（iOS 不在此弹权限） |
| 3 | `lib/app/lunio_app.dart:31 → LunioApp.build` | watch 主题偏好 → `MaterialApp.router`，路由挂全局单例 `appRouter` |
| 4 | `lib/app/app_router.dart:26 → appRouter` | 三条平级路由，初始 `/reminders`，每条渲染 `AppShell(selectedIndex: n)` |
| 5 | `lib/features/shell/app_shell.dart:34 → AppShell` | 主壳首帧 build：watch 全部 provider（此时数据库才真正打开） |

**注意**：数据库是**惰性**打开的——`appDatabaseProvider`（providers.dart:136）首次被 watch 时 `new AppDatabase()`，而 SQLite 文件连接由 Drift LazyDatabase 推迟到第一条 SQL（`lib/data/database/app_database.dart → _openConnection`，后台 isolate 打开 `lunio.sqlite`）。

### 1.2 首次进入（无任何数据）发生了什么

| 步骤 | 代码位置 | 做了什么 | 数据变化 |
|---|---|---|---|
| 1 | `lib/app/providers.dart:150 → defaultMaintenanceBootstrapProvider` | AppShell 首帧 watch 触发 `ensureBootstrapData()` | 见第 2 步 |
| 2 | `lib/data/repositories/built_in_catalog_repository.dart → BuiltInCatalogRepository.ensureBootstrapData()` → `_ensureVehicleModels` + `_ensureDefaultMaintenanceItems` | 从 asset `assets/data/catalog/`（templates.json + vehicles_a–z.json 字母分片）加载目录（**2026-09-01 动力类型改版后为 1675 条：懂车帝在售 1645 + 停售 30，车系名用懂车帝原名，每条带推荐动力类型；默认保养模板按动力类型分五组；同日起精简为每品牌最多 10 款热门车型，现共 1223 条**，见 ADR 0003），**按 catalogId 幂等对账**写入两张内置表 | `vehicle_models`、`vehicle_default_maintenance_items` 两表灌入/更新 |
| 3 | `lib/features/shell/reminders/reminder_page.dart:102 → EmptyVehicleCard` | appliedCarProvider 返回 null → 显示"还没有车辆"卡片 | 无 |
| 4 | `lib/features/shell/app_shell.dart:244 → _syncReminderNotifications` | 系统通知开关为默认开 → postFrame 触发首启权限请求 | 见 1.3 |

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
| 品牌/车型/上路日期/当前里程 | `reminder_page.dart:110-129 → LunioHeroCard` | `appliedCarProvider`（providers.dart:173）→ `repository.getAppliedCar()`（lunio_repository.dart:314，含偏好失效回退逻辑） |
| "到期概览"文案（超期 x / 到期 x / 全部正常） | `reminder_notifications.dart:484 → dueOverviewText` | 全量重算提醒行（见 2.4） |
| 右上角"切换车辆"按钮（多车才显示） | `reminder_page.dart:97 → showVehicleSwitcher` | `vehicles.dart:1052`，见 5.1.4 |

### 2.2 停车倒计时

**开始**：

| 步骤 | 代码位置 | 做了什么 | 数据变化 |
|---|---|---|---|
| 1 | `reminder_page.dart:128`（倒计时为 null 时按钮可用，进行中禁用）→ `parking_countdown.dart:586 → showParkingCountdownSheet` | 弹表单 sheet | — |
| 2 | `parking_countdown.dart → ParkingCountdownForm`（约 230 行起） | 入场时间（**点按钮此刻实时取系统时间，秒/毫秒截 0 默认整分**；时间轮可改时分秒）+ 免费时长（数字键盘输入框或 0.5/1/2 小时快捷 chip） | — |
| 3 | 提交 → `parking_countdown.dart → saveParkingCountdown(context, ref, countdown)` | ① 写偏好（经偏好门面 `LunioPreferences.saveParkingCountdown`） ② 失效 ③ 通知尾巴委托协调器 `onParkingCountdownSaved`（`notification_coordinator.dart`）：若系统通知开 → 请求权限（被拒回写开关关）→ 调度前比对**通知同步代数**（保存期间发生恢复/清空则放弃）→ Android 精确闹钟 → 调度通知。写偏好/失效阶段检查页面 context 仍挂载；sheet 提前关闭时通知尾巴照常走完（调度不依赖页面） | ① `parkingCountdown` = JSON ② 系统通知 id **9002**（Android 常驻 chronometer）+ **9001**（到点闹钟）；`systemNotificationPermissionRequested=true`；被拒时 `systemNotificationsEnabled=false` |
| 4 | `lunio_notification_service.dart:243 → scheduleParkingCountdownNotification` | 先成对取消旧 9001/9002，再排新闹钟；**到点时刻已过则静默 return** | — |

**展示**：`parking_countdown.dart → ParkingCountdownCard`（ConsumerStatefulWidget）——进度规则在 `lib/domain/rules/parking_countdown_rules.dart`（剩余≤20% 黄、到期红转正计时）；颜色映射 `_parkingStatusColor`。**卡片内部 1s Timer 自刷新**（时钟走 `appDateContextProvider.readSystemNow()`，测试可注入），重建范围只有这张卡。

**结束**：卡片"结束"按钮 → `parking_countdown.dart → clearParkingCountdown(context, ref)` → 删偏好 key + 失效 + 通知收尾委托协调器 `onParkingCountdownCleared`（系统通知开着时取消 9001/9002）。

> 已知问题：到期后倒计时不自动清除（须手动结束才能开始新的，R9/R17）。恢复备份/清空数据后的 9001/9002 残留已修复（恢复保留停车偏好不动其通知；清空显式成对取消，见 §5.4/§5.5）。

### 2.3 新增保养记录入口

`reminder_page.dart:126` → 记录表单（完整流程见 §4.2）。

### 2.4 保养提醒列表（"待关注项目"）

| 步骤 | 代码位置 | 做了什么 |
|---|---|---|
| 1 | `reminder_list.dart:22 → ReminderList` | 空态处理：无任何记录 → "记录首保后再生成保养提醒"（产品口径：无记录不产生提醒）；无启用项目 → 引导去"我的"配置 |
| 2 | `reminder_notifications.dart:85 → buildReminderRows` | 只取启用项目 → 逐项找最近记录（`:455 → latestRecordForItem`，先比日期同日比里程）→ 调 **进度计算**（见下）→ 排序（状态→百分比→sortOrder） |
| 3 | `lib/domain/rules/maintenance_rules.dart:120 → progressForItem` | 里程维（当前里程−基线）/间隔、时间维（今天−基线日）/总天数，**双维取大**为展示进度；状态按项目阈值（默认 100 黄 / 125 红） |
| 4 | `reminder_list.dart:88 → ReminderRow` | 进度环（`ReminderProgressRingPainter`）+ 状态徽章 + 剩余里程/时间文案 |
| 5 | 点击行 → `reminder_list.dart:174 → showReminderRecordDetail` | 弹上次保养日期/里程 sheet |

---

## 3. 应用内提醒弹窗（snooze / ack）

**触发时机**：通知同步控制器检测"应用内通知开 + 到期项变化/回到前台"（`reminders/notification_sync_controller.dart → _showDueInAppNotifications`）。

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
| 切换"按周期/按项目" | `records_page.dart:56`（LunioSegmentedControl） | `selectedMode` 0/1 |
| 年份/项目多选筛选 | `records_page.dart`（两个 `_FilterBar`，已回收为页面私有） | `selectedYears`/`selectedItemIds` 集合仅由用户点击变更；渲染与过滤用派生集合 `_validSelections`（自动忽略已失效的年份/项目） |
| 按周期视图 | `records_page.dart → RecordCycleCard`（SliverList.builder 逐条懒加载，ValueKey('record-<id>')） | 一条记录一张卡（日期+金额+里程+备注+项目 pills+编辑/删除） |
| 按项目视图 | `records_page.dart → RecordItemRowCard`（同样懒加载） | 记录×项目展开成行，可单独删某项 |

### 4.2 新增 / 编辑保养记录（两步表单）

**入口**：提醒页"新增保养记录"按钮（reminder_page.dart:126）或记录卡"编辑" → `records_page.dart:997 → showMaintenanceRecordFormSheet`。

| 步骤 | 代码位置 | 做了什么 | 数据变化 |
|---|---|---|---|
| 0 | `showMaintenanceRecordFormSheet` 开头 | await 车/项目/今天三个 provider；无车或无可用项目 → toast 拦截 | — |
| 1 | `MaintenanceRecordForm`（:455 起）第一步 | 日期（范围=上路日期~今天+365）、里程（默认车辆当前里程）、费用（元输入）、备注、项目多选 chip；编辑态可见"已禁用但被选过"的项目 | — |
| 1a | 行内"新增"项目 | `records_page.dart:850 → _addMaintenanceItem` → 弹项目表单（§5.2.2）→ 重拉列表 → **diff 出新 id 自动勾选** | 新项目已落库 |
| 2 | `_buildRecordDraft()`（:660 附近）+ `_goToIntervalStep` | UI 校验（里程非负/费用非负/至少一项）→ 构造记录草稿 → 为每个选中项目建间隔输入草稿 | — |
| 3 | 第二步 `_buildIntervalStep` | 每个项目"按里程/按时间"间隔输入（预填当前值，可改，可返回上一步） | — |
| 4 | `_submit()` → `_buildItemUpdates()` | 间隔校验；**有变化的项目**才生成 update 实体 | — |
| 5 | onSubmit（sheet 入口处）→ `shell_actions.dart → saveMaintenanceRecord`（动作层，ADR 0007） | 内部按 id 分流：新增 → `repository.saveMaintenanceRecordWithItemUpdates`（lunio_repository.dart:667）；编辑 → `updateMaintenanceRecordWithItemUpdates`(:721)。**单事务**：项目归属校验 → 同日唯一校验（`:1227 → _ensureRecordIsUnique`，**R4 收紧后同车同日只允许一条记录**，已有记录即抛"这辆车当天已有保养记录，请编辑原记录"，不再区分项目是否相同）→ 插/改主表+关联表 → 车辆里程只增同步 → 更新项目间隔；写完失效车辆家族 | `maintenance_records` + `maintenance_record_items`；可能更新 `cars.current_mileage_km`、`maintenance_items` 间隔 |
| 6 | 反馈薄壳：关 sheet（sheetContext）+ toast"保养记录已保存"（外层 context） | 记录页/提醒页/通知签名全部刷新 | — |

### 4.3 删除记录

| 操作 | 代码位置 | 数据变化 |
|---|---|---|
| 按周期删整条 | `records_page.dart → deleteMaintenanceRecord` → 确认框 → `shell_actions.dart → removeMaintenanceRecord`（动作层：`repository.deleteMaintenanceRecord`(:784，事务删主表+关联) + 失效） | 删 1 条记录 + N 条关联 |
| 按项目删单项 | `records_page.dart → deleteMaintenanceRecordItem` → 确认框（带项目名）→ `shell_actions.dart → removeMaintenanceRecordItem`（动作层：`repository.removeMaintenanceRecordItem`(:802)：**只剩这一项时连记录一起删**（返回 true），否则只删关联行 + 失效） | 删关联行（或整条记录） |

---

## 5. 我的页（/me）

页面装配：`lib/features/shell/profile/profile_page.dart:20 → ProfilePreviewPage`（结构：我的车辆 / 数据与工具 / 版本 footer）。

### 5.1 车辆管理

#### 5.1.1 添加车辆（两步向导）

**入口**：我的页"我的车辆 → 添加"（profile_page.dart:56）或提醒页/我的页空卡片"新增车辆" → `vehicles.dart:907 → showAddCarSheet`。

| 步骤 | 代码位置 | 做了什么 | 数据变化 |
|---|---|---|---|
| 1 | sheet 内 watch `vehicleModelsProvider` + `effectiveTodayProvider` | 车型目录/日期加载失败给行内提示 | — |
| 2 | 第一步 `AddCarForm`（vehicles.dart:272 起） | 选品牌车型（`VehicleModelPicker` → 双列选择 sheet `:672 → VehicleModelPickerSheet`，支持搜索；**列表外可"＋ 自定义输入…"手输品牌车型**，ADR 0003）、**动力类型五选一 chip 行**（`PowertrainPicker`，按目录推荐值预选，换车型时重置推荐、用户可改）、当前里程、上路日期、油箱容积（选填，升，1–999、最多四位小数，`FuelRules.validateTankCapacity` 校验） | — |
| 3 | "下一步" → `AddCarWizardState._handleCarDraft`（vehicles.dart:510 附近） | 车型或动力类型变化才加载默认模板：`loadDefaultItems` 闭包（showAddCarSheet 内）→ `catalogRepository.ensureBootstrapData()` + **车型专属模板优先**（`listDefaultItemsForVehicleModel`：品牌+车型命中目录条目、条目带 itemTemplate、所选动力类型=推荐值三者都满足才命中，目前仅思域→civicFuel 14 项，ADR 0004；不落库）→ 未命中 `listDefaultItemsForPowertrain`（built_in_catalog_repository.dart，**按车的动力类型取**）→ 模板转项目草稿 | 只读，无写库 |
| 4 | 第二步 `AddCarMaintenanceItemsStep`（maintenance_items.dart:32） | 默认项目草稿可编辑（草稿表单 `:1007 → showDraftMaintenanceItemFormSheet`，纯内存）/启停/删除（均受"至少一个启用项"拦截）/"恢复"补回被删默认项（`:133 → showRestoreDefaultItemsSheet` 勾选式） | 纯内存 |
| 5 | "保存车辆" → `AddCarWizardState._submit` → onSubmit（sheet 入口处）→ `shell_actions.dart → createCar`（动作层，ADR 0007） | `repository.createCarWithMaintenanceItems`（lunio_repository.dart:224，**单事务**：校验至少一个启用项目+逐项 validate → 插车辆 → 逐条插项目 → **无应用车辆时把新车设为当前**）；写完失效车辆家族 | `cars` +1、`maintenance_items` +N、可能写 `appliedCarId` |
| 6 | 反馈薄壳：关 sheet（sheetContext）+ toast"车辆已保存"（外层 context） | 提醒页立即显示新车 | — |

#### 5.1.2 编辑车辆

车辆卡"编辑" → `vehicles.dart:988 → showEditCarSheet` → `AddCarForm` 编辑模式（**品牌车型与动力类型只读**——身份字段，ADR 0003）→ `shell_actions.dart → updateCar`（动作层：`repository.updateCar`（lunio_repository.dart:291，写里程/日期/油箱容积/sync）+ 失效车辆家族）→ 反馈薄壳关 sheet + toast"车辆已保存"。⚠ 里程可改小（无回退限制）。油箱容积在此可随时补填/修改（加油预估用，ADR 0002）。

#### 5.1.3 删除车辆

车辆卡"删除" → `shell_actions.dart → deleteCar` → 确认框 → 协调器 `runCarDeletion`（`notification_coordinator.dart`：**先 bump() 通知同步代数**作废在途任务，再执行 `repository.deleteCar`（lunio_repository.dart 主仓库，**事务级联**：记录关联→记录→项目→appliedCarId 偏好（仅当指向本车，经偏好门面）→加油预测行（借道 `FuelRepository.deleteForCar`）→车辆；删完按 AppliedCarRules 把应用车辆指向剩余第一辆，无剩余清空），删完 **取消保养/里程 8000/8900 系系统通知**。R1：同步控制器在无车时短路不走重排，删最后一辆车后旧调度无人清理，必须显式取消；非最后一辆车的场景取消后会随 invalidate 触发的重排恢复。停车 9001/9002 与车辆无关，不在此处理。删库失败（异常）时旧通知原样保留）→ invalidate。

#### 5.1.4 切换当前应用车辆

| 入口 | 代码位置 |
|---|---|
| 提醒页右上角"切换车辆" | `vehicles.dart → showVehicleSwitcher`（async：先 await 车辆列表与应用车辆，加载失败 toast"车辆加载失败"；sheet 列车，点非当前车确认） |
| 车辆卡"应用"按钮 | `profile_page.dart` → `shell_actions.dart → applyCar`（动作层：经偏好门面 `LunioPreferences.setAppliedCarId` 写 `appliedCarId` + 失效车辆家族） |

切换 sheet 里的选中卡片同走 `applyCar`。

### 5.2 保养项目管理

#### 5.2.1 打开项目 sheet

车辆卡"项目" → `maintenance_items.dart:364 → showMaintenanceItemsSheet`（car 为空时管当前应用车辆）。sheet 内部是**手写局部状态机**（`:415 → MaintenanceItemsSheetContent`，自管 loading/error/代数防乱序，不走全局 provider），每次操作后 `_reload` 重拉列表。

#### 5.2.2 各操作

| 操作 | 代码位置 | 数据变化 |
|---|---|---|
| 新增项目 | 卡片区"新增" → `:969 → showMaintenanceItemFormSheet`（表单：名称+里程/时间开关行+间隔，数字键盘）→ `shell_actions.dart → saveMaintenanceItem`（动作层，内部按 id 分流 `repository.saveMaintenanceItem`（lunio_repository.dart:516））→ 成功 toast"保养项目已保存" | `maintenance_items` +1 |
| 编辑项目 | 卡片"编辑" → 同上表单 → 同上动作层函数（`repository.updateMaintenanceItem`（:556）；停用态先过"至少一个启用"校验）→ 成功 toast"保养项目已保存" | 更新该行 |
| 启停项目 | 卡片"已启用/已禁用"按钮 → `:1038 → toggleMaintenanceItem` → `shell_actions.dart → setMaintenanceItemEnabled`（动作层：`repository.setMaintenanceItemEnabled`（:590）+ 失效） | 更新 enabled |
| 删除项目 | 卡片"删除" → 确认框 → `:1065 → deleteMaintenanceItem` → `shell_actions.dart → removeMaintenanceItem`（动作层：`repository.deleteMaintenanceItem`（:626，**有历史记录直接抛错**拒绝删除）+ 失效） | 删该行（或报错 toast） |

> "恢复默认"只存在于**添加向导草稿**内；已保存车辆没有该功能。

### 5.3 备份导出

我的页"备份数据" → `settings_data.dart:170 → exportBackup`：

1. `backupRepository.exportBackupPayload`——4 张业务表 + 加油设置全量读（不含偏好/停车倒计时/油价缓存/目录），schemaVersion 固定 1（只认当前版本，不做旧备份兼容，见 docs/adr/0005）；
2. `BackupCodec().encode`（lib/data/backup/backup_codec.dart）——手写 JSON 序列化；
3. `NativeFiles.exportJsonFile`（lib/core/platform/native_files.dart）——MethodChannel `lunio/native_files` → Android `MainActivity.kt`（ACTION_CREATE_DOCUMENT）/ iOS `SceneDelegate.swift`（临时文件+UIExporter）弹系统保存框，文件名 `lunio-backup-yyyyMMdd-HHmmss.json`；
4. 成功/失败 toast。

### 5.4 恢复备份

我的页"恢复数据" → `settings_data.dart → restoreBackupFromFile`：

1. 确认框（明示"先清空本地车辆、保养项目、保养记录，再写入备份数据。**主题、通知等偏好设置会保留**"）；
2. `NativeFiles.pickJsonFile` 选文件 → `BackupCodec().decode`（版本≠2 抛 UnsupportedError）；
3. 协调器 `runBackupRestore`（`notification_coordinator.dart`）**先 bump() 通知同步代数**（providers.dart `notificationSyncGenerationProvider`，作废同步控制器在途任务）再执行恢复；
4. `backupRepository.restoreBackupPayload`——事务外**两层预校验**：引用完整性（`_validateBackupReferences`）+ 业务规则（`_validateBackupBusinessRules`：逐条 `item.validate()` / `RecordRules.validateRecord`，篡改备份直接拒绝且不碰库）→ 单一大事务：`_clearRestorableDataInTransaction` **只清 4 张业务表 + 按前缀清提醒抑制键（snooze/ack），偏好整体保留** → cars→items→records 逐行插入（id 全换新雪花 id，旧→新映射）→ 应用车辆指向第一辆；任何一行失败整体回滚；
5. 恢复成功后模板收尾：取消旧数据残留的 8000/8900 系（停车 9001/9002 不动——停车倒计时偏好保留且其通知仍有效）；恢复失败（异常上抛）时不取消，旧通知原样保留；
6. `invalidateAllAppDataProviders` → 全量刷新（车型目录由 bootstrap 自动重灌）；
7. 失败分支：唯一约束冲突 → 弹"本次恢复未写入任何数据"对话框；其他 → toast。

### 5.5 清空数据

我的页"清空数据" → `settings_data.dart → clearAllData` → 确认框（明示"默认车辆模型与默认保养项目目录会保留"）→ 协调器 `runAllDataClear`（`notification_coordinator.dart`：**先 bump() 通知同步代数** → `backupRepository.clearAllData`（事务删 5 张表：4 张业务表 + 偏好表）→ 取消停车 9001/9002 与保养/里程 8000/8900 系系统通知——偏好已删，倒计时与通知开关都不复存在，残留通知必须取消；清库失败异常上抛、不取消）→ invalidate 全量（bootstrap 重灌车型目录）→ 成功 overlay"已清空数据"（失败 toast，try/catch 包裹）。

### 5.6 通知设置

我的页"通知提醒" → `settings_data.dart → showNotificationSettingsSheet`：

1. 打开前 `await ref.read(notificationSettingsProvider.future)`（加载失败 toast"设置加载失败"并返回，杜绝 loading 期默认值覆盖真实设置）；
2. 打开时协调器 `reconcileSystemEnabled`（`notification_coordinator.dart`）向系统查真实开关并回写偏好（不一致才写；查询失败回退偏好值，R14）；
3. 表单：系统通知状态行（只读）+ "系统设置"跳转（`NativeNotificationSettings` → 原生设置页，跳转后 sheet 关闭）+ 应用内通知开关 + 到期重复频率三段（每周/每 2 周/每月）；
4. 保存 → `shell_actions.dart → saveNotificationSettings`（动作层：先协调器 `reconcileSystemEnabled` 对账系统真值，再经偏好门面 `LunioPreferences.saveNotificationSettings`（**一个事务内批量写 3 个偏好 key**），协调器内部失效偏好缓存）→ 反馈薄壳关 sheet + toast"设置已保存" → 同步控制器签名变化触发系统通知重排。

> 产品口径：保养到期提醒是 App 核心能力，**不提供用户关闭入口**（R5 确认；原 `maintenanceDueEnabled` 偏好已于 2026-08-29 移除）。

### 5.7 手动日期（开发者模式专属）

1. 开发者模式：版本 footer **连点 5 次** → `profile_page.dart:156 → _handleVersionTap` → `shell_actions.dart → setDeveloperModeEnabled`（动作层：写 `developerModeEnabled`，关闭时**连带清 `manualDateEnabled`/`manualDate`/`fuelPredictionEnabled`**——加油预测开关入口只在开发者模式可见）；
2. "手动日期"行 → `settings_data.dart:568 → showManualDateSheet`：开关+日期（1990~今天+10 年）→ `shell_actions.dart → saveManualDate`（动作层：写 `manualDateEnabled`/`manualDate` + 失效偏好家族）→ 反馈薄壳关 sheet + toast"手动日期已保存" → **`effectiveTodayProvider`（providers.dart:127）重算**，所有提醒进度/表单默认日期/通知签名里的 today 全部按新日期。

### 5.8 主题切换

我的页"主题模式"三段 → `settings_data.dart:135 附近 ThemeModeSettingRow` → `shell_actions.dart → setThemeModePreference`（动作层）写偏好 `themeMode` → `themeModePreferenceProvider` 刷新 → `lunio_app.dart` MaterialApp.themeMode 生效（appRouter 单例保证不跳页）。

### 5.9 加油预测开关（开发者模式专属）

"手动日期"行下方的"加油预测"开关行 → `profile_page.dart → _FuelPredictionSettingRow`，切换写偏好 `fuelPredictionEnabled`（`profile_page.dart → _setFuelPredictionEnabled`）→ invalidate → **`fuelPredictionEnabledProvider`（providers.dart）刷新** → `app_shell.dart` 底部导航实时插入/移除"加油"tab（无需重启 App）。关闭开发者模式时该偏好连带清掉（`_handleVersionTap`），加油 tab 随之消失；已填的加油数据保留。

### 5.10 加油页（/fuel，开发者开关打开时可见）

页面：`fuel/fuel_page.dart → FuelPreviewPage`。数据规则（词汇表 CONTEXT.md / ADR 0001 / ADR 0002 / ADR 0006）：

1. **油价卡**：手填价优先于数据源价；"刷新" → `FuelPriceController.manualRefresh`（失败保留旧数据并 toast）；**价格文字本身可点**（价格+标签胶囊旁有小编辑图标）→ `showLunioModalSheet → _ManualPriceForm` 编辑油价（**输入框每次留空，不预填**；留空提交按校验错误"请输入价格"处理），保存走 `shell_actions.dart → saveFuelManualPrice`（动作层：写 `fuelManualPrices` 偏好（按"省+油品"组合，`setFuelManualPrice`）+ 单点失效 `fuelManualPriceProvider`）+ toast"手填油价已保存"；价格行右侧"重置"按钮（**只有存有手填价时可用**，无手填价置灰）→ 重置走 `shell_actions.dart → saveFuelManualPrice`（pricePerLiter 传 null 删该组合键恢复数据源价；该处拿到的是 ProviderContainer，动作层签名只收 WidgetRef，故由加油仓库直呼 + 单点失效，语义与动作层一致）+ toast"已恢复数据源价"；**没拉到数据（无缓存/拉取失败/该省该油品无报价）时显示可点的"— 元/升"占位价 + "暂无数据"胶囊，点它即进上述手填编辑**（无数据状态下唯一的手填入口；油价获取中的加载态不可点）。数据源是 `QiyouJiaFuelPriceSource`（qiyoujiage 网页宽松解析，一次拉全国 31 省 + 调价预告，见 ADR 0006；`fuelPriceSourceProvider` 注入可换源）。自动更新：AppShell/加油页 watch `fuelPriceControllerProvider`，缓存距上次拉取 ≥10 个自然日或无缓存时静默拉取（缓存是全国价表，换省不重新拉），失败退回旧缓存。站点改版解析不到油价主体时抛 `FuelSourceException` → 控制器退回旧缓存；网络层已对字节流显式按 UTF-8 解码（该站响应头不带 charset），明文 http 在 iOS 走 ATS 例外域、Android 9+ 走 network security config 只对该域放行（见 ADR 0006）。
2. **预估下次油价块**（油价卡内，价格行下方）：标题"预估下次油价"（与"当前油价"同字号）；数值 = 生效价（手填优先）+ 调价预告变动中值（`FuelRules.predictedPricePerLiter`，先取整到分），右侧日期胶囊"X月X日调价"；展示样式与价格行一致（`_TagPill` 复用）。无预告/无基准价时显示"暂无调价预测"占位，不算错误。
3. **省份/油品编辑**（并入油价卡，无独立设置区）：副标题"湖北 · 92#"两段各自可点（`_SettingHotspot`）→ 弹对应选择 sheet，单选即写偏好并关 sheet。省份用列表（`_SheetOptionList`，`QiyouJiaFuelPriceSource.provinces` 31 项限高 320 可滚动、打开时定位到当前项）；油品固定 4 项，用一行胶囊单选（`_GradeChip`，sheet 贴内容收缩、无滚动无留白）。省份写 `fuelProvince`（默认湖北），油品写 `fuelGrade`（默认 92#），均走 `invalidateFuelPreferenceProviders`。
4. **加满预估卡（滚动定档）**：表头四列"当前油量 / 可加油量 / 加满价格 / 调价后价格"（`_TierHeaderRow`，列宽比例与 `_TierRow` 一致）。全量档位列表（`FuelRules.allTierPercents`，100%→0% 每 2% 一档共 51 档），窗口可见 5 档、整表上下滚动；`_RowSnapScrollPhysics` 吸附整行边界（**按父物理自然弹道投射停点再取最近整行**，照搬官方 `FixedExtentScrollPhysics` 模式——快速甩动可连滚多档、慢速就近弹回，停点严格对齐整行），`ScrollEnd` 后第一行档位 = 剩余油量，自动 `saveFuelPrediction` 写 `fuel_predictions`（默认 50%，从没滚动过不落库）；进入页面定位到已存档位在第一行。右上角返回图标（置灰条件：已停在 50%）→ `animateTo` 滚回 50% 在第一行，停稳后写库。当前油量 = 档位/100 × 容积（`FuelRules.litersInTank`）；可加油量 =（100−档位）/100 × 容积（`FuelRules.litersToFill`）；加满价格 = 可加油量 × 生效价（`FuelRules.fullTankCostCents`，分存储）；调价后价格 = 可加油量 × 预估价（`_predictedPriceProvider`，无预告时显示"—"）；第一行档位高亮、无"（当前）"文字。
5. **油箱容积入口在车辆管理**：添加/编辑车辆表单填写（选填，见 5.1.1/5.1.2）；未填容积时加满预估卡显示引导"先在'我的 → 车辆管理'里填写油箱容积，才能估算加满金额"，不显示金额列表。

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
  → syncFromProviders：读 6 个 provider 当前值（loading 中当 null，数据齐才继续）
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
             └─ Android 申请精确闹钟 → reschedule 前再比对一次同步代数
                  → rescheduleNotifications（lunio_notification_service.dart：
                     先精确取消 16 个在用 id（8000-8007/8900-8907，R10 收紧），
                     再每条通知排 8 次重复，
                     避开停车到点时刻 ±5 分钟步进错峰；月/日步进按日历字段
                     计算（R34：月末钳制 + 不做 24 小时累加））
      否 → 什么都不做
```

**防竞态三层**：① 同步代数（`notificationSyncGenerationProvider`，删车/恢复/清空由协调器 run* 模板 bump 作废在途任务）；② 执行中 pending 重跑（不丢更新）；③ `_disposed` 检查（控制器随主壳层销毁后所有 await 检查点放弃）。

> 通知域协议（权限真值对账、删车/恢复/清空的通知清扫、"稍后提醒/知道了"静默读写）的执行体集中在 `reminders/notification_coordinator.dart → LunioNotificationCoordinator`（CONTEXT.md 词汇：**通知协调器**）；控制器保留被动监听外壳，停车倒计时的通知尾巴由协调器 `onParkingCountdownSaved/Cleared` 承接。

**一句话：任何数据/偏好变化 → provider 变更 → listenManual 回调 → 签名 diff → 全量重排系统通知。**

### 6.4 系统通知 id 分配表

| id 段 | 用途 | channel |
|---|---|---|
| 8000-8007 | 保养到期汇总通知（8 次重复） | lunio_maintenance_due_heads_up |
| 8900-8907 | 里程更新提醒（9:05 起，8 次重复） | lunio_mileage_update_heads_up |
| 9001 | 停车到点闹钟 | lunio_parking_due_heads_up（alarm） |
| 9002 | Android 停车进行中常驻通知（chronometer 倒计时，到点自毁） | lunio_parking_ongoing |

---

## 7. 数据与偏好速查表

### 7.1 数据库表（schemaVersion = 1，`lib/data/database/app_database.dart`）

| 表 | 内容 | 关键唯一约束 |
|---|---|---|
| cars | 车辆（含油箱容积；含动力类型，默认 fuel） | {brand, model, roadDate} |
| vehicle_models | 内置车型目录（bootstrap 灌入，含推荐动力类型 template） | {catalogId}, {brand, model} |
| vehicle_default_maintenance_items | 默认项目模板，**按动力类型分组**（五组共 46 项，bootstrap 灌入） | {catalogId}, {powertrainType, itemName} |
| maintenance_items | 车辆保养项目 | {carsId, name}；普通索引 cars_id |
| maintenance_records | 保养记录主表 | **{carId, date}（一天一条）**；普通索引 car_id |
| maintenance_record_items | 记录-项目关联 | {carId, date, itemId}；普通索引 maintenance_record_id |
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
| `fuelPriceCache` | 油价缓存 JSON（全国价表 + 调价预告，**不进备份**） | FuelPriceController 拉取成功 |
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
