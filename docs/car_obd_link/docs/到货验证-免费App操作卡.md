# 到货验证操作卡

| 项 | 值 |
|---|---|
| 车型 | 十一代思域 2022 款 240TURBO |
| 硬件 | Vgate iCar Pro BLE 4.0 |
| 工具 | Car Scanner ELM OBD2（中文界面）、nRF Connect for Mobile（英文界面） |
| GATT UUID | Service `18F0`、Notify `2AF0`、Write `2AF1`（已实扫，设备名 `IOS-Vlink`） |
| 状态 | **29 条命令已实测（2026-11-12）。结果见 `实测结果与自研App开发依据.md`** |

Car Scanner 已在「所有传感器」页读到油量。本卡用于取回三类底层数据：当前 CAN 协议号、实扫的 BLE GATT UUID、`012F` 的原始响应字节。实测后把日志发回，由我判定是否保留硬件并确定自研 App 的初始化序列。

<hr style="border:0;border-top:1px solid #888;margin:10px 0 18px;">

## 1. 准备

1. 核对机身标签为 `iCar Pro Ble4.0`。不得使用 `BT3.0` 或 `Wi-Fi` 版本。
2. 安装 Car Scanner ELM OBD2。中国区名为「汽车扫描仪 - Car Scanner ELM OBD2」，官网 `carscanner.info`，开发者 `Stanislav Svistunov`，App ID `1259933623`。中国区有同名 App，不要装错。
3. 安装 nRF Connect for Mobile。
4. 将车辆电源置于 ON，或启动发动机。熄火后 OBD 口不提供实时数据。
5. 插入适配器。不要在「设置 > 蓝牙」中配对。iOS 必须在 App 内扫描连接。

<br>

## 2. 步骤 A：Car Scanner ELM OBD2

本节为已完成的读数步骤。需要重连或复核设置时按此执行。

首次启动会询问语言，选「简体中文」。以下中文为操作描述，括号内是英文原文。各版本中文译名略有差异，按菜单位置与英文对照定位。

1. 打开 App，进入设置（`Settings`）→ 连接（`Connection`）。
2. 进入适配器（`Adapter OBDII ELM327`），连接类型选 **`Bluetooth LE (4.0+)`**。不要选 `Wi-Fi`。
3. 进入选择设备（`Select device`），点刷新（`Refresh`），选扫描到的适配器。设备名可能是 `IOS-Vlink`、`V-LINK`、`OBDII`。
4. 返回设置，进入连接配置文件（`Connection profile`）→ 选择连接配置（`Choose connection profile`），选 Honda，再选 `OBD-II/EOBD`。若有 `AT/CVT (CAN)` 配置项，选它。
5. 进入设置 → 高级设置（`Advanced Settings`）→ ECU 协议（`ECU Protocol`）。部分版本在连接页里直接叫 `ECU protocol`。改选 **`7) ISO 15765-4 CAN (29 bit ID, 500 Kbaud)`**。默认自动探测常停在 11-bit 协议 6，会返回 `NO DATA`。
6. 回主页面点连接（`CONNECT`）。出现 `ELM connection: Connected` 与 `ECU connection: Connected` 才算连上。
7. 点所有传感器（`All sensors`），找 `Fuel Level` / `Fuel Tank Level Input`。中文译名未确认，按「燃油」关键字或列表位置找。记录数值，与仪表油量对照。
8. 没有该传感器时，进入设置 → 自定义传感器（`Custom sensors`）→ `+` → 新建 PID（`New PID`），按下列填写。表单字段多为英文，按英文标签对照。

| 字段（英文原标签） | 填什么 |
|---|---|
| `Name` / `Short Name` | `Fuel Level` |
| `Command` | `012F` |
| `Header` | **留空**（用协议 7 默认头，不要填 `7E0`） |
| `Decode Scheme` | 保持默认 |
| `Formula` | `A*100/255` |
| `Units` | `%` |
| `Min` / `Max` | `0` / `100` |

9. 点测试（`Test`）。有返回值后，到仪表盘（`Dashboard`）→ 齿轮 → 自定义页面（`Customize page`）→ `Items` → `Sensor` 添加显示。

设置里还有终端（`Terminal`）。部分版本可直接发 AT 命令，能否使用待确认。免费版是否锁住 ECU 协议与自定义传感器，官方未公布。

<br>

## 3. 步骤 B：nRF Connect for Mobile

### 3.1 扫描并连接

1. 打开 App，进入 **`Scanner`** 标签。
2. 点右上角 **`SCAN`**（或 Play ▶ 图标）开始扫描。
3. 在列表里找适配器。名称可能是 `IOS-Vlink`、`V-LINK`、`OBDII` 或空白，按 RSSI 最强、距离最近判断。
4. 点该行的 **`Connect`**。
5. 进入设备页，切到 **`Client`** 标签。部分版本需左滑到 `Services` 页。

### 3.2 核对 UUID（已实扫）

设备名 `IOS-Vlink`，已连接。实扫结果：

| 角色 | 16-bit UUID | 完整 UUID | 界面显示名 |
|---|---|---|---|
| Service | `18F0` | `000018F0-0000-1000-8000-00805F9B34FB` | `18F0` |
| 通知（Notify / Indicate） | `2AF0` | `00002AF0-0000-1000-8000-00805F9B34FB` | `Electric Current Specification` |
| 写入（Write / Write Without Response） | `2AF1` | `00002AF1-0000-1000-8000-00805F9B34FB` | `Electric Current Statistics` |

界面上的 `Electric Current ...` 是 nRF Connect 按 16-bit UUID 查 Bluetooth SIG 名称表得到的标签，与设备功能无关。厂商借用这组编号做串口透传。**按 UUID 判断，不要按名称判断。** 自研 App 的 `CoreBluetooth` 使用表中三个完整 UUID。

6. 确认 `CONNECTED SERVICES` 下有 `18F0 PRIMARY SERVICE`。
7. 确认该服务下 `2AF0` 属性为 `Notify, Indicate`，`2AF1` 属性为 `Write, Write Without Response`。
8. 截图保存这一屏。

### 3.3 启用通知

漏掉本节，收不到任何回复。

9. 点 `2AF0` 右侧的向下箭头 ↓，确认变成已订阅状态。
10. 该按钮无效时：展开 `2AF0` → `Client Characteristic Configuration (2902)` → 点右侧向上箭头 ↑ → `Write Value` 窗口选 `Bool` → 置 `True` → 点 `Write`。
11. 打开 `Log`，确认后续能看到收到的字节。

**保持当前连接**，不要点 `Disconnect` 或刷新服务。下一步直接发表 1 的第一条 `ATDPN`。

### 3.4 写入规则

12. 点 `2AF1` 右侧的向上箭头 ↑，弹出 `Write Value` 窗口。
13. 数据格式选 **`Byte Array`**（或 `HEX`）。该格式接受**连续 hex，不带 `0x` 前缀、不带空格**：`ATDPN` 填 `415444504E0D`。不要用 `UTF8` / `Text`：该模式无法输入 CR `0D`，命令不会结束；从聊天或网页复制文本还可能带入不可见的零宽空格 U+200B（字节 `E2 80 8B`）。iOS 键盘的回车只产生 LF `0A`。本卡统一用字节格式把 `0D` 编进末字节。
14. 若对话框提供写入类型，选 **`Request`**（write with response）；报错或无反应时改选 **`Command`**。部分 iOS 版本的 `Write Value` 对话框没有该选项，直接点 `Write` 即可。
15. 在 `Write value` 框填入命令表的 Hex，点 **`Write`** 发送。Android 版按钮叫 `SEND`。
16. **每条单独发，等 `Log` 里出现 `>` 再发下一条。** ELM327 不缓存后续命令，处理期间到达的字节会中断当前命令。不得把多条命令拼成一次写入。
17. 返回是 ASCII 文本，末尾 `3E` 即 `>`。例 `41 2F 80` 在线上是 `34312032462038300D3E`。

### 3.5 完整命令表

下表命令已于 2026 年 11 月 12 日实测。按 3.4 的规则逐条发，记录每条的 `Log` 原文。期望返回只作对照，实测结果见 `实测结果与自研App开发依据.md`。

#### 表 1　必发：初始化与油量

按表中顺序发送。`ATDPN` 必须在 `ATZ` 之前：`ATZ` 复位会恢复默认设置，`ATSP 7` 会把协议改成手动 7，两者都会抹掉连上时的原始协议信息。`A` 前缀表示自动探测所得，`A6` = 11-bit 500 kbit/s，`A7` = 29-bit 500 kbit/s。

**`ATZ` 会把协议复位回自动，因此第 7 步 `ATSP 7` 不得跳过。** 跳过时 `012F` 会返回 `NO DATA`。

| 命令 | 写入 Hex | 用途 | 期望返回 |
|---|---|---|---|
| `ATDPN` | `415444504E0D` | 读当前协议号 | `A6` / `A7` / `6` / `7` |
| `ATZ` | `41545A0D` | 全复位 | `ELM327 v2.x` + `>` |
| `ATE0` | `415445300D` | 关命令回显 | `OK>` |
| `ATL0` | `41544C300D` | 关响应换行 | `OK>` |
| `ATI` | `4154490D` | 读固件版本 | 版本字符串 |
| `0100` | `303130300D` | PID `01`–`20` 支持位图，兼作 ping | `41 00 ...` |
| `ATSP 7` | `4154535020370D` | 设 ISO 15765-4 CAN 29-bit 500 kbit/s | `OK>` |
| `012F` | `303132460D` | **燃油箱液位输入** | `41 2F xx>` |

`0100` 只覆盖 PID `01`–`20`，不含 `2F`。`2F` 属于 `21`–`40` 段，其支持位图用表 2 的 `0120`。

#### 表 2　补充：链路、能力与同类参数

在表 1 之后发送。全部记录原始返回。

| 命令 | 写入 Hex | 用途 | 期望返回 |
|---|---|---|---|
| `ATRV` | `415452560D` | 读 OBD 口电压，不依赖车辆应答，排障首选 | `xx.x V` |
| `010C` | `303130430D` | 发动机转速，验证链路 | `41 0C xx xx` |
| `0120` | `303132300D` | PID `21`–`40` 支持位图，含 `2F` | `41 20 ...` |
| `019D` | `303139440D` | 替代燃油率（OBDb 记录 `FUEL_RATE_ALT` / `VFUEL_RATE`） | `41 9D ...` |
| `015E` | `303135450D` | 发动机燃油率（python-OBD `FUEL_RATE`） | `41 5E xx xx` |
| `01 2F 0C 0D` | `30312032462030432030440D` | 一条报文取油量、转速、车速 | 多组 `41 ...`，按 PID 匹配 |
| `022F00` | `3032324630300D` | 冻结帧 0 的油量快照，非当前值 | `42 2F 00 xx` |

一条 OBD 请求最多 6 个 PID。不得把支持位图 PID 与数据 PID 混在同一条请求里。

#### 表 3　可选：本田私有 DID

**前置条件**：这组命令需 29-bit 物理寻址与 ISO-TP 多帧。先发对应的 `ATSH` 设置报文头，再发 DID。`ATSH` 会改变后续所有请求的头，本组结束后必须发 `ATZ` 复位。响应格式未解码，只记录原始字节。

| 命令 | 写入 Hex | 用途 | 期望返回 |
|---|---|---|---|
| `ATSH DA 60 F1` | `415453482044412036302046310D` | 把请求头设为 `18DA60F1` | `OK>` |
| `227029` | `3232373032390D` | `CIVIC_FLV`，OBDb 定义为 16 位 ÷ 100、单位升 | 多帧响应，记录原始字节 |
| `ATSH DA 10 F1` | `415453482044412031302046310D` | 把请求头设为 `18DA10F1` | `OK>` |
| `222623` | `3232323632330D` | 原始字节，OBDb 描述含 Fuel Level | 多帧响应，记录原始字节 |
| `222678` | `3232323637380D` | 原始字节，OBDb 描述含 Fuel Level(Average) | 多帧响应，记录原始字节 |

**不列入本表**：`222516`（`CIVIC_FLI_INPUT`）与 `22F42F`（`CIVIC_FLI_F4`）。两者带 2015 年份限定，OBDb 2022 记录为 unsupported。

#### 表 4　排障与恢复

按需发送。全部测试结束后，发 `ATSP 0` 恢复自动协议。`ATSP` 会写入适配器 EEPROM 成为默认值，自研 App 不得依赖这个记忆，必须在初始化序列里显式设协议。

| 命令 | 写入 Hex | 用途 | 期望返回 |
|---|---|---|---|
| `ATCRA` | `41544352410D` | 复位接收过滤，排查 `NO DATA` | `OK>` |
| `ATH1` | `415448310D` | 显示 CAN 报文头，确认响应 ID | `OK>` |
| `ATSP 6` | `4154535020360D` | 切到 11-bit 500 kbit/s 作对照 | `OK>` |
| `ATSP 0` | `4154535020300D` | 恢复自动协议 | `OK>` |
| `ATD` | `4154440D` | 恢复全部默认设置 | `OK>` |

#### 表 5　相关但非液位

用于对照，不返回剩余油量。

| 命令 | 写入 Hex | 用途 | 期望返回 |
|---|---|---|---|
| `0103` | `303130330D` | 燃油系统状态 | `41 03 xx xx` |
| `0151` | `303135310D` | 燃油类型 | `41 51 xx` |
| `0152` | `303135320D` | 乙醇比例 | `41 52 xx` |
| `0123` | `303132330D` | 燃油轨压力 | `41 23 xx xx` |

### 3.6 计算

油量 % = `xx` 转十进制 × 100 / 255。例 `41 2F 80` → 128 × 100 / 255 ≈ 50.2%。只记录实际返回值，不要用这个示例推填数据。

### 3.7 导出日志

1. `Log` 标签 → 右上角分享或三点菜单 → `Export` → 选 `Text` 或 `CSV`，保存文件。不同版本入口位置略有差异。
2. 截图 service / characteristic 列表，确保 UUID 完整可见。
3. 截图每条命令的返回；若导出日志已含全部返回，可只导出日志。

<br>

## 4. 排错

| `Log` 里看到 | 原因 | 动作 |
|---|---|---|
| `?` | 漏 `0D`、Hex 带空格，或误用 `UTF8` / `Text` 格式 | 改成连续 Hex，确认末字节 `0D`，确认格式为 `HEX` / `ByteArray` |
| 只有 `Wrote`、无返回，约 20 秒后回 `?` | 命令缺 `0D`，ELM327 一直在等结束符 | 确认写入值末字节是 `0D` |
| `Wrote` 里出现 `E2 80 8B` | UTF8 文本混入 U+200B 零宽空格，多从聊天或网页复制带入 | 不用文本模式；改用 `HEX` / `ByteArray` 填连续 Hex |
| `Write Value` 框内显示 `N/A` | 值预览解析失败。App 把 `2AF1` 当 SIG 的 Electric Current Statistics 解析，与 UUID 名称误标同源 | 不必改格式。直接点 `Write`，以日志 `Wrote` 后的 hex 为准 |
| 日志 `Wrote` 后的 hex 不是 `415444504E0D` | 写入值被改写或格式仍不对 | 清空输入框，用键盘逐字符重敲，不要复制；确认 `N/A` 之外无其它报错 |
| `NO DATA` | 协议错，或车不支持该 PID | 发 `ATRV`、`010C` 验链路，再发 `ATCRA`、`ATSP 6`、`ATSP 0` 作对照 |
| `BUS INIT... ERROR` | 协议选错 | 改 `ATSP 6` |
| 完全无记录 | `2AF0` 未订阅、写错 characteristic、写入类型不被接受 | 回 3.3 与 3.4 检查 |
| `2AF1` 写入成功但 `2AF0` 无返回 | 数据通道可能不是 `18F0` | 向下滚动服务列表，检查是否存在第二个自定义 service `E7810A71-73AE-499D-8C15-FAA9AEF0C3F2`。该通道未在本机验证 |

<br>

## 5. 需回传的数据

1. nRF Connect 导出的 `Log`（`Text` 或 `CSV`），包含全部命令与原始响应。
2. `18F0` 服务展开页截图（含 `2AF0` / `2AF1` 属性）。完整 128-bit UUID 已由 3.2 表给出。
3. 机身标签型号与 `ATI` 返回的固件版本。
4. 车辆状态（点火 ON 或发动机运行）、仪表显示的实际油量。
5. 若执行了表 3，注明每条 `ATSH` 与 DID 的对应关系，便于还原报文头。

验证后复测车辆能否正常启动、适配器是否休眠。官方手册警告：加装改装的电气设备可能影响车端通讯。

<br>

## 参考

[ELM327 官方数据手册](https://www.elmelectronics.com/wp-content/uploads/2016/07/ELM327DSF.pdf)、[Car Scanner 自定义 PID 文档](https://www.carscanner.info/?p=235)、[Stack Overflow：Vgate iCar Pro 的 `18F0` / `2AF0` / `2AF1` 服务结构](https://stackoverflow.com/q/61427535)、[Home Assistant 社区：iCar Pro BT4.0 的 UUID 配置](https://community.home-assistant.io/t/custom-component-nissan-leaf-via-lelink-2-elm327-ble/561961/56)、[OBDb Honda-Civic 2022 实车响应](https://github.com/OBDb/Honda-Civic/blob/main/tests/test_cases/2022/command_support.yaml)、[OBDb 本田信号定义](https://github.com/OBDb/Honda-Civic/blob/main/signalsets/v3/default.json)、[python-OBD `FUEL_LEVEL` 定义](https://github.com/brendan-w/python-OBD/blob/master/obd/commands.py)
