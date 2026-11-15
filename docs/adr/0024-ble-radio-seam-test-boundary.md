# ADR 0024：BLE 无线电面（ObdRadio）——测试接缝与假 radio 的证明边界

日期：2026-11-15
状态：已接受

## 背景

- 诊断页的 BLE 胶水（`ble_obd_link.dart`）承载门禁分流、扫描归属代数、起始窗口停扫、建链释放旗、单次断开、链路丢失监视等竞态协议。2026-11-15 三轮评审修复（`d162731` / `b1cfceb` / `0845142`）全部落在这层。
- 该层直接调用 flutter_blue_plus 静态门面，纯状态机没有 seam：唯一被直接测试的是错误分类（`ble_obd_errors_test.dart`）与扫描清单纯函数（`ble_scan_entries_test.dart`）。
- ADR 0020 接受「BLE 链路的真实验证只有真机清单一条路」。这是对无线电行为的接受，不是对「谁拥有扫描 / 何时可以停扫」这类纯状态机的接受。

## 关键取舍

- **接缝高度：插件面端口 vs 高层 link 工厂**。高层 link 工厂会把六步建链藏到接缝后面，竞态协议住进真 adapter、测试只能测假实现。选插件面端口：只镜像实际用到的 FBP 操作，业务决策全部留在端口上方。
- **纯测试接缝**：生产端只有 FBP 一个 adapter，第二个 adapter 只存在于测试。端口不为 WiFi / 其他插件预留——未来通道走 ADR 0020 的 `OBDTransport` 新实现。
- **假 radio 的证明边界**：假 radio 证明我方胶水协议，不证明 FBP 与无线电行为；假实现会漂移，真机验收清单仍是无线电行为的唯一真值。
- **错误契约**：能分类的平台错误在 FBP adapter 翻译成 `BleObdTransportException`；未分类异常原样透传，上方按调用点的 `mapBleObdLinkFailure(e, fallback: …)` 兜底——保持现有文案不变。
- **不换插件、不改公开接缝**：`OBDTransport`、`ObdScanner`、`Elm327Session`、解析器、`DiagnosticsConnectionController`、页面、扫描 sheet 不动；`obd_runtime.dart` 仍是唯一装配点。

## 决定

1. 新增端口 `ObdRadio`（`obd_radio.dart`）：适配器面（`isSupported` + `adapterState` 流，订阅回放当前值）、扫描面（`startScan` / `startDirectedScan` / `stopScan` + 全量扫描结果流）、设备面（`connect` / `disconnect` / `connectionState` 流（回放）/ `discoverServices`）、服务与 characteristic 数据面（`uuid` / 值流 / 开通知 / 写入）。跨端口只用自有类型，测试不 import flutter_blue_plus。
2. 生产 adapter `FlutterBluePlusObdRadio`（`ble_obd_radio.dart`）：唯一调用 FBP API 的文件；`License.nonprofit`、`continuousUpdates`、`withRemoteIds`、`withoutResponse: false` 等插件细节在此固定。
3. 平台错误识别（权限文本 → `permissionDenied`、`mapBleObdLinkFailure`）独立在 `ble_obd_platform_errors.dart`；`ble_obd_errors.dart` 只留分类与文案，不 import FBP。
4. `BleObdScanner` / `BleObdTransport` 改为消费 `ObdRadio`：门禁序列与 10 秒窗口、定向扫描 8 秒 / 建链 15 秒窗口（可注入，默认不变）、UUID 匹配、先订阅后开通知、链路丢失监视、扫描归属代数、单次断开、错误 fallback 全部留在端口上方。
5. `obd_runtime.dart` 新增 `obdRadioProvider`（默认 `FlutterBluePlusObdRadio`）；`BleObdScanner` 与 `BleObdTransport` 构造必填 radio；会话工厂闭包从 provider 取同一实例。
6. 测试：`FakeObdRadio`（`test/helpers/fake_obd_radio.dart`）脚本化适配器状态、扫描、设备建链/服务发现/断连、通知与写入，回放语义与 FBP 对齐；adapter 测试分两片（扫描器 → 传输层），时间控制用 `fake_async`（新增 dev_dependency）。
7. 行为保持：不删任何现有测试；全量 `flutter analyze` + `flutter test` 绿；两片完成后跑真机验收清单。

## 后果

- `flutter_blue_plus` 的 import 收敛到 `ble_obd_radio.dart` 与 `ble_obd_platform_errors.dart` 两个文件；状态机文件对插件零依赖。
- 竞态协议第一次有直接、确定性的测试；假 radio 与真实现的差异不在测试声明范围内，真机清单继续维护。
- 端口是内部测试边界，不是产品接口：未来换插件只改 `FlutterBluePlusObdRadio`；新增传输通道仍走 `OBDTransport`。
- 与 ADR 0020 的关系：不推翻其「真机验收」结论，只把可测边界从无线电推进到胶水状态机。
