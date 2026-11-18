// 一键检测快照集契约测试（2026-11-16 精简引入）：obdSnapshotCommands
// 与数据层推荐模板 + 内置种子的 mode 01 指令集合对账。2026-11-18 起
// 快照集只收模板（信息卡内置四条去重），护栏改为双向：a) 排除清单
// infoCardMode01Commands 与种子清单（油量/水温/两条燃油修正）镜像；
// b) 快照集 = 模板 mode 01 全集。任一侧改指令时这里红灯。
import 'package:flutter_test/flutter_test.dart';
import 'package:lunio/data/repositories/diagnostics_repository.dart';
import 'package:lunio/features/shell/diagnostics/obd_verification.dart';
import 'package:lunio/features/shell/diagnostics/probe_templates.dart';

void main() {
  test('快照集 = 模板 mode 01 指令（信息卡内置四条已轮询、不重复采）', () {
    final expected = <String>{
      for (final template in diagnosticsProbeTemplates)
        if (RegExp(r'^[0-9A-F]{4}$').hasMatch(template.command))
          template.command,
    };
    expect(obdSnapshotCommands, expected.toList()..sort());
    expect(obdSnapshotCommands.any(infoCardMode01Commands.contains), isFalse);
  });

  test('排除清单与信息卡内置种子镜像（种子改指令时红灯，0105→0167 先例）', () {
    final seedKeys = {
      'probe:fuelLevel',
      'probe:coolantTemp',
      'probe:stftBank1',
      'probe:ltftBank1',
    };
    final expected = [
      for (final seed in DiagnosticsRepository.builtInProbeSeeds)
        if (seedKeys.contains(seed.catalogKey) &&
            RegExp(r'^[0-9A-F]{4}$').hasMatch(seed.command))
          seed.command,
    ]..sort();
    // 双侧排序后比对（常量是种子声明序，镜像语义不看顺序）。
    expect([...infoCardMode01Commands]..sort(), expected);
  });

  test('快照集含 7 项、含 01A6、不含信息卡内置四条（2026-11-18 去重口径）', () {
    expect(obdSnapshotCommands, hasLength(7));
    expect(obdSnapshotCommands, contains('01A6'));
    expect(obdSnapshotCommands, isNot(contains('012F')));
    expect(obdSnapshotCommands, isNot(contains('0167')));
    expect(obdSnapshotCommands, isNot(contains('0106')));
    expect(obdSnapshotCommands, isNot(contains('0107')));
  });
}
