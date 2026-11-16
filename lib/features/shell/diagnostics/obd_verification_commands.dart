// 私有 DID 组（2026-11-16 精简，见 docs/car_obd_link/docs/
// 全量采集分析-2026-11-16.md）：只读 `227029` 油量 DID（满箱标定与
// 表显刻度交叉验证用）。原 OBDb Honda Civic 2022 全量 126 条清单已裁，
// 保养/维修模式等未来场景需要全量扫描时，从 git 历史恢复本文件或重跑
// OBDb 数据源：
// https://raw.githubusercontent.com/OBDb/Honda-Civic/main/tests/test_cases/2022/command_support.yaml
class ObdVendorCommandGroup {
  const ObdVendorCommandGroup({required this.header, required this.commands});

  final String header;
  final List<String> commands;
}

const List<ObdVendorCommandGroup> obdVendorCommandGroups = [
  ObdVendorCommandGroup(header: 'DA60F1', commands: ['227029']),
];
