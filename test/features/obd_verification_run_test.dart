// 一键验证 run 协议单测（2026-11-15，架构审查 C2）：用假命令执行器
// 驱动完整序列，锁头块与日志块逐字格式、超时继续 / 链路失败中止、
// 默认头恢复与中止行时序、执行器意外异常的归类。
//
// 时钟固定注入（日志时间戳确定性）；执行器零真实链路——与
// obd_verification_test.dart 的纯枚举测试互补：那边锁命令清单，这边
// 锁「怎么发、怎么收尾、日志长什么样」。
import 'package:flutter_test/flutter_test.dart';

import 'package:lunio/features/shell/diagnostics/elm327_session.dart';
import 'package:lunio/features/shell/diagnostics/obd_verification.dart';
import 'package:lunio/features/shell/diagnostics/obd_verification_commands.dart';
import 'package:lunio/features/shell/diagnostics/obd_verification_run.dart';

const _stamp = '2026-11-15T10:00:00.000';

/// 假执行器的一步脚本。
sealed class _Step {
  const _Step();
}

final class _Frame extends _Step {
  const _Frame(this.text);

  final String text;
}

final class _Timeout extends _Step {
  const _Timeout();
}

final class _Failure extends _Step {
  const _Failure();
}

/// run 装具：记录发送命令与日志块，按脚本返回结果。
class _Harness {
  _Harness({Map<String, _Step>? script, Set<String>? throwing})
      : script = script ?? const {},
        throwing = throwing ?? const {};

  final Map<String, _Step> script;
  final Set<String> throwing;
  final List<String> sent = [];
  final List<String> blocks = [];

  Future<ObdVerificationResult> run() {
    return runObdVerification(
      carLabel: '思域 2022',
      now: () => DateTime(2026, 11, 15, 10, 0, 0),
      onLog: blocks.add,
      send: (command) async {
        sent.add(command);
        if (throwing.contains(command)) {
          throw StateError('boom:$command');
        }
        final step = script[command] ?? const _Frame('OK');
        return switch (step) {
          _Frame(:final text) => ObdCommandFrame(text),
          _Timeout() => ObdCommandTimeout(
              Elm327TimeoutException(command),
            ),
          _Failure() => const ObdCommandFailure(
              Elm327SessionException('链路已断开'),
            ),
        };
      },
    );
  }
}

void main() {
  group('run 协议', () {
    test('头块逐字、序列与恢复头、位图枚举、日志拼接', () async {
      final harness = _Harness(script: {
        'ATI': const _Frame('ELM327 v2.3\r\r'),
        'ATDPN': const _Frame('A6'),
        'ATRV': const _Frame('12.1V\r\r'),
        // 0100 位图 = 本车实测三 ECU 帧：快照段内支持 04/0B/0C/0D/11。
        '0100':
            const _Frame('41 00 90 18 80 11\r41 00 B6 3C A8 13\r41 00 90 18 80 03\r\r'),
      });

      final result = await harness.run();

      expect(
        harness.blocks.first,
        'Lunio OBD 一键检测日志\n'
        '车辆：思域 2022\n'
        '开始：$_stamp\n'
        '说明：标准 PID 为内置与模板快照集经本车能力位图过滤（0100–01A0）；'
        'DTC 03/07/0A 标准读取；私有 DID 只读 227029（油量交叉验证）；'
        '末尾 ATSH DB 33 F1 恢复。\n\n',
      );
      // 命令 / 响应块逐字（时间戳 + CR 归一）。
      expect(harness.blocks[1], '[$_stamp] > ATI\n');
      expect(harness.blocks[2], '[$_stamp] ELM327 v2.3\n');

      expect(
        harness.sent.take(5).toList(),
        ['ATI', 'ATDPN', 'ATRV', 'ATSHDB33F1', '0100'],
      );
      expect(
        harness.sent,
        containsAllInOrder(['0104', '010B', '010C', '010D', '0111']),
      );
      expect(harness.sent, containsAllInOrder(['03', '07', '0A']));
      expect(
        harness.sent,
        containsAllInOrder(['ATSHDA60F1', '227029']),
      );
      expect(harness.sent.last, 'ATSHDB33F1');

      expect(result.aborted, isFalse);
      expect(result.error, isNull);
      expect(result.log, harness.blocks.join());
    });

    test('单条超时记 ERROR 后继续，位图缺失按无支持处理', () async {
      final harness = _Harness(script: {'0100': const _Timeout()});

      final result = await harness.run();

      expect(harness.sent, contains('0120'));
      expect(
        harness.blocks,
        contains(
          '[$_stamp] ERROR: Elm327SessionException: '
          '指令 0100 等提示符超时\n',
        ),
      );
      expect(result.aborted, isFalse);
    });

    test('链路失败中止整轮：后续命令不再发，恢复头仍尝试，中止行最后落', () async {
      final harness = _Harness(script: {'227029': const _Failure()});

      final result = await harness.run();

      expect(result.aborted, isTrue);
      expect('${result.error}', contains('链路已断开'));
      final failureIndex = harness.sent.indexOf('227029');
      expect(harness.sent.sublist(failureIndex + 1), ['ATSHDB33F1']);
      expect(
        harness.blocks,
        contains(
          '[$_stamp] ERROR: Elm327SessionException: 链路已断开\n',
        ),
      );
      expect(
        harness.blocks.last,
        '[$_stamp] 检测中止：Elm327SessionException: 链路已断开'
        '（默认头已恢复）\n',
      );
    });

    test('中止后恢复头失败：中止行写明恢复失败', () async {
      final harness = _Harness(script: {
        '227029': const _Failure(),
        'ATSHDB33F1': const _Timeout(),
      });

      final result = await harness.run();

      expect(result.aborted, isTrue);
      expect(
        harness.blocks.last,
        '[$_stamp] 检测中止：Elm327SessionException: 链路已断开'
        '（恢复失败：Elm327SessionException: 指令 ATSHDB33F1 等提示符超时）\n',
      );
    });

    test('执行器意外抛异常：记 ERROR 后继续（不中止）', () async {
      final harness = _Harness(throwing: {'ATDPN'});

      final result = await harness.run();

      expect(harness.sent, contains('ATRV'));
      expect(
        harness.blocks,
        contains('[$_stamp] ERROR: Bad state: boom:ATDPN\n'),
      );
      expect(result.aborted, isFalse);
    });
  });

  test('脚本默认帧不阻断私有 DID 分组（分组头按组设置）', () async {
    final harness = _Harness();
    await harness.run();

    final headers = obdVendorCommandGroups
        .map((group) => 'ATSH${group.header}')
        .toList();
    expect(harness.sent, containsAllInOrder(headers));
    expect(
      harness.sent,
      containsAllInOrder(
        obdVendorCommandGroups.expand((group) => group.commands).toList(),
      ),
    );
    // 标准采集命令仍排在私有 DID 之前。
    expect(
      harness.sent.indexOf('03'),
      lessThan(harness.sent.indexOf('ATSHDA60F1')),
    );
    expect(obdSupportQueries.every(harness.sent.contains), isTrue);
  });
}