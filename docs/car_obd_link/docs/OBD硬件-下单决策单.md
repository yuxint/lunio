# OBD 硬件下单决策单

适用：东风本田十一代思域 2022 款（中国），自研 iOS App 通过 BLE 读取油量。日期：2026 年 11 月 8 日。技术依据见 `十一代思域-OBD硬件调研与采购清单.md` 与 `OBD-iOS-App-调研报告.md`。

<hr style="border:0;border-top:1px solid #888;margin:10px 0 18px;">

## 结论

**买 Vgate iCar Pro BLE 4.0。不要买 WiFi 版，不要买 BT3.0 版，不要买标「WiFi + 蓝牙」的二合一产品。**

车辆已确认为 240TURBO 汽油版。2S 的 EV 远程唤醒、208 组 CAN 过滤器与 BLE 5.2 高吞吐都用不上，不必为此付费。BLE 4.0 的官方规格同样列 `ISO15765-4 CAN (29bit ID, 500 Kbaud)`，满足 29-bit 油量读取。

如果愿意海淘且能等到货，OBDLink CX 是开发文档更完整的替代项，见第 2 节。

三个硬条件决定这个选择：

1. iOS 只能连 BLE GATT。经典蓝牙 SPP 需要 MFi 认证，自研 App 用不了。
2. 这台车的油量必须走 29-bit CAN（`ATSP 7`）。适配器必须明确支持 `ISO 15765-4 CAN 29 bit ID 500 Kbaud`。
3. 自研 App 需要读写 BLE characteristic。厂商未公开 UUID 时，可以用 nRF Connect 扫一次。

<br>

## 1. 前提变化

智导互联未续费，云端读数不可用。上一份清单中「油量由原厂 App 免费提供」的结论作废。OBD 口现在是唯一可自研的数据源。

同时，官方手册「加装改装的电气设备有可能对车端通讯产生影响，导致远程启动空调等 APP 控车功能失效」不再构成约束，因为远控本身已不可用。馈电风险仍然存在。

**一个必须接受的差异**：OBD 读数要求车辆电源处于 ON 或发动机运行。熄火后、远程场景都读不到。这一点与智导互联不同，硬件到货前须确认符合预期。

<br>

## 2. 下单清单

| 优先级 | 物品 | 精确型号 / SKU | 渠道 | 约价 | 理由 |
|---|---|---|---|---|---|
| **主推** | BLE OBD 适配器 | `Vgate iCar Pro BLE 4.0`（商品名 `Vgate iCar Pro Ble4.0`） | Vgate 官方商城 `vgatemall.com`；国内淘宝 / 京东 Vgate 店 | 官方 $33.99 ≈ ¥228；国内约 ¥90–150（**未确认**） | 官方规格列 `ISO15765-4 CAN (29bit ID, 500 Kbaud)`；BLE，iOS App 内连接；休眠约 3 mA；不含用不上的 EV 唤醒与 208 组过滤器 |
| 可选升级 | BLE OBD 适配器 | `Vgate iCar Pro 2s Bluetooth iOS/Android/Windows` | 同上 | 官方 $37.99 | BLE 5.2 3 Mbps、EV 远程唤醒、208 组过滤器。240TURBO 汽油版用不上，见第 8.7 节 |
| **备选** | BLE OBD 适配器 | `OBDLink CX`（Model `CX101` / ASIN `B08NFLL3NT`） | 官网 `obdlink.com`、亚马逊海外购、代购 | $79.95，到手估 ¥600–800 | 唯一由厂商公开 GATT `FFF0` / `FFF1` / `FFF2` 与 iOS 接入文档；官方确认原生支持 29-bit CAN。**官网 2026-11-08 显示 Out of stock** |
| 建议配件 | 带独立开关的 OBD 一分二延长线 | 16 针 16 芯、0.5 m、物理开关 | 京东自营 / 天猫 | ¥51–76 | 长期停放物理断电，避免馈电；减少原车 OBD 口插拔磨损 |
| 可选 | ESP32-S3-DevKitC-1 N8R8 | — | 淘宝 / 京东 | ¥28–99 | 无车阶段烧 BLE ELM327 仿真固件，供真机调试 `CoreBluetooth` |

来源：[Vgate 官方商城 iCar Pro 系列 SKU](https://www.vgatemall.com/products/i-1/)、[Vgate 官方商城 iCar Pro 2S 规格（208 组过滤器、EV 唤醒）](https://vgatemall.com/products-detail/i-80/)、[Vgate iCar Pro BLE 4.0 规格与 2S 对比](https://elm327obd2.com/products/vgate-icar-pro-ble-4-0)、[OBDLink CX 产品页](https://www.obdlink.com/products/obdlink-cx/)、[OBDLink CX 开发者页](https://support.obdlink.com/support/solutions/articles/43000746707-obdlink-cx-adapter-notes)

### 不买清单

| 产品 | 排除原因 |
|---|---|
| `Vgate iCar Pro BT3.0` | Classic SPP，iOS 自研 App 连不上 |
| `Vgate iCar Pro Wi-Fi` | 占用 iPhone 唯一 WiFi；iOS 无 TCP 长连接后台模式；需本地网络授权弹窗 |
| 廉价 ELM327 WiFi 克隆（v1.5 / v2.1） | 29-bit 支持不可靠。社区记录 `ATSP 7` 下数值跳变、截断长响应、自动识别失败 |
| `BlueDriver` / `Carista EVO` | 私有协议，不向第三方 App 开放 AT 命令层 |
| 任何标「WiFi + 蓝牙」的二合一 | 多为三个独立 SKU，或蓝牙侧是 SPP；BLE 侧不跑完整 ELM327 AT 命令 |

### 为什么「蓝牙或 WiFi」不是二选一

| 维度 | BLE GATT | WiFi（适配器作 AP） |
|---|---|---|
| iOS 框架 | `CoreBluetooth` | TCP socket |
| MFi | 免 MFi | 免 MFi |
| 后台 | `bluetooth-central` 可用 | **无 TCP 长连接常驻后台模式**，锁屏后挂起 |
| 网络占用 | 不占用 | 占用唯一 WiFi，蜂窝流量代偿 |
| 配网 | App 内扫描连接 | `NEHotspotConfigurationManager`；本地网络授权弹窗 |
| 开发调试 | 需真机或 mock | TCP 易调试，适合仿真阶段 |

**开发阶段不需要买 WiFi 硬件**：用 TCP 仿真器即可搭协议层，见第 5 节。产品链路只保留 BLE。

<br>

## 3. 下单前发给卖家的核对话术

1. 请确认这一件是 **BLE / 蓝牙 4.0 或 5.x Low Energy** 版本，不是 BT3.0 经典蓝牙 SPP 版、也不是 WiFi 版？请拍外包装和机身标签实拍。
2. 标签上的完整型号是 `iCar Pro 2S`、`iCar Pro Ble4.0`、`iCar Pro BT3.0`、`iCar Pro Wi-Fi` 里的哪一个？只写「iCar Pro」三个字我就不下单。
3. iPhone 连接时，是在 App 内部扫描连接、系统「设置 > 蓝牙」列表里看不到设备吗？还是需要去系统设置里配对并输入 PIN `1234`？后者基本可判定是 SPP 版。
4. App 内扫描到的广播设备名是什么？广播的是 BLE GATT 服务吗？
5. 休眠电流是多少 mA？熄火后是否自动进入低功耗、能否被 BLE 唤醒？有没有过压保护？

Vgate 官方商城同页并列的四个商品名：`Vgate iCar Pro BT3.0`、`Vgate iCar Pro Ble4.0`、`Vgate iCar Pro Wi-Fi`、`Vgate iCar Pro 2s Bluetooth iOS/Android/Windows`。官方 WiFi 页写明连接方式三选一，不是一台设备双射频。

<br>

## 4. 29-bit 支持核实结果

| 型号 | `ATSP 7` / 29-bit 500K | GATT UUID | 判定 |
|---|---|---|---|
| OBDLink CX（STN） | **官方确认**。OBDWiz 规格列 `ISO 15765-4 (11-bit and 29-bit CAN)`；官方工程师确认 CX 原生支持 29-bit CAN ID；STN 原生预设 `STP 34`，`ATSP 7` 向后兼容 | 官方公开 `FFF0` / `FFF1` / `FFF2` | 最优，但缺货 |
| Vgate iCar Pro 2S / BT4.0 | **官方商城与手册明文列出** `ISO15765-4 CAN (29bit ID, 500 Kbaud)` | 未公开；第三方实测 `FFF0` / 写 `FFF2` / 通知 `FFF1`，同品牌不同型号可能不同 | 可行，需自扫 |
| Vgate vLinker MC+ / FD+ | 未确认。官方只写「ISO 15765-4 CAN」，未区分 11 / 29 bit | 未公开且型号间不一致 | 不推荐 |
| Veepeak OBDCheck BLE+ | 未确认 | 第三方开源库给出 `FFF0` / `FFF1` / `FFF2` | 不推荐 |
| 廉价 ELM327 WiFi 克隆 | 不可靠 | 不适用 | 排除 |
| MeatPi WiCAN PRO（WiFi 侧） | **源码级确认**：协议 7 = 29 bit / 500 kbaud，默认头正是 `0x18DB33F1` | BLE 侧 ELM327 仅 22 条命令的 Basic support | 仅适合抓包，不适合产品链路 |

依据：[DauntlessOBD 协议 ID 表（7 = ISO-15765 CAN 29-bit @ 500 kbps，注明 OBD-II on most Honda）](https://dauntlessdevices.com/support/dauntlessobd-developer-api-info/dauntlessobd-supported-protocol-ids/)、[OBDLink CX 选型表](https://support.obdlink.com/support/solutions/articles/43000713351-which-obdlink-adapter-is-right-for-me-)、[OBDWiz 规格（11-bit and 29-bit CAN）](https://www.obdlink.com/obd-apps/obdwiz-app/)、[WiCAN 固件 elm327.c](https://raw.githubusercontent.com/meatpiHQ/wican-fw/main/main/elm327.c)

<br>

## 5. 无硬件期间的开发准备

| 工具 | License | 连接模式 | 用途 |
|---|---|---|---|
| [qadanm/elmulator](https://github.com/qadanm/elmulator) | MIT | BLE + TCP | macOS 上起真实 BLE GATT 外设，供真机 iPhone 连接；含 CoreBluetooth-Mock，适合先写传输层 |
| [Ircama/ELM327-emulator](https://github.com/Ircama/ELM327-emulator) | **CC BY-NC-SA 4.0，禁商用** | TCP / serial / RFCOMM | 协议解析与场景最成熟，但不支持 BLE |
| [terrafirma2021/ESP32-S3-BLE-ELM327](https://github.com/terrafirma2021/ESP32-S3-BLE-ELM327) | **冲突**：LICENSE 为 GPL-3.0，README 写 MIT | 真实 BLE 广播 | 烧到 ESP32-S3 开发板，做端到端射频联调 |

**iOS Simulator 没有蓝牙。** 自研 App 必须用真 iPhone 调试，或用 CoreBluetooth-Mock 起 mock 层。真机调试需要 Mac 与 Xcode；Apple 免费开发者账号可以真机运行，只有上架 App Store 才需付费账号。

<br>

## 6. 到货验收命令

ELM327 序列，每行以 `\r` 结尾：

```text
ATZ
ATE0
ATL0
ATSP 7
012F
```

`ATSP 7` 下默认功能头就是 `0x18DB33F1`，`ATSH DB 33 F1` 与 `ATCP 18` 可以省。期望响应 `41 2F xx`，油量百分比按 `xx × 100 / 255` 计算。

若买的是 OBDLink CX，等价命令为 `STP 34`（STN 原生预设）；`ATSP 7` 作为向后兼容命令同样可用。

返回 `NO DATA` 时：先发 `ATCRA`（不带参数）复位接收过滤，再用 `ATH1` 开报文头，确认响应 ID 是否为 `18 DA F1 xx`。物理寻址备选 `ATSH DA 10 F1`。

验收还包括：用 nRF Connect 扫出实际 GATT service / characteristic UUID 并记录；熄火锁车静置 30 分钟后检查适配器是否休眠、次日车辆能否启动。

<br>

## 7. 未确认

1. 中国大陆 2022 款 240TURBO 的 29-bit 实车响应。OBDb 数据未标注市场，以北美车为主。
2. Vgate 具体批次对 `ATSP 7` 的实际行为，以及 iCar Pro BLE 4.0 的 GATT UUID。确认方法：nRF Connect 实扫 + 真车发命令。
3. 车型已确认：240TURBO 汽油版。e:HEV 混动版排除，2S 的 EV 唤醒与 208 组过滤器无需考虑。
4. OBDLink CX 官网补货时间、是否直邮中国、国内到手价。国内具体店铺与商品页未查到可核验页面。
5. 智导互联官方续费价。官方只公布「基础服务 5 年免费、到期后在服务商城购买」，未公布价目；非官方口径 ¥30–300 / 年，**未确认**。
6. Vgate 国内天猫 / 京东旗舰店的准确店铺名。

<br>

## 成本提醒

如果目标只是随时看到油量，续费智导互联的成本可能低于买硬件加自研 App。官方未公布续费价，非官方口径为 ¥30–300 / 年。但这条路径不提供本地数据，也不能自研。用户已明确选择自研，此处只作客观列示。

<br>

## 8. 不必要功能与精简型号

### 8.1 本需求真正的必需项

1. BLE GATT。iOS 自研 App 唯一可行的链路。
2. `ISO 15765-4 CAN 29 bit ID 500 Kbaud`（`ATSP 7`）。十一代思域读油量的硬要求。
3. 完整 ELM327 AT 命令层：`ATZ` / `ATE0` / `ATSP 7` / `012F` / `ATH1` / `ATCRA`。
4. 低休眠电流与 12V 过压保护。适配器长期插在常电 OBD 口上。

### 8.2 不必要但不单独计价的功能

| 类别 | 具体项 |
|---|---|
| 其他排放协议 | SAE J1850 PWM / VPW、ISO 9141-2、ISO 14230-4 KWP、SAE J1939、USER1 / USER2 CAN、11-bit 250K、29-bit 250K、Ford MS-CAN、GM SW-CAN |
| 诊断软件功能 | 读码、清码、I/M 就绪状态、氧传感器测试、EVAP 测试、冻结帧、Mode 06 / 09、厂商增强诊断包 |
| App 生态功能 | Torque / Car Scanner / BimmerCode / Carista 兼容、编码刷隐藏、HUD、油耗报表、驾驶行为分析、超速与疲劳提醒 |
| 平台与射频附加 | Android Classic 蓝牙双模、Windows 支持、24V 车辆支持、BLE 5.2 高吞吐、208 组 CAN 过滤器、EV / 混动远程唤醒、固件在线升级 |

**关键判断**：以上能力是 ELM327 全协议固件与配套 App 的固有组成部分。厂商按芯片与射频划分 SKU，不按功能拆分计价。砍掉这些功能不会降价，因此「找一款只有我需要的功能的量产型号」这条路不成立。真正决定价格的是芯片方案、射频类型、固件质量、休眠设计与品牌渠道。

### 8.3 真正能省钱的三个型号

| 型号 | 参考价 | 必需项 | 代价 |
|---|---|---|---|
| **Vgate iCar Pro BLE 4.0** | $33.99 ≈ ¥228；国内约 ¥90–150（**未确认**） | BLE；官方规格列 `ISO15765-4 CAN (29bit ID, 500 Kbaud)`；休眠约 3 mA | 蓝牙 4.0；无 EV / 混动远程唤醒；无 208 组 CAN 过滤器 |
| 国产 v1.5 `PIC18F25K80` BLE（Viecar 4.0 一类） | 海外 $26.58；国内约 ¥30–80（**未确认**） | 官方规格同样列 `29bit ID, 500 Kbaud`；BLE 双模下 iOS 走 LE | 克隆固件在 29-bit 下有数值跳变、截断长响应的社区记录；GATT UUID 未公开；休眠电流与过压保护常不标；易买到假 v1.5 或 v2.1 黑胶 |
| 最便宜的 ELM327 WiFi 克隆 | ¥15–50 | **不满足** | iOS 占 WiFi、无后台 TCP；29-bit 不可靠。排除 |

**车型已确认：240TURBO 汽油版**。`iCar Pro BLE 4.0` 足够，可省掉 2S 用不上的 BLE 5.2、EV 唤醒与 208 组过滤器。但官方差价只有约 $4，省的有限。

e:HEV 混动版已排除。若为混动版，2S 的 EV / 混动远程唤醒才有实际用途。

国产 v1.5 BLE 是真正的成本下探，代价是可靠性风险。到货后必须按第 6 节命令验证 `ATSP 7` 与 `012F` 的响应是否稳定，并连续观察数值有无跳变。

### 8.4 不得省的项

- BLE。iOS 硬要求。
- 29-bit 支持。车型硬要求。
- 低休眠电流与过压保护。防馈电。
- 带独立开关的 OBD 延长线。¥51–76，比更换电瓶便宜。

### 8.5 有没有「只有我需要的功能」的型号

没有量产消费品。ELM327 类适配器都是全协议固件，砍协议不省钱。要真正精简只能自研 `ESP32-S3` + CAN 收发器（BOM 约 ¥30–60），但必须自己实现 ELM327 AT 命令、ISO-TP 多帧与 29-bit 寻址。开发量远超省下的金额，不推荐。

### 8.6 产品页对照勾选清单

拿到任意一款产品页时，逐条核对：

- [ ] 无线类型写明 **BLE / Bluetooth 4.0 LE / 5.x LE**。不是 BT3.0、Classic、SPP，也不是 WiFi。
- [ ] 协议表含 `ISO15765-4 CAN (29bit ID, 500 Kbaud)`，或明确写支持 `ATSP 7`。
- [ ] 写明支持 iOS，且注明「App 内连接，无需系统蓝牙配对」。
- [ ] 芯片为 `PIC18F25K80`（v1.5）或品牌芯片。避免 v2.1 黑胶 blob。
- [ ] 标出休眠电流。≤ 3 mA 为佳。
- [ ] 有 12V 过压、反接或 load dump 保护。

来源：[Vgate iCar Pro BLE 4.0 规格与 2S 对比](https://elm327obd2.com/products/vgate-icar-pro-ble-4-0)、[Vgate iCar Pro 2S vs BLE 4.0 差异](https://blog.obdii365.com/2024/09/11/vgate-icar-pro-2s-vs-icar-pro-bluetooth-4-0/)、[Viecar 4.0 v1.5 PIC18F25K80 协议表](http://fr.chinaobd2.com/items/viecar-elm327-obd2-scanner-7183.html)、[国产 BLE 25K80 批发规格与协议表](https://www.globalsources.com/product/obd_1202531534f.htm)

<br>

### 8.7「208 组过滤器」是什么

Vgate 官方 2S 页原文：`Up to 208 sets of filters for passing, blocking, and flow control`。Amazon 官方文案补充：`to ensure more complex diagnostic needs for your hybrids or EVs`。厂商把它与 `Hybrid / Pure Electric Vehicle` 自动唤醒并列为卖点。

**技术含义**：CAN 是广播总线，所有节点都能看到所有帧。500 kbit/s 满载时每秒数千帧，而 BLE 上行带宽远小于总线吞吐。适配器必须在硬件层先筛掉无关 CAN ID，否则缓冲溢出丢帧。筛选用的是验收过滤器（acceptance filter）与掩码（mask）。

208 组指芯片能同时保存 208 条筛选规则，分三类：

| 类型 | 作用 | ELM327 / STN 对应命令 |
|---|---|---|
| pass（放行） | 只接收指定 CAN ID 的帧 | `ATCF` / `ATCM` |
| block（阻断） | 丢弃指定 CAN ID 的帧 | STN 的 `STFAB` |
| flow control（流控） | ISO-TP 多帧响应时自动回 Flow Control 帧 | `ATCFC0` / `ATCFC1`、STN 的 `STFAFC` |

标准 ELM327 只提供一组 filter 加一组 mask。ELM327 官方手册 p.41 原话：`Quite likely, you will never have to use the CM and CF commands.`

**为什么本需求用不上**：

1. 走「请求 → 响应」模式。发 `012F` 后，固件按协议 7 自动设置默认接收过滤，只收 `18 DA F1 xx` 的响应。用户不碰 `ATCF` / `ATCM`。
2. 不监听原始 CAN 帧，不用 `ATMA` / `STM`，不抓包，不逆向私有报文。
3. 只读一个 PID，没有多 ECU 并发 ISO-TP 多帧通信。
4. 汽油车总线报文种类少于混动与纯电。后者另有 BMS、电机、逆变器、电池模组温度等数据源。

**什么时候才需要**：抓全车 CAN 报文做 DBC 逆向、同时监听多个私有 CAN ID、或多 ECU 并发诊断。这台车 OBD 口经网关隔离，看不到主干 CAN，这些场景本身受限。

**易混淆点**：第 6 节排查 `NO DATA` 用的 `ATCRA`（不带参数）是标准 ELM327 的复位命令，把接收过滤恢复成默认的一小组。它与 2S 的 208 组高级规则不是同一层功能。

来源：[Vgate 官方商城 iCar Pro 2S 规格](https://vgatemall.com/products-detail/i-80/)、[Amazon 2S 官方文案](https://www.amazon.com/Vgate-iCar-Pro-2S-Diagnostic/dp/B0D6Y884YC)、[ELM327 官方手册 p.41：CAN 过滤](https://www.manualslib.com/manual/3455132/Elm-Elm327.html?page=41)、[ELM327 开发者指南：`ATCF` / `ATCM` / `ATCFC`](https://quantexlab.de/zh/develop/elm327.html)

<br>

### 8.8 2S 相对 BLE 4.0 的差异，以及自研能补回什么

**唯一官方承认的真实新增：EV / 混动远程唤醒。** Vgate 官方 2S 页原文：`has added the automatic wake-up function of electric vehicles to the iCar Pro`；官方 BLE 4.0 页写 `Electric vehicles are not supported this function`。240TURBO 汽油版用不上。

| 项 | 判定 |
|---|---|
| 蓝牙 4.0 → 5.2 | 真实差异。`012F` 响应仅几字节，不构成带宽瓶颈 |
| 3 Mbps | 官方用词是 `baudrate`，指内部 UART，不是 BLE 空口速率。BLE 5.2 的 LE 2M PHY 上限为 2 Mbps。属营销措辞 |
| 208 组过滤器 | 官方文案。第三方写作「208-Byte OBD Buffer」，与 vLinker MS 文案高度重合。实际数量与实现**未确认** |
| 过压 / 过温 / 过流保护 | BLE 4.0 同系列手册同样列出，不能认定为 2S 独占 |
| Windows 支持、更多第三方 App | 前者是 SKU / 官方口径不一致，后者是营销话术，均非硬件差异 |
| 固件升级、ELM327 v2.3、29bit / 500K、休眠约 3 mA | 两者相同 |
| 主控芯片 | 两款官方都不公布，`PIC18F25K80` 只出现在早期款销售页。**未确认** |
| ST 命令集 | 2S 官方未声明支持。明确写「ELM327 + STN ST 命令集」的是 vLinker 系列。**未确认** |

**标准 ELM327 命令层两者共有**：`ATCF`、`ATCM`、`ATCRA`、`ATCFC0` / `ATCFC1`、`ATMA`、`ATSH`、`ATCP`、`ATSP 7`、`ATST`。这些由 Elm Electronics 官方数据手册定义。自研 App 可以设置过滤规则、切换 29-bit 协议、监听 CAN，与型号无关。标准 ELM327 只有一组 mask 加一组 filter；208 条属固件扩展，没有标准命令可写入。

#### 可自研补回（纯 App 层，两款等价）

- 初始化序列：`ATZ` → `ATE0` → `ATL0` → `ATSP 7` → `ATSH` / `ATCP` → `ATCRA` → `ATCFC1` → `ATCAF1`。
- 轮询调度、限频、退避、超时 `ATST`。
- 软过滤：收到响应后按 CAN ID / PID 二次筛选。
- ISO-TP 组包。默认固件已用 `ATCAF1` / `ATCFC1` 处理；关闭后必须由 App 自己实现 SF / FF / CF / FC。
- `A × 100 / 255` 换算、滑动平均、中值去抖、异常值剔除。
- 缓存、断连重连、状态机、后台恢复。

#### 部分可补但有代价

| 能力 | 代价 |
|---|---|
| 用软过滤替代 208 条硬件规则 | 所有 CAN 帧必须先送到手机，耗 BLE 带宽、CPU 与电量，总线繁忙时可能丢帧 |
| EV 远程唤醒 | App 无法触发唤醒电路。只能人工重新插拔或断电复位 |
| 3 Mbps 吞吐 | 不能提升空口速率。只能降低轮询频率、只读单 PID，消除需求 |

#### 不可补回（物理层 / 固件层）

- BLE 5.2 射频、LE 2M PHY、内部 UART 波特率。
- 208 条硬件 pass / block / flow-control 过滤表。
- EV 远程唤醒电路。
- 过压 / 过温 / 过流保护元件、工作与休眠电流。

#### 对本场景的结论

`012F` 的响应只有 `41 2F XX` 几字节，远低于 BLE 4.0 的 1 Mbps 上限。请求 → 响应模式下固件自动只回目标 ECU 的响应，一组 `ATCRA` 已足够。汽油车点火时适配器自动启动。2S 的增量无一项构成刚需。

**真正值得自研的是两款都不提供的能力**：29-bit 协议自动切换与失败回退、油量数值去抖、熄火前最后一次值缓存、加油检测（油量跳升）、断连恢复、按 VIN 匹配车型配置。这些属于 App 层，换任何适配器都要自己写。

来源：[Vgate 官方 2S 页](https://vgatemall.com/products-detail/i-80/)、[Vgate 官方 BLE 4.0 页](https://vgatemall.com/products-detail/i-9?s=3)、[Elm Electronics ELM327 官方数据手册](https://www.elmelectronics.com/wp-content/uploads/2017/01/ELM327DS.pdf)、[Bluetooth SIG LE Primer](https://www.bluetooth.com/zh-cn/bluetooth-le-primer/)、[OBDII365：2S vs BLE 4.0](https://blog.obdii365.com/2024/09/11/vgate-icar-pro-2s-vs-icar-pro-bluetooth-4-0/)

<br>

## 主要来源

- [Vgate 官方商城：iCar Pro 系列 SKU](https://www.vgatemall.com/products/i-1/)、[Vgate WiFi 页（连接方式三选一）](https://www.vgatemall.com/products-detail/i-14/)
- [OBDLink CX 开发者页：BLE UUID、MTU、iOS 接入](https://support.obdlink.com/support/solutions/articles/43000746707-obdlink-cx-adapter-notes)
- [OBDLink CX 产品页](https://www.obdlink.com/products/obdlink-cx/)、[OBDLink 选型表](https://support.obdlink.com/support/solutions/articles/43000713351-which-obdlink-adapter-is-right-for-me-)
- [STN1110 FRPM：`STP` / `STPX` / `ATCP` / `ATSH`](http://www.scantool.net/downloads/98/stn1100-frpm.pdf)
- [DauntlessOBD 协议 ID 表](https://dauntlessdevices.com/support/dauntlessobd-developer-api-info/dauntlessobd-supported-protocol-ids/)
- [ELM327 官方手册 p.38：29-bit 头](https://www.manualslib.com/manual/3455132/Elm-Elm327.html?page=38)、[p.41：接收过滤](https://www.manualslib.com/manual/3455132/Elm-Elm327.html?page=41)
- [OBDb Honda Civic 2022 command_support.yaml](https://raw.githubusercontent.com/OBDb/Honda-Civic/main/tests/test_cases/2022/command_support.yaml)
- [Apple MFi FAQ：只用 BLE 的配件不属于 MFi](https://mfi.apple.com/faqs)
- [Apple TN3111：iOS Wi-Fi API 概览](https://developer.apple.com/documentation/technotes/tn3111-ios-wifi-api-overview)
