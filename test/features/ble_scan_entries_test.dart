// 扫描清单合并纯函数（mergeScanEntries）与节流合并器
//（ScanEntryCoalescer）单测。真扫描器碰 flutter_blue_plus 静态门面不
// 可单测，过滤、首见定序与发射节奏收在纯 Dart 里直接锁行为
//（2026-11-15：反转 story 5 空名过滤 + 首见定序 + ≤1Hz 节流，ADR 0020
// 修订节）。
import 'package:flutter_test/flutter_test.dart';

import 'package:lunio/features/shell/diagnostics/ble_scan_entries.dart';

BleObdScanEntry entry(String id, String name, int rssi) =>
    BleObdScanEntry(id: id, name: name, rssi: rssi);

void main() {
  group('mergeScanEntries：空名过滤 + 首见定序', () {
    test('广播名为空的设备不进清单', () {
      final merged = mergeScanEntries(const [], [
        entry('dev-A', 'IOS-Vlink', -58),
        entry('dev-B', '', -47),
        entry('dev-C', '', -40),
      ]);
      expect(merged, hasLength(1));
      expect(merged.single.id, 'dev-A');
    });

    test('全部空名返回空清单（不是 null）', () {
      final merged = mergeScanEntries(const [], [
        entry('dev-B', '', -47),
      ]);
      expect(merged, isEmpty);
    });

    test('首拍按信号强度降序', () {
      final merged = mergeScanEntries(const [], [
        entry('dev-A', 'IOS-Vlink', -58),
        entry('dev-B', 'Android-Vlink', -45),
        entry('dev-C', 'OBD Adapter', -66),
      ]);
      expect(merged.map((e) => e.id), ['dev-B', 'dev-A', 'dev-C']);
    });

    test('同拍同强度新设备按设备标识定序（排序确定性）', () {
      final merged = mergeScanEntries(const [], [
        entry('dev-C', 'Same-C', -50),
        entry('dev-A', 'Same-A', -50),
        entry('dev-B', 'Same-B', -50),
      ]);
      expect(merged.map((e) => e.id), ['dev-A', 'dev-B', 'dev-C']);
    });

    test('信号抖动只更新数字、不换位（首见定序冻结）', () {
      final first = mergeScanEntries(const [], [
        entry('dev-A', 'IOS-Vlink', -58),
        entry('dev-B', 'Android-Vlink', -45),
      ]);
      expect(first.map((e) => e.id), ['dev-B', 'dev-A']);

      final second = mergeScanEntries(first, [
        entry('dev-A', 'IOS-Vlink', -35),
        entry('dev-B', 'Android-Vlink', -80),
      ]);
      expect(second.map((e) => e.id), ['dev-B', 'dev-A']);
      expect(second.first.rssi, -80);
      expect(second.last.rssi, -35);
    });

    test('新设备插入到第一条比它弱的行之前', () {
      final previous = mergeScanEntries(const [], [
        entry('dev-A', 'Strong', -40),
        entry('dev-B', 'Weak', -80),
      ]);
      // 当前展示值：Strong -40、Weak -80。
      final merged = mergeScanEntries(previous, [
        entry('dev-A', 'Strong', -40),
        entry('dev-B', 'Weak', -80),
        entry('dev-C', 'Middle', -60),
      ]);
      expect(merged.map((e) => e.id), ['dev-A', 'dev-C', 'dev-B']);
    });

    test('新设备强于全表插到最前，弱于全表追加末尾', () {
      final previous = mergeScanEntries(const [], [
        entry('dev-A', 'Strong', -40),
        entry('dev-B', 'Weak', -80),
      ]);
      final withStrongest = mergeScanEntries(previous, [
        entry('dev-A', 'Strong', -40),
        entry('dev-B', 'Weak', -80),
        entry('dev-C', 'Strongest', -20),
      ]);
      expect(withStrongest.first.id, 'dev-C');
      final withWeakest = mergeScanEntries(withStrongest, [
        entry('dev-A', 'Strong', -40),
        entry('dev-B', 'Weak', -80),
        entry('dev-C', 'Strongest', -20),
        entry('dev-D', 'Weakest', -95),
      ]);
      expect(withWeakest.last.id, 'dev-D');
    });

    test('同强度新设备排在已有行之后（首见先后即次序）', () {
      final previous = mergeScanEntries(const [], [
        entry('dev-A', 'First', -60),
      ]);
      final merged = mergeScanEntries(previous, [
        entry('dev-A', 'First', -60),
        entry('dev-B', 'Second', -60),
      ]);
      expect(merged.map((e) => e.id), ['dev-A', 'dev-B']);
    });

    test('这一拍缺席的老设备保留原行原值（不闪行）', () {
      final previous = mergeScanEntries(const [], [
        entry('dev-A', 'IOS-Vlink', -58),
      ]);
      final merged = mergeScanEntries(previous, const []);
      expect(merged, hasLength(1));
      expect(merged.single.rssi, -58);
    });

    test('名瞬时为空时保留上次的非空名', () {
      final previous = mergeScanEntries(const [], [
        entry('dev-A', 'IOS-Vlink', -58),
      ]);
      final merged = mergeScanEntries(previous, [
        entry('dev-A', '', -50),
      ]);
      expect(merged.single.name, 'IOS-Vlink');
      expect(merged.single.rssi, -58);
    });

    test('入参清单不被原地修改（返回新清单）', () {
      final input = [
        entry('dev-A', 'IOS-Vlink', -58),
        entry('dev-B', 'Android-Vlink', -45),
      ];
      final merged = mergeScanEntries(const [], input);
      expect(input.map((e) => e.id).toList(), ['dev-A', 'dev-B']);
      expect(merged.map((e) => e.id).toList(), ['dev-B', 'dev-A']);
    });
  });

  group('ScanEntryCoalescer：≤1Hz 合并发射', () {
    late DateTime now;
    late List<List<BleObdScanEntry>> emissions;
    late ScanEntryCoalescer coalescer;

    setUp(() {
      now = DateTime(2026, 11, 15, 9);
      emissions = [];
      coalescer = ScanEntryCoalescer(
        emit: emissions.add,
        now: () => now,
      );
    });

    test('首拍立即发射', () {
      coalescer.accept([entry('dev-A', 'IOS-Vlink', -58)]);
      expect(emissions, hasLength(1));
      expect(emissions.single.single.id, 'dev-A');
    });

    test('窗口内纯信号变化不发射，到点补发最新值', () {
      coalescer.accept([entry('dev-A', 'IOS-Vlink', -58)]);
      now = now.add(const Duration(milliseconds: 300));
      coalescer.accept([entry('dev-A', 'IOS-Vlink', -70)]);
      expect(emissions, hasLength(1), reason: '窗口内不发');

      now = now.add(const Duration(milliseconds: 699));
      coalescer.flushIfDue();
      expect(emissions, hasLength(1), reason: '未满 1 秒不补发');

      now = now.add(const Duration(milliseconds: 1));
      coalescer.flushIfDue();
      expect(emissions, hasLength(2), reason: '满 1 秒补发尾拍');
      expect(emissions.last.single.rssi, -70);
    });

    test('新设备在窗口内也立即发射', () {
      coalescer.accept([entry('dev-A', 'IOS-Vlink', -58)]);
      now = now.add(const Duration(milliseconds: 200));
      coalescer.accept([
        entry('dev-A', 'IOS-Vlink', -60),
        entry('dev-B', 'OBD Adapter', -50),
      ]);
      expect(emissions, hasLength(2));
      expect(emissions.last.map((e) => e.id), ['dev-B', 'dev-A']);
    });

    test('flushIfDue 无待发更新不发射', () {
      coalescer.accept([entry('dev-A', 'IOS-Vlink', -58)]);
      now = now.add(const Duration(seconds: 2));
      coalescer.flushIfDue();
      expect(emissions, hasLength(1));
    });

    test('reset 清空定序与节流窗口：新会话首拍立即、重新定序', () {
      coalescer.accept([
        entry('dev-A', 'IOS-Vlink', -58),
        entry('dev-B', 'OBD Adapter', -45),
      ]);
      expect(emissions.last.map((e) => e.id), ['dev-B', 'dev-A']);

      coalescer.reset();
      expect(coalescer.entries, isEmpty);
      now = now.add(const Duration(milliseconds: 100));
      coalescer.accept([
        entry('dev-A', 'IOS-Vlink', -35),
        entry('dev-B', 'OBD Adapter', -80),
      ]);
      expect(emissions, hasLength(2), reason: 'reset 后首拍立即');
      expect(emissions.last.map((e) => e.id), ['dev-A', 'dev-B']);
    });
  });
}
