# AGENTS.md

## 项目定位

Lunio 是车辆保养记录 App 的 Flutter 单仓工程，当前可以按正式第一版产品处理。主壳层里包含提醒、记录、我的、车辆管理、保养项目、保养记录、通知、停车倒计时、手动日期、主题切换、备份导入导出等可交互能力。

后续协作时，先把它当作一个本地优先的车辆保养 App 处理，而不是通用 Flutter demo。

## 技术栈

- Flutter / Dart
- Riverpod：依赖注入、偏好与业务数据状态
- go_router：平级入口路由，固定路径为 `/reminders`、`/records`、`/me`，另有条件路径 `/fuel`（加油预测开关打开时才出现在底部导航，路由常驻），以及不挂主壳层的 pushed 子页 `/cost-stats`（费用统计）与 `/diagnostics`（车辆诊断，开发者模式区块开关打开后才有入口；两者同形态：默认转场，返回键在 LunioTopBar 的 leading 位）
- Drift + SQLite：本地数据库、唯一约束、事务、备份恢复
- Material 3 + 自定义 `LunioTokens`：浅色/深色主题 token

不要在没有明确要求时引入新框架、新状态管理、新路由方案或新的 UI 组件库。

## 关键入口

- `lib/main.dart`：App 启动入口。
- `lib/app/lunio_app.dart`：`MaterialApp.router`、主题模式和路由挂载。
- `lib/app/app_router.dart`：GoRouter 配置。`appRouter` 是稳定单例，主题切换时不要重建路由导致跳页。
- `lib/app/providers.dart`：Riverpod provider 总入口，包含数据库、偏好门面、各域仓库（主仓库/目录/加油/备份）、车辆、当前应用车辆、保养项目、记录、手动日期、生效今天（`effectiveTodayProvider` 零点自刷新，ADR 0025）、主题偏好、通知服务、两个缓存纪元（ADR 0017 及其 2026-10-06 修订节：偏好纪元 `preferencesEpochProvider`——偏好类缓存失效走纪元 bump，新增偏好派生 provider 在自己 build 首行 watch 纪元，停车倒计时 provider 例外维持写点直失效；车辆数据纪元 `vehicleDataEpochProvider`——车辆/项目/记录/加油四张业务表的派生缓存失效走纪元 bump，读这些表的 provider（cars/appliedCar/三个按车 family 及其 applied 派生/vehicleModels 共 9 个）build 首行 watch 纪元，数据束与费用统计接缝纯派生不 watch、刷新经上游传导，bootstrap 目录对账不 watch、重灌只在恢复备份/清空数据后走全量失效入口显式触发，机制测试在 `test/features/vehicle_data_epoch_test.dart`）、应用车辆数据束（`appliedCarBoardProvider`：当前应用车辆 + 项目清单 + 保养记录 + 生效今天四件套一次拿齐的读侧接缝；就绪语义「任一上游未就绪整体未就绪、无车是合法空态」只有这一份实现，按当前车消费数据的新页面/控制器/表单 watch 它一处即可，不要再各自手抄装载策略；通知设置/停车倒计时/加油记录不入束，机制测试在 `test/features/applied_car_board_test.dart`）、费用统计页数据接缝（`costStatsDataProvider` + 数据类 `CostStatsPageData`：数据束 + `appliedCarFuelRecordsProvider`（应用车辆加油派生，无车空表语义同源）一次拿齐，loading/error 随上游传导、费用统计页 watch 它一处单门卫收口，机制测试在 `test/features/cost_stats_data_test.dart`）等。油价域 provider（省份/油品/手填价/数据源/油价控制器/生效链）是例外，集中在 `features/shell/fuel/fuel_prices.dart`，本文件不 import 它，依赖单向。
- `lib/features/shell/app_shell.dart`：主壳层入口，保留平级入口页面挂载（加油项按开关条件显示）、底部导航、生命周期监听和提醒通知同步触发。
- `lib/features/shell/reminders/`：提醒页、停车倒计时、保养提醒量规清单（全量平铺，2026-09-30 拍板去分层，ADR 0018 修订节）、提醒行组装、通知内容组装与调度 helper、桌面小组件快照组装与同步（`widget_snapshot.dart` / `widget_snapshot_controller.dart`）。
- `lib/features/shell/records/`：记录页、记录筛选、保养记录表单和记录删除相关交互。两步表单的状态机（字段、步进、校验、同日查重循环驱动、里程单调软提示决策）收在 `record_form_controller.dart`（plain-Dart `RecordFormController`：弹窗/日期选择器实现经 `RecordFormUi` 注入、已有记录经快照 getter 注入，单测在 `test/features/record_form_controller_test.dart`）；费用区算链控制器 `record_cost_form_controller.dart` 作为它的内部实现被组合，间隔草稿与提交清单在 `record_interval_updates.dart`，widget 只渲染两步视图、转发事件并持有弹窗实现与文案。费用统计聚合纯函数在 `cost_stats.dart`（总额/年度/月度用记录总费用权威值、项目计费值=项目费用没填不参与、优惠分摊按费用权重最大余数法守恒、其他段守恒（总费用≡Σ项目实付+其他）、月均按首条记录月到当月全程摊薄、项目档案逐次明细）；独立统计页在 `cost_stats_page.dart`（路由 `/cost-stats`，**作用域永远当前应用车辆**，页面数据接缝 `costStatsDataProvider` 在 providers.dart——数据束 + 加油 applied 派生一次拿齐、页面单门卫收口，页面文件只做组装与渲染）：项目占比=100% 堆叠条+紧凑明细行（分段按实付降序主色深→浅，行=色点｜项目名｜百分比｜省额｜实付，三数值列固定槽右对齐）；保养费用=坐标系年度柱状图（每年一柱=该年总费用，柱色统一主色无高亮，纵轴刻度+虚线网格线、柱顶标金额，≥2 条记录展示）；加油费用卡固定在页面最后，头部一行「总费用+月均」，全历史连续月度柱（纵轴固定左侧+虚线网格线、柱顶标金额、轴标签「26.9」式，卡内无年度维度）；保养柱状图与加油柱共用同一图表行为（放得下铺满、超一屏横向滚动+底部滚动条+初始停最右），渲染体（柱数据项、纵轴刻度、虚线网格 painter、滚动/初始停最右/停稳吸附编排）2026-10-06 收编为 records 域命名模块 `axes_column_chart.dart`（`AxesColumnChart`+`AxesColumnItem`，两张卡经同一接口消费），共用标尺（刻度三档步进阶梯、柱高按峰刻度归一、滚动模式列宽取整校准）2026-10-01 收编为 records 域纯函数 `chart_scale.dart`（`chartScaleFor`/`ChartScale.fractionOf`/`calibrateColumnWidth`，直接单测 `test/features/chart_scale_test.dart`，下一张同坐标系图接入时复用同一把尺与同一个图），占比卡与加油卡头部一行=标签+金额+右侧小字；汇总卡=「总费用｜今年保养｜今年加油」三栏（无加油记录隐藏第三栏）；页面空态守卫=保养+加油都无记录。项目档案 sheet 在 `cost_item_history_sheet.dart`。加油费用聚合纯函数独立在 `fuel_cost_stats.dart`（口径=实付优先、没填取应付，见 ADR 0015），与保养口径互不掺和。记录页头部汇总行=「今年保养 + 今年加油」，两段按域各自显隐。
- `lib/features/shell/fuel/`：加油页（油价卡副标题点按改省份/油品、加满预估档位列表滚动定档；加油记录卡与记一笔/编辑/删除表单在 `fuel_records_card.dart`，字段=日期/油品/单价/应付/实付（容积由实体按应付÷单价算好落库**预留**、页面不展示；单价在表单油品=油价卡油品时预填生效价；应付与实付之间的箭头即「同应付」快捷回填）；表单决策体（字段态、回填优先级、预填一次性语义、快捷回填守卫、校验与提交载荷构造）收在 plain-Dart 控制器 `fuel_record_form_controller.dart`——日期选择器实现经 `FuelRecordFormUi` 注入、不持表单运行时把手不碰 BuildContext（接法同 `record_form_controller.dart` 先例，单测 `test/features/fuel_record_form_controller_test.dart`）；超过 5 条固定 5 行高卡内滚动+右侧滚动条，无展开/收起；加满预估档位列表的滚动定位决策体（已存档位/偏移/下标三向换算、停稳定档落库、外部档位变化重定位守卫）收在 plain-Dart 控制器 `fuel_tier_list_controller.dart`——落库动作与滚动真值经 `FuelTierListViewport`/闭包注入、widget 只转发滚动事件并渲染，单测 `test/features/fuel_tier_list_controller_test.dart`）；`fuel_prices.dart` 是油价域状态接缝（省份/油品/手填价/数据源/油价控制器/生效链 provider 集中在此）。加满可加油量与油箱总容积在添加/编辑车辆表单（均非必填，ADR 0022）。油价数据源契约见 `docs/adr/0001`，滚动定档与容积归属见 `docs/adr/0002`，油价按省抓详情页、缓存单省价表、换省手动刷新见 `docs/adr/0011`，加油记录数据模型见 `docs/adr/0015`。
- `lib/features/shell/profile/`：我的页、车辆新增/编辑/切换、保养项目管理、备份导入导出、通知设置、手动日期。开发者区块两颗开关（加油预测/车辆诊断，`profile_page.dart` 私有行组件），诊断开关打开后出现"进入诊断页"入口行，关开发者模式连带置 false（`shell_actions.dart → setDeveloperModeEnabled`）。
- `lib/features/shell/diagnostics/`：车辆诊断域（开发者模式工具页，ADR 0020/0021 修订节/0022/0023/0024；检测点每车一套）。会话层五模块（票 04）+ 连接编排（2026-11-15，GLOSSARY「诊断连接编排」）：传输层接口 `obd_transport.dart`（OBDTransport 字节流收发契约）+ 扫描器契约 `obd_scanner.dart`（ObdScanner 扫描器接缝，含门禁前置 `ensureReady`）+ BLE 实现（ADR 0024 接缝）：无线电面 `obd_radio.dart`（`ObdRadio` 端口：适配器状态/扫描/设备建链与服务发现/通知订阅与写入；跨端口自有类型，状态流订阅回放当前值）+ FBP adapter `ble_obd_radio.dart`（`FlutterBluePlusObdRadio`：唯一调用插件 API——License.nonprofit/continuousUpdates/withRemoteIds/withoutResponse 在此固定）+ 两个 adapter 状态机 `ble_obd_link.dart`（`BleObdScanner`/`BleObdTransport`：适配器门禁/定向扫描定位/建链/订阅 2AF0/写入 2AF1/断连监视/扫描归属代数；不 import flutter_blue_plus）+ 错误分类 `ble_obd_errors.dart`（分类与状态条文案单一出口，无 FBP 依赖）与平台错误识别 `ble_obd_platform_errors.dart`（权限文本嗅探 + fallback 包装，仅 FBP 侧使用），扫描清单协议在 `ble_scan_entries.dart` + Mock `mock_obd_transport.dart`（可编程响应脚本 + 语料演示脚本 `mockObdCorpusDemoResponses`，模拟器演示与单测共用）+ 解析纯函数 `elm327_parser.dart`（按 `>` 组帧缓冲、多 ECU 按请求 PID 匹配、PID 公式枚举解析、hex 原文提取）+ 会话决策体 `elm327_session.dart`（plain-Dart 控制器：AT 序列逐条发等 `>`、串行轮询按每检测点 `refresh_interval_seconds` 以 1 秒拍倒计时调度（默认 30s）、手动刷新 `requestImmediatePoll`、调试暂停 `pausePolling`/`resumePolling` 与原始命令 `sendRawCommand`、超时/延时经构造注入；会话一次性对象，重连=新建实例）+ 连接编排 `diagnostics_connection_controller.dart`（plain-Dart `DiagnosticsConnectionController`：相位机、尝试代数、直连/扫描分流、扫描会话、最后读数合并与落库策略；构造注入会话工厂/扫描器/设备记忆/读数落库/UI 动作接缝 `DiagnosticsConnectionUi`（开/关扫描 sheet）；状态经不可变 `DiagnosticsConnectionState` + ChangeNotifier 通知，页面只渲染与转发）；单测 `test/features/elm327_parser_test.dart`、`test/features/elm327_session_test.dart`（语料摘自 docs/car_obd_link/）、`test/features/diagnostics_connection_controller_test.dart`、`test/features/ble_obd_errors_test.dart`。页面三区实现（票 05）：`diagnostics_page.dart`（路由 `/diagnostics`，pushed 子页；只做数据门禁、渲染 controller 状态与转发动作）——连接状态条（未连接/扫描中/连接中/已连接/已断开+错误文案；行尾动作按相位：已断开=重连、未连接/扫描中=选择设备、**已连接=断开**（`disconnectManually` 释放会话落「未连接」相位、设备记忆保留，手动断开不落红色「已断开」；连接中无动作）——**连接流程（票 07，编排归 controller）：`start` 读设备记忆 `lastObdDeviceId` 命中直连，无记忆先过适配器门禁（`ObdScanner.ensureReady`）再落扫描选择 sheet `ble_scan_sheet.dart`（**纯渲染器**：按 controller `state.scan` 渲染 entries/连接中行/提示，点选回 `pickDevice`；**广播名为空的设备不进列表**——2026-11-15 拍板反转 story 5「全部显示防误伤」；**行序首见定序 + 信号数字 ≤1Hz 刷新**（同日拍板治行序乱跳）：`mergeScanEntries` 合并纯函数（过滤空名+位置冻结+新设备按当下强度插入）与 `ScanEntryCoalescer`（首拍/新设备立即发射、纯数字变化合并到 1Hz，扫描会话 start 复位）在扫描器数据源做（`ble_scan_entries.dart`）、真扫描器与测试替身同一合并函数，单测 `test/features/ble_scan_entries_test.dart`；列表 `padding: EdgeInsets.zero` 去安全区垫入、空态占位紧凑 24dp、无 `Center` 撑高，行内"连接中…"），直连失败自动落扫描，点选连接成功即写记忆（闭包注入的动作层 `rememberObdDevice`）；蓝牙权限/开关类失败状态条渲染明确文案不落扫描（Android 运行时权限在 `startScan`/`connect` 才请求，平台异常按消息归 `permissionDenied`；扫描启动门禁失败经 controller 关 sheet）；连接中关闭 sheet = 取消本次连接（controller 作废尝试代数，会话 dispose 收尾，迟到失败不改写相位）；扫描器接缝 `ObdScanner` 由 controller 消费（扫描启动/停止/结果订阅归 controller）**+ 核心值卡（油量百分比大字+双油量小字（`domain/rules/diagnostics_rules.dart` 的 `estimateFuel`：可用 = % × 加满可加油量、估算总 = 储备 + 可用；总容积未填只显可用；ADR 0022）、水温；与行列表共用 `readingFor`：实时读数优先、无实时回退持久化最后读数）+ 检测点行列表（名称+当前值+最后更新时间（`formatReadingTime`：今天 HH:mm:ss、非今天 M/d HH:mm:ss）+启停开关；无数据行级灰态；页面行只读实时读数（无数据附原因）；列表尾「管理检测点」行打开项目式管理 sheet（`probe_management_sheet.dart`：内置卡片可编辑不可删、自定义可增改删、刷新间隔表单、推荐模板）；**最后读数持久化（2026-11-15，ADR 0021 修订节）**：每个有效读数写一次库（`saveProbeReading` 只 UPDATE `last_value`/`last_percent`/`last_reading_at`，不盖同步章；「无数据」不写不覆盖；不进备份、删检测点列随行删；重进页面显最后有效值；写策略归 controller））；连接生命周期归 controller（页面触发：进页面 `start`、离开 `dispose`；断开重连=新会话实例），会话工厂/扫描器/无线电面接缝在 `obd_runtime.dart`（**票 07 起默认装配 BLE 真链路，2026-11-15 起扫描器与传输层共享 `obdRadioProvider` 的同一 radio 实例（ADR 0024）；`--dart-define=LUNIO_OBD_MOCK=true` 整链回退 Mock 语料演示**；会话工厂收目标设备标识；controller 的 `mockLink` 构造参数默认 `obdMockLink`）；启停走动作层 `setDiagnosticsProbeEnabled`（写库→逐出→等重算落地）；检测点表单（`probe_form.dart`，ADR 0016 统一出口，副标题注明「仅用于读取类指令」，删除在管理卡片上）：字段 = 名称/指令/刷新间隔（默认 30，5–3600）/解析类型/推荐模板；决策体 `probe_form_controller.dart`（plain-Dart：名称 trim、指令归一 normalizeObdCommand、刷新间隔校验、载荷 id/enabled/catalogKey 编辑守恒，单测 `test/features/probe_form_controller_test.dart` 11 用例）；动作层 `saveDiagnosticsProbe`/`removeDiagnosticsProbe`（按车 family 逐出+等重算落地）；新增 `probe_management_sheet.dart`（项目式检测点管理 sheet）与 `debug_panel.dart`（调试终端：暂停轮询/自由命令/日志复制；一键全量采集经 `obd_verification_run.dart`；会话经 `controller.session` 取）；`probe_templates.dart` 推荐模板第一批 010B 进气压力（010F 本车不支持）；`obd_verification.dart` / `obd_verification_commands.dart` 为采集编排与私有 DID 清单，`obd_verification_run.dart` 为一键验证 run 协议（顶层 `runObdVerification`：命令序列 + 默认头恢复 + 日志组装；执行器/时钟/日志出口注入，单条超时继续、链路失败中止，中止行在恢复尝试之后；纯 Dart 不 import 会话）；测试 `test/widget/diagnostics_test.dart`（21 用例：三区 9（状态序列/油量卡三态/无数据灰态/启停/离页/调试终端/一键采集接线）+ 表单 5 + BLE 连接流程 5（无记忆点选记忆/扫描无留白/行序稳定/已连接断开/取消后重选）+ 最后读数持久化 2，门闩夹具 `test/helpers/diagnostics_fixture.dart` + FakeObdScanner 假扫描器）+ `test/features/diagnostics_connection_controller_test.dart`（15 用例：直连与相位 7/扫描点选 6/最后读数 2）+ `test/domain/diagnostics_rules_test.dart` + `test/features/obd_verification_test.dart`（能力位图自动枚举/私有 DID 清单 6 用例）+ `test/features/obd_verification_run_test.dart`（run 协议 6 用例）+ `test/features/ble_obd_scanner_test.dart`（8 用例：门禁四路/启动顺序/起始窗口停扫/半开清理/合并节奏）+ `test/features/ble_obd_transport_test.dart`（12 用例：建链全序/定向扫描超时/通道缺失/回放与链路丢失/四个 await 边界取消/单次断开/发送/扫描归属）；开关/入口行在 profile 域（见上行），偏好走 `diagnosticsEnabled`/`lastObdDeviceId` 两 key（门面 typed 方法）。
- `lib/features/shell/shared/`：shell 内部共享的 modal/dialog/toast、日期选择器、格式化、错误文案、表单 sheet 运行时（`form_sheet.dart`，`showLunioFormSheet` + `FormSheetHandle` + `FormSheetHandleHost` 宿主 mixin（State 短名读 saving/errorText/setFormError，widget 实现 FormSheetHandleWidget 接口），ADR 0016：装载结果类型化（`showLunioFormSheet<R, D>` 的 load 返回装载结果直达 guard/builder，入口不写闭包共享变量；无装载入口走薄皮 `showLunioFormSheetNoLoad`）、装载失败/领域守卫 toast、barrierDismissible 固定 false、键盘 inset 经 sheet context、提交成功 pop+successMessage toast、非提交出口 close 全部统一出口——编辑表单一律走它，不要手写 showLunioModalSheet+PrototypeSheetFrame+pop/toast）和小型 UI 组件（数字输入统一走 `LunioNumberField`，空态占位统一走 `LunioEmptyCard`，居中弹窗卡片统一走 `LunioDialogCard`/`LunioDialogActions`——不要手写 Dialog+Container 装饰块；整卡可点统一走 `LunioTappableCard`——卡圆角与按压水波裁剪圆角在组件内部取同一 `radiusLarge` 对齐，不要手写 LunioCard+透明 Material+InkWell 三明治）。
  - `reminders/parking_countdown.dart`：停车倒计时卡片、表单和时间选择器（保存/清除走动作层 `shell_actions.dart`）。
  - `reminders/reminder_list.dart`：保养提醒平铺清单（去分层，ADR 0018 修订节）、横向量规提醒行（百分比固定槽右对齐）、记录详情 sheet 和进度环画笔（画笔现仅供停车倒计时卡）。
  - `reminders/notification_coordinator.dart`：通知协调器（LunioNotificationCoordinator），通知域规则的唯一拥有者——权限真值对账、删车/恢复/清空的通知清扫模板、停车倒计时通知尾巴、"稍后提醒/知道了"抑制读写；通知相关偏好 key 的唯一写点。恢复备份收尾的强制补判经 bump 守卫模块的显式同步信号发出（2026-10-06 起，不再 invalidate 数据 provider 当信号）。`reminders/notification_sync_guard.dart`：通知同步守卫（NotificationSyncGuard/SyncRun）——同步代数与写库中间态旗的唯一拥有者（代数 provider 也定义在此；显式同步信号 `notificationSyncSignalProvider` 同住本模块：协调器 bump、同步控制器订阅，恢复屏障重算后的强制补判通道），协调器是唯一写者，两条 lane 执行体（控制器侧）与协调器经 `acquire()` 领票在检查点问 `run.isValid`，新检查点不要手抄旗/代数协议。`reminders/notification_sync_engine.dart`：通知同步 engine（NotificationSyncEngine/SyncLaneOutcome + 「同步快照」`NotificationSyncSnapshot`，GLOSSARY 词条，2026-11-15 收编）——变更判定与分发模块：`sync()` 读一份快照（车/项目/记录/生效今天 + 通知设置切片 + 停车倒计时），系统通知 / 应用内两条 lane 各自与自己上次成功消费的快照比较（`sameSystemLane`/`sameInAppLane`，字段清单镜像收编前的字符串签名），不等价才调注入的 sink 执行，`applied`/`skipped` 才记账（`aborted`/`failed` 不记、下一轮补判）；两个 per-lane `GuardedOp` 负责重入/pending 重跑；`invalidateSystemLane`/`invalidateInAppLane`/`invalidateAllLanes` 供权限请求成功、回前台、弹窗动作后强制重排（失效代数保证在途轮次不吞掉强制重跑）；入口早退（disposed/写库中间态/输入未就绪）同归本模块，单测 `test/features/notification_sync_engine_test.dart`（快照字段覆盖 + lane 独立 + 记账时机 + pending/失效）。`reminders/notification_sync_controller.dart`：通知同步控制器 + 同步数据源清单单一出口——被动监听外壳：`notificationSyncSources`（通知设置/应用车辆数据束/停车倒计时）在模块内唯一声明，`start()` 的 listenManual 订阅与恢复备份屏障重算的等待名单（`waitForNotificationSyncSources`，动作层恢复编排经注入 read 调用）都从它推导；清单之外另有两条控制面订阅（停车实时活动对账 + 显式同步信号）；`syncFromProviders()` 是薄入口（首启权限链保持每次入口一次，再委托 engine），两个执行体（系统调度 / 应用内弹窗）作为 engine 的 sink；调整同步引擎监听面（换接缝/增删数据源）只改这一处，动作层不要再抄第二份等待名单，机制测试在 `test/features/notification_sync_controller_test.dart`。
  - `reminders/reminder_rows.dart`：提醒行视图模型与组装（`buildReminderRows`）、空态分类单一出口（`classifyReminderRows`）、`reminderRowsProvider`（提醒页数据接缝，watch 应用车辆数据束 `appliedCarBoardProvider`，英雄卡与列表共消费）；通知侧复用同一组装函数。
  - `reminders/widget_snapshot.dart`：桌面小组件快照组装纯函数（`buildWidgetSnapshotJson`，契约 `schemaVersion: 1` + 14 天预生成窗口，ADR 0013）；`reminders/widget_snapshot_controller.dart`：快照同步控制器（AppShell 挂载、listenManual 应用车辆数据束，内容相同不重写、失败不记账）。`reminders/guarded_op.dart`：重入防护小模块（`GuardedOp`：enter/exit 配对 + 重跑动作经回调注入）——"执行中来了新请求不丢弃、本轮结束用最新数据重跑一轮"协议的单一实现（2026-10-06 从通知同步控制器私有 _GuardedOp 收编），通知同步 engine（系统通知 lane / 应用内 lane 两实例）与小组件快照控制器共用；isDisposed 只参与记 pending 与重跑决策、执行内销毁检查归调用方/守卫票，机制测试在 `test/features/guarded_op_test.dart`。
  - `reminders/reminder_notifications.dart`：系统通知内容组装（`buildScheduledNotifications`）、到期清单（`maintenanceNotices`，"没记录不产生提醒"产品约定）、**生效到期清单单一出口**（`buildActiveDueList` + 数据类 `ActiveDueList` + 静默判定接缝类型 `ReminderSilenceRead`：到期清单逐项过静默、跳过无 id 项目、里程更新提醒到期+静默判定一次拿齐；静默语义按通道由调用方绑定协调器两个同名单方法参数化、循环内检查点经可选 `shouldAbort` 接缝注入——系统通知与应用内弹窗两通道取同一份，2026-10-19 收编，机制测试在 `test/features/active_due_list_test.dart`）、全量数据签名（已随「同步快照」收编删除，见 `notification_sync_engine.dart`）。`reminders/reminder_dialog_flow.dart`：应用内提醒弹窗链路的决策体（`InAppReminderDialogFlow.checkAndPresent`：经 `buildActiveDueList` 单一出口取生效到期清单（注入应用内通道静默判定与 `shouldAbort` 票谓词）、弹窗动作分支、检查点、动作后强制重排判定，返回 `SyncLaneOutcome`）——plain-Dart 不碰 BuildContext，静默读/弹窗呈现/抑制偏好写/重排全部经注入接缝（接法同 `RecordFormUi` 先例；`ReminderDialogAction` 枚举也定义在此，弹窗 UI 反向消费），通知同步 engine 管变更判定与 per-lane 防重入，控制器只保留生产接缝组装与两个执行体，单测（completer 驱动 await 边界 + 检查点位点变异验证）在 `test/features/reminder_dialog_flow_test.dart`。`reminders/reminder_dialogs.dart`：应用内提醒弹窗（抑制读写经通知协调器）。
  - `profile/vehicles.dart`：车辆列表、车辆卡片、车辆切换，以及添加/编辑车辆 sheet 入口（数据装载守卫 + 提交给动作层的接线）；添加车辆两步向导（第一步表单 + 草稿状态机控制器 `AddCarWizardController`：模板加载经注入、项目草稿变更面（编辑/启停/删除，内置"至少一个启用项目"守卫）plain-Dart 可单测）在 `profile/add_car_wizard.dart`，车型目录选择器（搜索过滤/品牌派生/生效品牌回退三个纯函数）在 `profile/vehicle_model_picker.dart`。向导第一步与编辑车辆共用的"车辆基础信息表单"决策体（初始态新增默认/编辑回填、换车型重置推荐动力类型、里程与容积校验、容积回填文本格式、提交载荷与同步元数据构造；日期选择器实现经 `CarFormUi` 注入，接法同 `RecordFormUi` 先例）在 `profile/car_form_controller.dart` 的 plain-Dart 控制器 `CarFormController`，widget 只渲染转发，单测在 `test/features/car_form_controller_test.dart`。
  - `profile/maintenance_items.dart`：保养项目 sheet、列表、卡片、项目表单和恢复默认草稿。
  - `profile/settings_data.dart`：个人中心设置行、主题行与版本 footer；备份导出/恢复/清空的编排收在动作层「备份与数据重置」分节，页面只留反馈薄壳；通知设置 sheet 在 `settings_notifications.dart`，手动日期 sheet 在 `settings_manual_date.dart`。
  - `shared/shell_shared.dart`：shell shared barrel；具体实现分别在 `shared_widgets.dart`、`date_picker.dart`、`modal_feedback.dart`、`form_sheet.dart`、`formatters.dart`、`shell_actions.dart`、`scroll_snap.dart`（`RowSnapScrollPhysics` 整行/整柱吸附物理：档位列表/加油记录卡/统计图表三处共用，纯手势对齐不记录）、`scroll_window.dart`（`LunioSnapScrollWindow` 定高吸附滚动窗口：定行高视口 + 3dp 细滚动条样式 + 拇指让位缩进（`thumbInset` 常量，定高表头对齐引用同一份）收在组件内部、按 `rowExtent` 组装吸附物理（组合不复制）；档位列表/加油记录卡两处垂直滚动共用，统计图表横向未接入（动态列宽/底边让位/初始停最右，原因见该处注释）、但其滚动条样式常量（`scrollbarThickness`/`scrollbarRadius`）引用本组件同一份——全局调滚动条手感只改 scroll_window.dart 一处；新的卡内定行滚动列表走它，不要手抄 Scrollbar+SizedBox+ListView 三明治）。
  - `shared/shell_actions.dart`：保存动作层（ADR 0007）——每个业务变更一个具名函数，内部固定编排"写库 → 失效 provider 家族 →（需要时）组合通知协调器"；只收 `WidgetRef`，确认框/pop/toast 留在调用方，异常穿透（例外：`deleteCar`/`restoreBackupFromFile`/`clearAllData` 收 `BuildContext`，确认框在动作层内弹——破坏性操作，确认文案属 UI 决策；后两者返回 `Future<bool>` 区分完成/用户取消，ADR 0007 修订节）。新增保存路径进动作层加函数，不要在 UI 里手排失效序列。编辑表单 sheet 的 pop/toast 反馈薄壳归表单运行时 `form_sheet.dart`（ADR 0016），动作层不变。
- `lib/core/theme/lunio_tokens.dart`、`lib/core/theme/lunio_theme.dart`：全局视觉 token 和 ThemeData。做全局视觉调整优先改这里。语义三色的浅色值是 ADR 0019 对比度档（绿 #15803d / 黄 #b45309 / 红 #dc2626；深色维持亮档、六个 soft 底不动），改这三个值必须同步两个 iOS 扩展常量副本：`LunioWidgetsExtension/MaintenanceOverviewWidget.swift`（`LunioStatusColor`）与 `ParkingCountdownExtension/ParkingCountdownLiveActivity.swift`（`ParkingThemeColors.danger`）；该同步义务由契约测试 `test/core/semantic_color_contract_test.dart` 守卫（纯 Dart 文本解析两侧源文件逐值比对，任一侧漂移跑常规 `flutter test` 即红灯，失败文案指明两侧路径与色值）——改完直接跑测试确认，不再只靠本条文字提醒。
- `DESIGN.md`：设计 token 与产品 UI 原则。改视觉、颜色、间距、反馈模式时要同步检查，必要时同步更新。

## 目录职责

- `lib/domain/entities/`：领域实体，保持纯 Dart 数据结构与基础校验。
- `lib/domain/rules/`：业务规则，例如保养进度、记录校验、当前应用车辆回退规则。优先把可测试的业务判断放这里。
- `lib/domain/errors/lunio_error.dart`：表单提交路径的业务错误类型（`LunioErrorException` + kind 枚举）。Repository 抛它、`friendlyError` 按类型翻译，不要靠异常文本猜（错误文案在 throw 点书写）。
- `lib/data/database/app_database.dart`：Drift 表结构与数据库连接，当前 `schemaVersion` 为 6（v3→v4 建 `diagnostics_probes`，ADR 0021；v4→v5 加最后读数三列；v5→v6 加 `cars.total_tank_capacity_liters` 与检测点 `car_id`/`refresh_interval_seconds`/`header`，唯一键改 `{carId, catalogKey}` 并重建表、存量归第一辆车；ADR 0021 修订节/0022/0023；迁移链纪律：`createTable` 永远建当前形态的表，建表分支与加列分支必须互斥 else-if，v5→v6 同时收敛重复建表分支）。
- `lib/data/database/app_database.g.dart`：Drift 生成文件。改表结构后用 build_runner 生成，不要手写。
- `lib/data/repositories/`：数据层按域拆分的仓库家族（共享行↔实体↔Companion 编解码在 `entity_row_codec.dart`，一张表的字段清单全库只有一份）：
  - `lunio_repository.dart`：主仓库——车辆/保养项目/保养记录核心域的事务与校验（应用车辆回退统一走 AppliedCarRules）；
  - `built_in_catalog_repository.dart`：车型目录与默认模板两张内置表 + 首启 bootstrap 幂等对账；
  - `fuel_repository.dart`：加油预测设置表 + 加油记录表（ADR 0015 应付/实付模型）+ 油价缓存/手填油价（临时偏好经偏好门面原语存取）；
  - `diagnostics_repository.dart`：车辆诊断检测点表（每车一套，挂 carId，ADR 0021 修订节）——按车列表/CRUD（内置可编辑、不可删；自定义可增改删）+ 每车内置三条种子幂等补齐（新增车辆经 `createCar` 动作收尾播种；bootstrap 按车补缺失、不纠偏用户编辑）+ 最后读数写点 `saveProbeReading`（只 UPDATE `last_value`/`last_percent`/`last_reading_at` 三列、不盖同步章；「无数据」不写不覆盖；行不存在静默跳过）；列表 provider `diagnosticsProbesProvider` 是按车 family，走"写点直失效"模型（不 watch 任何纪元，同停车倒计时先例），机制测试 `test/features/diagnostics_probes_provider_test.dart`；
  - `backup_repository.dart`：备份导出/恢复/清空数据（恢复与手工录入共用同一份 Companion 字段清单）。
- `lib/data/preferences/app_preferences.dart`：偏好门面（`LunioPreferences`）——全部偏好 key 常量、编解码与 typed 读写的唯一出口，新偏好进这里加 typed 方法，不要在调用方拼 key 字符串。停车倒计时偏好与提醒抑制 key 前缀也登记在此。
- `lib/data/backup/backup_codec.dart`：`schemaVersion: 5` JSON 备份契约编码/解码（接受 v1–v4 兼容读——缺 `itemCosts` 等于项目费用全空、缺 `fuelRecords` 等于无加油记录、缺 `diagnosticsProbes` 等于无自定义检测点，ADR 0010/0014/0021；其余版本直接拒绝；v3 的 fuelRecords 条目按 ADR 0015 应付/实付模型解码，满箱段旧结构条目解码即拒；v4 的 diagnosticsProbes 段只含自定义项、条目不带自身 id/catalogKey；v5 增 `cars.totalTankCapacityLiters` 与检测点条目 `carId`/`refreshIntervalSeconds`/`header`（v4 无 carId 归第一辆车），内置三条不进备份、恢复后按车 bootstrap 重建；**检测点最后读数不进备份**（导出 payload 显式剥掉读数三列，编码条目不写这些字段，恢复后从零积累）。
- `lib/core/date/`：`LocalDate`、可手动覆盖的应用日期上下文与「生效今天」零点调度纯函数（`midnight.dart` 的 `untilNextMidnight`；`effectiveTodayProvider` 自刷新用，ADR 0025）。
- `lib/core/format/clock.dart`：HH:mm:ss 时刻格式化 + `formatReadingTime` 读数时刻（今天 HH:mm:ss、非今天 M/d HH:mm:ss，now 注入可单测）（通知服务与停车倒计时共用；core 不反向依赖 features）。
- `lib/core/platform/native_channel.dart`：五个原生桥共用的通道降级守卫（`guardedChannelCall`）——PlatformException/MissingPluginException → 哨兵值（false/null）的翻译与 debugPrint 日志的唯一出口；各桥只声明通道与参数，不要手写 try/catch，新桥一律走它；四个桥的 Dart 侧契约测试在 `test/core/native_*_test.dart`（锁 method 名/参数键/异常翻译，新契约测试参照 native_live_activities_test）。
- `lib/core/platform/native_files.dart`：原生文件保存/选择桥接。
- `lib/core/platform/native_live_activities.dart`：停车倒计时 iOS 实时活动（灵动岛/锁屏卡片）的原生桥（ADR 0012）。Swift 执行体在 `ios/Runner/ParkingCountdownActivityController.swift`，卡片 UI 在 Widget Extension target `ios/ParkingCountdownExtension/`，通道经 SceneDelegate 挂 `lunio/native_live_activities`；启停/对账编排挂通知协调器。零更新渲染（系统自动走时），iOS 16.2 以下或系统关实时活动静默降级；本机模拟器构建不可用，外观只能真机验收。
- `lib/core/platform/native_widgets.dart`：保养提醒桌面小组件（iOS WidgetKit）的快照通道桥（ADR 0013）。扩展 target `ios/LunioWidgetsExtension/`，契约/存取在共享 Swift 文件 `LunioWidgetSnapshotStore.swift`（显式编进 Runner 与扩展两个 target），通道经 SceneDelegate 挂 `lunio/native_widgets`；数据经 App Group `group.com.example.lunio`；非 iOS 平台方法自禁用。
- `lib/core/notifications/lunio_notification_service.dart`：系统通知、保养提醒、里程更新提醒和停车倒计时通知。普通可实例化类（生产用 `LunioNotificationService.instance` 单例），经 `lunioNotificationServiceProvider` 装配，测试逐用例覆盖新实例。
- `lib/core/platform/native_notification_settings.dart`：原生通知设置跳转桥接。
- `test/domain/`：领域规则测试。
- `test/core/`：core 层测试（五个原生桥的 Dart 侧契约 native_files / native_live_activities / native_notification_settings / native_system_ui / native_widgets、id/ 雪花 id 生成器、notifications/ 通知服务、semantic_color_contract 语义三色跨端副本守卫——见上文 lunio_tokens 条目）。
- `test/data/`：数据库、Repository、备份测试，按域拆分（database_test=核心 CRUD/仓库校验、catalog_bootstrap_test=车型目录与默认模板、backup_restore_test=备份导出恢复清空）。
- `test/widget/`：主 UI 交互测试，按页面域拆分（app_shell / reminders / parking / records / vehicles / maintenance_items / settings / fuel）。
- `test/helpers/widget_app.dart`：widget 测试共享夹具（pumpApp、TestRepositories 装配/播种门面——含 insertCarForTest 裸插替身与 seedCarAndItem/saveItem 种子、通知/原生通道 mock、造数函数）与两个交互惯用语：`gotoTab`（底部导航切换=断言存在+点击+settle，「加油」tab 条件存在需先种子开关）/ `drainToastTimer`（冲 toast 定时器防 pending timer，时长经 modal_feedback 导出的 `statusOverlayVisibleDuration` 编译期绑定）。
- `test/helpers/builders.dart`：测试数据 builder 层（defaultCar / defaultOilItem / defaultRecord / defaultFuelRecord + testSync）——四个核心实体「最小合法数据」唯一出口；默认值只取既有测试的高频事实、不发明数据，备份载荷里带 id 的行重建继续走实体构造器。
- `docs/code-review-report.md`：代码审查未修条目台账（未修 R9/R17/R30/R36；编号沿用原 R1-R38 报告，已修历史见 git）。
- `docs/iteration-plan.md`：迭代跟进总账（已排队事项与未排期产品方向，每条含来源与验收口径，维护规则见该文件第 2 节）——完成或新增事项时同步更新其状态。
- `docs/operations-manual.md`：UI 操作 ↔ 代码对照手册（改流程须同步维护）。
- `docs/migration/current-database-schema.md`：当前数据库结构事实（升级策略见 `docs/adr/0005`）。

## 数据与契约注意点

- 产品/文档版本、车型目录 asset `schemaVersion` 当前为 1；数据库 `schemaVersion` 为 6（v5→v6 加 `cars.total_tank_capacity_liters` 与检测点 `car_id`/`refresh_interval_seconds`/`header`，唯一键改 `{carId, catalogKey}` 并重建表；ADR 0021 修订节/0022/0023）、备份 JSON `schemaVersion` 为 5，两者的加油记录结构按 ADR 0015 的应付/实付模型定义——含满箱段旧结构加油条目的 v3 库与新代码不兼容，必须卸载重装；含满箱段旧结构加油条目的 v3 备份恢复被拒（例外详情见 ADR 0015 与 `docs/migration/current-database-schema.md`）。数据库升级策略（ADR 0005）：纯增量变更（新增表/列）写 `onUpgrade` 增量迁移、存量数据保留，破坏性变更才删库重建；改 Drift 表结构必须把 `schemaVersion` +1 并补对应迁移分支（迁移链纪律：建表分支与加列分支必须互斥 else-if）。备份解码接受 v1–v4 兼容读（纯增量缺失按空处理）+ v5，其余版本直接拒绝。
- 加油记录（ADR 0015）：五项输入=日期（上限今天）/油品（默认 92#）/单价/应付金额/实付金额（选填），容积=应付÷单价由实体算好落库**预留**（页面不展示，与油箱容积无关）；统计口径=实付优先、没填取应付（`FuelRecord.effectiveCostCents` 唯一实现点）。`fuel_records` 表**故意不设** {carId, date} 唯一约束（同车同日多箱合法，没有"同日查重"），保存也不联动车辆当前里程——保养记录是车辆里程的唯一写源。这两条规则只属于加油记录，别套用保养记录的直觉。
- 不要随意改 Drift 表字段、唯一约束、偏好 key 或备份 JSON 字段语义；如果必须改，要同步考虑版本号、测试和文档。
- 保养记录项目费用（ADR 0010）：费用三列挂在记录-项目关联表行上（材料/工时/项目费用，单位分可空）；单个项目以项目费用为准、单条记录以总费用为准；不一致（项目费用≠材料+工时、总费用≠合计）是合法数据，红字黄三角纯提示、不拦截保存，读取方不做读时修正。**数据不变量**：材料/工时任一有值 ⇒ 项目费用必有值，由记录-项目关联行写入 seam（`entity_row_codec.dart` 的 `maintenanceRecordItemCompanion`，内置 `RecordRules.normalizeItemCost`）单点补齐，三条写路径（手工录入/编辑重建/恢复备份）天然继承，不要再在上游重复调用 normalize。
- 重要偏好 key 包括 `appliedCarId`、`developerModeEnabled`、`manualDateEnabled`、`manualDate`、`themeMode`、`systemNotificationsEnabled`、`inAppNotificationsEnabled`、`maintenanceDueRepeat`、`parkingCountdown`、`fuelPredictionEnabled`、`fuelProvince`（默认湖北）、`fuelGrade`、`fuelPriceCache`、`fuelManualPrices`（后两个是临时数据，不进备份）、`diagnosticsEnabled`、`lastObdDeviceId`（诊断开关进开发者门控与关开发者模式连带；设备标识 = 票 07 设备记忆，扫描点选连接成功即写、进页直连按它）。不要把展示文案当作稳定标识。（没有 `maintenanceDueEnabled` 开关：保养到期提醒是产品核心能力，不提供关闭入口（审查报告 R5）；老库残留的该 key 无人读取，无害。）
- 删除车辆、恢复备份、切换当前应用车辆都涉及事务和 provider 失效，优先沿用主仓库（`LunioRepository`）与 `providers.dart` 里的现有模式。读偏好/写偏好走 `LunioPreferences` typed 方法。
- 默认车辆模型和默认保养项目通过 Repository bootstrap 写入，避免在 UI 层重复拼业务数据。
- 停车倒计时是临时偏好状态，落在 `app_preferences.parkingCountdown`，不进入 JSON 备份。保存、结束、关闭系统通知、清空数据和恢复备份都要同步考虑通知清理。
- 停车倒计时在 iOS 16.2+ 有实时活动（Live Activity：锁屏卡片 + 灵动岛 + 通知中心顶部，ADR 0012）：Widget Extension target `ParkingCountdownExtension` 与 Attributes 共享文件（`ParkingCountdownAttributes.swift`）同时编进 Runner 与扩展两个 target，改动活动数据形态要两侧同步；编排（保存→启、清除/清空→撤、删车/恢复备份/通知总开关→不动、冷启/回前台对账三态）挂在通知协调器，不要再在 UI 层碰通道。本机模拟器构建不可用（运行时/SDK 错配），实时活动外观与灵动岛动画只能真机验收。
- 保养提醒桌面小组件（iOS 16.2+，ADR 0013）：Widget Extension target `LunioWidgetsExtension`；快照 JSON（`schemaVersion: 1`，含 14 天预生成窗口的逐日条目）由 `reminders/widget_snapshot.dart` 组装、经 `WidgetSnapshotController`（监听数据上游，AppShell 挂载）自动重写——数据写点不需要也不能单独通知它；小组件只渲染快照不做计算，点击经 `widgetURL`（`lunio:///reminders`，scheme 注册在 Runner Info.plist，ADR 0013）深链落提醒页——go_router 只匹配 path，URL 必须三斜杠形态，双斜杠 host 吃掉路径会匹配失败。快照存取契约在共享 Swift 文件 `LunioWidgetSnapshotStore.swift`（编进 Runner 与扩展两个 target）；App Group 标识 `group.com.example.lunio` 跟 bundle id 走，改 bundle id 时两个 entitlements 与 `appGroupId` 常量要一起改。改快照 JSON 契约要 `widgetSnapshotSchemaVersion` +1 并同步 Swift 侧模型。

## UI 与交互约定

- 主交互按 shell 子目录拆分；改 UI 前先从 `app_shell.dart` 定位入口，再读 `reminders/`、`records/`、`profile/` 或 `shared/` 的相关局部代码，避免跨区域重构。
- 安全区统一由 `LunioPage` 内置 `SafeArea` 提供：tab 页的壳层也包一层、嵌套幂等；新的 pushed 子页用了 `LunioPage` 就天生有安全区，不要再自己包。
- 视觉改动优先走 `LunioTokens` 和 `buildLunioTheme`，不要在页面里散落新的硬编码颜色。
- 改全局视觉、产品原则或 token 时，同步检查 `DESIGN.md`。
- 瞬时成功反馈使用页面内容区内的轻量 toast 风格；不要轻易改回系统底部 `SnackBar`，也不要贴近系统状态栏。
- 车辆/保养类 UI 偏好紧凑、直接、少重复入口。能整行点击就不要再加冗余编辑图标。
- 日期选择器和底部 sheet 要注意纵向空间，优先原地切换内容，避免把下方内容挤出视野。
- 主题切换后要保持当前路由稳定，并在偏好写入和 provider 失效后再显示反馈。
- 停车倒计时位于提醒页当前车辆卡片和保养提醒列表之间；倒计时进行中入口禁用，状态颜色复用保养提醒的 normal/warning/danger 语义。
- Android 通知行为与 iOS 不完全相同：停车倒计时有 ongoing chronometer 通知和到点 alarm 通知，回归时要分别验证调度和取消。

## 注释约定

- 本仓库注释面向 Java Web 背景读者，使用中文详细注释（用户明确要求，优先级高于"少写注释"的通用习惯）。
- 文件头：`//` 注释块，说明职责、在 App 中的位置、与 Java 概念的类比。
- 类与公开方法：`///` 文档注释，说明职责、参数、返回值、副作用（写库、失效 provider、调度通知）。
- 关键业务逻辑加行内注释；纯 UI 布局代码（间距/颜色等）不逐行注释。
- 文件头不要用 `///`（会触发 dangling_library_doc_comments 告警）。
- 已知问题在注释中以"⚠"标注并引用报告编号（编号沿用原 R1-R38 报告，未修条目见 `docs/code-review-report.md` 台账）；修复问题时同步删掉对应标注。

## 文档维护义务

- 改动 UI 流程、数据写点、通知行为或 Provider 依赖关系时，必须同步维护 `docs/operations-manual.md` 对应章节（维护规则见该手册第 8 节）。
- 修复 `docs/code-review-report.md` 中记录的问题后，把对应条目标记为已修复并注明日期。
- 完成或新增 `docs/iteration-plan.md` 中的迭代事项时，同步更新该文档的状态与分组（勾选注明日期，规则见其第 2 节）。
- 视觉/token 改动同步 `DESIGN.md`；数据库结构改动同步 `docs/migration/current-database-schema.md`；新业务词汇或架构决定同步 `GLOSSARY.md`（词汇表）与 `docs/adr/`（决定记录）。

## 常用命令

```bash
flutter analyze
flutter test
flutter build ios --simulator
dart run build_runner build
```

验证优先级：

- Dart/Flutter 代码改动：先跑 `flutter analyze`。
- 领域规则改动：跑相关 `test/domain/*_test.dart`。
- 数据库、Repository、备份改动：跑相关 `test/data/*_test.dart`。
- UI 交互改动：跑相关 widget test；必要时补充手动启动验证。
- Drift 表结构改动：先运行 `dart run build_runner build` 并检查 `app_database.g.dart`，再顺序跑分析和测试。

这个仓库里测试或生成任务可能受 Flutter startup lock / native asset generation / codesign 临时文件影响，避免同时并行跑多个 Flutter/Dart 生成或测试命令。推荐顺序是 `dart run build_runner build`（仅表结构改动需要）→ `flutter analyze` → 定向 `flutter test ...` → 全量 `flutter test`。

## 架构改进流水线（arch-pipeline）

- 本仓项目版工作流 `.zcode/workflows/arch-pipeline.dwf.ts` 已同步为全局通用版（8 参数），默认参数即本仓口径：flutter analyze + 全量 flutter test 两层门禁、逐候选提交推送，一般无需传参；在本仓按名字运行命中本仓版（同名遮蔽全局版）。
- 全局版（`~/.zcode/workflows/arch-pipeline.dwf.ts`）是通用模板：更新后需同步本仓项目版（TypeScript 代码保持逐字节一致，仅元数据与头注释按本仓定制）。
- 运行：对话里说「用 arch-pipeline 跑一轮架构改进（试跑）」；断点续跑传 resumeDir=.scratch/arch-<MMDD>（现存 .scratch/arch-0928 五张真票可直接续）；图文运行手册在 `.scratch/arch-pipeline-workflow.html`。

## Agent skills

### Issue tracker

Issues live as local markdown under `.scratch/<feature-slug>/`（本地 markdown，无远端 tracker）. See `docs/agents/issue-tracker.md`.

### Triage labels

默认五角色词汇（needs-triage / needs-info / ready-for-agent / ready-for-human / wontfix）. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context：根目录 `GLOSSARY.md` + `docs/adr/`. See `docs/agents/domain.md`.
