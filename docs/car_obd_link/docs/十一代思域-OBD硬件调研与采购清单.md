# 十一代思域 2022 款（中国）OBD 硬件调研与采购清单

调研日期：2026 年 11 月 8 日。目标车型：东风本田第十一代思域，2022 款，中国大陆销售，含 240TURBO 三厢汽油版与 e:HEV 两厢混动版。本轮只调研硬件，不设计 App，未做实车验证。

<hr style="border:0;border-top:1px solid #888;margin:10px 0 18px;">

## 结论

**就这台车而言，插 OBD 硬件无法达成最初的两个目标。** 三个决定性事实：

1. **四轮胎压数值在这辆车上不存在。** 东风本田 2022 款思域用户手册原文：「本车上的胎压监测系统并不直接测量每个轮胎的胎压，而是在您驾驶时监测并比较每个车轮和轮胎的滚动半径和旋转特性」。这是间接式 TPMS，只有欠压报警与校准，没有压力传感器，也没有压力数值。任何 OBD 适配器、增强诊断包或 CAN 嗅探都读不到。
2. **剩余油量不在默认 OBD 寻址上。** OBDb 的 2022 年款实车响应数据记录：`7E0.012F:FLI` 为 unsupported，但 `DA10` 与 `DB33`（29-bit 扩展寻址）下的 `012F:FLI` 为 supported。通用 App 默认发 11-bit `0x7DF`，会返回 `NO DATA`。
3. **智导互联的油量与远程控车走另一条链路。** 车端 TCU / T-Box 读车身 CAN，经内置 SIM 蜂窝网络上云，手机 App 从云端取数据。OBD 口是网关后的标准化只读诊断窗口，与这条链路无关。

此外，东风本田 2022 款思域手册有一条与本项目直接相关的警告：「加装改装的电气设备有可能对车端通讯产生影响，导致远程启动空调等 APP 控车功能失效」。插适配器后必须复测原厂远控功能。

**因此：油量已经由智导互联免费提供，胎压只能靠加装传感器。OBD 硬件的增量价值只剩本地标准诊断数据（转速、水温、负荷、故障码、VIN）与低延迟读取。这个项目的目标需要重新确认。**

> 2026 年 11 月 8 日补充：用户已放弃胎压需求。油量通过 OBD 口可以拿到，方案见第 9 节。

<br>

## 1. 需求重估

| 数据项 | 智导互联 | OBD 口 | 说明 |
|---|---|---|---|
| 剩余油量 / 可续航里程 | 支持 | 条件支持 | OBD 需设 29-bit 扩展寻址；智导互联走云端，不受距离限制 |
| 四轮胎压数值 | 不支持 | **不支持** | 全系间接式 TPMS，车上无该数据 |
| 车门、灯、后备箱、空调状态 | 支持 | 不支持 | 厂商私有 CAN 信号 |
| 远程开空调、锁车、解锁 | 支持 | **不支持** | 需蜂窝上行、云端与车厂鉴权；标准 OBD 是只读窗口 |
| 转速、车速、水温、负荷、故障码、VIN | 不支持 | 支持 | Mode 01 / 03 / 09 标准 PID |
| 车辆位置、行程记录、驾驶报告 | 支持 | 不支持 | 云端服务 |

一个容易出现的认知偏差：把「整车 CAN 上有这个数据」等同于「OBD 诊断接口开放这个数据」。T-Box 是整车 CAN 的一等节点，能读私有报文并上云；OBD 口经网关隔离，只提供立法排放诊断服务。两者物理位置、协议栈、权限都不同。

<br>

## 2. 车型技术档案

### 2.1 TPMS：间接式，官方一手证据

东风本田 2022 思域三厢汽油版《用户手册》「胎压监测系统」章节原文：

> 本车上的胎压监测系统并不直接测量每个轮胎的胎压，而是在您驾驶时监测并比较每个车轮和轮胎的滚动半径和旋转特性，来确定一个或多个轮胎是否明显充气不足。

同页还写明：低速行驶时系统不监测；充气过足时报警灯不点亮；调整胎压、轮胎换位、更换轮胎后「必须进行胎压监测系统校准」；校准需以 40–100 km/h 累积行驶约 30 分钟。e:HEV 两厢混动版手册措辞一致。官方配置表列的是「TPMS 胎压预警系统」，不是胎压显示。

来源：[东风本田 2022 思域三厢汽油版用户手册](https://www.dongfeng-honda.com/car/civic/manual/2022/42T20C100/html/6791c0d46ae9.html)、[2022 思域两厢混动版用户手册](https://www.dongfeng-honda.com/car/civic/manual/2022/42T50C000/hybrid/html/b9c49ecfee9e.html)、[快速指南](https://www.dongfeng-honda.com/car/civic/manual/2022/42T20C100/html/4b445105bba1.html)

**配置差异：未发现。** 汽油版与混动版手册措辞一致，配置表全系为报警型。个别英文 SEO 站称高配改直接式，与厂方手册冲突，不予采信。

### 2.2 排放协议与 29-bit 扩展寻址

- 法定排放诊断：`ISO 15765-4 CAN`，pin 6 / 14，11-bit 500 kbit/s。
- 本田在同平台上大量使用 **29-bit 扩展寻址**：功能请求 `0x18DB33F1`，物理请求 `0x18DA10F1`，响应 `0x18DAF110`。这是本田车系长期特征，社区实测记录可追溯至 2016 年。
- 直接后果：默认 11-bit `0x7DF` 的通用 OBD 请求在这台车上可能拿不到应答，包括标准 PID `2F`。
- ELM327 侧必须先把协议切到 29-bit：`ATSP 7`（`ISO 15765-4 CAN 29-bit 500 kbit/s`）。随后设头 `ATSH DB 33 F1`（优先级字节 `ATCP 18` 为默认，通常可省），或四字节写法 `ATSH 18 DB 33 F1`；物理寻址用 `ATSH DA 10 F1`。STN 芯片另可用 `STPX` 直接发 29-bit 帧。只设 `ATSH` 而不切协议时，请求仍按 11-bit 发出，会返回 `NO DATA`。

来源：[ELM327 官方数据手册 p.38（Setting the Headers）](https://www.manualslib.com/manual/3455132/Elm-Elm327.html?page=38)、[Autosport Labs 论坛 29-bit Honda 实测帖](https://forum.autosportlabs.com/viewtopic.php?t=4671)、[OBDb Honda Civic signalset](https://raw.githubusercontent.com/OBDb/Honda-Civic/main/signalsets/v3/default.json)

**未确认**：中国大陆 2022 款专属的排放协议书面确认；上述 29-bit 结论部分来自同代平台与海外实测数据，需实车验证。

### 2.3 剩余油量的实车响应数据

OBDb 仓库 `tests/test_cases/2022/command_support.yaml`（`model_year: 2022`，**未标注市场**）：

| 命令 | 头 | 状态 |
|---|---|---|
| `7E0.012F:FLI` | 11-bit 物理寻址 | **unsupported** |
| `012F:FLI` | `DA10` | supported |
| `DB33.012F:FLI` | 29-bit 功能寻址 | supported |
| `DA60.60.227029:CIVIC_FLV` | 29-bit 私有 DID | supported |
| `DA10.10.222516:CIVIC_FLI_INPUT` | 带 `f=2015-;-2015` 年份过滤 | unsupported（老款专用） |

同一文件中**没有任何 supported 的胎压 / TPMS 信号**；`DA26`（signalset 中标为 tpms ECU）的命令均为 unsupported。OBDb 车型汇总页对 2012–2026 年款标注 `Tire pressures: No data`。

**判断**：通用 App 只发 11-bit 请求时读不到油量。要读必须让工具使用 29-bit 头，或用本田私有 DID `DA60 22 7029`。这一点决定了硬件验收步骤（见第 7 节）。

**未确认**：OBDb 数据以北美车为主，中国大陆 2022 款 240TURBO / e:HEV 是否完全一致，须实车验证。

来源：[OBDb 2022 command_support.yaml](https://raw.githubusercontent.com/OBDb/Honda-Civic/main/tests/test_cases/2022/command_support.yaml)、[OBDb / Pelican Civic 车型页](https://pelican.clutch.engineering/cars/honda/civic/)

### 2.4 网关隔离

2022 Civic 专业安装线路表把 OBD pin 6 / 14 标为 `HS CAN 3 / DIAG-CAN`，B-CAN 另接 BCM；十一代思域车主论坛亦有「OBD2 口在网关另一侧，无法直接访问原始 F-CAN / B-CAN」的实测讨论。本田维修手册（第十代 FC/FK 架构）明确 F-CAN 与 B-CAN 在仪表控制模块（网关）互联，并存在独立 CAN Gateway 模块。

**影响**：即使买支持原始 CAN 监听的硬件，从 OBD 口也看不到主干车身报文。私有 CAN 逆向这条路的收益有限。

### 2.5 opendbc 覆盖

`commaai/opendbc` 已收录第十一代思域：PR [#620「2022 Honda Civic DBC」](https://github.com/commaai/opendbc/pull/620) 于 2022 年 6 月 14 日合并，文件 `honda_civic_ex_2022_can_generated.dbc`。该 DBC 含 `WHEEL_SPEEDS`（四轮轮速，节点 VSA，正是间接式 TPMS 的依据）、`TRIP_FUEL_CONSUMED`（行程累计耗油量，不是油箱液位）、`ENGINE_DATA`、`POWERTRAIN_DATA` 等，**不含 fuel level 信号，不含 tire pressure 信号**。openpilot 的 `docs/CARS.md` 把 `Civic 2022-26`（Bosch B）与第十代分开列出，并注明以北美市场为准。

注意：这是 openpilot 所需的 ADAS / 动力总成信号子集，不是全车信号全集。

<br>

## 3. 智导互联的链路边界

### 3.1 系统名称与架构

- 车机 / 车联网系统：**Honda CONNECT 3.0（智导互联）**，第十一代思域是首款搭载车型（本田中国 2021 年 9 月 24 日发布稿）。
- 手机端 App：**智导互联**（东风本田）。
- 架构：车身 CAN → 车端 **TCU / T-Box** → 内置 SIM 蜂窝网络 → 云端 TSP → 手机 App。官方手册要求「车联网卡实名认证」，并写明「所有功能均在移动数据网络连接前提下才可正常使用」。4.0 手册更直白：「系统内置 SIM 卡，使用中国联通物联网实现网络连接」。
- 官方功能清单（车况中心）：剩余油量、可续航里程、空调开关状态、引擎 / 车门锁 / 后备箱 / 灯光状态；远程控制含空调、除霜、落锁、开锁，且「远程控制无距离限制」。**清单中没有胎压项**，与间接式 TPMS 一致。

来源：[Honda 中国 2021-09-24 发布稿](https://www.honda.com.cn/news/20210924.html)、[Honda 中国 2021-03-22 发布稿](https://www.honda.com.cn/news/20210322.html)、[东风本田 2022 思域 Honda CONNECT 3.0 手册](https://www.dongfeng-honda.com/car/civic/manual/2022/42T51C000/hybrid/html/9c596bb6f78b.html)、[智导互联隐私政策](https://agreement.hynex.com.cn:16001/privacy.html)

**未确认**：官方手册写的是「剩余油量」，未写「百分比」。App 界面是否以百分比呈现，未找到可引用的官方截图。本田未公开该油量值来自哪条车身 CAN 报文。

### 3.2 与 OBD 硬件无关的功能

| 功能 | 判定 | 依据 |
|---|---|---|
| 剩余油量 / 续航 / 车门灯光状态 | OBD 硬件不能复现 | 数据由 T-Box 从车身私有 CAN 取到后上云；OBD 口只读标准诊断 |
| 远程开空调 / 锁车 / 解锁 | OBD 硬件不能复现 | 标准 OBD 是只读 Mode 01–09；控制类写入属 UDS 且受安全网关鉴权；BLE 无蜂窝上行与车厂账号鉴权 |
| 标准 Mode 01 实时数据 | OBD 硬件可提供 | 智导互联不提供这一组数据 |

### 3.3 官方改装警告（必须先看）

东风本田 2022 款思域手册「系统更新条款和条件」原文：

> 加装改装的电气设备有可能对车端通讯产生影响，导致远程启动空调等 APP 控车功能失效。

同章另有「请勿分解、改造本系统装置」。长期插着 OBD 适配器后，必须复测智导互联的远程控车是否仍然正常。这是本项目最容易被忽略的成本。

来源：[东风本田 2022 思域手册（系统更新条款和条件）](https://www.dongfeng-honda.com/car/civic/manual/2022/42T40C000/html/7eb536fef13d.html)

### 3.4 云端 API 现状

- **未找到**面向中国「智导互联 / Honda CONNECT 3.0」的官方公开 API 或开发者平台。
- 已核实的非官方逆向项目：`pymyhondaplus`、`myhondaplus-homeassistant`（**Europe only**，README 明确不兼容亚洲 Honda Connect）、`ha-hondalink`（北美 HondaLink）。都不是中国智导互联。
- 这类项目共性风险：非官方接口随时变更、连续登录失败会锁账号、远控指令依赖 TCU 在线。

**判断**：不要以「逆向智导互联云端」作为替代方案。它既无现成实现，也影响原厂账号与服务条款。

<br>

## 4. 硬件候选与采购清单

### 4.1 BLE OBD 适配器对比

| 型号 | 射频 | 协议 / 关键能力 | 公开 GATT | 参考价 | 国内可得 |
|---|---|---|---|---|---|
| **OBDLink CX** | BLE 5.1，官方明示无 Classic | `ISO 15765-4`；`ISO 11898 raw CAN`；完整 STN 命令集（`STM` / `STMA` / `STPX`） | **官方公开** `FFF0` / notify `FFF1` / write `FFF2` | $79.95 ≈ ¥537，到手估 ¥600–800 | 无官方旗舰店，海淘 / 代购 |
| **Vgate iCar Pro 2S** | 双模（BT3.0 Classic + BLE） | `ISO 15765-4 CAN 11bit 500K`；工作 34 mA / 休眠 3 mA | 未公开，需 nRF Connect 实扫 | $45.99 ≈ ¥309；国内报价 ¥205–343（未确认） | 淘宝 / 京东 Vgate 店，易购 |
| **Vgate iCar Pro BT4.0** | BLE 4.0 | `ISO 15765-4 CAN 11bit 500K` | 第三方库记录 `FFE0` / `FFE1` | $33.99 ≈ ¥228 | 易购 |
| **Vgate vLinker MC+** | BLE 4.0 双模 | `ISO 15765-4` + `ISO 11898 raw CAN`；休眠 3 mA | 未确认 | $66.99 ≈ ¥450 | 官方商城 / 代购 |
| **Veepeak OBDCheck BLE+** | BLE + Classic 双模 | `ISO 15765-4`；官方 FAQ 给出 Honda CAN 车型的 Car Scanner 连接配置 | 第三方库记录 `FFF0` / `FFF1` / `FFF2` | $39.87–41.99 ≈ ¥268–282 | 海淘 |
| 不推荐：OBDLink MX+ | Classic + MFi，非 BLE | 全协议 + MS-CAN / SW-CAN | — | $139.95 | iOS 自研 App 用不了 |
| 不推荐：BlueDriver | 专有 | 只配自家 App | 不开放 | $99.95 | 第三方 / 自研 App 用不了 |
| 不推荐：Carista EVO | 官方未明写 BLE | Honda 支持说明自相矛盾 | 未确认 | £59.50 ≈ ¥536 | 订阅制，高级功能另付费 |

价格为 2026 年 11 月 8 日前后公开报价折算（1 USD ≈ 6.7168 CNY），海淘运费与关税未计；国内电商实际成交价**未确认**。

**关于「同时带 WiFi 和蓝牙」**：Vgate iCar 系列是 WiFi / BT3.0 / BLE4.0 三个独立 SKU，不是一台设备双射频。买错 SKU 是本项目最常见的采购事故。

### 4.2 买前 / 到货核对清单

| # | 核对项 | 判定标准 |
|---|---|---|
| 1 | 无线类型 | 必须书面确认 **BLE / Bluetooth Low Energy / BT4.0 / 2S**。要求机身标签实拍：BLE 版标 `BLE` / `4.0` / `LE`，Classic 版标 `BT3.0` |
| 2 | iOS 连接行为 | 必须「**不在 iOS 系统蓝牙设置里配对，只在 App 内扫描连接**」。卖家只给 Android「配对码 1234」说明的，就是 Classic SPP 版，iOS 连不上 |
| 3 | 协议与固件 | 确认支持 `ISO 15765-4 CAN 11-bit 500 kbit/s`；索要固件版本；确认「协议不符 / 连不上 iOS 可无损退换」 |
| 4 | 29-bit 能力 | 确认能设 `ATSH` / `ATCP` 或 STN `STPX`。这台车读油量需要 29-bit 扩展寻址 |
| 5 | 退换窗口 | 到货后 7 天内完成第 7 节验收，保留退换权 |

### 4.3 推荐采购组合

| 档位 | 清单 | 用途 | 约价 |
|---|---|---|---|
| **最小验证套装** | OBDLink CX + Car Scanner 免费版 | 验证 iPhone ↔ BLE 链路、VIN、标准 PID、29-bit 下的 `012F` 油量 | ≈ ¥537 |
| 预算替代 | Vgate iCar Pro 2S + Car Scanner 免费版 | 同上，但需自扫 GATT UUID，29-bit 支持度需实测 | ≈ ¥309 |
| **胎压数值方案** | 原厂纯正用品 TPMS（见第 5 节）或 BLE 广播型外置传感器 ×4 | 四轮压力与温度 | ≈ ¥80–372 |
| 可选抓包件 | MeatPi WiCAN / WiCAN PRO + 桌面 SavvyCAN | 原始 CAN 采集与 DBC 逆向 | ≈ ¥282–598 |
| 可选配件 | 带独立物理开关的 OBD 一分二 / 延长线 | 长期停放断电，保留 4S 诊断口 | ≈ ¥30–87 |

**如果只买一件先验证：OBDLink CX。** 理由：厂商公开完整 GATT UUID、明确无 Classic、休眠 < 2 mA、带完整 STN 抓包命令，自研 App 阶段省掉协议逆向。若已下单的是 Vgate 2S，也可以继续，但要接受自扫 UUID 与 29-bit 支持度未确认。

**不推荐采购**：Honda / Acura 增强诊断包。OBD Fusion 官方增强品牌列表不含 Honda；Car Scanner 的 Honda 条目是连接配置而非增强 PID 包；BlueDriver 的 Honda 增强仅限北美且闭源。这台车也根本没有胎压数值可读。把预算花在增强包上没有收益。

### 4.4 原始 CAN 抓包硬件的边界

OBDLink CX 的 `STM` / `STMA` / `STCMM` / `STPX` 足以被动监听 **OBD 口可见总线**，但有三条限制：

1. CX 只引出 HS-CAN（pin 6 / 14）与 ISO / KWP（pin 7 / 15），无 MS-CAN / SW-CAN；而本车 OBD 口是网关后的 DIAG-CAN。
2. BLE MTU 最大 247 字节且不支持 Queued Writes，长报文需自行分片；500 kbit 满载总线上 `STM` / `STMA` 会缓冲溢出丢帧。
3. iOS 没有 USB CAN 路径。panda 以 USB 为主、WiFi 支持已弃用，不适合 iOS；SavvyCAN 只有桌面版。

若确需抓包，用 WiCAN 走 WiFi TCP 接桌面 SavvyCAN，iOS 侧只做 BLE 参数读取。

<br>

## 5. 胎压数值的唯一路径

### 5.1 原厂纯正用品（目标是「看到数值」）

东风本田 / 广汽本田纯正用品目录列出两款：

| 型号 | 名称 | 功能 |
|---|---|---|
| `08E35-HA1-Y00` | **TPMS 数字显示胎压监测系统** | 4 轮实时精准监测胎压 + 温度，原车一体化安装，东风 Honda 全系车型适用，3 年 / 10 万公里同车质保 |
| `08E35-HA1-Y00A` | **胎压云监控** | 通用品，云端同步 |

来源：[本田汽车用品官方产品目录（东风本田通用品）](https://www.honda-access.cn/WDHAC/31)、[澎湃新闻：第十一代思域 HATCHBACK 上市发布稿（纯正用品清单）](https://thepaper.cn/newsDetail_forward_21256226)

淘宝导购页标价约 ¥372（**低可信度，须向 4S 店核实**）。这条路的优势是原厂适配、带质保、不影响整车。劣势是数据在其自有屏 / 自有云，**未确认**是否开放给自研 iOS App。发布稿把「手机蓝牙一键连接」写在胎压云监控条目上，协议开放性未确认。

### 5.2 第三方 BLE 广播型传感器（目标是「自研 App 读数」）

必须区分两类后装产品：

| | A. 433 / 315 MHz 传感器 + 接收器 + 蓝牙转发 | B. 传感器直接 BLE 广播 |
|---|---|---|
| iOS 连的是 | 接收器（GATT 多为私有协议） | 不需要连接，扫描广播即可 |
| 自研 App | 基本不可行 | 可行，`CBAdvertisementDataManufacturerDataKey` 直读 |
| 典型坑 | 商品页写「蓝牙 5.0」，规格写 `Frequency: 315 MHz` | 需确认「传感器自身 BLE 广播、无需接收器」 |

已公开逆向的两套互不兼容格式：

| 来源项目 | Service | Manufacturer Data | 字段 |
|---|---|---|---|
| [andi38/TPMS](https://github.com/andi38/TPMS)（配 SYTPMS App 的 `BR` 传感器） | `0x27A5` | 7 字节 | `SS BB TT PPPP CCCC`：状态 / 电池 0.1V / 温度 ℃ / 绝对压力 0.1 psi / 校验 |
| [ra6070/BLE-TPMS](https://github.com/ra6070/BLE-TPMS)（ZEEPIN / TP630 类） | `0xFBB0` | 18 字节 | 轮位、传感器地址、压力 kPa 小端 uint32 ÷1000、温度 ℃ 小端 uint32 ÷100、电池、报警 |

`ra6070/iOS-BLE-Tire-Logger` 给出了 iOS 上用 `CBCentralManager.scanForPeripherals` 直接读广播的示例。

iOS 侧限制：只能扫描广播、不能 `connect()`；传感器间歇广播，会漏包，需缓存去重；iOS 不暴露 BLE MAC 地址，必须用广播载荷里的传感器 ID / 轮位字节做身份；后台扫描受限。协议是社区逆向公开，不是厂商 SDK，同型号不同批次固件可能变化。**买前必须让卖家给广播原始数据，或用 nRF Connect 实测。**

国内四只外置气门嘴套装约 ¥80–250（导购页区间，低可信度）。

<br>

## 6. 供电与安装风险

- **OBD pin 16 是常电**（SAE J1962），熄火锁车仍有电。J1962 没有点火 / ACC 引脚，适配器只能靠电压跌落与总线活动推断熄火；推断失败就一直醒着。
- **官方手册未标注 DLC 专用保险丝**。2022 Civic 保险丝表中相关常电回路有 `BACK UP 15A`（机舱 #19）、`BACKUP FI-ECU 10A`（#24）、`BACKUP2 30A`，但哪一路给 pin 16 供电**未确认**，以保险丝盒盖标签为准。
- **休眠电流**（厂商 / 第三方口径，冲突处并列）：

| 型号 | 工作 | 休眠 | 来源可信度 |
|---|---|---|---|
| OBDLink CX | 55 mA | < 2 mA（开发者页）/ < 1 mA（产品页） | 官方，两处冲突，按 < 2 mA 保守 |
| Vgate iCar Pro 2S | 34 mA | 3 mA | 厂商说明书 |
| Veepeak OBDCheck BLE+ | 35–45 mA | 15 mA | 官方手册，两处工作电流冲突 |
| 廉价 ELM327 | — | 20–50 mA，个别实测近 150 mA | 第三方实测 |

Veepeak 官方建议：可连续插几天，停车超过 1 周务必拔掉。

- **一分二 / 延长线**：线缆本身无功耗，但并联设备可能阻止整车 ECU 休眠，长线接触电阻会让适配器的电压判据偏移，两个设备争总线主控会导致响应超时。优先单设备直插；确需一分二，选带独立物理开关的型号。
- **OBD 口位置**：驾驶员侧仪表台下方、脚部空间，靠近引擎盖释放拉手（第三方定位资料）。东风本田官方手册对应页**未确认**，以实车手册为准。

<br>

## 7. 到货后的硬件验收步骤

本步骤只验硬件，不写 App。建议 7 天内完成，保留退换权。

1. 核对机身标签与包装 SKU，确认是 BLE 版，不是 BT3.0 / WiFi 版。
2. 打开 iPhone 蓝牙，**不要**在「设置 > 蓝牙」里配对；用 nRF Connect 或 LightBlue 扫描，确认能发现设备并读出 GATT 服务与 characteristic。
3. 用 Car Scanner 免费版连接，选择 Honda 的 `OBD-II/EOBD + AT/CVT (CAN)` 配置。读取 VIN、转速、水温、车速。记录是否成功。
4. 在 AT 终端发 `0100` 记录能力位图，再发 `012F`。返回 `NO DATA` 属预期结果（11-bit 默认头）。
5. 先发 `ATSP 7` 把协议切到 29-bit 500 kbit/s，再发 `ATSH DB 33 F1`，重发 `012F`。记录是否返回 `41 2F xx`。油量按 `xx × 100 / 255` 换算为百分比。这一步决定油量能否从 OBD 口读到。若仍返回 `NO DATA`，先发 `ATCRA`（不带参数）复位接收过滤，再用 `ATH1` 开报文头确认响应 ID 是否为 `18 DA F1 xx`。
6. 熄火、锁车、静置 30 分钟以上。观察适配器是否进入休眠，次日检查车辆能否正常启动。
7. **用智导互联实测远程开空调、锁车、解锁各一次**。确认官方警告中的「加装改装电气设备导致 APP 控车功能失效」没有发生。若失效，拔掉适配器复测。

第 5 步与第 7 步是本车型独有的关键验收项。

<br>

## 8. 待确认

1. 已下单或准备购买的具体型号与 SKU。若是 BT3.0 / WiFi 版，iOS 自研 App 用不了，建议退换。
2. 项目目标已收窄为「拿到油量」。第 9 节给出三条路径，其中 OBD 口路径需实车验证。
3. 胎压已确认不需要。第 5 节的原厂 TPMS 配件与 BLE 传感器方案仅作存档，不再纳入采购。
4. 是否接受长期插着适配器带来的馈电风险与原厂远控受影响的风险。
5. 车辆是 240TURBO 三厢还是 e:HEV 两厢。两者 TPMS 手册措辞一致，但 29-bit 诊断响应可能不同。

<br>

## 9. 油量获取方案（胎压需求放弃后补充）

**结论：可以拿到。** 优先走 OBD 口的 29-bit 扩展寻址，读标准 PID `2F`。这条路径不需要自研 App，也不需要自定义 PID。

### 9.1 路径 A：OBD 口，29-bit 扩展寻址（推荐）

依据：OBDb 的 `model_year: 2022` 实车响应数据中，`7E0.012F:FLI` 为 unsupported，`DB33.012F:FLI` 与 `DA10` 下的 `012F:FLI` 为 supported。`DB33` 即 29-bit 功能寻址 `0x18DB33F1`。

ELM327 完整命令序列，每行以 `\r` 结尾：

```text
ATZ
ATE0
ATL0
ATSP 7
ATSH DB 33 F1
012F
```

`ATSP 7` 是 `ISO 15765-4 CAN 29-bit 500 kbit/s`。ELM327 在该协议下的默认功能头就是 `0x18DB33F1`，因此 `ATSH` 一行可省。`ATCP 18` 是默认值，同样可省。期望响应 `41 2F xx`，油量百分比按 `xx × 100 / 255` 计算。

若返回 `NO DATA`，先发 `ATCRA`（不带参数）复位接收过滤，再用 `ATH1` 开报文头，确认响应 ID 是否为 `18 DA F1 xx`。物理寻址备选 `ATSH DA 10 F1`。ELM327 手册明确：过滤器或掩码设置不当会让标准 OBD 请求也被忽略，此时用 `AT CRA`、`AT D` 或 `AT WS` 恢复默认。

**免代码做法**：Car Scanner 免费版在「高级设置 > ECU 协议」中，把协议从默认的 `6) ISO 15765-4 CAN (11 bit ID, 500 Kbaud)` 改为 `7) ISO 15765-4 CAN (29 bit ID, 500 Kbaud)`，再打开内置的 Fuel Level 传感器。若内置传感器仍无数据，用「自定义 PID」：Command 填 `012F`，Header 留空，Formula 填 `A*100/255`，单位填 `%`。Car Scanner 会跳过报文头、数据长度、模式标记与 PID 字节，`A` 即第一个数据字节。自定义 PID 也支持在「Start diagnostic command」里放完整 ELM327 命令，可用 `;`、`,` 或 `\` 分隔。

**前提与局限**：

- 车辆电源必须处于 ON 或发动机运行。熄火后 OBD 口不提供实时数据。
- 只返回 0–100% 的油箱液位百分比，不返回升数。
- OBDb 数据未标注市场，以北美车为主。中国大陆 2022 款 240TURBO / e:HEV 的响应**未验证**。
- 该值是 ECU 诊断响应；智导互联显示的是 T-Box 上云的缓存值。两者数据源与刷新时机不同，不得假设相等。
- 东风本田手册的加装改装警告仍然适用。插硬件后必须复测智导互联远控。

来源：[OBDb 2022 command_support.yaml](https://raw.githubusercontent.com/OBDb/Honda-Civic/main/tests/test_cases/2022/command_support.yaml)、[ELM327 官方手册 p.38：29-bit 头](https://www.manualslib.com/manual/3455132/Elm-Elm327.html?page=38)、[ELM327 官方手册 p.41：接收过滤](https://www.manualslib.com/manual/3455132/Elm-Elm327.html?page=41)、[Car Scanner 自定义 PID 文档](https://www.carscanner.info/?p=235)、[WiCAN 文档：Car Scanner 的 ECU 协议 7](https://meatpihq.github.io/wican-fw/car_scanner/usage/)

### 9.2 路径 B：OBD 口，本田私有 DID（备选）

仅在路径 A 失败时使用。OBDb 记录 `DA60.60.227029:CIVIC_FLV` 为 supported；signalset 另有 `DA10` 下含 Fuel Level 的未解码 raw 命令 `222623` 与 `222678`。这些参数的缩放公式未公开，需抓包逆向出字节位置与系数，工作量明显高于路径 A。

`DA10.10.222516:CIVIC_FLI_INPUT` 带 `filter: from 2015, to 2015`，2022 年款不支持，不得使用。

### 9.3 路径 C：智导互联云端（不推荐程序化读取）

人眼读数：智导互联 App 的「车况中心」直接提供剩余油量与可续航里程。无需额外硬件，不受距离限制。

程序化读取：需自行逆向中国 Honda CONNECT 3.0 的私有云端 API。已核实的非官方项目（`pymyhondaplus`、`myhondaplus-homeassistant`、`ha-hondalink`）分别面向欧洲 My Honda+ 与北美 HondaLink，中国智导互联**未找到**公开实现。风险包括账号锁定、接口随时变更、服务条款约束。Smartcar 商业 API 只覆盖北美与欧洲。

### 9.4 选型建议

| 目标 | 建议路径 |
|---|---|
| 自研 iOS App 在车旁读油量 | 路径 A |
| 只想随时看到油量 | 智导互联 App，不买硬件 |
| 想远程、熄火后仍读油量，且要程序化 | 路径 C，成本高、稳定性差 |
| 路径 A 在中国版不响应 | 路径 B，需抓包逆向私有 DID |

<br>

## 主要来源

- [东风本田 2022 思域三厢汽油版用户手册：胎压监测系统](https://www.dongfeng-honda.com/car/civic/manual/2022/42T20C100/html/6791c0d46ae9.html)
- [东风本田 2022 思域两厢混动版用户手册：胎压监测系统](https://www.dongfeng-honda.com/car/civic/manual/2022/42T50C000/hybrid/html/b9c49ecfee9e.html)
- [东风本田 2022 思域手册：系统更新条款和条件（改装警告）](https://www.dongfeng-honda.com/car/civic/manual/2022/42T40C000/html/7eb536fef13d.html)
- [东风本田 2022 思域 Honda CONNECT 3.0 手册：车况中心与远程控制](https://www.dongfeng-honda.com/car/civic/manual/2022/42T51C000/hybrid/html/9c596bb6f78b.html)
- [Honda 中国：第十一代思域首搭 Honda CONNECT 3.0](https://www.honda.com.cn/news/20210924.html)
- [OBDb Honda Civic 2022 command_support.yaml](https://raw.githubusercontent.com/OBDb/Honda-Civic/main/tests/test_cases/2022/command_support.yaml)
- [OBDb / Pelican Civic 车型参数页](https://pelican.clutch.engineering/cars/honda/civic/)
- [ELM327 官方数据手册 p.38：29-bit CAN 头设置](https://www.manualslib.com/manual/3455132/Elm-Elm327.html?page=38)
- [commaai/opendbc PR #620：2022 Honda Civic DBC](https://github.com/commaai/opendbc/pull/620)
- [OBDLink CX 开发者页：GATT UUID、MTU、电流](https://support.obdlink.com/support/solutions/articles/43000746707-obdlink-cx-adapter-notes)
- [本田汽车用品官方产品目录：TPMS 数字显示 / 胎压云监控](https://www.honda-access.cn/WDHAC/31)
- [澎湃新闻：第十一代思域 HATCHBACK 纯正用品清单](https://thepaper.cn/newsDetail_forward_21256226)
- [ra6070/BLE-TPMS](https://github.com/ra6070/BLE-TPMS)、[andi38/TPMS](https://github.com/andi38/TPMS)
- [OBD Fusion 官方增强诊断品牌列表](https://www.obdsoftware.net/software/obdfusion)
