# 实测数据说明

全部数据采集于 2026 年 11 月 12 日，车型为东风本田十一代思域 2022 款 240TURBO，硬件为 Vgate iCar Pro BLE 4.0，车辆点火 ON、未启动、静止。

| 文件 | 来源 | 内容 |
|---|---|---|
| `IOS-Vlink.txt` | nRF Connect for Mobile 导出 | 完整 BLE 日志。173 行，19:25:12–19:32:14，28 条命令、45 条响应事件 |
| `CarScanner-20261112.csv` | Car Scanner ELM OBD2 导出 | 传感器时间序列。3977 行，68 个 PID，时间跨度 407.7 s |
| `exported_records.zip` | 用户原始文件 | 内含上份 CSV，原始文件名为 `2026-11-12 13-00-20.csv` |

## IOS-Vlink.txt

日志有两种级别，`Normal` 是实际事件，`Application` 是同一事件的重复记录。解析时只取 `Normal`。

关键格式：

```text
Normal: Wrote 415444504e0d to 2AF1 Characteristic
Normal: Updated Value of Characteristic 2AF0 to <hex>.
```

`Updated Value` 里的 hex 带分组空格，需先去掉空格再解码。值为 ASCII 文本，`0D` 是 CR，`3E` 是提示符 `>`。

关键结果：

- `ATZ` / `ATI` → `ELM327 v2.3`
- `ATRV` → `11.2V`
- `ATSP 7` → `OK`
- `012F` → `41 2F 60 \r` 与 `\r>`，分两次通知，间隔 209 ms
- `0100` → 三个 ECU 的能力位图
- `227029` / `222623` / `222678` → 均返回 `0x62` 正响应，多帧带 `0:` 至 `8:` 帧编号

不采信的部分见 [开发依据第 6 节](../docs/实测结果与自研App开发依据.md)：`ATSP 0` 与 `ATD` 复位协议之后发的四条 PID 全部 `NO DATA`；另有四条命令日志无响应记录。`ATDPN` 返回 `7` 来自另一份截图日志，不在本文件内。

## CarScanner-20261112.csv

UTF-8、分号分隔、CRLF。列为 `SECONDS` / `PID` / `VALUE` / `UNITS`。这是 App **解码后的传感器数值**，不是底层协议日志，不含 AT 命令、协议号或 GATT UUID。

关键结果：

- `燃油位输入 (%)` = 37.6470588 %，按 `A × 100 / 255` 反推 A = `0x60`，即 `41 2F 60`。该反推已由 `IOS-Vlink.txt` 证实。
- `燃油位输入 (V)` 18.8235 L 与 `油箱内的自由空间` 31.1765 L 之和为 50.0000 L。**50 L 是 Car Scanner 的设定值，不是车辆上报**；官方手册为 47 L。名字带 `(V)` 但单位为 L，不要按电压理解。
- 油量采样 89 次，间隔中位数 1.04 s，最大间隔 245 s（录制中断）。
- 全部燃油值恒定，车静止且油量未变，无法用于验证去抖与加油检测。

## 数据关系

CSV 用于反推原始字节，TXT 用于证实反推并给出协议层细节。两份数据不能互相替代。
