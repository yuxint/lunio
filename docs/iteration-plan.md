# Lunio 迭代计划

> 性质：跟进台账（排期、状态与验收口径），不是需求文档

## 1. 文档定位

本文件是 Lunio 的迭代总账：记录已排队事项与未排期的产品方向，供逐项跟进与销号。

与其他文档的分工：

- 业务规则与数据口径：`docs/prd/business-logic-prd.md`；
- UI 操作 ↔ 代码对照：`docs/operations-manual.md`；
- 架构决定及其修订：`docs/adr/`；
- 未修问题台账（R 编号）：`docs/code-review-report.md`；
- 本文件：接下来做什么、做到什么程度算完成。

单事项的执行票据按仓库惯例放 `.scratch/<feature-slug>/`（惯例见 `docs/agents/issue-tracker.md`），本文件只管总账，不收实现细节。

## 2. 维护规则

1. **完成一项**：勾选对应 checkbox 并注明日期（`（完成于 YYYY-MM-DD）`）；源自审查台账的事项同步更新 `docs/code-review-report.md`；涉及 UI 流程、数据写点、通知行为或 Provider 依赖的改动按 `docs/operations-manual.md` 第 8 节同步手册。
2. **新增事项**：写清内容、来源、验收口径，归入合适的分组（排队事项用 P 编号顺延，想法进第 4 节）；只收值得跟进的，随手小事不进本文件。
3. **排期调整**：直接改分组与顺序，不在文中写变更叙述，历史靠 git。

## 3. 已排队事项

### P1 真机复验轮（验证债，最先做）

- [ ] 提醒行百分比槽居中观感、记录页按项目视图形态（一行一卡）确认。
- [ ] 加油预估卡连续拖动确认；若不跟手，勿盲调 `RowSnapScrollPhysics`（`lib/features/shell/shared/scroll_snap.dart`），先查档位列表的 key 是否挂了「写库后回读的值」——那种 key 会让列表每次停稳就整体重建、第二段手势丢失；key 只放身份，数值纠偏走 `didUpdateWidget`。
- [ ] 实时活动（灵动岛/锁屏卡片）与桌面小组件在 ADR 0019 语义色下的外观（Swift 副本与 token 的一致性由 `test/core/semantic_color_contract_test.dart` 守卫；观感只能真机验收，ADR 0012）。
- [ ] 小组件深链 `lunio:///reminders` 真机走通（必须三斜杠形态，双斜杠 host 会吃掉路径导致匹配失败，ADR 0013）。

来源：ADR 0012/0013/0019 的真机验收条款。
验收：各项观感与走通确认；发现问题开票再修，不就地扩散。

### P2 停车倒计时过期态（R9/R17，用户可见 bug）

- [ ] R17：保存/编辑停车倒计时时所选时刻已过期的处理（保存时校验拦截，或「该时刻已过期」提示）。
- [ ] R9：已到点状态的出口（「已到点」一键开始新计时，或到期超过 N 小时自动清除并取消通知）。

来源：`docs/code-review-report.md` R9/R17（叠加态=「看着在计时其实什么都不会发生」）。
验收：具体方案做票时拍板；补通知服务/协调器测试；修后台账销号并删代码里的 ⚠ 标注。

### P3 Android 回归轮（第二平台补课）

- [ ] 油价抓取 Android 实拉验证（明文例外配置，ADR 0006/0011）。
- [ ] 停车倒计时 ongoing chronometer 通知与到点 alarm 通知的调度/取消回归。
- [ ] `README.md`「发布前仍需确认」的 Android 物理机清单（通知权限、文件选择器、分享面板、返回键、键盘、安全区）。

来源：ADR 0006；AGENTS.md「Android 通知行为与 iOS 不完全相同」；README 发布前清单。
验收：真机实测记录归档（截图或笔记）。

### P4 架构卫生四票（arch-0928 剩余）

- [x] 01 车辆数据纪元：动作层车辆域失效名单 `invalidateVehicleProviders` 换成数据纪元 bump（`vehicleDataEpochProvider`，与偏好纪元 `preferencesEpochProvider` 同构），新增按车派生缓存只需 watch 纪元一行（完成于 2026-10-06，ADR 0017 修订节）。
- [x] 02 坐标系柱状图命名模块：渲染体（柱数据项/纵轴刻度/虚线网格 painter/滚动与初始停最右编排）收编为 `lib/features/shell/records/axes_column_chart.dart`（`AxesColumnChart`/`AxesColumnItem`，保养年度柱与加油月度柱经同一接口消费），统计页文件只剩页面组装（完成于 2026-10-06；刻度纯函数部分先由 arch-1001/07 覆盖，此前本节误记整票已覆盖）。
- [ ] 03 同步信号接缝：恢复备份后的强制补判改为显式同步信号，协调器不再拿数据 provider 失效当信号用。
- [ ] 05 重入防护共享模块：通知同步控制器与小组件快照控制器的 busy/pending 重入协议收成一份小模块。

票据：`.scratch/arch-0928/issues/`（本机未跟踪文件，换机即丢）；04 票的目标已由现存共享模块覆盖（`lib/features/shell/shared/scroll_window.dart`），不再立项。
跑法：arch-pipeline 续跑（resumeDir=.scratch/arch-0928）或逐票 implement。
验收：各票自带验收清单；`flutter analyze` + 全量测试绿。

### P5 里程/日期历史合法性软提示

- [ ] 保存记录时「时间倒回但里程反增」的软提示（不拦截保存）：按项目参照上一条记录（用全部记录找，不只启用的）、按车维度里程随日期单调。

来源：保存路径现状不校验历史合法性（时间倒回、里程反增可正常入库）；软提示先例=同日查重弹窗、费用口径红字。
验收：`RecordFormController` 单测 + records widget 测试；`docs/operations-manual.md` 同步。

### P6 文档债（PRD 与 ADR 0005）

- [ ] PRD §13 偏好 key 清单补加油域（`fuelPredictionEnabled`/`fuelProvince`/`fuelGrade`/`fuelPriceCache`/`fuelManualPrices`，后两个为临时数据不进备份）。
- [ ] PRD §16 代码来源补齐现状（仓库家族、偏好门面、`entity_row_codec`、shell 各域、`fuel_prices.dart` 例外）。
- [ ] ADR 0005 文件名 `fresh-install-only-no-upgrade-paths` 与修订后内容（增量迁移政策）名不符实：改名并 `rg` 同步全部引用。

来源：PRD 与现状比对（偏好 key 权威清单见 AGENTS.md「数据与契约注意点」）。
验收：文档自洽、无断链（`git diff --check` + rg 引用检查）。

## 4. 未排期产品方向（想法池，按当前价值排序）

1. **备份自动化**：定期导出提醒或启动时温和提示。单机应用最大的实际风险是用户忘了备份，价值高于任何新功能。
2. **油耗/成本分析**：加油记录容积已落库预留（ADR 0015），百公里油耗、每公里成本有现成数据基础，不动表结构。
3. **多设备/云同步**：与本地优先哲学正面冲突，动工前先 grill 定形态（轻量备选：iCloud 文档同步备份文件）。
4. **对外发布**：对齐 `README.md`「发布前仍需确认」清单（Bundle ID/签名/图标/商店资产）+ 隐私清单；发布后第 5 节数据兼容红线即生效。
5. **watchOS 停车倒计时**：实时活动的自然延伸，最低优先级。

## 5. 迭代期铁律（出处见 AGENTS.md 与对应 ADR）

- 改表结构：数据库 `schemaVersion`+1、`onUpgrade` 增量迁移、迁移测试锁政策（ADR 0005 修订）；**对外发布后禁止卸载重装式/就地重定义式切换**，红线。
- 新保存路径进动作层（ADR 0007）、新偏好进偏好门面 typed 方法、编辑表单走表单运行时（ADR 0016）。
- R30/R36 维持不做（见 `docs/code-review-report.md`，属产品规则而非 bug）。

---

*本文档与其他文档或代码冲突时，以代码与对应文档为准，并回改本文件。*
