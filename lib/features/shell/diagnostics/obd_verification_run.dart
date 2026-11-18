// 一键检测 run 协议（ADR 0023）：命令序列 + 默认头恢复 + 日志组装。
//
// 从调试终端 widget 收编（2026-11-15，架构审查 C2）：widget 只负责暂停
// 轮询、渲染日志与复制；本模块拥有「发什么、按什么顺序发、日志长什么
// 样、结束时怎么收尾」。纯 Dart：不 import 会话与 BuildContext，命令
// 执行器、时钟、日志出口经注入——单测直接驱动假执行器，零真实链路。
//
// ≈ Java 的批处理 Job 类：命令清单是 Job 参数，execute ≈ 跑完整轮，
// 日志经回调逐条吐出（≈ Appender），收尾的默认头恢复在 finally 里。
//
// 语义（2026-11-15 拍板）：
// - 单条超时 / 意外错误：记 ERROR 后继续（宽扫的正常噪声）；
// - 链路 / 会话级失败：记 ERROR 后中止整轮，不再发后续命令；
// - 默认头恢复：正常结束与中止路径都在 finally 里尝试 ATSH DB33F1，
//   失败只记日志不再中止；中止行在恢复尝试之后落日志，写清恢复结果；
// - 日志格式与旧 widget 实现逐字一致（分析方按它读日志）。
import 'elm327_parser.dart' show normalizeObdCommand;
import 'obd_verification.dart';
import 'obd_verification_commands.dart';

/// 单条命令的执行结果（命令执行器 seam 的返回值）。
sealed class ObdCommandOutcome {
  const ObdCommandOutcome();
}

/// 收到完整帧（提示符前的原始文本，可能含 CR 分片残留）。
final class ObdCommandFrame extends ObdCommandOutcome {
  const ObdCommandFrame(this.frame);

  final String frame;
}

/// 单条超时：记 ERROR 后继续。
final class ObdCommandTimeout extends ObdCommandOutcome {
  const ObdCommandTimeout(this.error);

  final Object error;
}

/// 单条意外错误（执行器自身抛异常的兜底归类）：记 ERROR 后继续。
final class ObdCommandError extends ObdCommandOutcome {
  const ObdCommandError(this.error);

  final Object error;
}

/// 链路 / 会话级失败：该条记 ERROR 后中止整轮。
final class ObdCommandFailure extends ObdCommandOutcome {
  const ObdCommandFailure(this.error);

  final Object error;
}

/// run 的最终结果。
class ObdVerificationResult {
  const ObdVerificationResult({
    required this.log,
    required this.aborted,
    this.error,
  });

  /// 完整日志文本（头块 + 逐条时间戳块 + 可能的中止行）。
  final String log;

  /// 是否因链路 / 会话级失败中止。
  final bool aborted;

  /// 中止原因（[aborted] 为 true 时非空）。
  final Object? error;
}

/// 跑一轮一键检测：读能力位图 → 发快照集 ∩ 本车位图 → DTC → 私有 DID
/// 227029 → 恢复默认头。日志经 [onLog] 逐块吐出（块已含时间戳 / 换行），
/// 返回值同时携带完整文本与中止事实。
///
/// [send] 为命令执行器 seam：返回帧 / 超时 / 误差分类由调用方 adapter
/// 决定（诊断页把 `Elm327TimeoutException` 映射超时、其余会话异常映射
/// 失败）；本函数不 import 会话类型。执行器自身抛异常按单条错误继续。
/// [now] 时钟注入（默认 DateTime.now），单测固定时间断言日志格式。
Future<ObdVerificationResult> runObdVerification({
  required String carLabel,
  required Future<ObdCommandOutcome> Function(String command) send,
  required void Function(String block) onLog,
  DateTime Function()? now,
}) async {
  final clock = now ?? DateTime.now;
  final buffer = StringBuffer();

  void emit(String block) {
    buffer.write(block);
    onLog(block);
  }

  void emitLine(String text) {
    emit('[${clock().toIso8601String()}] $text\n');
  }

  // 旧 `_append` 的归一化口径：CRLF/CR → LF、去尾部空白（帧尾常有 \r\r）。
  String normalizeFrame(String frame) =>
      frame.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trimRight();

  Future<ObdCommandOutcome> capture(
    String command, {
    required bool abortOnFailure,
  }) async {
    final normalized = normalizeObdCommand(command);
    emitLine('> $normalized');
    ObdCommandOutcome outcome;
    try {
      outcome = await send(normalized);
    } catch (error) {
      // 执行器自身抛异常（理论上不该发生）：归单条错误、继续（拍板）。
      outcome = ObdCommandError(error);
    }
    switch (outcome) {
      case ObdCommandFrame(:final frame):
        emitLine(normalizeFrame(frame));
      case ObdCommandTimeout(:final error):
        emitLine('ERROR: $error');
      case ObdCommandError(:final error):
        emitLine('ERROR: $error');
      case ObdCommandFailure(:final error):
        emitLine('ERROR: $error');
        if (abortOnFailure) {
          throw _VerificationAborted(error);
        }
    }
    return outcome;
  }

  emit(
    'Lunio OBD 一键检测日志\n'
    '车辆：$carLabel\n'
    '开始：${clock().toIso8601String()}\n'
    '说明：标准 PID 为模板快照集经本车能力位图过滤（0100–01A0，信息卡'
    '内置四条已实时轮询不重复采）；DTC 03/07/0A 标准读取；私有 DID 三'
    '段只读（仪表 227029/22702A/227060/227028/227022、TCM 222301 CVT '
    '油温、ECM 222666 机油温度，候选验证）；末尾 ATSH DB 33 F1 恢复。'
    '\n\n',
  );

  Object? abortError;
  ObdCommandOutcome? restoreOutcome;
  try {
    await capture('ATI', abortOnFailure: true);
    await capture('ATDPN', abortOnFailure: true);
    await capture('ATRV', abortOnFailure: true);
    await capture('ATSH DB33F1', abortOnFailure: true);
    final supportFrames = <String, String>{};
    for (final command in obdSupportQueries) {
      final outcome = await capture(command, abortOnFailure: true);
      if (outcome is ObdCommandFrame) {
        supportFrames[command] = outcome.frame;
      }
    }
    for (final command in buildSnapshotVerificationCommands(supportFrames)) {
      await capture(command, abortOnFailure: true);
    }
    for (final group in obdVendorCommandGroups) {
      await capture('ATSH ${group.header}', abortOnFailure: true);
      for (final command in group.commands) {
        await capture(command, abortOnFailure: true);
      }
    }
  } on _VerificationAborted catch (aborted) {
    abortError = aborted.cause;
  } finally {
    // 默认头恢复：正常结束与中止路径都尝试；失败只记日志、不再中止。
    restoreOutcome = await capture('ATSH DB33F1', abortOnFailure: false);
  }

  if (abortError != null) {
    // 中止行在恢复尝试之后：最后几行写清「到底恢没恢复」，读日志不用回翻。
    final restoreCopy = switch (restoreOutcome) {
      ObdCommandFrame() => '默认头已恢复',
      ObdCommandTimeout(:final error) => '恢复失败：$error',
      ObdCommandError(:final error) => '恢复失败：$error',
      ObdCommandFailure(:final error) => '恢复失败：$error',
    };
    emitLine('检测中止：$abortError（$restoreCopy）');
  }

  return ObdVerificationResult(
    log: buffer.toString(),
    aborted: abortError != null,
    error: abortError,
  );
}

/// 内部中止信号：链路 / 会话级失败时打断嵌套的命令序列。
class _VerificationAborted implements Exception {
  _VerificationAborted(this.cause);

  final Object cause;
}