// OBD 会话日志模块（2026-11-18 拍板）：单次 OBD 连接期间的轮询读数
// 记录为 JSONL 文件（App 文档目录 obd_sessions/），支持列表/导出/删除，
// 保留策略 = 7 天 + 50 个文件双上限、超限删最旧。清理时机 = 每次新
// 建会话时顺带清理（2026-11-18 深审统一口径：长期不连接时过期文件
// 留到下次连接清，不设 App 启动钩子）。
//
// ≈ Java 的按日滚动的本地日志 Service：每个会话一个文件（类似按天
// 滚动），[ObdSessionLogStore] 是目录管家（列表/删除/清理），[ObdSess
// ionLogRecorder] 是单会话追加写手（≈ Logger with FileHandler）。纯
// Dart + dart:io，目录经构造注入可测（临时目录单测）。
//
// 行契约（JSONL，一行一个 JSON 对象）：
//  {"t":"start","at":"ISO8601","device":"xx","mock":false}   会话头
//  {"t":"r","probe":"水温","cmd":"0167","v":"95℃","at":"ISO"} 读数
//  {"t":"r","probe":"..","cmd":"..","v":null,"r":"超时","at":"ISO"}
//  {"t":"e","e":"disconnect","at":"ISO","reason":".."}        事件
//  {"t":"e","e":"verify","log":"..多行一键检测日志..","at":"ISO"}
//  {"t":"e","e":"lifecycle","s":"paused","at":"ISO"}          应用生命周期
//  {"t":"e","e":"fuel_gate","probe":"油量","raw":27.0,"held":40.0,
//   "n":3,"span":13.0,"at":"ISO"}                            油量门限拒绝
//
// 生命周期行（2026-11-20 拍板）：诊断页/主壳层把 AppLifecycleState.name
// 原样上报，用于归因轮询空档。三种空档的日志形态互斥——App 挂起：
// paused/resumed 成对出现、中间无任何行；链路卡死：每条指令都有
// 超时行（`"r":"超时"`）；调试终端独占链路：verify 段整段日志。没有
// 生命周期行时无法区分前两者，这是本行的唯一目的。
//
// 油量门限行（2026-11-21 拍板）：`012F` 的原始值一律进读数行，被门限
// 丢掉的那拍另记一行 fuel_gate（raw = 本拍原始值、held = 卡片保持值、
// n/span = 当前窗口样本数与极差）。没有这一行时，日志里看起来「卡片
// 跳了」而实际是「原始值跳了、卡片没动」，事后无法区分。
//
// 文件命名：session-<yyyyMMdd-HHmmss>.jsonl（连接建立时刻，用户拍板
// 「以连接的日期时分秒来命名」）。
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path_provider/path_provider.dart';

import '../../../domain/entities/diagnostics_probe.dart';
import 'elm327_parser.dart';

/// 会话日志文件条目（列表页展示用）。
class ObdSessionLogEntry {
  const ObdSessionLogEntry({
    required this.fileName,
    required this.startedAt,
    required this.lineCount,
    required this.bytes,
  });

  /// 文件名（session-yyyyMMdd-HHmmss.jsonl）。
  final String fileName;

  /// 会话开始时刻（从文件名解析）。
  final DateTime startedAt;

  /// 行数（读数 + 事件）。
  final int lineCount;

  /// 文件字节数。
  final int bytes;
}

/// 会话日志存储管家：obd_sessions/ 目录下的列表/读取/删除/清理。
/// 目录经构造注入（生产走应用文档目录，测试注入临时目录）。
class ObdSessionLogStore {
  ObdSessionLogStore({required Directory directory})
      : _dir = directory;

  final Directory _dir;

  /// 生产装配：应用文档目录下的 obd_sessions/。
  static Future<ObdSessionLogStore> production() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/obd_sessions');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return ObdSessionLogStore(directory: dir);
  }

  /// 列出全部会话日志（按开始时刻倒序，新的在前）。
  Future<List<ObdSessionLogEntry>> list() async {
    if (!_dir.existsSync()) {
      return const [];
    }
    final entries = <ObdSessionLogEntry>[];
    await for (final file in _dir.list()) {
      if (file is! File || !file.path.endsWith('.jsonl')) {
        continue;
      }
      final name = file.uri.pathSegments.last;
      final startedAt = _parseSessionFileName(name);
      if (startedAt == null) {
        continue;
      }
      final stat = await file.stat();
      final content = await file.readAsString();
      final lineCount = content
          .split('\n')
          .where((line) => line.trim().isNotEmpty)
          .length;
      entries.add(ObdSessionLogEntry(
        fileName: name,
        startedAt: startedAt,
        lineCount: lineCount,
        bytes: stat.size,
      ));
    }
    entries.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return entries;
  }

  /// 读整个文件内容（导出用）；文件不存在返回空串。
  Future<String> readContent(String fileName) async {
    final file = File('${_dir.path}/$fileName');
    if (!await file.exists()) {
      return '';
    }
    return file.readAsString();
  }

  /// 删除一个会话日志文件。
  Future<void> delete(String fileName) async {
    final file = File('${_dir.path}/$fileName');
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// 保留策略清理（2026-11-18 拍板：7 天 + 50 个文件双上限，删最旧）。
  /// 返回删除的文件数。清理时机 = 每次新建会话时顺带清理（2026-11-18
  /// 深审统一口径；长期不连接时过期文件留到下次连接清）。
  ///
  /// 边界语义：开始时刻恰为 now - keepDays 的文件算「未过期」不删，
  /// 但计入 50 个文件上限（两条规则互补、不重叠不落空）。
  Future<int> cleanup({
    required DateTime now,
    int keepDays = 7,
    int keepMax = 50,
  }) async {
    final entries = await list();
    var deleted = 0;
    // 7 天过期：开始时刻早于 now - keepDays。
    final cutoff = now.subtract(Duration(days: keepDays));
    for (final entry in entries) {
      if (entry.startedAt.isBefore(cutoff)) {
        await delete(entry.fileName);
        deleted++;
      }
    }
    // 50 条上限：仍超限的按旧→新删。过滤必须与上面的删除条件互补
    // （!isBefore 含 cutoff 等号）：第一轮按 isBefore 删、恰好 7 天算保留，
    // 这些文件若不在这里计数，就会既不删也不计入上限，总数可停在 51。
    final remaining = (await list())
        .where((e) => !e.startedAt.isBefore(cutoff))
        .toList()
      ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
    while (remaining.length > keepMax) {
      await delete(remaining.first.fileName);
      remaining.removeAt(0);
      deleted++;
    }
    return deleted;
  }
}

/// 从文件名解析会话开始时刻（session-yyyyMMdd-HHmmss.jsonl；解析失败
/// 返回 null，坏名文件列表时跳过、清理按时刻排序时沉底）。
DateTime? _parseSessionFileName(String fileName) {
  final match =
      RegExp(r'^session-(\d{8})-(\d{6})\.jsonl$').firstMatch(fileName);
  if (match == null) {
    return null;
  }
  final d = match.group(1)!;
  final t = match.group(2)!;
  return DateTime(
    int.parse(d.substring(0, 4)),
    int.parse(d.substring(4, 6)),
    int.parse(d.substring(6, 8)),
    int.parse(t.substring(0, 2)),
    int.parse(t.substring(2, 4)),
    int.parse(t.substring(4, 6)),
  );
}

/// 单次会话记录器：connected 建、断开收尾；每次读数/事件追加一行
/// JSONL。文件名取会话开始时刻（时分秒命名）。
class ObdSessionLogRecorder {
  ObdSessionLogRecorder({required Directory directory})
      : _store = ObdSessionLogStore(directory: directory);

  final ObdSessionLogStore _store;
  File? _file;

  /// 文件名（记录中才有；列表页「当前会话」指示用）。
  String? get fileName => _file?.uri.pathSegments.last;

  /// 会话开始：创建文件并写 start 行。重复 start 抛 StateError。
  ///
  /// 同秒冲突（2026-11-18 深审修复）：同名文件已存在（同秒重连）时顺
  /// 延 1 秒重取文件名（至多 60 次），保持文件名可被 _parseSessionFileName
  /// 解析；60 次仍冲突抛 StateError（极端场景，不静默截断旧会话）。
  Future<void> start({
    required DateTime at,
    String? device,
    bool mock = false,
  }) async {
    if (_file != null) {
      throw StateError('会话日志已在记录中');
    }
    File? file;
    var stamp = at;
    for (var attempt = 0; attempt < 60; attempt++) {
      final candidate = File(
        '${_store._dir.path}/session-${_stamp(stamp)}.jsonl',
      );
      if (!candidate.existsSync()) {
        file = candidate;
        break;
      }
      stamp = stamp.add(const Duration(seconds: 1));
    }
    if (file == null) {
      throw StateError('会话日志文件名冲突（同秒 60 次）');
    }
    await file.writeAsString(
      jsonEncode({
        't': 'start',
        'at': at.toIso8601String(),
        'device': device,
        'mock': mock,
      }),
    );
    await file.writeAsString('\n', mode: FileMode.append);
    _file = file;
  }

  /// 追加一条读数（值或无数据都记；无数据带原因 r）。
  Future<void> appendReading({
    required String probeName,
    required String command,
    required String? display,
    required String? noDataReason,
    required DateTime at,
  }) async {
    final file = _file;
    if (file == null) {
      return;
    }
    final line = jsonEncode({
      't': 'r',
      'probe': probeName,
      'cmd': command,
      'v': display,
      'r': ?noDataReason,
      'at': at.toIso8601String(),
    });
    await file.writeAsString('$line\n', mode: FileMode.append);
  }

  /// 追加事件行（disconnect / verify 等）。
  Future<void> appendEvent({
    required String event,
    Map<String, Object?> extra = const {},
    required DateTime at,
  }) async {
    final file = _file;
    if (file == null) {
      return;
    }
    final line = jsonEncode({
      't': 'e',
      'e': event,
      ...extra,
      'at': at.toIso8601String(),
    });
    await file.writeAsString('$line\n', mode: FileMode.append);
  }

  /// 会话收尾（断开）：写 disconnect 行、置空句柄。幂等。
  Future<void> close({String? reason, required DateTime at}) async {
    if (_file == null) {
      return;
    }
    await appendEvent(event: 'disconnect', extra: {'reason': reason}, at: at);
    _file = null;
  }
}

/// 时刻 → 文件名时间戳段（yyyyMMdd-HHmmss，本地时刻）。
String _stamp(DateTime at) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${at.year}${two(at.month)}${two(at.day)}'
      '-${two(at.hour)}${two(at.minute)}${two(at.second)}';
}


/// controller 的会话日志接缝（plain-Dart 接口；测试注入假件断言调用）。
/// 生命周期：connected → onSessionStart、每次读数 → onProbeReading、
/// 断开 → onSessionEnd；一键检测日志 → onVerificationLog。
abstract class ObdSessionLogSink {
  /// 会话开始（连接成功）。
  void onSessionStart(DateTime at, {String? deviceId, bool mock = false});

  /// 一条轮询读数（值或无数据都记）。
  void onProbeReading(DiagnosticsProbe probe, ObdReading reading, DateTime at);

  /// 会话结束（断开）。
  void onSessionEnd(DateTime at, {String? reason});

  /// 一键检测整段日志（追加进当次会话文件）。
  void onVerificationLog(String log, DateTime at);

  /// 应用生命周期事件（2026-11-20）：`AppLifecycleState.name` 原样传
  /// 入（resumed/inactive/hidden/paused/detached）。无会话时静默丢弃
  /// ——同 [onProbeReading]，生命周期上报先于连接也照常调用。
  void onAppLifecycle(String state, DateTime at);

  /// 油量门限丢弃一拍（2026-11-21）：[raw] 本拍原始值、[held] 卡片保持
  /// 值、[samples]/[span] 当前窗口状态。原始读数已经由 [onProbeReading]
  /// 记过，本行只补「这一拍没被采用」的判定结果。
  void onFuelGateRejected({
    required String probeName,
    required double raw,
    required double? held,
    required int samples,
    required double? span,
    required DateTime at,
  });

  /// 当前正在记录的会话文件名（null = 无进行中会话）。列表页「正在记
  /// 录」指示与删除保护用（2026-11-18 深审修复：sheet 可删正在记录的
  /// 会话文件）。
  String? get currentRecordingFileName;
}

/// 生产实现：内部持 [ObdSessionLogRecorder]（懒建目录），所有异步写经
/// 内部 Future 链串行化（事件顺序 = 调用顺序）；每次新建会话时顺带跑
/// 保留策略清理（7 天/50 个，2026-11-18 深审统一口径）。
class ProductionObdSessionLogSink implements ObdSessionLogSink {
  ProductionObdSessionLogSink({ObdSessionLogStore? store})
      : _injectedStore = store;

  final ObdSessionLogStore? _injectedStore;
  ObdSessionLogStore? _store;
  ObdSessionLogRecorder? _recorder;
  Future<void> _chain = Future.value();

  /// 内部串行链句柄（测试等待落盘完成用，替代睡眠等待）。
  @visibleForTesting
  Future<void> get chainIdle => _chain;

  @override
  String? get currentRecordingFileName => _recorder?.fileName;

  Future<ObdSessionLogStore> _ensureStore() async {
    final injected = _injectedStore;
    if (injected != null) {
      return injected;
    }
    return _store ??= await ObdSessionLogStore.production();
  }

  /// 把异步写串进内部链（事件顺序 = 调用顺序；失败静默——日志是附属
  /// 品，不打断连接主链）。
  void _enqueue(Future<void> Function() work) {
    _chain = _chain.then((_) => work()).catchError((_) {});
  }

  @override
  void onSessionStart(DateTime at, {String? deviceId, bool mock = false}) {
    _enqueue(() async {
      final store = await _ensureStore();
      await store.cleanup(now: DateTime.now());
      final recorder = ObdSessionLogRecorder(directory: store._dir);
      await recorder.start(at: at, device: deviceId, mock: mock);
      _recorder = recorder;
    });
  }

  @override
  void onProbeReading(DiagnosticsProbe probe, ObdReading reading, DateTime at) {
    _enqueue(() async {
      final recorder = _recorder;
      if (recorder == null) {
        return;
      }
      final noData = reading is ObdNoData;
      await recorder.appendReading(
        probeName: probe.name,
        command: probe.command,
        display: noData ? null : reading.display,
        noDataReason: noData ? reading.reason : null,
        at: at,
      );
    });
  }

  @override
  void onSessionEnd(DateTime at, {String? reason}) {
    _enqueue(() async {
      await _recorder?.close(reason: reason, at: at);
      _recorder = null;
    });
  }

  @override
  void onVerificationLog(String log, DateTime at) {
    _enqueue(() async {
      await _recorder?.appendEvent(
        event: 'verify',
        extra: {'log': log},
        at: at,
      );
    });
  }

  @override
  void onAppLifecycle(String state, DateTime at) {
    // 读点收在闭包内（与 onProbeReading 同款）：排在本行的排队写按调用
    // 顺序执行，start 之后才落盘的 paused 不会因句柄尚未赋值而丢失、
    // close 之后排队的也不会复活已收尾的会话。
    _enqueue(() async {
      await _recorder?.appendEvent(
        event: 'lifecycle',
        extra: {'s': state},
        at: at,
      );
    });
  }

  @override
  void onFuelGateRejected({
    required String probeName,
    required double raw,
    required double? held,
    required int samples,
    required double? span,
    required DateTime at,
  }) {
    _enqueue(() async {
      await _recorder?.appendEvent(
        event: 'fuel_gate',
        extra: {
          'probe': probeName,
          'raw': raw,
          'held': held,
          'n': samples,
          'span': span,
        },
        at: at,
      );
    });
  }
}
