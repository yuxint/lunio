# ADR 0020：车辆诊断 OBD 链路——flutter_blue_plus 插件与 OBDTransport 传输层抽象

日期：2026-11-12
状态：已接受

## 背景

新增开发者模式门控的「车辆诊断」工具页（GLOSSARY「车辆诊断」词条），
经 BLE 连 Vgate iCar Pro BLE 4.0（ELM327 v2.3）读取车辆实时数据。
硬件与协议已于 2026-11-12 实车验收，协议事实、GATT UUID、初始化序列
与离线日志语料全部收在 `docs/car_obd_link/`（开发依据为该目录
`docs/实测结果与自研App开发依据.md`）。

本仓既有原生集成传统是轻功能方法通道（五个 `core/platform/native_*`
桥，统一走 `guardedChannelCall` 降级守卫）。蓝牙链路与它们不同：
BLE 会话是有状态长连接（扫描、发现服务、订阅通知、分帧收发、断连），
Dart 侧需要持续字节流事件，方法通道形态承载不了。

## 关键取舍

- **flutter_blue_plus 插件 vs 自写原生通道**：自写意味着 Swift 与
  Kotlin 各一套 CoreBluetooth / Android BLE 会话状态机，复杂度量级
  远超现有轻功能桥，双端行为差异还要自己抹平。选插件：双端白送、
  社区事实标准、维护活跃。flutter_reactive_ble 曾入候选，维护历史
  波动更大，否。
- **传输层抽象 OBDTransport（BLE + Mock 双实现）**：iOS 模拟器没有
  蓝牙，BLE 链路只能真机验收；AT 状态机、分帧解析、PID 解码与全部
  页面开发挂在 Mock 实现上，测试语料用实车日志
  `docs/car_obd_link/data/IOS-Vlink.txt`。WiFi/TCP 通道（ELM327
  WiFi 克隆硬件）不做：没有硬件，不在产品路线。
- **初始化序列是连接流程的固定部分，不进指令库**：`ATZ → ATE0 →
  ATL0 → ATSP 7` 是适配器会话协议，不是用户数据；且 `ATSP 7` 必须
  显式发（实车验证：协议复位后发 PID 全部 NO DATA），不可依赖
  EEPROM 记忆。
- **不自动重连、不做后台保活**：断连恢复、熄火重连都在硬件文档
  「仍未验证」清单里，行为未标定前 v1 手动重连最诚实；后台保活是
  iOS 平台硬难题，明确不做。

## 决定

1. 依赖 `flutter_blue_plus`；诊断域新建传输层接口 `OBDTransport`，
   v1 两个实现：BLE（真机）与 Mock（模拟器/单测）。
2. 连接流程固定执行初始化序列，每条等 `>` 提示符再发下一条；命令
   以 CR（0x0D）结尾、带响应写入（CoreBluetooth
   WriteWithResponse 等价形态）。
3. 响应按 `>` 组帧缓冲（BLE 通知会分片，不能按单次通知解析）；多
   ECU 响应按请求 PID 匹配，不假设单帧。
4. 轮询一轮 = 串行按序发所有启用检测点，每条等响应或超时；轮间隔
   为常量（默认 3 秒，真机联调再定）。离开页面断开连接。

## 后果

- pubspec 新增 flutter_blue_plus（首个 BLE 插件）；iOS Info.plist
  补蓝牙权限文案，Android 补 BLUETOOTH_SCAN / BLUETOOTH_CONNECT
  权限声明。
- BLE 链路的真实验证只有真机清单一条路；Mock 与真机的行为差异（分片
  时序、断连）要真机联调回归。
- 未来若支持其他适配器（WiFi ELM327、OBDLink CX 等），走
  OBDTransport 新实现，协议层与页面不动。

## 修订节（2026-11-15，票 07 落地时补充）

- **flutter_blue_plus 2.x 许可口径**：2.x 起商业用途付费、个人/非营利
  用途免费，connect 需显式传 `License.nonprofit`。本应用单人自用，落
  在免费档；若未来商业化需购买商业授权。
- **直连 = 定向扫描窗口**（实现细化，非推翻）：iOS 按标识直连要求设
  备在系统缓存里，直接 connect 不可靠；`BleObdTransport.connect` 第
  一步按设备标识过滤扫描（`withRemoteIds`，8 秒窗口）定位设备，再
  connect（15 秒窗口，FBP 默认 35 秒收窄）。
- **mock 回退开关**：装配默认 BLE；`--dart-define=LUNIO_OBD_MOCK=true`
  整链回退票 05 语料演示 Mock——模拟器无蓝牙，视觉验收走它。
- **扫描器接缝**：设备发现单独收 `ObdScanner` 抽象（真实现
  `BleObdScanner`），扫描 sheet 经 `obdScannerProvider` 消费、测试换
  受控假扫描器——FBP 静态门面与传输层同手法隔离。
- **扫描列表不过滤设备名**（spec story 5 拍板）：`startScan` 不带名
  称/服务过滤（`continuousUpdates` 开 RSSI 持续刷新，信号强度降序），
  选中靠用户点选；识别靠名称"IOS-Vlink"与信号强度。
- **扫描列表过滤空名设备**（2026-11-15 同日反转上一条的产品口径）：
  广播名为空的设备不进列表。上条"不过滤"的本意是不按关键词/服务筛
  "哪些设备可被发现"（防误伤有自定义名的适配器）；实车反馈无名广播
  （手机/手环/周边传感器的随机地址条目）数量多且不可连，会淹没有效
  目标。过滤在扫描器数据源做（`mergeScanEntries` 纯函数：过滤空名
  + 首见定序，单一出口），真扫描器与测试替身走同一合并函数，
  sheet 只渲染收到的清单。
- **扫描列表首见定序 + ≤1Hz 刷新**（2026-11-15，实车反馈行序乱跳）：
  根因是列表每次扫描拍都按**当时 RSSI** 全量重排，而 RSSI 每拍抖
  ±3~10dBm——排序键本身在抖，重排频率又高（`continuousUpdates`
  每秒多拍），行序自然乱跳。决定：设备位置在首次发现时定死（首见
  定序），后续拍摄只更新信号数字、不重排；新设备按当下展示强度插
  入（同强度排已有行之后）；合并器 `ScanEntryCoalescer` 把发射压到
  ≤1Hz（首拍与新设备立即发，纯数字变化合并等待），定序状态按扫描
  会话（start→stop）复位——失败恢复扫描至多重排一次，接受，不为
  此增加跨会话协议。数字仍显当前值（1Hz 刷新），行序语义是"首见
  序"不是"当前强度序"；不做自动停扫与重排动画（范围控制）。
  纯函数/合并器单测在 `test/features/ble_scan_entries_test.dart`，
  widget 顺序稳定性用例在 `test/widget/diagnostics_test.dart`。
- **story 6"连接中/已选"两态的落地口径**：点选行显"连接中…"即已选行
  的连接反馈；建链成功 sheet 随即关闭（设备记忆已写），不存在独立的
  "已选但未连接"停留态，故不做第二个徽标。
- **点选流会话级失败也回填 sheet**：适配器建链成功但 AT 初始化超时
  （芯片无响应）时，cause 链没有 BLE 可辨识异常——页面按"会话级失败"
  分支同样调 `reportPickFailed` 回填行态恢复扫描，行不冻在"连接中…"。

## 修订节（2026-11-15，轮询节奏与调试）

ADR 0023 起轮询不再固定 3 秒：每个检测点按自己的
`refresh_interval_seconds`（默认 30 秒、范围 5–3600）以 1 秒拍倒计时
调度；会话新增手动刷新 `requestImmediatePoll`、调试暂停
`pausePolling`/`resumePolling` 与原始命令 `sendRawCommand`。初始化
序列、按 `>` 组帧与串行发送约定不变。
