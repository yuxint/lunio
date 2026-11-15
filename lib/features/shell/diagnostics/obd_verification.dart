// 一键采集的标准 PID 编排（ADR 0023 2026-11-15 扩展）：先读本车能力
// 位图，再按位图枚举所有支持的标准 PID；09/06 各自读 00 位图；DTC
// 03/07/0A 只读。私有 DID 清单在 obd_verification_commands.dart。
//
// 命令来源：SAE J1979 标准（0100/0120/0140/0160/0180/01A0/01C0/01E0、
// 0900、0600、03/07/0A）；不按猜测清单逐条试，避免漏数据和反复试错。
import 'elm327_parser.dart';

/// 能力位图查询命令：mode 01 各段 + mode 09/06 的 00 位图。
const List<String> obdSupportQueries = [
  '0100',
  '0120',
  '0140',
  '0160',
  '0180',
  '01A0',
  '01C0',
  '01E0',
  '0900',
  '0600',
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

/// 标准采集命令：mode 01 全支持量 + mode 09/06 支持项 + DTC 03/07/0A。
/// [supportFrames] 的键是 [obdSupportQueries]（缺失/空帧按无支持处理）。
List<String> buildStandardVerificationCommands(
  Map<String, String> supportFrames,
) {
  final mode01 = <int>{};
  for (final query in const [
    '0100',
    '0120',
    '0140',
    '0160',
    '0180',
    '01A0',
    '01C0',
    '01E0',
  ]) {
    final frame = supportFrames[query];
    if (frame != null && frame.isNotEmpty) {
      mode01.addAll(
        decodeSupportedPids(frame, sentCommand: query),
      );
    }
  }
  const boundaries = {0x00, 0x20, 0x40, 0x60, 0x80, 0xA0, 0xC0, 0xE0};
  final commands = <String>[
    for (final pid in (mode01.toList()..sort()))
      if (!boundaries.contains(pid)) '01${_hexPid(pid)}',
  ];
  final mode09 = decodeSupportedPids(
    supportFrames['0900'] ?? '',
    sentCommand: '0900',
  );
  for (final pid in (mode09.toList()..sort())) {
    if (pid != 0) {
      commands.add('09${_hexPid(pid)}');
    }
  }
  final mode06 = decodeSupportedPids(
    supportFrames['0600'] ?? '',
    sentCommand: '0600',
  );
  for (final pid in (mode06.toList()..sort())) {
    if (pid != 0) {
      commands.add('06${_hexPid(pid)}');
    }
  }
  commands.addAll(const ['03', '07', '0A']);
  return commands;
}

String _hexPid(int pid) => pid.toRadixString(16).padLeft(2, '0').toUpperCase();