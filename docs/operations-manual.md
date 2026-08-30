# Lunio UI 操作手册（操作 ↔ 代码对照）

> 版本：2026-08-25 · 基于 schemaVersion 5 / 备份 schemaVersion 2 代码快照
>
> **用途**：某个操作步骤出了问题，从本手册查到"这个操作经过哪些代码、改了哪些数据"，快速定位到文件和函数。
>
> **锚点约定**：引用格式为 `文件路径 : 行号 → 函数/类名`。代码改动后行号会漂移，**以"文件 + 函数名"为主锚点**，行号仅辅助；只改函数内部实现时通常无需更新本手册，改了流程/入口/数据写点才必须同步维护。
>
> **读法提示**（Java 背景）：`Repository` ≈ Service+DAO；`Provider` ≈ Spring Bean；`ref.invalidate` ≈ 缓存逐出。所有写操作的固定模式是：**UI 事件 → ref.read(Repository).写库 → invalidateXxxProviders → FutureProvider 重新查库 → UI 自动刷新**。

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
  → repository.saveMaintenanceRecordWithItemUpdates()            # 事务：校验+写库
  → invalidateVehicleProviders(ref)                              # 逐出缓存
  → appliedCarRecordsProvider 等重算 → AppShell build → UI 刷新
```

**三大缓存失效入口**（`lib/app/providers.dart:205-230`）：

| 函数 | 失效内容 | 什么时候调 |
|---|---|---|
| `invalidateVehicleProviders` (:205) | 车辆/车型/项目/记录 5 个 provider | 任何车辆/项目/记录写操作后 |
| `invalidatePreferenceProviders` (:214) | 开发者模式/手动日期/生效日期/主题/通知设置 | 任何偏好写操作后 |
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
| 2 | `lib/core/notifications/lunio_notification_service.dart:78 → initialize()` | 时区数据库 + 本地时区（失败回退 UTC）+ 插件初始化（iOS 不在此弹权限） |
| 3 | `lib/app/lunio_app.dart:31 → LunioApp.build` | watch 主题偏好 → `MaterialApp.router`，路由挂全局单例 `appRouter` |
| 4 | `lib/app/app_router.dart:26 → appRouter` | 三条平级路由，初始 `/reminders`，每条渲染 `AppShell(selectedIndex: n)` |
| 5 | `lib/features/shell/app_shell.dart:34 → AppShell` | 主壳首帧 build：watch 全部 provider（此时数据库才真正打开） |

**注意**：数据库是**惰性**打开的——`appDatabaseProvider`（providers.dart:136）首次被 watch 时 `new AppDatabase()`，而 SQLite 文件连接由 Drift LazyDatabase 推迟到第一条 SQL（`lib/data/database/app_database.dart → _openConnection`，后台 isolate 打开 `lunio.sqlite`）。

### 1.2 首次进入（无任何数据）发生了什么

| 步骤 | 代码位置 | 做了什么 | 数据变化 |
|---|---|---|---|
| 1 | `lib/app/providers.dart:150 → defaultMaintenanceBootstrapProvider` | AppShell 首帧 watch 触发 `ensureBootstrapData()` | 见第 2 步 |
| 2 | `lib/data/repositories/lunio_repository.dart:162 → ensureBootstrapData()` → `_ensureVehicleModels`(:120) + `_ensureDefaultMaintenanceItems`(:65) | 从 asset `assets/data/built_in_vehicle_catalog.json` 加载目录（约 190 车型 + 5 套保养模板），**按 catalogId 幂等对账**写入两张内置表 | `vehicle_models`、`vehicle_default_maintenance_items` 两表灌入/更新 |
| 3 | `lib/features/shell/reminders/reminder_page.dart:102 → EmptyVehicleCard` | appliedCarProvider 返回 null → 显示"还没有车辆"卡片 | 无 |
| 4 | `lib/features/shell/app_shell.dart:244 → _syncReminderNotifications` | 系统通知开关为默认开 → postFrame 触发首启权限请求 | 见 1.3 |

**首启不会创建默认车辆**——必须用户手动走添加向导；车辆级保养项目也是添加车辆时才从模板复制。

### 1.3 首次通知权限请求

| 步骤 | 代码位置 | 做了什么 | 数据变化 |
|---|---|---|---|
| 1 | `lib/features/shell/app_shell.dart:333 → _ensureInitialSystemNotificationPermission` | 读偏好 `systemNotificationPermissionRequested` | — |
| 2a | 未请求过 → `lunio_notification_service.dart:103 → requestNotificationPermission` | 弹系统权限对话框（iOS/Android 13+） | 写 `systemNotificationPermissionRequested=true`、`systemNotificationsEnabled=<授权结果>` |
| 2b | 请求过 → `notificationsEnabled()` 查系统真实开关 | 用户可能在系统设置改过，回写偏好保持一致 | 可能更新 `systemNotificationsEnabled` |
| 3 | `invalidatePreferenceProviders` + 清空签名 | 下帧触发系统通知首次全量重排 | — |

---

## 2. 提醒页（/reminders）

页面装配：`lib/features/shell/reminders/reminder_page.dart:44 → ReminderPreviewPage`（250ms ticker 驱动停车倒计时刷新，`:55`）。

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
| 2 | `parking_countdown.dart → ParkingCountdownForm`（约 230 行起） | 入场时间（默认现在，时间轮只能改时分秒）+ 免费时长（输入框或 0.5/1/2 小时快捷 chip） | — |
| 3 | 提交 → `parking_countdown.dart:614 → saveParkingCountdown(ref, countdown)` | ① 写偏好 ② 失效 ③ 若系统通知开：请求权限 → Android 精确闹钟 → 调度通知 | ① `parkingCountdown` = JSON ② 系统通知 id **9002**（Android 常驻 chronometer）+ **9001**（到点闹钟）；`systemNotificationPermissionRequested=true`；被拒时 `systemNotificationsEnabled=false` |
| 4 | `lunio_notification_service.dart:243 → scheduleParkingCountdownNotification` | 先成对取消旧 9001/9002，再排新闹钟；**到点时刻已过则静默 return** | — |

**展示**：`parking_countdown.dart:36 → ParkingCountdownCard`——进度规则在 `lib/domain/rules/parking_countdown_rules.dart`（剩余≤20% 黄、到期红转正计时）；颜色映射 `_parkingStatusColor`。刷新由提醒页 ticker 传入新 `now`。

**结束**：卡片"结束"按钮（`reminder_page.dart:142`）→ `parking_countdown.dart:647 → clearParkingCountdown(ref)` → 删偏好 key + 失效 + 取消 9001/9002。

> 已知问题：到期后倒计时不自动清除（须手动结束才能开始新的）；恢复备份/清空数据后 9001/9002 不会被取消（见报告 R1/R9/R17）。

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

**触发时机**：AppShell 检测"应用内通知开 + 到期项变化/回到前台"（`app_shell.dart:468 → _showDueInAppNotifications`）。

| 步骤 | 代码位置 | 做了什么 | 数据变化 |
|---|---|---|---|
| 1 | `reminder_notifications.dart:420 → maintenanceNotices` | 到期项收集（无记录直接空）；snooze/当日 ack 的过滤在 `:384 → isSnoozed` / `isAcknowledgedToday`（逐项读偏好） | — |
| 2 | `reminder_dialogs.dart:26 → showMaintenanceReminderDialog` | 弹保养提醒框（逐项列出） | — |
| 3a | 点"知道了" | 返回 acknowledged，AppShell 逐项写当日 ack | `maintenanceInAppReminderAcknowledgedOn:<itemId>` = 今天（当天不再弹，系统通知照发） |
| 3b | 点"15 天内不再提醒" | 弹窗内 `onSnoozeAll`（reminder_dialogs.dart:26 内）直接写 snooze | `maintenanceReminderSnoozedUntil:<itemId>` = 今天+15 天（`snoozeUntilDate`，系统+应用内一起静默） |
| 4 | 有动作后 | `app_shell.dart` 末尾清空两个签名 + setState | 下帧重排系统通知（snooze 影响通知内容） |
| 5 | 里程更新弹窗同构 | `reminder_dialogs.dart:60 → showMileageUpdateReminderDialog`；是否到期判定 `reminder_notifications.dart → mileageUpdateReminderDue`（上次里程更新日 = car.sync.updatedAt + 按记录频率推断的间隔） | `mileageUpdateSnoozedUntil:<carId>` / `mileageUpdateInAppAcknowledgedOn:<carId>` |
| 6 | 回到前台 | `app_shell.dart:90 → didChangeAppLifecycleState` 清空应用内签名 | 强制重查（处理完离开再回来，到期会再弹） |

---

## 4. 记录页（/records）

页面装配：`lib/features/shell/records/records_page.dart:29 → RecordsPreviewPage`。

### 4.1 列表与筛选

| 用户操作 | 代码位置 | 做了什么 |
|---|---|---|
| 切换"按周期/按项目" | `records_page.dart:56`（LunioSegmentedControl） | `selectedMode` 0/1 |
| 年份/项目多选筛选 | `records_page.dart:78-113`（两个 FilterBar） | `selectedYears`/`selectedItemIds` 集合 toggle；`_filterRecords`(:350 附近) 双条件过滤 |
| 按周期视图 | `records_page.dart:196 → RecordCycleList` | 一条记录一张卡（日期+金额+里程+备注+项目 pills+编辑/删除） |
| 按项目视图 | `records_page.dart:296 → RecordItemList` | 记录×项目展开成行，可单独删某项 |

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
| 5 | onSubmit（sheet 入口处） | 新增 → `repository.saveMaintenanceRecordWithItemUpdates`（lunio_repository.dart:667）；编辑 → `updateMaintenanceRecordWithItemUpdates`(:721)。**单事务**：项目归属校验 → 同日唯一校验（`:1227 → _ensureRecordIsUnique`，重复抛中文文案）→ 插/改主表+关联表 → 车辆里程只增同步 → 更新项目间隔 | `maintenance_records` + `maintenance_record_items`；可能更新 `cars.current_mileage_km`、`maintenance_items` 间隔 |
| 6 | `invalidateVehicleProviders` + 关 sheet | 记录页/提醒页/通知签名全部刷新 | — |

### 4.3 删除记录

| 操作 | 代码位置 | 数据变化 |
|---|---|---|
| 按周期删整条 | `records_page.dart:1064 → deleteMaintenanceRecord` → 确认框 → `repository.deleteMaintenanceRecord`(:784，事务删主表+关联) | 删 1 条记录 + N 条关联 |
| 按项目删单项 | `records_page.dart:1084 → deleteMaintenanceRecordItem` → 确认框（带项目名）→ `repository.removeMaintenanceRecordItem`(:802)：**只剩这一项时连记录一起删**（返回 true），否则只删关联行 | 删关联行（或整条记录） |

---

## 5. 我的页（/me）

页面装配：`lib/features/shell/profile/profile_page.dart:20 → ProfilePreviewPage`（结构：我的车辆 / 数据与工具 / 版本 footer）。

### 5.1 车辆管理

#### 5.1.1 添加车辆（两步向导）

**入口**：我的页"我的车辆 → 添加"（profile_page.dart:56）或提醒页/我的页空卡片"新增车辆" → `vehicles.dart:907 → showAddCarSheet`。

| 步骤 | 代码位置 | 做了什么 | 数据变化 |
|---|---|---|---|
| 1 | sheet 内 watch `vehicleModelsProvider` + `effectiveTodayProvider` | 车型目录/日期加载失败给行内提示 | — |
| 2 | 第一步 `AddCarForm`（vehicles.dart:272 起） | 选品牌车型（`VehicleModelPicker` → 双列选择 sheet `:672 → VehicleModelPickerSheet`，支持搜索）、当前里程、上路日期 | — |
| 3 | "下一步" → `AddCarWizardState._handleCarDraft`（vehicles.dart:510 附近） | 车型变化才加载默认模板：`loadDefaultItems` 闭包（showAddCarSheet 内）→ `repository.ensureBootstrapData()` + `listDefaultItemsForModel`（lunio_repository.dart:494 附近）→ 模板转项目草稿 | 只读，无写库 |
| 4 | 第二步 `AddCarMaintenanceItemsStep`（maintenance_items.dart:32） | 默认项目草稿可编辑（草稿表单 `:1007 → showDraftMaintenanceItemFormSheet`，纯内存）/启停/删除（均受"至少一个启用项"拦截）/"恢复"补回被删默认项（`:133 → showRestoreDefaultItemsSheet` 勾选式） | 纯内存 |
| 5 | "保存车辆" → `AddCarWizardState._submit` → onSubmit（sheet 入口处） | `repository.createCarWithMaintenanceItems`（lunio_repository.dart:224，**单事务**：校验至少一个启用项目+逐项 validate → 插车辆 → 逐条插项目 → **无应用车辆时把新车设为当前**） | `cars` +1、`maintenance_items` +N、可能写 `appliedCarId` |
| 6 | `invalidateVehicleProviders` + 关 sheet | 提醒页立即显示新车 | — |

#### 5.1.2 编辑车辆

车辆卡"编辑" → `vehicles.dart:988 → showEditCarSheet` → `AddCarForm` 编辑模式（**品牌车型只读**）→ `repository.updateCar`（lunio_repository.dart:291，只写里程/日期/sync）→ invalidate。⚠ 里程可改小（无回退限制）。

#### 5.1.3 删除车辆

车辆卡"删除" → `shell_actions.dart:47 → deleteCar` → 确认框 → `repository.deleteCar`（lunio_repository.dart:334，**事务级联**：记录关联→记录→项目→appliedCarId 偏好（仅当指向本车）→车辆；删完应用车辆指向剩余第一辆，无剩余清空）→ invalidate。

#### 5.1.4 切换当前应用车辆

| 入口 | 代码位置 |
|---|---|
| 提醒页右上角"切换车辆" | `vehicles.dart:1052 → showVehicleSwitcher`（sheet 列车，点非当前车确认） |
| 车辆卡"应用"按钮 | `profile_page.dart` → `shell_actions.dart:21 → applyCar` |

两者最终都走 `repository.setAppliedCarId`（lunio_repository.dart:1020，写偏好 `appliedCarId`）+ `invalidateVehicleProviders`。

### 5.2 保养项目管理

#### 5.2.1 打开项目 sheet

车辆卡"项目" → `maintenance_items.dart:364 → showMaintenanceItemsSheet`（car 为空时管当前应用车辆）。sheet 内部是**手写局部状态机**（`:415 → MaintenanceItemsSheetContent`，自管 loading/error/代数防乱序，不走全局 provider），每次操作后 `_reload` 重拉列表。

#### 5.2.2 各操作

| 操作 | 代码位置 | 数据变化 |
|---|---|---|
| 新增项目 | 卡片区"新增" → `:969 → showMaintenanceItemFormSheet`（表单：名称+里程/时间开关行+间隔）→ `repository.saveMaintenanceItem`（lunio_repository.dart:516） | `maintenance_items` +1 |
| 编辑项目 | 卡片"编辑" → 同上表单 → `repository.updateMaintenanceItem`（:556；停用态先过"至少一个启用"校验） | 更新该行 |
| 启停项目 | 卡片"已启用/已禁用"按钮 → `:1038 → toggleMaintenanceItem` → `repository.setMaintenanceItemEnabled`（:590） | 更新 enabled |
| 删除项目 | 卡片"删除" → 确认框 → `:1065 → deleteMaintenanceItem` → `repository.deleteMaintenanceItem`（:626，**有历史记录直接抛错**拒绝删除） | 删该行（或报错 toast） |

> "恢复默认"只存在于**添加向导草稿**内；已保存车辆没有该功能。

### 5.3 备份导出

我的页"备份" → `settings_data.dart:170 → exportBackup`：

1. `repository.exportBackupPayload`（lunio_repository.dart:852）——4 张业务表全量读（不含偏好/停车倒计时/目录），schemaVersion 固定 2；
2. `BackupCodec().encode`（lib/data/backup/backup_codec.dart）——手写 JSON 序列化；
3. `NativeFiles.exportJsonFile`（lib/core/platform/native_files.dart）——MethodChannel `lunio/native_files` → Android `MainActivity.kt`（ACTION_CREATE_DOCUMENT）/ iOS `SceneDelegate.swift`（临时文件+UIExporter）弹系统保存框，文件名 `lunio-backup-yyyyMMdd-HHmmss.json`；
4. 成功/失败 toast。

### 5.4 恢复备份

我的页"恢复" → `settings_data.dart:199 → restoreBackupFromFile`：

1. 确认框（明示"先清空车辆/项目/记录/**偏好**"）；
2. `NativeFiles.pickJsonFile` 选文件 → `BackupCodec().decode`（版本≠2 抛 UnsupportedError）；
3. `notificationSyncGeneration++`（shell_actions.dart:18，作废 AppShell 在途通知任务）；
4. `repository.restoreBackupPayload`（lunio_repository.dart:890）——事务外引用完整性预校验（`:1360 附近 → _validateBackupReferences`）→ 单一大事务：**清空全部数据（含偏好）** → cars→items→records 逐行插入（id 全换新雪花 id，旧→新映射）→ 应用车辆指向第一辆；任何一行失败整体回滚；
5. `invalidateAllAppDataProviders` → 全量刷新（车型目录由 bootstrap 自动重灌）；
6. 失败分支：唯一约束冲突 → 弹"本次恢复未写入任何数据"对话框；其他 → toast。

> ⚠ 已知问题：偏好（主题/通知设置/开发者模式/snooze）被清且不随备份恢复（R2）；停车闹钟 9001/9002 残留（R1）。

### 5.5 清空数据

我的页"清空数据" → `settings_data.dart:254 → clearAllData` → 确认框 → generation++ → `repository.clearAllData`（lunio_repository.dart:1072，事务删 5 张表含偏好）→ invalidate 全量（bootstrap 重灌车型目录）。

### 5.6 通知设置

我的页"通知提醒" → `settings_data.dart:273 → showNotificationSettingsSheet`：

1. 打开时 `refreshSystemNotificationPreference`（`:325 附近`）向系统查真实开关并回写偏好；
2. 表单：系统通知状态行（只读）+ "系统设置"跳转（`NativeNotificationSettings` → 原生设置页，跳转后 sheet 关闭）+ 应用内通知开关 + 到期重复频率三段（每周/每 2 周/每月）；
3. 保存 → `saveNotificationSettings`（`:344 附近`）串行写 4 个偏好 key → `invalidatePreferenceProviders` → AppShell 签名变化触发系统通知重排。

> ⚠ 已知问题：`maintenanceDueEnabled` 提交时硬编码 true（R5）；loading 期默认值覆盖风险（R6）。

### 5.7 手动日期（开发者模式专属）

1. 开发者模式：版本 footer **连点 5 次** → `profile_page.dart:156 → _handleVersionTap` → 写 `developerModeEnabled`（关闭时连带清 `manualDateEnabled`/`manualDate`）；
2. "手动日期"行 → `settings_data.dart:568 → showManualDateSheet`：开关+日期（1990~今天+10 年）→ 写 `manualDateEnabled`/`manualDate` → invalidate → **`effectiveTodayProvider`（providers.dart:127）重算**，所有提醒进度/表单默认日期/通知签名里的 today 全部按新日期。

### 5.8 主题切换

我的页"主题模式"三段 → `settings_data.dart:135 附近 ThemeModeSettingRow` → `shell_actions.dart:29 → setThemeModePreference` 写偏好 `themeMode` → `themeModePreferenceProvider` 刷新 → `lunio_app.dart` MaterialApp.themeMode 生效（appRouter 单例保证不跳页）。

---

## 6. 主壳层与通知同步引擎

### 6.1 底部导航

`lib/features/shell/app_shell.dart:161-190`：三个 `_BottomNavItem`，点击 → `dismissTransientUi`（收键盘/toast/snackbar，modal_feedback.dart）→ `context.go('/xx')` → NoTransitionPage 重建 AppShell（selectedIndex 由路由决定）。

### 6.2 生命周期

`app_shell.dart:90 → didChangeAppLifecycleState`：resumed（回前台）清空应用内提醒签名（强制重查弹窗）+ 刷新 Android 导航 inset + setState。Android 三键导航 inset 适配在 `:199 附近 → _refreshAndroidSystemNavigationInset`（requestId+mounted 双检查）。

### 6.3 系统通知同步引擎（核心机制）

**位置**：`app_shell.dart:244 → _syncReminderNotifications`（每次 build 调用）。

```
build（数据变化/invalidate/ticker 都会触发）
  → 拼"系统通知签名" = 重复频率 + 停车倒计时摘要 + 全量数据签名
      （reminder_notifications.dart:219 → reminderNotificationDataSignature：
       车辆/项目/记录全部相关字段 + today 拼成一个大字符串）
  → 签名 != 上次记录？
      是 → 记录新签名 → postFrame 执行 _applySystemNotificationSchedule（:387）
             ├─ 开关关 → cancelLunioNotifications（全取消）
             ├─ 查系统权限（必要时补请求/回写偏好）
             ├─ buildScheduledNotifications（reminder_notifications.dart:132）
             │    ├─ 到期项目（snooze 过滤后）≥1 → 汇总通知 id 8000
             │    └─ 里程更新到期且未 snooze → id 8900（9:05 错峰）
             └─ Android 申请精确闹钟 → rescheduleNotifications
                  （lunio_notification_service.dart:174：先 cancel 8000-8999，
                   再每条通知排 8 次重复，避开停车到点时刻 ±5 分钟步进错峰）
      否 → 什么都不做
```

**一句话：任何数据/偏好变化 → provider 刷新 → build → 签名 diff → 全量重排系统通知。**

### 6.4 系统通知 id 分配表

| id 段 | 用途 | channel |
|---|---|---|
| 8000-8007 | 保养到期汇总通知（8 次重复） | lunio_maintenance_due_heads_up |
| 8900-8907 | 里程更新提醒（9:05 起，8 次重复） | lunio_mileage_update_heads_up |
| 9001 | 停车到点闹钟 | lunio_parking_due_heads_up（alarm） |
| 9002 | Android 停车进行中常驻通知（chronometer 倒计时，到点自毁） | lunio_parking_ongoing |

---

## 7. 数据与偏好速查表

### 7.1 数据库表（schemaVersion = 5，`lib/data/database/app_database.dart`）

| 表 | 内容 | 关键唯一约束 |
|---|---|---|
| cars | 车辆 | {brand, model, roadDate} |
| vehicle_models | 内置车型目录（bootstrap 灌入） | {catalogId}, {brand, model} |
| vehicle_default_maintenance_items | 默认项目模板（bootstrap 灌入） | {catalogId}, {brand, model, itemName} |
| maintenance_items | 车辆保养项目 | {carsId, name} |
| maintenance_records | 保养记录主表 | **{carId, date}（一天一条）** |
| maintenance_record_items | 记录-项目关联 | {carId, date, itemId} |
| app_preferences | 偏好 KV | {key} |

### 7.2 偏好 key 清单（app_preferences 表）

| key | 含义 | 写入点 |
|---|---|---|
| `appliedCarId` | 当前应用车辆 id | applyCar / getAppliedCar 回退 / 删车 / 恢复备份 |
| `themeMode` | light/dark/system | 主题切换 |
| `systemNotificationsEnabled` | 系统通知开关 | 权限链 / 通知设置 / 停车保存被拒时 |
| `systemNotificationPermissionRequested` | 是否请求过权限 | 首启权限链 / 停车保存 |
| `inAppNotificationsEnabled` | 应用内弹窗开关 | 通知设置 |
| `maintenanceDueEnabled` | 保养到期提醒开关（**当前被硬编码 true**） | 通知设置 |
| `maintenanceDueRepeat` | 到期重复频率 | 通知设置 |
| `developerModeEnabled` | 开发者模式 | 版本连点 |
| `manualDateEnabled` / `manualDate` | 手动日期 | 手动日期 sheet / 关开发者模式 |
| `parkingCountdown` | 停车倒计时 JSON（**不进备份**） | 停车保存/结束 |
| `maintenanceReminderSnoozedUntil:<itemId>` | 保养项 snooze 截止日 | 应用内弹窗 |
| `maintenanceInAppReminderAcknowledgedOn:<itemId>` | 保养项当日 ack | 应用内弹窗 |
| `mileageUpdateSnoozedUntil:<carId>` | 里程提醒 snooze | 应用内弹窗 |
| `mileageUpdateInAppAcknowledgedOn:<carId>` | 里程提醒当日 ack | 应用内弹窗 |

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
