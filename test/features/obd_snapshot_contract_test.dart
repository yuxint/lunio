// 一键检测快照集契约测试（2026-11-16 精简引入）：obdSnapshotCommands
// （诊断域纯 Dart 模块的镜像常量）与数据层内置种子 + 推荐模板的
// mode 01 指令集合对账。种子/模板增删指令时这里红灯，提示同步
// obd_verification.dart 的内置镜像 `_builtInMode01Commands`。
import 'package:flutter_test/flutter_test.dart';
import 'package:lunio/data/repositories/diagnostics_repository.dart';
import 'package:lunio/features/shell/diagnostics/obd_verification.dart';
import 'package:lunio/features/shell/diagnostics/probe_templates.dart';

void main() {
  test('快照集 = 内置 mode 01 指令 ∪ 模板指令（单一来源对账）', () {
    final expected = <String>{
      for (final seed in DiagnosticsRepository.builtInProbeSeeds)
        if (RegExp(r'^[0-9A-F]{4}$').hasMatch(seed.command)) seed.command,
      for (final template in diagnosticsProbeTemplates) template.command,
    };
    expect(obdSnapshotCommands, expected.toList()..sort());
  });

  test('快照集含 11 项、含 0167 与 01A6（2026-11-17 燃油修正转正口径）', () {
    expect(obdSnapshotCommands, hasLength(11));
    expect(obdSnapshotCommands, contains('0167'));
    expect(obdSnapshotCommands, contains('01A6'));
    expect(obdSnapshotCommands, contains('0106'));
    expect(obdSnapshotCommands, contains('0107'));
  });
}
