// 语义色跨端副本契约测试：Dart token ↔ 两个 iOS 扩展的 Swift 常量副本。
//
// 背景：iOS 扩展进程读不到 Flutter 主题，语义三色在 Swift 侧只能按值
// 常量副本存在（ADR 0012 先例、ADR 0019 对比度档三处清单）——
//   - LunioWidgetsExtension/MaintenanceOverviewWidget.swift 的
//     LunioStatusColor（桌面小组件状态色：绿/黄/红三份）；
//   - ParkingCountdownExtension/ParkingCountdownLiveActivity.swift 的
//     ParkingThemeColors.danger（实时活动到点警示红一份）。
// 此前同步靠 AGENTS.md 文字义务，改了 Dart 忘了 Swift 只能靠人眼发现；
// 本测试以文本方式读取两个 Swift 源文件、解析常量副本的 RGB 分量，
// 逐值断言与 LunioTokens 浅色档一致——漂移即测试红灯，文案直接指明
// 两侧文件与不一致的色值，可照着修。
//
// Java 对照：≈ 跨服务的契约测试（consumer 端锁 provider 的 schema），
// 只不过这里锁的是"跨语言常量副本"而不是接口。
//
// 纯 Dart 可跑（dart:io 读文本），不依赖 Xcode / 模拟器 / 真机，
// 随常规 flutter test 全量集合执行。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunio/core/theme/lunio_tokens.dart';

/// 小组件副本源文件（相对项目根；flutter test 的工作目录即项目根，
/// 与 test/helpers/built_in_catalog_loader.dart 读 asset 的做法一致）。
const _widgetSwiftPath =
    'ios/LunioWidgetsExtension/MaintenanceOverviewWidget.swift';

/// 实时活动副本源文件。
const _liveActivitySwiftPath =
    'ios/ParkingCountdownExtension/ParkingCountdownLiveActivity.swift';

/// 匹配 Swift 的 `Color(red: A / 255, green: B / 255, blue: C / 255)` 构造。
/// 分量字面量兼容两种既有写法：十进制（小组件副本 `180 / 255`）与
/// 十六进制（实时活动副本 `0xdc / 255`）。
final _colorCtorPattern = RegExp(
  r'Color\(\s*red:\s*(0x[0-9a-fA-F]+|\d+)\s*/\s*255\s*,'
  r'\s*green:\s*(0x[0-9a-fA-F]+|\d+)\s*/\s*255\s*,'
  r'\s*blue:\s*(0x[0-9a-fA-F]+|\d+)\s*/\s*255\s*\)',
);

/// 解析出的一个 Swift 侧色副本：hex 值 + 源文件行号（供失败文案指路）。
class _SwiftColorCopy {
  const _SwiftColorCopy(this.hex, this.line);

  /// #rrggbb 小写形态，与 ADR 0019 / DESIGN.md 的 hex 表述一致。
  final String hex;
  final int line;
}

/// 把 0-255 的 RGB 分量格式化为 #rrggbb。
String _toHex(int r, int g, int b) {
  String two(int v) => v.toRadixString(16).padLeft(2, '0');
  return '#${two(r)}${two(g)}${two(b)}';
}

/// 把 Dart 侧 Color 格式化为 #rrggbb（token 常量都是不透明 sRGB 值）。
String _tokenHex(Color color) => _toHex(
      (color.r * 255).round(),
      (color.g * 255).round(),
      (color.b * 255).round(),
    );

/// 读源文件文本；文件缺失直接失败——源文件被移动/删除时守卫必须红灯，
/// 不能静默跳过。
String _readSource(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    fail('语义色契约测试找不到源文件：$path（文件被移动或删除？'
        '请同步更新 test/core/semantic_color_contract_test.dart 的路径）');
  }
  return file.readAsStringSync();
}

/// 在 [source] 中从 [fromIndex] 起找第一个 `Color(red:…)` 构造。
/// 找不到返回 null（调用方负责以指名 marker 的文案失败）。
_SwiftColorCopy? _firstColorCtorAfter(String source, int fromIndex) {
  final matches = _colorCtorPattern.allMatches(source, fromIndex).iterator;
  if (!matches.moveNext()) {
    return null;
  }
  final match = matches.current;
  // int.parse 在不指定 radix 时自动识别 0x 前缀，十进制与十六进制通吃。
  final r = int.parse(match.group(1)!);
  final g = int.parse(match.group(2)!);
  final b = int.parse(match.group(3)!);
  // match.start 是文件内偏移，换算成 1 起始的行号供失败文案指路。
  final line = '\n'.allMatches(source.substring(0, match.start)).length + 1;
  return _SwiftColorCopy(_toHex(r, g, b), line);
}

/// 切出 `enum Xxx { … }` 块，返回 (块在全文中的偏移, 块文本)。
/// 用首个行首 `}` 作为块结束——仓库 Swift 副本的 enum 体都是顶层、
/// 一层大括号，够用且不需完整语法树。
(int, String) _enumBlock(String source, String enumName, String path) {
  final start = source.indexOf('enum $enumName');
  if (start < 0) {
    fail('语义色契约测试在 $path 中找不到 `enum $enumName`'
        '（常量副本被重命名？请同步契约测试）');
  }
  final bodyStart = source.indexOf('{', start);
  final end = source.indexOf('\n}', bodyStart);
  if (bodyStart < 0 || end < 0) {
    fail('语义色契约测试无法切出 $path 的 `enum $enumName` 块');
  }
  return (start, source.substring(start, end));
}

/// 在 [block]（偏移 [blockStart] 起的文本）中找 [marker] 之后第一个
/// Color 构造；marker 或构造缺失时以指名两者的文案失败。
_SwiftColorCopy _colorAfterMarker(
  String source,
  int blockStart,
  String block,
  String marker,
  String path,
) {
  final markerIndex = block.indexOf(marker);
  if (markerIndex < 0) {
    fail('语义色契约测试在 $path 中找不到标记 `$marker`'
        '（常量副本分支被改写？请同步契约测试）');
  }
  final copy = _firstColorCtorAfter(source, blockStart + markerIndex);
  if (copy == null) {
    fail('语义色契约测试在 $path 的 `$marker` 之后找不到 '
        '`Color(red:… / 255, green:…, blue:…)` 构造'
        '（写法变了？请同步契约测试的正则）');
  }
  return copy;
}

/// 聚合比对并断言：所有不匹配项一次报全，逐项给出两侧路径与色值。
void _expectNoDrift(
  String swiftPath,
  Map<String, _SwiftColorCopy> copies,
  Map<String, String> expected,
) {
  final failures = <String>[];
  for (final entry in copies.entries) {
    final want = expected[entry.key]!;
    if (entry.value.hex != want) {
      failures.add(''
        '${entry.key}：\n'
        '  Dart 侧 lib/core/theme/lunio_tokens.dart LunioTokens.light.'
        '${entry.key} = $want（期望）\n'
        '  Swift 侧 $swiftPath:${entry.value.line} = ${entry.value.hex}'
        '（实际）');
    }
  }
  expect(
    failures,
    isEmpty,
    reason: failures.isEmpty
        ? ''
        : '语义色副本与 Dart token 漂移——改语义三色必须按 ADR 0019 三处清单'
            '同步（token light 三值 + 两个 iOS 扩展常量副本），守卫测试见 '
            'test/core/semantic_color_contract_test.dart：\n'
            '${failures.join('\n')}',
  );
}

void main() {
  test('桌面小组件 LunioStatusColor 三色副本与 LunioTokens 浅色档逐值一致',
      () {
    final source = _readSource(_widgetSwiftPath);
    // 先切出 enum 块：文件里还有别的 switch 也带 default:，裸搜会错位。
    final (blockStart, block) =
        _enumBlock(source, 'LunioStatusColor', _widgetSwiftPath);

    // 副本侧：default 分支即 success（正常/绿）。
    final copies = {
      'success': _colorAfterMarker(
          source, blockStart, block, 'default:', _widgetSwiftPath),
      'warning': _colorAfterMarker(
          source, blockStart, block, 'case "warning":', _widgetSwiftPath),
      'danger': _colorAfterMarker(
          source, blockStart, block, 'case "danger":', _widgetSwiftPath),
    };

    // 期望侧：Dart token 浅色档（ADR 0019 对比度档）。
    final expected = {
      'success': _tokenHex(LunioTokens.light.success),
      'warning': _tokenHex(LunioTokens.light.warning),
      'danger': _tokenHex(LunioTokens.light.danger),
    };

    _expectNoDrift(_widgetSwiftPath, copies, expected);
  });

  test('实时活动 ParkingThemeColors.danger 副本与 LunioTokens 浅色档一致',
      () {
    final source = _readSource(_liveActivitySwiftPath);
    // `static let danger` 全文件唯一（其余出现是使用点
    // ParkingThemeColors.danger），直接锚定，不必切 enum 块。
    final markerIndex = source.indexOf('static let danger');
    if (markerIndex < 0) {
      fail('语义色契约测试在 $_liveActivitySwiftPath 中找不到标记 '
          '`static let danger`（常量副本被重命名？请同步契约测试）');
    }
    final copy = _firstColorCtorAfter(source, markerIndex);
    if (copy == null) {
      fail('语义色契约测试在 $_liveActivitySwiftPath 的 `static let danger` '
          '之后找不到 `Color(red:… / 255, green:…, blue:…)` 构造'
          '（写法变了？请同步契约测试的正则）');
    }

    _expectNoDrift(
      _liveActivitySwiftPath,
      {'danger': copy},
      {'danger': _tokenHex(LunioTokens.light.danger)},
    );
  });
}
