// 一键采集编排单测：用 2026-11-15 实车日志的 0100/0120/0140/0160
// 三 ECU 位图锁标准 PID 自动枚举；用 OBDb 2022 支持清单锁私有 DID 组。
import 'package:flutter_test/flutter_test.dart';
import 'package:lunio/features/shell/diagnostics/obd_verification.dart';
import 'package:lunio/features/shell/diagnostics/obd_verification_commands.dart';

void main() {
  group('decodeSupportedPids（本车日志）', () {
    test('0100 三 ECU 位图并集，不含 05/0F/10', () {
      const frame =
          '41 00 90 18 80 11 \r41 00 B6 3C A8 13 \r41 00 90 18 80 03 \r\r';
      final pids = decodeSupportedPids(frame, sentCommand: '0100');
      expect(
        pids,
        containsAll([1, 3, 4, 6, 7, 11, 12, 13, 14, 17, 19, 21, 28, 31, 32]),
      );
      expect(pids, isNot(contains(5)));
      expect(pids, isNot(contains(15)));
      expect(pids, isNot(contains(16)));
    });

    test('0120/0140/0160 位图', () {
      const frame0120 =
          '41 20 00 00 00 01 \r41 20 B0 07 A0 11 \r41 20 80 00 A0 01 \r\r';
      expect(
        decodeSupportedPids(frame0120, sentCommand: '0120'),
        containsAll([0x21, 0x23, 0x24, 0x2E, 0x2F, 0x31, 0x33, 0x3C, 0x40]),
      );
      const frame0140 =
          '41 40 40 00 00 01 \r41 40 F2 C2 8C 01 \r41 40 C0 80 00 01 \r\r';
      expect(
        decodeSupportedPids(frame0140, sentCommand: '0140'),
        containsAll([
          0x41,
          0x42,
          0x43,
          0x44,
          0x47,
          0x49,
          0x4A,
          0x4F,
          0x51,
          0x55,
          0x56,
          0x60,
        ]),
      );
      const frame0160 =
          '41 60 02 00 00 00 \r41 60 07 11 40 01 \r41 60 02 10 00 00 \r\r';
      expect(
        decodeSupportedPids(frame0160, sentCommand: '0160'),
        containsAll([0x66, 0x67, 0x68, 0x6C, 0x70, 0x72, 0x80]),
      );
    });

    test('mode 09/06 的 00 位图解出各自支持项', () {
      expect(
        decodeSupportedPids(
          '49 00 40 00 00 00 \r\r',
          sentCommand: '0900',
        ),
        {0x02},
      );
      expect(
        decodeSupportedPids(
          '46 00 80 00 00 00 \r\r',
          sentCommand: '0600',
        ),
        {0x01},
      );
    });
  });

  group('buildStandardVerificationCommands', () {
    test('本车日志：枚举全部支持项，排除不支持与段边界', () {
      final commands = buildStandardVerificationCommands(const {
        '0100': '41 00 90 18 80 11 \r41 00 B6 3C A8 13 \r41 00 90 18 80 03 \r\r',
        '0120': '41 20 00 00 00 01 \r41 20 B0 07 A0 11 \r41 20 80 00 A0 01 \r\r',
        '0140': '41 40 40 00 00 01 \r41 40 F2 C2 8C 01 \r41 40 C0 80 00 01 \r\r',
        '0160': '41 60 02 00 00 00 \r41 60 07 11 40 01 \r41 60 02 10 00 00 \r\r',
      });
      expect(
        commands,
        containsAll([
          '0104',
          '010B',
          '010C',
          '010D',
          '010E',
          '0111',
          '012F',
          '0142',
          '0149',
          '014A',
          '014F',
          '0151',
          '0155',
          '0156',
          '0166',
          '0168',
          '016C',
          '0170',
          '0172',
          '03',
          '07',
          '0A',
        ]),
      );
      expect(commands, isNot(contains('0105')));
      expect(commands, isNot(contains('010F')));
      expect(commands, isNot(contains('0110')));
      expect(commands, isNot(contains('0120')));
      expect(commands, isNot(contains('0140')));
      expect(commands, isNot(contains('0160')));
    });

    test('09/06 支持位图 → 09xx/06xx 命令', () {
      final commands = buildStandardVerificationCommands(const {
        '0900': '49 00 40 00 00 00 \r\r',
        '0600': '46 00 80 00 00 00 \r\r',
      });
      expect(commands, containsAll(['0902', '0601', '03', '07', '0A']));
    });
  });

  group('obdVendorCommandGroups', () {
    test('OBDb 2022 支持清单含本车已验证 DID，不含 2023+/老款专属项', () {
      final all = obdVendorCommandGroups
          .expand((group) => group.commands)
          .toSet();
      expect(
        all,
        containsAll(['227029', '22267A', '222623', '222678', '222681', '22268E']),
      );
      expect(all, isNot(contains('22202C')));
      expect(all, isNot(contains('2223E2')));
      expect(all, isNot(contains('222516')));
      expect(
        obdVendorCommandGroups.map((group) => group.header),
        contains('DA60F1'),
      );
    });
  });
}