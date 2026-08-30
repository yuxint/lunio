# Lunio 修复方案（备份/恢复/清空语义 + R3…R37 + 5.2/5.3）

> 制定日期：2026-08-26 · 依据：`docs/code-review-report.md`（R1-R38 问题清单）+ 用户澄清的备份/恢复/清空语义
>
> **执行状态（2026-08-26）**：批次 A-H 已全部执行完毕（5.3.2/5.3.5 与"明确不做"清单按计划跳过）。验证：flutter analyze 零告警、flutter test 136 条全过、flutter build ios --simulator 成功。各问题修复详情见 `docs/code-review-report.md` 对应条目的【已修复】标注。

## 0. 语义澄清结论（备份 / 恢复 / 清空）

用户澄清的口径：

- **备份**：备份车辆、项目配置、保养记录。
- **恢复**：恢复备份的数据。
- **清空**：清空车辆、项目配置、保养记录、偏好设置，但默认车辆模型和默认保养项目不能被清空。

与现状核对：

| 功能 | 现状 | 结论 |
|---|---|---|
| 备份 | 导出内容为车辆 + 项目配置 + 保养记录（`backup_codec.dart`，schemaVersion 2，不含偏好） | **已符合，不改** |
| 恢复 | `_clearAllDataInTransaction`（`lunio_repository.dart:1079`）删 5 张表**含 `app_preferences`**，偏好全部丢失 | **需修**：恢复只替换三类业务数据，偏好保留（即修复 R2） |
| 清空 | 删车辆/项目/记录/偏好，保留 `vehicle_models` 与 `vehicle_default_maintenance_items` 两张默认目录表 | 数据行为已符合；但**恢复/清空后不取消系统通知**（8000/8900 系残留、停车 9001/9002 残留），**需补**（R1 的恢复/清空路径） |

已确认的四个决策（2026-08-26）：

1. 恢复 = 保留偏好 + 清 snooze/ack 抑制键（推荐方案）。
2. LoadingPage/ErrorPage 三页统一推广（5.2）。
3. 死代码清理做**全清**（含 `createCar`/`createCarWithDefaultItems`）。
4. 5.3.2 三套 sheet 骨架收敛**本轮跳过**。

覆盖范围：R3/R6/R7/R8/R11/R12/R13/R15/R16/R18/R19/R21/R22/R23/R24/R25/R26/R27/R28/R29/R31/R32/R33/R35/R37 + §5.2/§5.3 + 备份/恢复/清空语义修复（连带修 R2、R1 部分）。

---

## 批次 A · 备份/恢复/清空语义对齐（修 R2、R1 恢复/清空路径、R35、R6）

### Repository（`lib/data/repositories/lunio_repository.dart`）

1. 新增私有 `_clearRestorableDataInTransaction()`：删 4 张业务表（recordItems/records/items/cars，**不动 app_preferences**）+ 按 4 个前缀删提醒抑制键：`maintenanceReminderSnoozedUntil:`、`mileageUpdateSnoozedUntil:`、`maintenanceInAppReminderAcknowledgedOn:`、`mileageUpdateInAppAcknowledgedOn:`（like 查询删除）。`restoreBackupPayload`（:899）改用它；`clearAllData` 仍用原 `_clearAllDataInTransaction`（清全部 5 张表）。
2. 4 个前缀定义为 `LunioRepository` 上的静态常量，`reminder_notifications.dart` 的 key 构造函数改为引用该常量（消除双份魔法字符串）。
3. R35：`restoreBackupPayload` 在 `_validateBackupReferences` 之后、开事务之前，逐条调 `item.validate()` 和 `RecordRules.validateRecord(record)`，失败抛 `ArgumentError('备份文件中存在无效数据：…')`（保证"未写入任何数据"语义不变）。

### UI（`lib/features/shell/profile/settings_data.dart`）

4. 恢复确认文案改为："恢复会先清空本地车辆、保养项目、保养记录，再写入备份文件中的数据。主题、通知等偏好设置会保留。该操作不可撤销。"
5. 恢复成功后、invalidate 前补 `await LunioNotificationService.instance.cancelLunioNotifications()`（清掉旧数据残留的 8000/8900 系；停车 9001/9002 不动，因为停车倒计时偏好现在保留且其通知仍有效；空备份 car==null 时同步引擎不会重排，显式取消兜底）。
6. 清空流程：确认文案补"默认车辆模型与默认保养项目目录会保留"；`clearAllData()` 成功后补 `cancelParkingCountdownNotification()`（9001/9002，偏好已删必须取消）+ `cancelLunioNotifications()`；补 try/catch 与成功 overlay"已清空数据"（与恢复反馈对齐）。
7. R6：`showNotificationSettingsSheet` 打开前 `await ref.read(notificationSettingsProvider.future)`，失败 toast"设置加载失败"并返回，杜绝 loading 期默认值覆盖真实设置。

### 测试

- `database_test.dart` round-trip 用例改断言：恢复前写入 themeMode/manualDate/parkingCountdown/snooze key → 恢复后前三者保留、snooze 清除。
- 新增篡改备份（负金额/负里程/空 itemIds/无效项目间隔）被拒且库未动。
- `widget_test.dart` 恢复确认文案若有断言同步改。
- 新增"清空后 9001/9002/8000 系取消"用例（先启动停车倒计时再清空，断言 mock cancel 调用）。

---

## 批次 B · 通知引擎重构（R12+R3+R8+R13 同做，另含 R15、R7、R18）

1. **R12**：新建 `lib/features/shell/reminders/notification_sync_controller.dart`，把 `_syncReminderNotifications`、`_ensureInitialSystemNotificationPermission`、`_applySystemNotificationSchedule`、`_showDueInAppNotifications` 从 `app_shell.dart` 移入。AppShell 的 `initState` 创建控制器（传入 `ref`、`isAlive: () => mounted`、`shellContext`），控制器 `start()` 对 6 个 provider `ref.listenManual(..., fireImmediately: true)`（数据变化/首拍触发，不再挂在 build 上）；`didChangeAppLifecycleState(resumed)` 改调 `controller.onAppResumed()`；`dispose` 关闭订阅。`app_shell.build` 删除 6 个 watch 与同步调用，只渲染。弹窗用 `shellContext()`（null 即放弃）。
2. **R3**：`_applySystemNotificationSchedule` 的 in-flight 守卫由"直接 return"改为置 `_pendingSystemNotificationSync = true`；`finally` 里若有 pending → 先把 `_systemNotificationSignature` 置 null 再跑一轮 `syncFromProviders()`，用**最新数据**强制重排，保证不丢更新。reschedule 前再查一次 generation，变了就放弃。
3. **R8**：`shell_actions.dart` 的全局 `notificationSyncGeneration` 删除，改 `providers.dart` 里 `NotifierProvider<NotificationSyncGeneration, int>`（`bump()` 自增）；settings_data 两处自增、控制器快照/比对、`parking_countdown.dart` 的 `saveParkingCountdown` 入口快照、调度通知前比对（不一致即放弃）全部走 provider。
4. **R13**：控制器内所有 await 后补 `if (_disposed) return;`；`saveParkingCountdown`/`clearParkingCountdown` 增加 `BuildContext` 参数，每个 await 后 `if (!context.mounted) return;`（页面 context 由 `showParkingCountdownSheet` 传入）。
5. **R15**：`main.dart` initialize 包 try/catch（debugPrint + 继续 runApp）；`LunioNotificationService` 增加 `_available` 标志与 `markInitializationFailed()`，不可用时 `notificationsEnabled`/两个权限请求返回 false、schedule/cancel 全部安全 no-op。补服务测试。
6. **R7**：`native_files.dart` 两个方法补 `PlatformException`/`MissingPluginException` 捕获（返回 false/null + debugPrint）；`SceneDelegate.swift` 的 `configureNativeFilesChannel` 改造为 `…IfNeeded`（存 channel 属性 + guard），在 willConnectTo 延迟一拍与 `sceneDidBecomeActive` 重试，完全镜像通知设置桥的写法。需 `flutter build ios --simulator` 验证。
7. **R18**：`_nextOccurrence` monthly 分支加月末钳制（year/month 进位 + `DateTime(y, m+1, 0).day` 取月末，day 取 min），服务测试补"1 月 31 日排月度 → 下次 2 月 28/29 日"。

---

## 批次 C · schema v6（R16 + R19）

- `app_database.dart` 三张表加 `@TableIndex`：`idx_maintenance_records_car_id`、`idx_maintenance_record_items_record_id`、`idx_maintenance_items_cars_id`。
- `schemaVersion` 5→6；`onUpgrade` 补 `from < 6` 分支 `m.createIndex(...)` ×3（drift 2.33 生成 Index getter）。
- 跑 `dart run build_runner build` 并检查 `app_database.g.dart`。
- 同步更新 **AGENTS.md**（schemaVersion 5→6）与 `docs/migration/current-database-schema.md`（v6 索引 + R19：记录"升级库部分唯一索引 vs 全新安装表内 UNIQUE"两种等价形态）。
- `database_test.dart` 补 sqlite_master 索引存在断言。

---

## 批次 D · 数据访问与 provider 健壮性（R27/R28/R29/R31）

1. **R27**：Repository 新增 `getPreferenceValues(List<String> keys)`（单条 IN 查询）与 `updatePreferenceValues(Map<String, String?>)`（事务内循环复用 `_writePreferenceValue`）；`notificationSettingsProvider` 与 `saveNotificationSettings` 改用批量接口。
2. **R28**：Repository 实例内 memoize 目录解析 Future（`_catalogFuture ??= …`），`ensureBootstrapData`/`ensureVehicleModels`/`ensureDefaultMaintenanceItems` 共用；更新 :161 注释。
3. **R29**：`carsProvider` 改 `await ref.watch(defaultMaintenanceBootstrapProvider.future)`、`appliedCarProvider` 改 `await ref.watch(carsProvider.future)`，依赖显式化（行为等价）。
4. **R31**：`maintenanceItemHasHistory` 加 `limit(1)`；`deleteCar`/`_ensureAppliedCarInTransaction`/`getAppliedCar` 改点查 + limit(1)（保持 listCars 排序语义与 AppliedCarRules 回退行为，实施时先确认 listCars 的排序字段）。

---

## 批次 E · UI 性能与正确性（R11/R21/R22/R24/R25/R33/R23）

1. **R11**：删除 `reminder_page.dart` 页面级 250ms Timer；`ParkingCountdownCard`（parking_countdown.dart）改 StatefulWidget，内部 1s Timer 驱动自身 setState（真实时钟，倒计时存在即计时，含"已到点"正计时态）；英雄卡 dueOverviewText 不再每秒重算。
2. **R21**：`records_page.dart` build 里的 `selectedYears.removeWhere`/`selectedItemIds.removeWhere` 改为派生集合（渲染与过滤用 `where(valid)` 的视图，不改 state；state 仅由用户点击变更）。
3. **R22+5.3.4**：`ItemPills` 内部改 `Wrap`（spacing/runSpacing 沿用现有间隙值），删除 `_packedPillRows` 与 `_measureTextWidth`（TextPainter 泄漏随之消失）；3 处调用点视觉核对。
4. **R24**：`records_page.dart:276`、`maintenance_items.dart:647/:243` 的 `!= list.last` 全部改下标循环判断。
5. **R25**：`LunioPage` 增加可选 slivers 构造（CustomScrollView + SliverToBoxAdapter 头部，加法式改动不影响另两页）；记录页两个列表改 `SliverList.builder` + `ValueKey('record-${id}')`。若实施中与底部 padding/导航交互异常，回退为保 Column+for 仅加 key。
6. **R33**：记录页空态文案改为指向真实入口（如"暂无保养记录，可在提醒页点「新增保养记录」。"），同步文件头注释。
7. **R23**：`showVehicleSwitcher` 改 async：`await ref.read(carsProvider.future)`（catch → toast"车辆加载失败"），appliedCar 同步 await；后续逻辑加 `context.mounted` 检查。

---

## 批次 F · 组件复用整理（5.2 统一推广 + 5.3 其余项 + R32）

1. **5.2**：记录页、我的页的 loading/error 改用 `LoadingPage`/`ErrorPage`（与提醒页同构：`when(loading: LoadingPage, error: ErrorPage, data: LunioPage(...))`，三页统一）；`FilterBar`、`ChoiceChipButton` 移入 `records_page.dart` 私有；单点格式化函数回收——`formatMoney`→records_page、`itemRuleText`+`defaultItemRuleText` 合并为一个函数放 maintenance_items.dart、`mileageReminderText`/`displayPercentForThresholds`→reminder_notifications.dart、`normalizeItemName`→maintenance_items.dart；formatters.dart 保留多文件复用项（formatNumber 系、friendlyError 等）。
2. **5.3.1**：`RecordIntervalInputRow` 与 `ReminderRuleInputRow` 合并为 shared 的一个组件（可选 Switch 的数字输入行），两个表单迁移。
3. **5.3.3**：`_formatClock` 双实现合并为 `formatters.dart` 的 `formatClock`，两处调用。
4. **R32 余项**：vehicles.dart 添加/编辑 sheet 两份"车型/日期加载失败"检查块提取为文件内私有 helper。
5. sheet 骨架收敛（5.3.2）与 FormActions（5.3.5）本轮不做（已确认跳过）。

---

## 批次 G · 死代码全清（R26 + R37）

删除清单：

- `lib/core/id/id_generator.dart` + pubspec `uuid` 依赖（`flutter pub get`）。
- `reminder_page.dart:32-35` barrel re-export。
- `maintenanceRepeatFrequency`（删前 rg 复核零调用）。
- 停车表单 `initial` 编辑分支（含 reminder_page 调用点参数）。
- `showLunioModalSheet` 的 `isScrollControlled` 参数 + 13 处调用。
- `AppDateContext.withManualDate/withoutManualDate`（保留 `manualDate` 字段，测试仍在用）。
- `statusForPercent`（连 4 处测试）。
- R37 `noHistoryBaselineMileageKm` 死参数（`progressForItem`/`_mileageProgress` 签名收缩，4 处测试去参，doc 注释写明"无历史按 0 里程基线"为 PRD 设计）。
- `createCar`/`createCarWithDefaultItems`（测试内写等价 helper：前者换 `createCarWithMaintenanceItems(car, const [])`，后者在测试文件里用 ensureBootstrapData+listDefaultItemsForModel 组合复刻，约 23 处调用点机械改写）。

---

## 批次 H · 文档与验证收尾

### 文档

- `docs/operations-manual.md`：恢复/清空流程（偏好语义+通知取消）、通知同步引擎（控制器新位置与 listenManual 触发）、记录页（懒加载/空态文案）、切换车辆、通知设置打开、停车倒计时卡片自计时。
- `docs/code-review-report.md`：标记已修复+日期：R2、R3、R6、R7、R8、R11、R12、R13、R15、R16、R18、R19、R21、R22、R23、R24、R25、R26、R27、R28、R29、R31、R32（部分：骨架子项未做）、R33、R35、R37、§5.2、§5.3（除 5.3.2）；**R1 标部分修复**（恢复/清空路径已补取消，"删除最后一辆车"路径不在本轮）。
- `DESIGN.md`：ItemPills→Wrap 后的 pill 间距口径、三页统一 loading/error 形态（如有相关章节）。
- 代码内对应"⚠ R 编号"注释随修复删除（AGENTS.md 约定）。

### 验证顺序

串行执行，避免 Flutter startup lock 冲突：

1. 每批次后 `flutter analyze` + 定向测试。
2. 批次 C 后先 `dart run build_runner build`。
3. 最终全量 `flutter test`（约 130 条 + 新增）。
4. 批次 B 后 `flutter build ios --simulator` 验证原生改动。

### 手动冒烟点

- 恢复/清空全流程（偏好保留/目录保留/通知取消）。
- 停车倒计时起停。
- 记录页滚动与筛选。
- 各表单视觉（Wrap 化 pills、合并输入行、统一 loading 态）。

---

## 主要风险

1. 批次 B 把通知同步从 build 改为 listenManual 驱动，60 条 widget 测试的触发时序可能需要个别调整（最可能出回归的一批）。
2. 全清 createCar 系 API 触及 ~23 处测试改写。
3. 恢复"保留偏好"是产品行为变化，靠确认文案 + 文档 + 测试三处锁口径。
4. ItemPills/Wrap 与统一 loading 态有轻微视觉变化，需手动核对。

## 明确不做

- R1 的"删除最后一辆车"残留路径。
- R4/R5/R9/R10/R14/R17/R20/R30/R34/R36/R38。
- 5.3.2 sheet 骨架收敛、5.3.5 FormActions。
- 不执行 git commit/push。
