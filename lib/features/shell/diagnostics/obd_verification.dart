// 一键检测（2026-11-16 精简，ADR 0023 修订节）：命令来源从「枚举一切」
// 收敛为「快照集 ∩ 本车能力位图」+ DTC + 单个油量 DID。2026-11-16 全量
// 采集日志（docs/car_obd_link/docs/全量采集分析-2026-11-16.md）定案后，
// 捞数据阶段结束：私有 DID 全量清单、09xx 车辆信息段、06xx 排放段裁掉，
// 需要时从 git 历史恢复。
//
// 命令来源：SAE J1979 标准；快照集 = 内置三条 + 推荐模板的 mode 01
// 指令（单一来源=种子/模板清单，本模块镜像内置指令 + 契约测试对账，
// 纯 Dart 不依赖 data 层）。
import 'elm327_parser.dart'
    show normalizeObdCommand, obdFrameLines, extractHexBytes;
import 'probe_templates.dart';

/// 能力位图查询命令：mode 01 6 张。2026-11-16 精简——快照集最大 PID
/// 0xA6 落在 01A0 段，01C0/01E0 对快照过滤无用；09/06 位图随 09xx/
/// 06xx 段一并裁掉。
const List<String> obdSupportQueries = [
  '0100',
  '0120',
  '0140',
  '0160',
  '0180',
  '01A0',
];

/// 解一个支持位图帧 → 支持的 PID 集合。响应可多 ECU（按请求 service/PID
/// 逐行取位图并求并集）；帧里的 `039`/`0:` 等杂项由 extractHexBytes 跳过。
Set<int> decodeSupportedPids(
  String frame, {
  required String sentCommand,
}) {
  final command = normalizeObdCommand(sentCommand);
  if (command.length < 4) {
    return const {};
  }
  final service = int.parse(command.substring(0, 2), radix: 16);
  final pid = int.parse(command.substring(2, 4), radix: 16);
  final responseService = service | 0x40;
  final result = <int>{};
  for (final line in obdFrameLines(frame, sentCommand: command)) {
    final bytes = extractHexBytes(line);
    if (bytes.length < 6 ||
        bytes[0] != responseService ||
        bytes[1] != pid) {
      continue;
    }
    for (var byteIndex = 0; byteIndex < 4; byteIndex++) {
      final mask = bytes[2 + byteIndex];
      for (var bit = 0; bit < 8; bit++) {
        if ((mask & (1 << (7 - bit))) != 0) {
          result.add(pid + byteIndex * 8 + bit + 1);
        }
      }
    }
  }
  return result;
}

/// 内置三条中的 mode 01 指令（镜像自 DiagnosticsRepository
/// .builtInProbeSeeds；契约测试 test/features/obd_snapshot_contract_test
/// .dart 锁同步——种子改指令时这里红灯提示）。
const List<String> _builtInMode01Commands = ['012F', '0167'];

/// 一键检测快照集：内置三条 + 推荐模板的全部 mode 01 指令，字典序。
/// 过滤语义见 [buildSnapshotVerificationCommands]。
final List<String> obdSnapshotCommands = _snapshotCommands();

List<String> _snapshotCommands() {
  final commands = <String>{..._builtInMode01Commands};
  for (final template in diagnosticsProbeTemplates) {
    commands.add(normalizeObdCommand(template.command));
  }
  final sorted = commands.toList()..sort();
  return List.unmodifiable(sorted);
}

/// 一键检测标准段命令：快照集 ∩ 本车位图支持集，后接 DTC 03/07/0A。
/// [supportFrames] 的键是 [obdSupportQueries]；位图缺失/空帧按无支持
/// 处理 → 快照里该 PID 被跳过（支持集是过滤闸门不是枚举来源）。
List<String> buildSnapshotVerificationCommands(
  Map<String, String> supportFrames,
) {
  final supported = <int>{};
  for (final query in obdSupportQueries) {
    final frame = supportFrames[query];
    if (frame != null && frame.isNotEmpty) {
      supported.addAll(decodeSupportedPids(frame, sentCommand: query));
    }
  }
  final commands = <String>[
    for (final command in obdSnapshotCommands)
      if (_pidSupported(command, supported)) command,
  ];
  commands.addAll(const ['03', '07', '0A']);
  return commands;
}

/// mode 01 四位 hex 指令按支持集过滤；其余形态（防御性）直通。
bool _pidSupported(String command, Set<int> supported) {
  if (!RegExp(r'^[0-9A-F]{4}$').hasMatch(command)) {
    return true;
  }
  final pid = int.parse(command.substring(2), radix: 16);
  return supported.contains(pid);
}