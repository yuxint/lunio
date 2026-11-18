import 'package:flutter_test/flutter_test.dart';
import 'package:lunio/domain/rules/diagnostics_rules.dart';

void main() {
  group('水温色档（2026-11-17 拍板口径）', () {
    test('<70 灰（冷车，非警告）', () {
      expect(
        DiagnosticsRules.coolantTempTone(69),
        DiagnosticsReadingTone.muted,
      );
    });
    test('70-85 黄（未达最佳）', () {
      expect(
        DiagnosticsRules.coolantTempTone(70),
        DiagnosticsReadingTone.warning,
      );
      expect(
        DiagnosticsRules.coolantTempTone(84),
        DiagnosticsReadingTone.warning,
      );
    });
    test('85-100 绿（最佳工作状态）', () {
      expect(
        DiagnosticsRules.coolantTempTone(85),
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
    test('>100 红（过热）', () {
      expect(
        DiagnosticsRules.coolantTempTone(101),
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
}
