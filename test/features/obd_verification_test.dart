// 一键检测编排单测：用 2026-11-15/16 实车日志的位图语料锁「快照集 ∩
// 位图支持集」过滤；锁定精简后的私有 DID 组（只留 227029）。
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

  group('buildSnapshotVerificationCommands', () {
    test('本车日志位图：5 项快照全过 + DTC（01A6/0142 升内置、燃油修正探针在轮询）', () {
      final commands = buildSnapshotVerificationCommands(const {
        '0100': '41 00 90 18 80 11 \r41 00 B6 3C A8 13 \r41 00 90 18 80 03 \r\r',
        '0120': '41 20 00 00 00 01 \r41 20 B0 07 A0 11 \r41 20 80 00 A0 01 \r\r',
        '0140': '41 40 40 00 00 01 \r41 40 F2 C2 8C 01 \r41 40 C0 80 00 01 \r\r',
        '0160': '41 60 02 00 00 00 \r41 60 07 11 40 01 \r41 60 02 10 00 00 \r\r',
        '01A0': '41 A0 24 00 00 00 \r\r',
      });
      expect(commands, [
        '0104',
        '010B',
        '010C',
        '010D',
        '0111',
        '03',
        '07',
        '0A',
      ]);
    });

    test('位图只有 0100 段：段外快照项被过滤（支持集是过滤闸门）', () {
      final commands = buildSnapshotVerificationCommands(const {
        '0100': '41 00 90 18 80 11 \r41 00 B6 3C A8 13 \r41 00 90 18 80 03 \r\r',
      });
      expect(commands, ['0104', '010B', '010C', '010D', '0111', '03', '07', '0A']);
    });
  });

  group('obdVendorCommandGroups', () {
    test('2026-11-21 两组：仪表段四条 + TCM 已转正（227060/ECM 段撤除）', () {
      expect(obdVendorCommandGroups, hasLength(2));
      expect(obdVendorCommandGroups[0].header, 'DA60F1');
      expect(obdVendorCommandGroups[0].commands,
          ['227029', '22702A', '227028', '227022']);
      expect(obdVendorCommandGroups[1].header, 'DA1EF1');
      expect(obdVendorCommandGroups[1].commands, ['222301']);
      // 227060（原以为的保养余量）四次一键检测恒回 7F 22 31，与 222666
      // 同一条 NRC，2026-11-21 起与 ECM 段一起不进快照链。
      expect(
        obdVendorCommandGroups.expand((g) => g.commands),
        isNot(contains('227060')),
      );
      // 机油温度候选（DA10F1 的 222666/22261A/22262A）本车恒回 NRC 31，
      // 2026-11-20 起不再进这条只读快照链。
      expect(
        obdVendorCommandGroups.map((g) => g.header),
        isNot(contains('DA10F1')),
      );
    });
  });
}
