# OBD 硬件与 iOS App 读取车辆数据调研报告

调研日期：2026 年 11 月 7 日。范围：需求前提核查、数据可得性、iOS 连接约束、硬件选型、软件架构、可复用的 GitHub 项目、实施路径。本阶段只做调研，未编写 App 代码，未做实车验证。

<hr style="border:0;border-top:1px solid #888;margin:10px 0 18px;">

## 结论

**在不知道具体车型的前提下，无法承诺「通过 OBD 适配器 + iOS App 读到剩余油量和胎压」。** 决定性变量是车型、年款与销售市场，不是 App 的实现方式。

三个前提需要纠正：

1. **胎压不属于标准 OBD-II 数据。** 立法 OBD 只覆盖排放相关系统。胎压数值只能来自厂商扩展诊断或私有 CAN 报文，必须逐车型适配。部分车型用间接式 TPMS，车上根本不存在压力数值。
2. **剩余油量在标准里有定义，但不是强制项。** PID `2F` 返回油箱液位百分比，不是升数；实车支持情况和稳定性都需逐车验证。
3. **iOS 不能连接普通「蓝牙 ELM327」。** 这类设备走经典蓝牙 SPP，iOS 侧需要 MFi 认证。自研 App 必须选 BLE GATT 设备，或走 WiFi。「同时带 WiFi 和蓝牙」既无必要，也基本没有对应的单台量产型号。

**建议调整实施顺序：先花低成本在目标车上做数据探测，再决定 App 架构。当前直接开始写 App，缺少验收标准。**

<br>

## 1. 需求前提核查

### 1.1 立法 OBD 的数据边界

`ISO 15765-4` 的标题是 `Requirements for emissions-related systems`（排放相关系统要求）。它是 DoCAN 传输层，不定义 PID；PID 与服务由 `SAE J1979` / `ISO 15031-5` 定义。欧盟法规 (EU) 2017/1151 附录 6.5.3 要求「标准化、无限制访问」的对象是**排放相关诊断系统**，不是整车所有数据。附录 6.5.3.2 明确引用 `ISO 15031-5 ... Emissions-related diagnostic services` 或 `SAE J1979`。

这条边界解释了后面的不对称：油量与燃油蒸发排放监测相关，所以进入了标准 PID 表；胎压属于底盘安全系统，与排放无关，从未纳入。

### 1.2 剩余油量：有 PID，但不保证

| 项目 | 内容 |
|---|---|
| 定义 | Service 01，PID `2F`，`Fuel Tank Level Input` |
| 响应 | 1 字节 A |
| 公式 | `A × 100 / 255` |
| 单位 | %（相对油箱标称容量），不是升 |
| 强制性 | 非强制支持，法规只要求支持一个 PID 子集 |
| 自检命令 | `0100` 查能力位图；`012F` 返回 `NO DATA` 即不支持 |

实车支持率没有权威的车队级普查。可查到的口径互相有出入：OBD 软件厂商 OBD Experts FAQ 给出「约 85% 支持、约 15% 不支持」，属厂商自有数据，**未独立核实**；RealDash 开发者的表述更保守，称「many vehicles do not send this information to OBD2 port via SAE-Standard PID」。丰田 FT86 平台车主记录标准 PID「fluctuates a lot and isn't very useful」，改用厂商自定义 PID。

因此，油量只能作为「按车型验证后可用」的数据项，不能作为产品承诺。

### 1.3 胎压：标准中没有该数据

标准 Mode 01 的 PID 全表中没有胎压或 TPMS 条目。Service 02 沿用 Mode 01 的同一 PID 表；Service 03 / 07 / 0A 只返回故障码；Service 09 只返回 VIN、校准 ID 等车辆信息。Teltonika 官方支持的答复原文：

> TPMS is not a standard OBD-II PID — Tire pressure is not part of the standard OBD-II diagnostic parameter set (SAE J1979). It's typically transmitted on the vehicle's internal CAN bus as a manufacturer-specific parameter.

OBDLink 官方知识库把 TPMS 归入 enhanced diagnostics，说明其 DTC 与参数都是 OEM-specific。`python-OBD` 的 `commands.py` 里有 `FUEL_LEVEL`，对 `tire` / `tyre` / `TPMS` 检索命中 0 条，可作为交叉印证。

**法规层面的常见误读**：GB 26149-2017《乘用车轮胎气压监测系统的性能要求和试验方法》于 2017 年 10 月 14 日发布、2018 年 1 月 1 日实施；2020 年 1 月 1 日起所有在产乘用车强制安装。但标准前言写明强制内容是欠压报警、故障报警和开机检查信号装置等**安全相关功能**，不是压力数值显示，更不是对外数据接口。「法规要求装 TPMS」与「App 能读到压力值」之间没有标准层面的桥梁。

**间接式 TPMS 是另一个硬约束**。NHTSA 评估报告的结论是 `Pressure displays are only possible with direct TPMS`。间接式通过比较轮速差估算欠压，没有压力数值，也不能定位具体轮胎。公开资料记载大众与奥迪部分在产车型曾使用间接式。GB 26149 允许间接式合规，因此仅凭「车辆有胎压监测功能」无法推断能读到数值。

### 1.4 数据可得性矩阵

| 数据项 | 标准 OBD | 前提条件 | 可靠性 |
|---|---|---|---|
| 转速、车速、水温、负荷、进气温度 | Mode 01 标准 PID | 绝大多数车支持 | 高 |
| 故障码、VIN、校准 ID | Mode 03 / 09 | 支持多帧响应 | 高 |
| 剩余油量 | PID `2F`，非强制 | 能力位图声明支持 | 中，仅百分比，可能抖动 |
| 四轮胎压 | **无标准 PID** | 厂商 DID 或私有 CAN + DBC | 低，逐车型，间接式车型无数值 |
| 四轮胎温 | **无标准 PID** | 同上 | 低 |
| 纯电车 SOC / 续航 | **无标准 PID** | 厂商私有 | 低 |

### 1.5 车型差异的实测证据

| 车系 | 公开记录 |
|---|---|
| 大众 / 斯柯达（VAG） | 油量需 Mode 22 DID `0x2206`，header `714` / 响应 `77E`，可返回升数；OBD 口经网关隔离，直接嗅探看不到主干 CAN；仪表 CAN 帧中的胎压只有报警灯位 |
| 通用 GM | 油量 DID `221155` / `2212C5` 在 P10 / P12 PCM 返回否定响应，在 2005 Yukon LM7 才有值；同品牌不同 ECU 即不同 |
| 现代 Ioniq 5 | header `7A0`，`0x22C00B` 一次返回四轮压力与温度（Teltonika 官方回复） |
| 马自达 MX-5 ND | 胎压 DID `2A05`–`2A08`，欧版返回 `NO DATA`，美版可用；同车型不同市场也有差异 |
| 丰田 FT86 平台 | 标准 `2F` 抖动，改用 header `0x7C0` / PID `0x2129` / `A × 0.5`（升） |
| 比亚迪（MOBD 车型库） | 多个车型标注「胎压不在检测范围，剩余油量高端车型可以支持」 |

结论：胎压与可靠油量的实现成本，几乎全部在**车型适配**，不在 iOS 端。

<br>

## 2. iOS 连接约束

### 2.1 蓝牙 SPP 的 MFi 陷阱

`CoreBluetooth` 是 BLE / GATT 抽象。iOS 13 增加的 `Core Bluetooth for BR/EDR` 是在经典蓝牙链路上跑 GATT，不是 RFCOMM / SPP；HC-05 / HC-06 这类 SPP 虚拟串口仍不能通过 `CoreBluetooth` 访问。Apple DTS 工程师在开发者论坛的原文：

> Bluetooth Low Energy (BLE) devices are not governed by MFi... If you want to transfer arbitrary data using Classic Bluetooth (BR/EDR), then you will need to sign up for the MFi program.

Apple MFi FAQ 也把「仅使用 BLE 的配件」列为**不属于** MFi Program 的类别。普通 ELM327 蓝牙版走 SPP（UUID `00001101-0000-1000-8000-00805F9B34FB`，PIN `1234` / `0000`），因此**自研 iOS App 不能购买 SPP 蓝牙 ELM327**。

判断方法：要求在 App 内连接、不在「设置 > 蓝牙」配对的是 BLE；要求 PIN `1234` 配对的是 Classic SPP。

### 2.2 BLE 与 WiFi 的对比

| 维度 | BLE GATT | WiFi（适配器作 AP） |
|---|---|---|
| iOS 框架 | `CoreBluetooth` | `Network.framework` / TCP socket |
| MFi | 免 MFi | 免 MFi |
| 典型参数 | 自定义 UART service，OBDLink CX 官方为 `FFF0` / notify `FFF1` / write `FFF2` | SSID `WiFiOBD` / `V-LINK`，TCP `192.168.0.10:35000` |
| 占用 WiFi | 否 | 是，iPhone 无法同时连其他 WiFi |
| 后台模式 | `bluetooth-central` | **无 TCP 长连接常驻后台模式**，锁屏后 socket 被挂起 |
| 额外权限 | 蓝牙权限 | iOS 14+ `NSLocalNetworkUsageDescription` 本地网络授权 |
| 配网 | 无需 | `NEHotspotConfigurationManager`（`joinOnce = true`），只需打开 Hotspot Configuration capability |

`NEHotspotHelper` 需要 Apple 特殊授权。Apple TN3111 原文说明该 API 只适用于上网热点集成，存在技术与商务限制，不得用于配件配网；用它给 OBD 配件配网有拒审风险，且该 API 在 iOS 26 起已废弃。

**结论：BLE 是面向 iOS 的主链路，WiFi 只适合作为调试和仿真通道。**

### 2.3 「同时带 WiFi 和蓝牙」的选型误区

**未确认**存在单台同时具备 WiFi 与 BLE 的量产型号。检索到的产品实际分三类：

1. BLE + Classic 双模蓝牙，无 WiFi（Veepeak OBDCheck BLE+、Vgate iCar Pro BT4.0、Carista）。
2. WiFi + Classic SPP 双板克隆，蓝牙部分只供 Android，iOS 仍只能走 WiFi。
3. 同一产品线下 WiFi / BT3.0 / BLE4.0 是三个独立 SKU。Vgate 官方 iCar 手册原文：`All iCar OBD II adapter have Wi-Fi and Bluetooth (BT3.0/BLE4.0) models`。

电商标题「ELM327 WiFi + Bluetooth 4.0」的规格选择器多为 `WIFI` / `BT3.0` / `BT4.0` 三选一，不是一台设备双射频。

<br>

## 3. 硬件选型

### 3.1 推荐型号

| 型号 | 射频 | 关键能力 | 参考价格 | 适用阶段 |
|---|---|---|---|---|
| **Vgate iCar Pro BT4.0 / 2S** | BLE 4.0 | 五种法定协议，休眠约 3 mA，国内易购 | 约 ¥90–150 | **验证阶段首选** |
| **OBDLink CX** | BLE 5.1，官方明示无 Classic | STN 芯片，`ISO 11898 raw CAN`，官方公开 GATT UART 协议与开发文档 | $79.95 | **开发阶段首选** |
| Veepeak OBDCheck BLE+ | BT 4.0 双模（Classic + LE） | ELM327 v2.2，不支持 MS-CAN / SW-CAN | $41.99 | 备选 |
| ELM327 WiFi 克隆 | WiFi AP | 便宜，便于接 TCP 仿真器 | 约 ¥25–50 | 仅调试 / 仿真 |
| OBDLink MX+ | Classic v3.0 + MFi | 全协议 + MS-CAN / SW-CAN | $139.95 | 不适合自研 iOS App |
| BlueDriver LSB2 | 未确认，官方称 Apple 认证 | 厂商明确不兼容第三方 App | $99.95 | 不适合自研 App |

价格为 2026 年 11 月前后公开报价与海外定价折算，波动较大；国内实际到手价**未确认**。OBDLink CX 不支持 J1850 PWM / VPW、MS-CAN、SW-CAN，选购前须与目标车协议核对。

### 3.2 芯片与固件：为什么它决定能否读到胎压

胎压需要读厂商私有数据，硬件必须能监听原始 CAN 帧或发送自定义 DID 请求。

| 方案 | 原始 CAN 能力 | 限制 |
|---|---|---|
| STN1110 / STN2120（OBDLink 采用） | `STM` / `STMA` / `ATMA` 监听，`STCMM` 设监控模式，`ATCF` / `ATCM` 配过滤器，`STPX` 发原始帧；完全兼容 ELM327 AT 命令集并扩展 ST 命令集 | 需学习 ST 命令集 |
| ELM327 v1.5 克隆（PIC18F25K80） | 有 `ATMA` | Linux 内核 `can327` 驱动文档记录：不支持 `AT CSM`、不支持 RTR 帧、无全双工、UART 缓冲溢出会 `BUFFER FULL` 丢帧 |
| ELM327 v2.1 廉价克隆 | 基本不可靠 | 常砍掉 J1850、缺 AT 命令、多帧 VIN 损坏、无过压保护 |

Elm Electronics 原厂版本线里没有 v1.5；市面「v1.5 / v2.1」都是克隆固件版本号。

### 3.3 胎压的替代硬件路径

如果目标车是间接式 TPMS，或私有 CAN 逆向成本过高，**加装一套 BLE 广播型独立 TPMS 传感器**（外置气门嘴或内置）可以绕开 OBD：iOS 直接用 `CoreBluetooth` 收广播，拿到四轮压力与温度。开源项目 `andi38/TPMS` 记录了一类传感器的广播格式：短名 `BR`、service `0x27a5`、7 字节 manufacturer data `SSBBTTPPPPCCCC`（状态 / 电池 / 温度 / 压力 / 校验）。

限制：市售成品的协议多为私有，自研 App 需选开放协议的模块或自行逆向；这套传感器与原车 TPMS 是两套独立系统；传感器电池需要更换；iOS 无法直接接收 433 MHz 信号，需 ESP32 / CC1101 网关转发。

**这条路径与 OBD 适配器并不冲突**：OBD 读动力总成与油量，独立 BLE TPMS 读胎压，App 内做数据聚合。

<br>

## 4. 软件架构

按五层拆分，保证无车也能开发、换车型不改 App 主体。

| 层 | 职责 | 关键实现 |
|---|---|---|
| 1. 传输层 | 字节流收发 | 定义 `OBDTransport` 协议，三个实现：BLE（`CoreBluetooth`）、TCP（WiFi / 仿真器）、Mock |
| 2. 帧层 | 分帧与初始化 | 以 `>` 为 prompt 分帧；AT 状态机 `ATZ → ATE0 → ATH1 → ATL0 → ATSP0 → ATDPN` |
| 3. 协议层 | 标准诊断 | 能力位图探测（`0100` / `0120` / `0140`）、按优先级轮询 PID、`41 xx` 公式解码、DTC、VIN 多帧（ISO-TP） |
| 4. 扩展层 | 厂商数据 | Mode 22 / UDS `ReadDataByIdentifier`、原始 CAN 监听、DBC 解码 |
| 5. 领域层 | 车型适配与展示 | 按 VIN 匹配车型配置（JSON + DBC）；SwiftUI 明确区分「暂无数据」与「该车型不支持」 |

三条设计约束：

- PID 与 DID 必须配置化，不得写死在 UI 里。油量是否可用、单位、换算系数都来自车型配置。
- 传输层必须可 mock。iOS Simulator 没有蓝牙，无车开发依赖仿真器。
- 只实现读操作。不得发 `04` 清码，不得随意注入 CAN 帧。

<br>

## 5. GitHub 开源项目

以下仓库经 GitHub 检索确认存在。star 与最近提交为 2026 年 11 月 7 日查询结果，采用前须复核。

### 5.1 iOS 侧可直接参考

| 仓库 | 作用 | 传输 | License | 备注 |
|---|---|---|---|---|
| [mickeyl/LTSupportAutomotive](https://github.com/mickeyl/LTSupportAutomotive) | ObjC OBD2 库 | **BLE + WiFi + USB** | MIT | 最完整：`LTOBD2AdapterELM327`、PID 命令类、ISO 15765-4 / 9141-2 / J1850 协议类、VIN 解码、BLE↔NSStream 桥。README 明确 iOS 不支持 Classic rfcomm。bugfix-only 维护态 |
| [kkonteh97/SwiftOBD2](https://github.com/kkonteh97/SwiftOBD2) + [SwiftOBD2App](https://github.com/kkonteh97/SwiftOBD2App) | Swift / SPM 库 + SwiftUI Demo | 宣称 BLE + WiFi | MIT | iOS 侧较现代的起点。README 把 BLE 列在 Roadmap，配套 App 的 Milestone 又标 BLE 已完成，**实现状态需实测** |
| [lemberg/obd2-swift-lib](https://github.com/lemberg/obd2-swift-lib) | Mode 01/02/03/04/09 PID 全表与解析 | 仅 WiFi TCP | MIT | 可复用 PID 表、`SensorDescriptorTable`、Parser、NSStream 串行调度；BLE 需自加 |
| [waruc/OBD2_BLE](https://github.com/waruc/OBD2_BLE) | Swift framework，CoreBluetooth 对接 OBD | BLE | MIT | 2017 年项目，仅参考 `CBCentralManager` 流程与 AT 初始化序列 |
| [qadanm/elmulator](https://github.com/qadanm/elmulator) | BLE + TCP ELM327 模拟器 | BLE + TCP | MIT | **无车开发首选**：JSON scenario、macOS 上真实 CoreBluetooth 外设广播 Nordic UART、`ElmulatorMockPeripheral`、iOS CI、Swift GATT 状态机 |

### 5.2 协议表与 CAN 信号定义

| 仓库 | 作用 | License | 可复用部分 |
|---|---|---|---|
| [brendan-w/python-OBD](https://github.com/brendan-w/python-OBD) | Python OBD-II 参考实现 | **GPL-2.0** | `obd/commands.py` 的 PID 定义、`obd/elm327.py` 的 AT 序列与以 `>` 分帧的读取逻辑、协议自动探测顺序。仅作规范参考，避免直接拷贝代码 |
| [EricSmekens/node-bluetooth-obd](https://github.com/EricSmekens/node-bluetooth-obd) | Node.js 蓝牙 OBD 连接器 | 元数据 NOASSERTION / 源码头 Apache-2.0 | `obdInfo.js` 的 `responsePIDS` 表：含 pid / bytes / min / max / unit / 转换函数，便于翻译成 Swift |
| [commaai/opendbc](https://github.com/commaai/opendbc) | 开源 DBC 集合 + 解析 API | MIT | 车型 CAN 信号定义。已定位到 `ford_cgea1_2_bodycan_2011.dbc` 的 `BO_ 951 TPM_Frame` / `SG_ TirePress_Frame_Press`，`generator/hyundai/hyundai_palisade_2023.dbc` 的 `BO_ 1427 TPMS11`，`mazda_rx8.dbc` 的 `SG_ FuelLevel` |
| [openvehicles/Open-Vehicle-Monitoring-System-3](https://github.com/openvehicles/Open-Vehicle-Monitoring-System-3) | OVMS3 车载监控固件 | 有 LICENSE 文件，需复核 | 标准 metrics `v.t.pressure` / `v.t.temp` / `v.t.health`、DBC 解码器、逆向工具、逐车型 vehicle module |
| [commaai/panda](https://github.com/commaai/panda) + [collin80/SavvyCAN](https://github.com/collin80/SavvyCAN) | CAN 抓包硬件固件 / 桌面 DBC 工具 | MIT | 抓包与 DBC 逆向，生成信号定义后再带进 iOS |

### 5.3 仿真与 TPMS 专项

| 仓库 | 作用 | License |
|---|---|---|
| [Ircama/ELM327-emulator](https://github.com/Ircama/ELM327-emulator) | Python 模拟器，支持 TCP `-n 35000`、多 ECU、UDS / ISO-TP、scenario | **CC BY-NC-SA 4.0，禁商用**；其蓝牙为 Classic SPP，iOS 不可用，只能走 TCP |
| [terrafirma2021/ESP32-S3-BLE-ELM327](https://github.com/terrafirma2021/ESP32-S3-BLE-ELM327) | ESP32-S3 硬件 BLE ELM327 模拟器，真射频端到端联调 | 冲突：API GPL-3.0 / README MIT，须复核 |
| [andi38/TPMS](https://github.com/andi38/TPMS) | 逆向 433 MHz 与 BLE 胎压传感器，附广播格式与 bleak / bluepy 示例 | 无 |
| [ra6070/BLE-TPMS](https://github.com/ra6070/BLE-TPMS) | ESP32 解码 BLE 胎压传感器 | MIT |
| [merbanan/rtl_433](https://github.com/merbanan/rtl_433) | ISM 频段解码器，含 TPMS 解码器 | GPL-2.0 |

**iOS 侧必须自己写**：`CoreBluetooth` BLE 传输层、以 `>` 分帧的 AT 状态机、PID 轮询调度、`41 xx` 解码、按 VIN 匹配的车型配置加载、以及胎压等私有信号的 DBC 解析。**可以直接复用**：MIT 的 `LTSupportAutomotive` / `SwiftOBD2` / `elmulator` 骨架、`python-OBD` 的 PID 表作为规范参考（注意 GPL-2.0）、`opendbc` 与 OVMS 的信号定义。

**License 提醒**：`python-OBD` 为 GPL-2.0，`Ircama/ELM327-emulator` 为 CC BY-NC-SA 4.0（禁商用），`AndrOBD` 为 GPL-3.0。产品化前须逐项复核，优先选 MIT / Apache-2.0 项目。

<br>

## 6. 实施路径

**当前不建议直接开始写 App。** 阶段 0 与阶段 1 未完成前，请求 / 响应层没有验收标准。

| 阶段 | 动作 | 交付物 |
|---|---|---|
| 0 | 确认目标车品牌、车型、年款、生产市场、燃油 / 纯电、直接式或间接式 TPMS | 车型清单 |
| 1 | 买 BLE 适配器，用现成 App（OBD Fusion / Car Scanner / Torque）在目标车上发 `0100` / `0120` / `012F`，记录响应；读不到时再抓 CAN 或探测 Mode 22 DID | **PID 支持位图与私有信号清单**，这是后续所有设计的事实基础 |
| 2 | 用 `elmulator` 或 `ELM327-emulator` TCP 模式，搭 SwiftUI + `CoreBluetooth` 骨架，实现 AT 状态机、能力探测、PID 解码、VIN | 无车可跑的 App 原型 |
| 3 | 真车联调，校准轮询频率、超时与断连重连 | 单车可用版本 |
| 4 | 按阶段 1 的结果补厂商 DID / DBC，扩展车型配置库 | 多车型支持 |

阶段 1 的成本很低（一个 BLE 适配器加一款现成 App），但能提前暴露「目标车根本不提供胎压数值」这类不可解的问题。

<br>

## 7. 风险与成本

- **主要成本在车型适配，不在 App 开发。** 同一参数在不同品牌、年款、市场的 DID、header 与缩放公式都不同，且无公开文档，部分资料来自论坛众包，可能出错。
- **网关隔离**。部分车系（如 VAG 新平台）的 OBD 口经网关隔离，看不到主干 CAN 报文，逆向路径也会受阻。
- **常电耗电**。OBD pin 16 为常电，劣质克隆长期插着有电瓶馈电风险；选带休眠的型号，并设计断连后的休眠流程。
- **安全边界**。只做读操作；`04` 清码与 CAN 帧注入会影响车辆状态。App 不得鼓励行车中交互。
- **数据合规**。车辆数据若上云，按《个人信息保护法》处理；位置与行程数据尤其敏感。
- **硬件clone风险**。v2.1 廉价克隆的多帧响应与 AT 命令不完整，联调阶段会出现难以定位的假故障。
- **iOS 后台**。若选 WiFi 路线，锁屏后 TCP 连接会被挂起，无法实现常驻采集。

<br>

## 8. 待确认

1. 目标车的品牌、车型、年款、生产市场、燃油或纯电、直接式或间接式 TPMS。
2. 是否接受「先买适配器实测，再开发 App」的顺序。
3. 若目标车读不到胎压，是否接受加装独立 BLE TPMS 传感器。
4. App 定位：单车自用，还是面向多车型的通用产品。这决定车型配置库的规模。
5. 是否计划上架 App Store。这决定 MFi、配网与后台模式的设计取舍。

<br>

## 主要来源

- [ISO 15765-4:2021 官方页](https://www.iso.org/standard/78384.html)、[欧盟 (EU) 2017/1151 附录](https://www.legislation.gov.uk/eur/2017/1151/attachment/43/2020-01-31)
- [国家标准全文公开系统：GB 26149-2017](https://openstd.samr.gov.cn/bzgk/gb/newGbInfo?hcno=BFBF3C14BF19BCD6DB781E2059436268)
- [NHTSA TPMS 评估报告：Pressure displays are only possible with direct TPMS](https://crashstats.nhtsa.dot.gov/Api/Public/ViewPublication/811681)
- [OBDLink 知识库：标准诊断与增强诊断的区别](https://obdsol.freshdesk.com/support/solutions/articles/43000713278-what-s-the-difference-between-obd-ii-standard-and-enhanced-diagnostics-)
- [Teltonika 官方支持：TPMS 不是标准 OBD-II PID](https://community.teltonika.lt/t/tpms-data-fmx003-1/20188)
- [Apple 开发者论坛：BLE devices are not governed by MFi](https://developer.apple.com/forums/thread/765687)、[MFi FAQ](https://mfi.apple.com/faqs)
- [Apple TN3111：iOS Wi-Fi API 概览](https://developer.apple.com/documentation/technotes/tn3111-ios-wifi-api-overview)、[CoreBluetooth 文档](https://developer.apple.com/documentation/corebluetooth)
- [OBDLink CX 产品页](https://www.obdlink.com/products/obdlink-cx/)、[OBDLink CX 适配器 GATT 说明](https://support.obdlink.com/support/solutions/articles/43000746707-obdlink-cx-adapter-notes)
- [Veepeak OBDCheck BLE+ 官方页](https://veepeak.com/products/obdcheck-ble-plus)、[Vgate iCar 手册](https://eu.manuals.plus/m/1303a63bfc81ebe0d5ec093aa91664290a86ae77d9c9bf3975b8a55e5ff83adb)
- [Linux 内核 can327 驱动文档（ELM327 克隆实测限制）](https://fossd.anu.edu.au/linux/v6.0/source/Documentation/networking/device_drivers/can/can327.rst)
- [python-OBD commands.py](https://github.com/brendan-w/python-OBD/blob/master/obd/commands.py)、[commaai/opendbc](https://github.com/commaai/opendbc)、[OVMS metrics 文档](https://docs.openvehicles.com/en/latest/userguide/metrics.html)
