import 'package:flutter_test/flutter_test.dart';
import 'package:lunio/domain/rules/diagnostics_rules.dart';

void main() {
  group('水温色档（2026-11-18 五段拍板）', () {
    test('<50 红（冷启动磨损窗口）', () {
      expect(
        DiagnosticsRules.coolantTempTone(49),
        DiagnosticsReadingTone.danger,
      );
    });
    test('50-80 黄（升温中）', () {
      expect(
        DiagnosticsRules.coolantTempTone(50),
        DiagnosticsReadingTone.warning,
      );
      expect(
        DiagnosticsRules.coolantTempTone(79),
        DiagnosticsReadingTone.warning,
      );
    });
    test('80-100 绿（最佳工作状态）', () {
      expect(
        DiagnosticsRules.coolantTempTone(80),
        DiagnosticsReadingTone.normal,
      );
      expect(
        DiagnosticsRules.coolantTempTone(95),
        DiagnosticsReadingTone.normal,
      );
      expect(
        DiagnosticsRules.coolantTempTone(100),
        DiagnosticsReadingTone.normal,
      );
    });
    test('100-105 黄（风扇启动区间缓冲）', () {
      expect(
        DiagnosticsRules.coolantTempTone(101),
        DiagnosticsReadingTone.warning,
      );
      expect(
        DiagnosticsRules.coolantTempTone(105),
        DiagnosticsReadingTone.warning,
      );
    });
    test('>105 红（真过热）', () {
      expect(
        DiagnosticsRules.coolantTempTone(106),
        DiagnosticsReadingTone.danger,
      );
    });
  });

  group('电压色档', () {
    test('<11.5 红（严重亏电）', () {
      expect(
        DiagnosticsRules.batteryVoltageTone(11.4),
        DiagnosticsReadingTone.danger,
      );
    });
    test('11.5~14.8 绿（静置/充电正常带）', () {
      expect(
        DiagnosticsRules.batteryVoltageTone(11.5),
        DiagnosticsReadingTone.normal,
      );
      expect(
        DiagnosticsRules.batteryVoltageTone(12.5),
        DiagnosticsReadingTone.normal,
      );
      expect(
        DiagnosticsRules.batteryVoltageTone(13.8),
        DiagnosticsReadingTone.normal,
      );
      expect(
        DiagnosticsRules.batteryVoltageTone(14.8),
        DiagnosticsReadingTone.normal,
      );
    });
    test('>14.8 红（过充）', () {
      expect(
        DiagnosticsRules.batteryVoltageTone(14.9),
        DiagnosticsReadingTone.danger,
      );
    });
  });

  group('燃油修正色档', () {
    test('±10 内绿（健康）', () {
      expect(
        DiagnosticsRules.fuelTrimTone(0),
        DiagnosticsReadingTone.normal,
      );
      expect(
        DiagnosticsRules.fuelTrimTone(10),
        DiagnosticsReadingTone.normal,
      );
      expect(
        DiagnosticsRules.fuelTrimTone(-10),
        DiagnosticsReadingTone.normal,
      );
    });
    test('±10~15 黄', () {
      expect(
        DiagnosticsRules.fuelTrimTone(10.1),
        DiagnosticsReadingTone.warning,
      );
      expect(
        DiagnosticsRules.fuelTrimTone(15),
        DiagnosticsReadingTone.warning,
      );
      expect(
        DiagnosticsRules.fuelTrimTone(-15),
        DiagnosticsReadingTone.warning,
      );
    });
    test('超 ±15 红', () {
      expect(
        DiagnosticsRules.fuelTrimTone(15.1),
        DiagnosticsReadingTone.danger,
      );
      expect(
        DiagnosticsRules.fuelTrimTone(-20),
        DiagnosticsReadingTone.danger,
      );
    });
  });

  group('display 文本解析（2026-11-19 回退染色修复）', () {
    test('水温/CVT/电压 display 格式解析成功', () {
      expect(DiagnosticsRules.parseDisplayNumber('95℃', '℃'), 95.0);
      expect(DiagnosticsRules.parseDisplayNumber('69℃', '℃'), 69.0);
      expect(DiagnosticsRules.parseDisplayNumber('11.2V', 'V'), 11.2);
    });

    test('格式不符/非数值返回 null（不染兜底）', () {
      expect(DiagnosticsRules.parseDisplayNumber('66,068 km', '℃'), isNull);
      expect(DiagnosticsRules.parseDisplayNumber('95', '℃'), isNull);
      expect(DiagnosticsRules.parseDisplayNumber('℃', '℃'), isNull);
      expect(DiagnosticsRules.parseDisplayNumber('abc℃', '℃'), isNull);
    });
  });
}
