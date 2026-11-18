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
- [ ] OBD 快速连接按钮四态颜色在主色渐变底上的可读性、油量水温信息卡刷新手感、跨 tab 常驻连接的耗电与稳定性（ADR 0027 真机验收条款）。
- [ ] 设置页与我的页新行序观感、连点手势与转正开关互不干扰（ADR 0028 真机验收条款）。
- [ ] 到期概览值文案语义色在浅色渐变底上的对比度（2026-11-16 拍板接受的代价）。

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

### P4 架构卫生五票（arch-0928 剩余）

- [x] 01 车辆数据纪元：动作层车辆域失效名单 `invalidateVehicleProviders` 换成数据纪元 bump（`vehicleDataEpochProvider`，与偏好纪元 `preferencesEpochProvider` 同构），新增按车派生缓存只需 watch 纪元一行（完成于 2026-10-06，ADR 0017 修订节）。
- [x] 02 坐标系柱状图命名模块：渲染体（柱数据项/纵轴刻度/虚线网格 painter/滚动与初始停最右编排）收编为 `lib/features/shell/records/axes_column_chart.dart`（`AxesColumnChart`/`AxesColumnItem`，保养年度柱与加油月度柱经同一接口消费），统计页文件只剩页面组装（完成于 2026-10-06；刻度纯函数部分先由 arch-1001/07 覆盖，此前本节误记整票已覆盖）。
- [ ] 03 同步信号接缝：恢复备份后的强制补判改为显式同步信号，协调器不再拿数据 provider 失效当信号用。
- [x] 04 吸附滚动视口共享模块：档位列表/加油记录卡垂直两处三明治收编为 `lib/features/shell/shared/scroll_window.dart`（`LunioSnapScrollWindow`，完成于 2026-10-06：垂直两处 2026-10-01 先行收编，本次补齐滚动条样式常量 `scrollbarThickness`/`scrollbarRadius` 单一出处、统计图表横向经论证不接入组件——参数管道，见票据决策日志；此前本节误记整票已覆盖不再立项）。
- [x] 05 重入防护共享模块：通知同步控制器与小组件快照控制器的 busy/pending 重入协议收成一份小模块（完成于 2026-10-06：`lib/features/shell/reminders/guarded_op.dart`（`GuardedOp`，enter/exit 配对 + 重跑回调注入），快照控制器手抄 `_writing`/`_pending` 标志位一并换用，机制测试 `test/features/guarded_op_test.dart`）。
- [x] 06 诊断连接编排：诊断页连接编排（相位机/尝试代数/扫描会话/最后读数合并与落库策略）收进 plain-Dart `DiagnosticsConnectionController`，页面只渲染转发、扫描 sheet 降为纯渲染器；widget 决策与竞态用例迁 controller 单测（完成于 2026-11-15；`test/features/diagnostics_connection_controller_test.dart` 15 用例，widget 29→20；GLOSSARY「诊断连接编排」；来源 2026-11-15 架构审查 C1，票据 `.scratch/diagnostics-connection-module/`）。

票据：`.scratch/arch-0928/issues/`（本机未跟踪文件，换机即丢）。
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

### P7 车辆诊断（OBD 油量水温读取，开发者模式工具页）

- [x] 01 检测点数据层：`diagnostics_probes` 全局表（不挂 carId）、仓库 CRUD（内置只读可启停、自定义可增改删）、内置三条种子幂等对账并入 bootstrap 总入口、DB v4 增量迁移、列表 provider 写点直失效（完成于 2026-11-12，ADR 0021）。
- [x] 02 备份 v4：`diagnosticsProbes` 段只导自定义项、版本白名单 [1,2,3,4]、恢复事务内重插（id 重新生成）（完成于 2026-11-12，ADR 0021；v1–v3 兼容读缺段=空，恢复后内置随 bootstrap 重建、自定义项存活）。
- [x] 03 开关与入口：开发者模式区块两行（开关行 + 入口行）、关开发者模式连带清理诊断开关（完成于 2026-11-13；偏好 `diagnosticsEnabled`/`lastObdDeviceId` 进门面 typed 方法，开关 provider watch 偏好纪元，动作层 `setDiagnosticsEnabled` + `setDeveloperModeEnabled` 连带分支，`/diagnostics` pushed 占位页）。
- [x] 04 ELM327 会话决策体：分帧缓冲、AT 序列状态机、串行轮询编排（plain-Dart 控制器 + Mock transport 单测）（完成于 2026-11-13；`obd_transport.dart` + `mock_obd_transport.dart` + `elm327_parser.dart` + `elm327_session.dart` 四模块，语料摘自实车日志，变异 3 处击杀：ATSP 7 必发/PID 匹配/组帧缓冲）。
- [x] 05 诊断页：三区布局（状态条/核心值卡/检测点行列表）+ Mock transport 页面测试（完成于 2026-11-13；`obd_runtime.dart` 域内接缝（transport=Mock 演示表+会话工厂，票 07 换 BLE）、`diagnostics_rules.dart` 升数估算、动作层 `setDiagnosticsProbeEnabled`、widget 测试 6 用例门闩夹具零真实定时器、变异 2/2 击杀，743 绿）。
- [x] 06 检测点表单：增改删自定义项，走表单 sheet 运行时 + plain-Dart 决策体（完成于 2026-11-13；`probe_form_controller.dart` 9 单测变异 2/2、`probe_form.dart` 表单+入口（ADR 0016 统一出口、删除确认入口弹）、动作层 `saveDiagnosticsProbe`/`removeDiagnosticsProbe`、内置行点按无编辑入口（story 23）、widget 5 用例升到 11，757 绿）。
- [x] 07 BLE 真链路：flutter_blue_plus + OBDTransport 传输层抽象（BLE/Mock 两实现）（完成于 2026-11-15；`ble_obd_transport.dart` 传输层+扫描器接缝+可辨识异常文案单一出口、`ble_scan_sheet.dart` 扫描选择 sheet、连接流程接设备记忆（直连/落扫/权限文案三向分流）、动作层 `rememberObdDevice`、双端权限声明、`--dart-define=LUNIO_OBD_MOCK=true` mock 回退开关、widget 11 新用例（页面测试共 22 用例）/ 全量 769 绿；2026-11-15 审查修复：建链/释放竞态收尾、首用门禁前置、Android 权限映射、连接中关 sheet 取消、停扫起始窗口（补 3 widget 用例 + 1 会话单测）；复核轮修复：teardown 订阅成对捕获、重选会话同一性、单次 device.disconnect、扫描归属代数（补 1 widget 重选用例）；FBP 2.x 商业授权口径进 ADR 0020 修订节；**真机验收待执行**——清单在手册 5.10 节）。
- [x] 08 文档收尾：operations-manual 诊断页章节、真机验收清单归档（完成于 2026-11-15；手册 5.10 补连接流程/扫描 sheet/BLE 传输层/真机验收清单六条；收尾核对：手册行号锚点三轮全量比对修正 80 处漂移（含 provider 依赖图 26 节点刷新、漏绘诊断域两 provider 图后补注、偏好纪元清单 11→12 计数修正），AGENTS/GLOSSARY/ADR/migration v4 事实核对一致，DESIGN.md 无新视觉 token 不动。2026-11-15 审查退回修正手册 5 处事实漂移：开关行类名统一为 `_DeveloperSwitchRow`、`lastObdDeviceId` 写点、7.1 表清单补 `diagnostics_probes`、5.7 关开发者连带清单补 `diagnosticsEnabled`、连接入口改按 `_startConnect`/`_openScanSheet` 分述）。
- [x] 09 扫描弹层修复：过滤空名设备 + 留白根因两处（完成于 2026-11-15；拍板反转 story 5「全部显示防误伤」——广播名为空的设备不进列表，`visibleScanEntries` 纯函数（过滤空名+信号降序）在扫描器数据源做、真扫描器与测试替身同一整备函数，单测 `test/features/ble_scan_entries_test.dart`；`ListView` 显式 `padding: EdgeInsets.zero` 去安全区垫入、空态占位去 `Center` 改紧凑上下 24dp；widget 加无留白几何回归用例；ADR 0020 修订节记反转）。
- [x] 10 断开按钮：已连接状态条行尾「断开」（完成于 2026-11-15；`_disconnectManually` 释放会话落「未连接」相位（黄色未连接适配器+选择设备按钮），不落红色「已断开」；设备记忆保留、重进仍直连；手动断开后置会话 null，迟到断开事件不改写相位；连接中不加取消（拍板保持范围）；widget 用例锁相位与记忆保留）。
- [x] 11 最后读数持久化：检测点行持久化最后有效读数（完成于 2026-11-15，ADR 0021 修订节；`diagnostics_probes` 加 `last_value`/`last_percent`/`last_reading_at` 三列、DB v4→v5 增量迁移（建表/加列分支互斥纪律）、只存有效值（无数据不写不覆盖）、每有效读数写一次不盖同步章（`saveProbeReading` 只 UPDATE 三列）、备份不携带（导出 payload 剥除、恢复从零积累）、行尾时间今天 `HH:mm:ss`/非今天 `M/d HH:mm:ss`（`formatReadingTime` 注入时钟可单测）、油量/水温核心值卡同源恢复；迁移 v2/v3 跨版本升级重复列缺陷当场修复并加 else-if 纪律；数据层三测试（迁移/仓库读数写点/备份契约）+ 跨天格式单测 + widget 2 用例（重进显读数/无数据不写不覆盖），全量 784 绿）；**真机视觉复验待执行**——留白/断开按钮/时间格式三项清单在手册 5.10 节 ⑦⑧⑨。
- [x] 12 扫描列表稳定性：首见定序 + ≤1Hz 刷新（完成于 2026-11-15，ADR 0020 修订节；根治实车反馈「行序频繁乱跳」——根因是每次扫描拍按当时 RSSI 全量重排而 RSSI 每拍抖动；`mergeScanEntries` 合并纯函数（空名过滤沿用、已有行位置冻结只更新数字、新设备按当下强度插入一次）+ `ScanEntryCoalescer`（首拍/新设备立即发射、纯数字变化合并至 1Hz，扫描会话 start 复位；定时器随会话起停）接入真扫描器；测试替身 emit 走同一合并函数、start 复位镜像；单测 16 条（合并语义 11 + 节流 5）+ widget 顺序稳定用例 1（页面共 27 用例）；不做自动停扫/重排动画/额外文案（拍板范围）；**真机视觉复验待执行**——手册 5.10 节 ⑩）。

票据：`.scratch/car-obd-diagnostics/issues/`（本机未跟踪文件）。
来源：2026-11-12 grill 三轮 spec（`.scratch/car-obd-diagnostics/spec.md`）+ ADR 0020/0021 + 硬件实车验收语料 `docs/car_obd_link/`。
验收：各票自带验收清单；BLE 真链路不进自动化，走 spec 的真机验收清单。

### P8 车辆诊断 v2（每车检测点 / 刷新规则 / 双油量 / 调试终端，2026-11-15）

- [x] 01 每车检测点：DB v6、备份 v5、每车播种/删车级联、`diagnosticsProbesProvider` 按车 family、项目式检测点管理 sheet（内置可编辑不可删、自定义可增改删）（完成于 2026-11-15，ADR 0021 修订节）。
- [x] 02 刷新规则：每检测点 `refresh_interval_seconds` 默认 30（5–3600）、1 秒拍调度、手动刷新 `requestImmediatePoll`、调试暂停（完成于 2026-11-15，ADR 0023）。
- [x] 03 双油量：车辆加满可加油量/油箱总容积、诊断油量卡可用/估算总油量、加油页不改（完成于 2026-11-15，ADR 0022）；测试覆盖思域 23.137% × 40.487 + 6.513 口径。
- [x] 04 调试终端与一键全量采集：`debug_panel.dart`、本车能力位图自动枚举标准 PID + 09/06/DTC + OBDb Honda Civic 2022 `supported_commands_by_ecu` 126 条私有 DID 分组、日志复制；私有 DID 只验证不进正常轮询（完成于 2026-11-15，ADR 0023）。
- [x] 05 测试/文档：全量 817 绿；迁移 v2–v5→v6、备份 v4→v5、检测点每车 CRUD/种子、会话手动刷新/暂停原始命令、widget 双油量/管理 sheet/调试终端、能力位图自动枚举/私有 DID 清单；010F 模板换 010B 进气压力；手册 5.10/5.10.1、AGENTS、migration schema、GLOSSARY、ADR 同步。
- [x] 06 全量采集与定案（原 Phase 2，2026-11-16 形态变化关闭）：用户跑一键全量采集（1465 行日志）→ 分析定案三点——水温走标准 PID `0167`（`coolantTempAux`，`22267A` 假设作废，Phase 2 私有头/ISO-TP 重组不再需要）、`227029` = 表显刻度交叉验证不接卡片（ADR 0022 修订节）、`01A6` 里程表入模板并同步车辆里程（ADR 0026）；内置水温切换 0105→0167（存量车手动编辑迁移）。
- [ ] 07 电瓶健康检查（2026-11-17 拍板立项，ADR 0029 后续）：静置→启动→充电三点测量引导流程（熄火静置 12.4-12.6V 满电 / 启动瞬间 <9.6V 电池老化 / 运行 13.5-14.5V 充电正常），三态引导 UI + 结果解读；OBD 单点电压不能判断寿命，三点测量才是。
- [x] 08 一键精简与常用检测点（2026-11-16）：一键脚本从枚举一切（约 150 条 ≈28s）精简为健康快照（约 24 条 ≈5s，快照集 ∩ 位图 + DTC + 只留 227029，ADR 0023 修订节），文案改「一键检测」；推荐模板第二批 01A6 里程表（燃油修正/氧传感器/011F/013C 拍板不加）；ECU 里程同步两档（确认式默认 + 管理 sheet「ECU 里程自动同步」开关默认关，ADR 0026）；分析文档 `docs/car_obd_link/docs/全量采集分析-2026-11-16.md`（含满箱采集操作卡，满箱点只精化 227029 斜率）；GLOSSARY「里程表（ECU）」、「实测总油量」词条改弃用。

## 4. 未排期产品方向（想法池，按当前价值排序）

- **本田私有 DID 探索（2026-11-17 想法池收录，ADR 0029 后续）**：变速箱油温（CVT）、续航里程、机油温度——标准 PID 本车全不支持（全量采集位图证实），只能实车探索 22xxxx 私有 DID 空间（一键检测私有段扩展或 Car Scanner 厂商库交叉验证）；读到之前阈值分析（CVT 60-85 绿 / 85-100 黄 / >100 红）是纸上谈兵。

1. **备份自动化**：定期导出提醒或启动时温和提示。单机应用最大的实际风险是用户忘了备份，价值高于任何新功能。
2. **油耗/成本分析**：加油记录容积已落库预留（ADR 0015），百公里油耗、每公里成本有现成数据基础，不动表结构。
3. **多设备/云同步**：与本地优先哲学正面冲突，动工前先 grill 定形态（轻量备选：iCloud 文档同步备份文件）。
4. **对外发布**：对齐 `README.md`「发布前仍需确认」清单（Bundle ID/签名/图标/商店资产）+ 隐私清单；发布后第 5 节数据兼容红线即生效。
5. **watchOS 停车倒计时**：实时活动的自然延伸，最低优先级。
6. **诊断模式分层（保养模式/维修模式）**：当前诊断页 = 日常用车检测点（用户 2026-11-16 拍板口径）；未来按"保养模式/维修模式"分层显示不同数据（维修模式可能需要恢复全量私有 DID 扫描，精简掉的 126 条清单可从 git 历史恢复或重跑 OBDb 数据源）。动工前先 grill 模式边界与切换形态。

## 5. 迭代期铁律（出处见 AGENTS.md 与对应 ADR）

- 改表结构：数据库 `schemaVersion`+1、`onUpgrade` 增量迁移、迁移测试锁政策（ADR 0005 修订）；**对外发布后禁止卸载重装式/就地重定义式切换**，红线。
- 新保存路径进动作层（ADR 0007）、新偏好进偏好门面 typed 方法、编辑表单走表单运行时（ADR 0016）。
- R30/R36 维持不做（见 `docs/code-review-report.md`，属产品规则而非 bug）。

---

*本文档与其他文档或代码冲突时，以代码与对应文档为准，并回改本文件。*
