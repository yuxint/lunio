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
- 测试面不变：widget_test 已锁 toast 文案、落库结果与跨页刷新，
  行为等价改造应全绿；不为纯编排搬家新增独立测试层。
