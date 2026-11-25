// 私有 DID 组（2026-11-16 精简 + 2026-11-18 候选段扩展 + 2026-11-21 撤
// 227060，见 docs/car_obd_link/docs/全量采集分析-2026-11-16.md 与
// 私有DID网络调研-2026-11-18.md）：按 ECU 分头，全部只读（UDS 0x22，
// 无写入风险）：
//  - DA60F1（仪表，与本车已验证的 227029 同头）：227029 油量标定 +
//    22702A 续航候选（14-15 字节）+ 227028 车外温度 + 227022 里程表
//    （数据区第 6–8 字节三字节大端，2026-11-21 与 01A6 同刻比对 66,333
//    完全一致，历史五次单调同步）。**四条仪表已有（2026-11-18 拍板不
//    卡片化，仅留档采集）**；
//  - DA1EF1（TCM）：222301 多行帧。一帧三量（2026-11-21 交叉验证）：
//    数据区第 7–8 字节 = 转速（与 010C 差 0–8 rpm）、第 20 字节 −40 =
//    水温（与 0167 差 ≤1℃）、第 26 字节 −40 = CVT 油温（已转正的卡片
//    来源）。后两者只从原始日志取，不改解析类型——见 ADR 0023 修订节六。
//
// 227060（原以为的「保养余量」）2026-11-21 撤除：11-18、11-19 两次、
// 11-21 共四次一键检测恒回 `7F 22 31`，与 222666 同一条 NRC。仪表段
// 其余四条每次都正常返回，说明不是会话问题，是本车没有这个 DID。
//
// ECM 机油温度候选段已于 2026-11-20 撤除（原 DA10F1：222666 + 备选
// 22261A/22262A）：四次一键检测全部回 `7F 22 31`（NRC requestOutOfRange），
// 本车 ECM 不提供该 DID；标准 PID 5C 也不在能力位图内（0140 三段第四
// 字节均为 0x01，只声明支持 0x60）。继续采只是每次多三条恒定的否定
// 响应。若要再验证，只在调试终端手动做一次扩展会话实验（ATSH DA10F1 →
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
    '227028',
    '227022',
  ]),
  ObdVendorCommandGroup(header: 'DA1EF1', commands: ['222301']),
];
