// 一键检测快照集契约测试（2026-11-16 精简引入）：obdSnapshotCommands
// 与数据层推荐模板 + 内置种子指令集合对账。2026-11-18 二次修订：快
// 照集只收模板（01A6 升内置后模板移除；燃油修正探针保留轮询但卡撤
// 下——pollingBuiltInCommands 语义 = 「内置且正在轮询」），护栏双向：
// a) pollingBuiltInCommands 与种子清单（六条轮询探针）镜像；b) 快照
// 集 = 模板 mode 01 全集。任一侧改指令时这里红灯。
import 'package:flutter_test/flutter_test.dart';
import 'package:lunio/data/repositories/diagnostics_repository.dart';
import 'package:lunio/features/shell/diagnostics/obd_verification.dart';
import 'package:lunio/features/shell/diagnostics/probe_templates.dart';

void main() {
  test('快照集 = 模板 mode 01 指令（内置轮询探针不重复采）', () {
    final expected = <String>{
      for (final template in diagnosticsProbeTemplates)
        if (RegExp(r'^[0-9A-F]{4,}$').hasMatch(template.command))
          template.command,
    };
    expect(obdSnapshotCommands, expected.toList()..sort());
    expect(obdSnapshotCommands.any(pollingBuiltInCommands.contains), isFalse);
  });

  test('轮询内置指令清单与种子镜像（种子改指令时红灯，0105→0167 先例）', () {
    final seedKeys = {
      'probe:fuelLevel',
      'probe:coolantTemp',
      'probe:stftBank1',
      'probe:ltftBank1',
      'probe:cvtOilTemp',
      'probe:odometer',
    };
    final expected = [
      for (final seed in DiagnosticsRepository.builtInProbeSeeds)
        if (seedKeys.contains(seed.catalogKey) &&
            RegExp(r'^[0-9A-F]{4,}$').hasMatch(seed.command))
          seed.command,
    ]..sort();
    // 双侧排序后比对（常量是种子声明序，镜像语义不看顺序）。
    expect([...pollingBuiltInCommands]..sort(), expected);
  });

  test('快照集 = 模板 6 项（01A6 已升内置、燃油修正探针在轮询不重复采）', () {
    expect(obdSnapshotCommands, hasLength(6));
    expect(obdSnapshotCommands, isNot(contains('01A6')));
    expect(obdSnapshotCommands, isNot(contains('012F')));
    expect(obdSnapshotCommands, isNot(contains('0167')));
    expect(obdSnapshotCommands, isNot(contains('0106')));
    expect(obdSnapshotCommands, isNot(contains('0107')));
  });
}
