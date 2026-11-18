// 私有 DID 组（2026-11-16 精简 + 2026-11-18 候选段扩展，见
// docs/car_obd_link/docs/全量采集分析-2026-11-16.md 与
// 私有DID网络调研-2026-11-18.md）：三组按 ECU 分头，全部只读（UDS
// 0x22，无写入风险）：
//  - DA60F1（仪表，与本车已验证的 227029 同头）：227029 油量标定 +
//    22702A 续航候选（14-15 字节）+ 227060 保养余量 + 227028 车外温度
//    + 227022 里程表/车速（与 01A6 互证）。**四条仪表已有（2026-11-18
//    拍板不卡片化，仅留档采集）**；
//  - DA1EF1（TCM）：222301 CVT 油温候选（数据区第 26 字节 −40，三源
//    一致 + 2022 款真实帧，实车验证第一位；无响应时手动改试 222311）；
//  - DA10F1（ECM）：222666 机油温度候选（数据区 11/14 双槽 −40，双
//    槽对照实车定）。
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
  ObdVendorCommandGroup(header: 'DA10F1', commands: [
    '222666',
    // 机油温度备选（2026-11-18 拍板：222666 本车 NRC31 不支持，备选
    // 两条下轮实车一键采集顺带复测）。
    '22261A',
    '22262A',
  ]),
];
