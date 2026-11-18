// 一键检测快照集契约测试（2026-11-16 精简引入）：obdSnapshotCommands
// （诊断域纯 Dart 模块的镜像常量）与数据层内置种子 + 推荐模板的
// mode 01 指令集合对账。种子/模板增删指令时这里红灯，提示同步
// obd_verification.dart 的内置镜像 `_builtInMode01Commands`。
import 'package:flutter_test/flutter_test.dart';
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
    // 信息卡内置四条（实时轮询）不在快照集（2026-11-18 拍板去重）。
    expect(obdSnapshotCommands.any(['012F', '0167', '0106', '0107'].contains), isFalse);
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
