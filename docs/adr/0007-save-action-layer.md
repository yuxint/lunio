# ADR 0007：保存动作层收编"写库 → 失效 → 收尾"编排

日期：2026-09-03
状态：已接受

## 背景

providers.dart 顶部长期挂着一条警告："手动失效模式：漏调 invalidate 会导致
跨页面数据陈旧"。"写库 → 失效对应 provider 家族 →（需要时）通知域收尾 →
反馈"这条顺序约束是每个保存路径的隐式接口，却由约 15 个调用点各自手排：

- 7 处 sheet 保存（记录/车辆×2/手填油价/通知设置/手动日期/保养项目）各自
  重复"写库 + invalidate + mounted 检查 pop + toast"，且 pop/toast 用哪个
  context 有两套写法（fuel 的双 context 版考虑了 sheet 关闭后外层还能弹
  toast，其余单 context 版没有）；
- 8 处两步动作（删除×4、开发者模式/加油预测开关等）各自拼"写哪些偏好
  key + 失效哪个家族"，开发者模式关闭时要连带写 4 个 key 的规则只活在
  UI 注释里。

漏配失效的症状出现在离写库很远的页面上（"别的页面数据陈旧"），这类
wiring bug 在历次审查中反复出现（R1/R8/R13 都涉及编排顺序）。

## 决定

1. **`shared/shell_actions.dart` 扩容为保存动作层**：每个业务变更一个
   具名函数（`createCar` / `saveMaintenanceRecord` / `saveManualDate` /
   `saveFuelManualPrice` 等 14 个），内部固定编排"写库 → 失效 →（需要时）
   组合通知协调器"。分域分节：车辆 / 保养记录 / 保养项目 / 偏好 / 加油 /
   通知设置。
2. **动作层只收 WidgetRef，不碰 BuildContext**：不弹确认框、不 pop、
   不 toast。这些留在调用方，形成三行反馈薄壳——pop 用 sheet 的
   context、toast 用打开 sheet 前的外层 context（统一采用原 fuel 页的
   双 context 写法，两处 mounted 检查各自独立）。
3. **异常穿透**：动作函数不 try-catch。"没抛即成功"是返回值语义
   （全部返回 `Future<void>`）；异常照旧抛给表单的行内错误机制
   （`friendlyError` 翻译），将来若做"表单提交运行器"（审查报告候选 6）
   可直接把动作函数当 onSubmit 的业务体。
4. **失效家族知识收进动作函数**：调用方不再选择失效家族；
   `invalidateVehicleProviders` / `invalidatePreferenceProviders` 降级为
   动作层与少数既有调用方（备份恢复、清空数据、通知协调器）的内部
   实现。加油手填价保持单点失效 `fuelManualPriceProvider`（与偏好家族
   粒度不同，理由收进函数注释）。
5. **UI 侧连带规则一并收编**：开发者模式关闭时连带关闭手动日期与加油
   预测（入口只在开发者模式可见）这条业务规则从 profile_page 移入
   `setDeveloperModeEnabled`。
6. **范围边界**：通知域协议（权限对账、通知清扫、抑制读写）仍归
   通知协调器（ADR 见 docs/adr 目录，通知协调器 9-3 重构）；动作层在
   业务动作内部组合协调器，是它的上层入口。`deleteCar` 例外地保留
   确认框（破坏性操作的确认文案属 UI 决策）；停车倒计时的
   保存/清除两函数本就是"写+失效+协调器收尾"的完整动作形态，
   含 R13 的页面挂载检查，本决定未改动。

## 后果

- 新增保存路径时只有一个正确的写法：进动作层加一个函数，UI 侧只剩
  确认框与反馈薄壳，漏失效类 bug 的面收窄到一处。
- 手册第 0 节的通用模式从"UI 手排三步"改为"UI 调动作函数"；
  各流程步骤表中的 invalidate 描述同步指向动作层函数。
- `applyCar` / `setThemeModePreference` 顺手去掉了从未使用的
  `BuildContext` 参数（调用点 3 处同步更新）。
- 加油页 `_resetManualPrice`（重置手填价）因调用方持有的是
  `ProviderContainer` 而非 `WidgetRef`，保持原有三行手写，未强行收编。
  **（2026-09-09 更新：该例外已消除**——`ref` 改由 `_priceRow` 正常传入，
  重置走 `saveFuelManualPrice(pricePerLiter: null)`，"写库+失效"重新
  单一出口。）
- 测试面不变：widget 测试（`test/widget/`）已锁 toast 文案、落库结果
  与跨页刷新，行为等价改造应全绿；不为纯编排搬家新增独立测试层。

## 更新（2026-09-25：备份与数据重置分节收编）

- **新增"备份与数据重置"分节**：`exportBackup` / `restoreBackupFromFile` /
  `clearAllData` 三函数自 `settings_data.dart` 迁入动作层，编排（确认框 →
  原生文件桥 → 协调器 run* 模板 → `invalidateAllAppDataProviders`）全库
  只此一份。settings_data 头部自flag 的"⚠ 跨层依赖：UI 直接 import
  BackupCodec"随编码/解码下沉 `BackupRepository`（新增
  `exportBackupJson` / `decodeBackupJson`）一并消灭——codec 是备份契约的
  一部分，收在 data 层不再出界。
- **确认框例外从 deleteCar 扩到 restoreBackupFromFile / clearAllData**：
  两者同为破坏性操作（恢复不可撤销 / 清空不可撤销），确认文案跟着操作走。
  成功 overlay / 失败反馈仍留调用方（profile_page 三个私有反馈薄壳）。
- **返回值语义偏离第 3 条"全部返回 `Future<void>`"**：这三个函数返回
  `Future<bool>`——true=完成、false=用户取消（确认框/选文件/保存框取消
  都静默）、异常=失败穿透。确认框收进动作函数后，调用方必须能区分
  "取消"与"完成"才能决定是否弹成功 overlay；deleteCar 维持 void（删除
  无成功 toast，列表刷新即反馈）。
- **错误分类不动**：恢复失败中唯一约束冲突的"未写入任何数据"专用对话框
  留调用方，靠 `formatters.isUniqueConstraintError` 文本识别——这是
  ADR 0009 明文的驱动层兜底口径（恢复事务虽握在仓库手里、技术上可
  catch 后包装，但类型化属扩大 ADR 0009 范围，本轮不做；将来要做单独
  小轮修订）。
- 文件拆分：settings_data.dart 只剩静态行组件；通知设置与手动日期两个
  sheet 拆到 `settings_notifications.dart` / `settings_manual_date.dart`
  （vehicles.dart 拆分先例）。

## 更新（2026-09-26：偏好类失效改偏好纪元，ADR 0017）

- 决定 4 中的偏好类失效家族（`invalidatePreferenceProviders` /
  `invalidatePreferenceProvidersWithRef` / `invalidateFuelPreferenceProviders`
  及其共用实现）被**偏好纪元**取代（ADR 0017）：动作层偏好类函数
  （主题/手动日期/开发者模式/加油开关/省份/油品/手填价）与通知协调器
  三个偏好写点改为写完库 bump 一次，偏好派生 provider watch 纪元自动
  重算。"加油手填价保持单点失效"一并并入纪元（粗化影响：多出的重算
  都是本地单行读，无行为回归面）。
- 车辆类家族（`invalidateVehicleProviders`）维持手动失效模型不变；
  `invalidateAllAppDataProviders` 内含纪元 bump。
