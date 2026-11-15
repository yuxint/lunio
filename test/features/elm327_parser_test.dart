// ELM327 解析纯函数模块单测（票 04）：语料全部摘自实车日志
// docs/car_obd_link/data/IOS-Vlink.txt（209ms 分片双通知、三 ECU 并
// 发、NO DATA、独立提示符帧、多行帧编号）。
//
// 只测外部行为：喂字节 → 收帧/收解析结果，不测私有内部结构。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lunio/domain/entities/diagnostics_parse_type.dart';
import 'package:lunio/features/shell/diagnostics/elm327_parser.dart';

List<int> bytes(String text) => latin1.encode(text);

void main() {
  group('normalizeObdCommand', () {
    test('大写 + 去空白（ATSP 7 与 01 2F 两种形态）', () {
      expect(normalizeObdCommand('ATSP 7'), 'ATSP7');
      expect(normalizeObdCommand('01 2f'), '012F');
      expect(normalizeObdCommand('atrv'), 'ATRV');
    });
  });

  group('ObdFrameAssembler 组帧', () {
    test('209ms 分片双通知组装出完整帧（012F 语料形态）', () {
      final assembler = ObdFrameAssembler();
      expect(
        assembler.push(bytes('41 2F 60 \r')),
        isEmpty,
      );
      expect(assembler.hasPendingBytes, isTrue);
      expect(assembler.push(bytes('\r>')), ['41 2F 60 \r\r']);
      expect(assembler.hasPendingBytes, isFalse);
    });

    test('独立 > 提示符帧不丢不粘', () {
      final assembler = ObdFrameAssembler();
      // 语料 ATSP 6 形态：OK\r\r 与裸 3E 分两次通知。
      expect(assembler.push(bytes('OK\r\r')), isEmpty);
      expect(assembler.push(bytes('>')), ['OK\r\r']);
      // 语料 012F 形态：\r> 独立帧 + 后续数据帧互不粘连。
      expect(assembler.push(bytes('\r>')), ['\r']);
      expect(assembler.push(bytes('41 05 82 \r\r>')), ['41 05 82 \r\r']);
    });

    test('一次通知含两个提示符时提交两帧', () {
      final assembler = ObdFrameAssembler();
      expect(
        assembler.push(bytes('41 2F 60 \r\r>41 05 82 \r\r>')),
        ['41 2F 60 \r\r', '41 05 82 \r\r'],
      );
    });
  });

  group('obdFrameLines 行提取与去回显', () {
    test('按 CR 拆行去空行（0100 三 ECU 语料形态）', () {
      expect(
        obdFrameLines(
          '41 00 90 18 80 11 \r41 00 B6 3C A8 13 \r41 00 90 18 80 03 \r\r',
          sentCommand: '0100',
        ),
        [
          '41 00 90 18 80 11',
          '41 00 B6 3C A8 13',
          '41 00 90 18 80 03',
        ],
      );
    });

    test('回显行防御性剥除（ATD 复位后 0103 语料形态）', () {
      expect(
        obdFrameLines(
          '0103\rNO DATA\r\r',
          sentCommand: '0103',
        ),
        ['NO DATA'],
      );
    });
  });

  group('多 ECU 按请求 PID 匹配', () {
    test('0100 三响应取 41 00 目标行', () {
      final lines = [
        '41 00 90 18 80 11',
        '41 00 B6 3C A8 13',
        '41 00 90 18 80 03',
      ];
      expect(matchResponseLine(lines, '0100'), lines.first);
    });

    test('AT 指令恒不 PID 匹配', () {
      expect(matchResponseLine(['OK'], 'ATRV'), isNull);
    });

    test('混应答：NO DATA 行 + 数据行，PID 匹配跳过错误行', () {
      final lines = ['NO DATA', '41 2F 60'];
      expect(matchResponseLine(lines, '012F'), '41 2F 60');
    });
  });

  group('parseProbeResponse 公式枚举四类', () {
    test('油量 41 2F 60 → 37.6%（实测 96×100/255）', () {
      final reading = parseProbeResponse(
        command: '012F',
        parseType: DiagnosticsParseType.fuelLevel,
        frameText: '41 2F 60 \r\r',
      ) as ObdValue;
      expect(reading.percent!, closeTo(37.647, 0.001));
      expect(reading.display, '37.6%');
    });

    test('水温 41 05 82 → 90℃（A−40）', () {
      final reading = parseProbeResponse(
        command: '0105',
        parseType: DiagnosticsParseType.coolantTemp,
        frameText: '41 05 82 \r\r',
      ) as ObdValue;
      expect(reading.celsius, 90);
      expect(reading.display, '90℃');
    });

    test('电压文本 11.2V（ATRV 语料形态）', () {
      final reading = parseProbeResponse(
        command: 'ATRV',
        parseType: DiagnosticsParseType.voltageText,
        frameText: '11.2V\r\r',
      ) as ObdValue;
      expect(reading.display, '11.2V');
    });

    test('进气压力 41 0B 65 → 101 kPa', () {
      final reading = parseProbeResponse(
        command: '010B',
        parseType: DiagnosticsParseType.mapPressure,
        frameText: '41 0B 65 \r\r',
      ) as ObdValue;
      expect(reading.display, '101 kPa');
    });

    test('rawHex：多行帧编号原文照显（227029 语料形态）', () {
      final frame =
          '039 \r0: 62 70 29 8F FC 00 \r1: 00 00 00 2F FF FF 06 CF \r\r';
      final reading = parseProbeResponse(
        command: '227029',
        parseType: DiagnosticsParseType.rawHex,
        frameText: frame,
      ) as ObdValue;
      expect(
        reading.display,
        '039 0: 62 70 29 8F FC 00 1: 00 00 00 2F FF FF 06 CF',
      );
    });

    test('rawHex：文本响应原文照显（story 24 至少能看到原文）', () {
      final reading = parseProbeResponse(
        command: 'ATRV',
        parseType: DiagnosticsParseType.rawHex,
        frameText: '11.2V\r\r',
      ) as ObdValue;
      expect(reading.display, '11.2V');
    });

    test('NO DATA / CAN ERROR 映射无数据', () {
      expect(
        parseProbeResponse(
          command: '019D',
          parseType: DiagnosticsParseType.fuelLevel,
          frameText: 'NO DATA\r\r',
        ),
        isA<ObdNoData>(),
      );
      expect(
        parseProbeResponse(
          command: '019D',
          parseType: DiagnosticsParseType.rawHex,
          frameText: 'CAN ERROR\r\r',
        ),
        isA<ObdNoData>(),
      );
    });

    test('混应答：fuelLevel 跳过 NO DATA 行取到值（单点失败不连坐）', () {
      final reading = parseProbeResponse(
        command: '012F',
        parseType: DiagnosticsParseType.fuelLevel,
        frameText: 'NO DATA\r41 2F 60 \r\r',
      ) as ObdValue;
      expect(reading.percent!, closeTo(37.647, 0.001));
    });
  });
}
