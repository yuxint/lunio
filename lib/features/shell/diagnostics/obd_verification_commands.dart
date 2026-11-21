// 私有 DID 组（2026-11-16 精简 + 2026-11-18 候选段扩展，见
// docs/car_obd_link/docs/全量采集分析-2026-11-16.md 与
// 私有DID网络调研-2026-11-18.md）：按 ECU 分头，全部只读（UDS 0x22，
// 无写入风险）：
//  - DA60F1（仪表，与本车已验证的 227029 同头）：227029 油量标定 +
//    22702A 续航候选（14-15 字节）+ 227060 保养余量 + 227028 车外温度
//    + 227022 里程表/车速（与 01A6 互证）。**四条仪表已有（2026-11-18
//    拍板不卡片化，仅留档采集）**；
//  - DA1EF1（TCM）：222301 CVT 油温（数据区第 26 字节 −40，三源一致 +
//    2022 款真实帧，2026-11-18 实车验证转正；无响应时手动改试 222311）。
//
// ECM 机油温度候选段已于 2026-11-20 撤除（原 DA10F1：222666 + 备选
// 22261A/22262A）：三次一键检测（11-18 20:28、11-19 07:31/07:58/08:30）
// 全部回 `7F 22 31`（NRC requestOutOfRange），本车 ECM 不提供该 DID；
// 标准 PID 5C 也不在能力位图内。继续采只是每次多三条恒定的否定响应。
// 若要再验证，只在调试终端手动做一次扩展会话实验（ATSH DA10F1 →
// 1003 → 222666 → 1001），**不要放进一键检测**：会话切换是有状态操作，
// 不该混进这条只读快照链。
//
// 原 OBDb Honda Civic 2022 全量 126 条清单已裁，保养/维修模式等未来
// 场景需要全量扫描时，从 git 历史恢复本文件或重跑 OBDb 数据源：
// https://raw.githubusercontent.com/OBDb/Honda-Civic/main/tests/test_cases/2022/command_support.yaml
class ObdVendorCommandGroup {
  const ObdVendorCommandGroup({required this.header, required this.commands});

  final String header;
  final List<String> commands;
}

const List<ObdVendorCommandGroup> obdVendorCommandGroups = [
  ObdVendorCommandGroup(header: 'DA60F1', commands: [
    '227029',
    '22702A',
    '227060',
    '227028',
    '227022',
  ]),
  ObdVendorCommandGroup(header: 'DA1EF1', commands: ['222301']),
];
