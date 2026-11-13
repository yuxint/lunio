// ELM327 会话决策体（ADR 0020）：连接→AT 初始化序列→串行轮询编排的
// plain-Dart 解析控制器。不碰 BuildContext；transport、超时、轮询间
// 隔、延时与时钟经构造注入（接法同记录表单控制器先例），单测零真实
// 等待、completer 驱动 await 边界。
//
// ≈ Java 的有状态 Service + ScheduledExecutorService：connect ≈ 建连
// +握手，startPolling ≈ 调度串行任务循环，disconnect ≈ 取消任务；事
// 件经 broadcast Stream 广播（≈ ApplicationEvent）。
//
// 会话是一次性对象：connect → (startPolling)* → disconnect；重连 =
// 新建会话实例（story 7 手动重连由页面新建，本类不自动重连，ADR
// 0020"不自动重连、不做后台保活"）。构造后状态 idle；disconnect 后
// 状态终态 disconnected，不可再 connect。
import 'dart:async';
import 'dart:convert';
import 'dart:collection';
import 'dart:typed_data';

import '../../../domain/entities/diagnostics_probe.dart';
import 'elm327_parser.dart';
import 'obd_transport.dart';

/// 会话级可辨识错误（票 04 验收：序列失败上抛可辨识错误）。初始化失
/// 败、发送失败、主动断开中断在途请求，统一翻译成本类型。
class Elm327SessionException implements Exception {
  const Elm327SessionException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() =>
      'Elm327SessionException: $message${cause == null ? '' : ' ($cause)'}';
}

/// 单条指令等提示符超时（[Elm327SessionException] 子类）：轮询侧映射
/// 行级"无数据"，连接初始化侧归并进初始化失败。
class Elm327TimeoutException extends Elm327SessionException {
  Elm327TimeoutException(String command)
      : super('指令 $command 等提示符超时');
}

/// 会话状态：idle（未连）→ connecting → connected → disconnected
/// （终态）。
enum Elm327SessionState { idle, connecting, connected, disconnected }

/// 会话事件（[Elm327Session.events] 流广播；页面状态条/值卡/行列表
/// 消费）。
sealed class Elm327SessionEvent {
  const Elm327SessionEvent();
}

/// 连接成功（AT 序列完成）。
final class Elm327Connected extends Elm327SessionEvent {
  const Elm327Connected();
}

/// 连接断开（初始化失败/链路错误/显式断开）。[cause] 供状态条错误文
/// 案与日志。
final class Elm327Disconnected extends Elm327SessionEvent {
  const Elm327Disconnected(this.cause);

  final Object? cause;
}

/// 单条检测点一轮读取结果（值或行级无数据）。
final class Elm327ProbeReading extends Elm327SessionEvent {
  const Elm327ProbeReading({
    required this.probeId,
    required this.reading,
    required this.at,
  });

  /// 检测点行 id（轮询快照来自库表，恒有 id）。
  final int probeId;
  final ObdReading reading;

  /// 读取时间（story 14 行尾"最后更新时间"的数据源；注入时钟）。
  final DateTime at;
}

/// ELM327 会话控制器（职责与生命周期见文件头）。
class Elm327Session {
  Elm327Session({
    required this._transport,
    DateTime Function()? now,
    Future<void> Function(Duration)? delay,
    this.responseTimeout = const Duration(seconds: 5),
    this.pollInterval = const Duration(seconds: 3),
  })  :
        _now = now ?? DateTime.now,
        _delay = delay ?? _realDelay;

  final OBDTransport _transport;
  final DateTime Function() _now;
  final Future<void> Function(Duration) _delay;

  /// 响应超时（单条指令等 `>` 的上限；真机联调再定）。
  final Duration responseTimeout;

  /// 轮间隔（ADR 0020 决定 4：常量默认 3 秒，真机联调再定）。
  final Duration pollInterval;

  static Future<void> _realDelay(Duration d) => Future<void>.delayed(d);

  /// AT 初始化序列（实车验证口径，ADR 0020 决定 2）：ATZ 复位 →
  /// ATE0 关回显 → ATL0 关行馈送 → ATSP 7 显式指定 CAN 协议。ATSP 7
  /// 必发不省略（实车验证：协议复位后发 PID 全 NO DATA）。发送前逐条
  /// 规整（normalizeObdCommand）。
  static const List<String> initSequence = ['ATZ', 'ATE0', 'ATL0', 'ATSP 7'];

  final _events = StreamController<Elm327SessionEvent>.broadcast();

  /// 会话事件流（broadcast；不重放历史，页面 initState 先听后连）。
  Stream<Elm327SessionEvent> get events => _events.stream;

  Elm327SessionState _state = Elm327SessionState.idle;

  /// 当前会话状态。
  Elm327SessionState get state => _state;

  StreamSubscription<Uint8List>? _byteSub;
  final _assembler = ObdFrameAssembler();
  final _frames = Queue<String>();
  bool _stopPolling = false;
  Future<void>? _pollLoop;
  Completer<String>? _frameWaiter;
  int _generation = 0;

  /// 连接并跑完 AT 初始化序列。成功 → 状态 connected + 发
  /// [Elm327Connected]；失败 → 状态 disconnected、发
  /// [Elm327Disconnected]，并上抛 [Elm327SessionException]（可辨识，
  /// 页面 await 处接状态条错误文案；事件与异常同源同因）。
  ///
  /// AT 序列逐条"发指令 → 等提示符帧"（每条成功 = 收到 `>`，不校验
  /// banner/OK 内容——适配器差异大，内容校验脆弱）。
  Future<void> connect() async {
    if (_state != Elm327SessionState.idle) {
      throw StateError('connect() 只允许从 idle 进入（当前 $_state）');
    }
    _state = Elm327SessionState.connecting;
    try {
      await _transport.connect();
      // 先订阅再发首条指令，ATZ 横幅早到不丢字节。
      _byteSub = _transport.byteStream.listen(
        _onBytes,
        onError: _onLinkLost,
        onDone: () => _onLinkLost('字节流关闭'),
        cancelOnError: true,
      );
      for (final command in Elm327Session.initSequence) {
        await _request(normalizeObdCommand(command));
      }
    } catch (e) {
      _markDisconnected(e);
      await _teardown();
      throw Elm327SessionException('AT 初始化序列失败', e);
    }
    _state = Elm327SessionState.connected;
    _events.add(const Elm327Connected());
  }

  /// 启动串行轮询循环（要求 connected；已启动再调抛 StateError）。
  /// 每轮开头经 [enabledProbes] 取一次"启用检测点"快照——启停下一轮
  /// 生效、不中断当前轮；一轮 = 串行发全部启用项，每条等响应或超时
  /// （单条超时 → 行级无数据、不阻塞后续），单条链路级失败 → 整轮退
  /// 出 + 断开事件。停轮/断开在探测点边界与轮间延时后检查点退出。
  void startPolling({
    required List<DiagnosticsProbe> Function() enabledProbes,
  }) {
    if (_state != Elm327SessionState.connected) {
      throw StateError('startPolling() 要求 connected（当前 $_state）');
    }
    if (_pollLoop != null) {
      throw StateError('轮询已启动，不要重复调用');
    }
    _stopPolling = false;
    _pollLoop = _poll(enabledProbes);
  }

  /// 停轮：不中断当前条请求（等它响应或超时），检查点退出循环。可重
  /// 入，幂等。
  void stopPolling() {
    _stopPolling = true;
  }

  Future<void> _poll(
    List<DiagnosticsProbe> Function() enabledProbes,
  ) async {
    try {
      while (!_stopPolling) {
        final probes = enabledProbes();
        for (final probe in probes) {
          if (_stopPolling || _state != Elm327SessionState.connected) {
            return;
          }
          final probeId = probe.id;
          if (probeId == null) {
            // 未入库检测点跳过（快照契约是库表行；null id 属上游 bug，
            // 跳过保轮询存活，事件里不冒出假 id）。
            continue;
          }
          final command = normalizeObdCommand(probe.command);
          try {
            final frame = await _request(command);
            final reading = parseProbeResponse(
              command: command,
              parseType: probe.parseType,
              frameText: frame,
            );
            _events.add(Elm327ProbeReading(
              probeId: probeId,
              reading: reading,
              at: _now(),
            ));
          } on Elm327TimeoutException {
            _events.add(Elm327ProbeReading(
              probeId: probeId,
              reading: const ObdNoData('超时'),
              at: _now(),
            ));
          } on Elm327SessionException {
            // 链路/会话级失败（send 失败、断开中断）：整轮退出 +
            // 断开事件，连接级语义（story 16）。
            _markDisconnected(
              const Elm327SessionException('轮询中链路失败'),
            );
            return;
          } catch (e) {
            // 其他异常（解析缺陷等非链路问题）归单条无数据，不连坐
            // 断连语义、不中断轮询。
            _events.add(Elm327ProbeReading(
              probeId: probeId,
              reading: ObdNoData('读取失败：$e'),
              at: _now(),
            ));
          }
        }
        await _delay(pollInterval);
      }
    } finally {
      _pollLoop = null;
    }
  }

  /// 单条指令"发送 → 等提示符帧"（严格串行：同时只能有一条在途，重
  /// 入抛 StateError）。超时走注入延时接缝竞速（不用 future.timeout，
  /// 定时器形态可被测试零等待驱动）；超时即清缓冲与帧队列（迟到碎片
  /// 整体丢弃，防串扰下一条指令）。返回提示符前的完整帧文本。
  Future<String> _request(String command) async {
    if (_frameWaiter != null) {
      throw StateError('上一条指令未完成，串行违规');
    }
    // 串行语义：请求起点还压在队列里的帧必是上一条的残留（超时清
    // 缓冲竞态窗口漏网的迟到完整帧），不属于本条指令，丢弃防占位。
    _frames.clear();
    final completer = Completer<String>();
    _frameWaiter = completer;
    // 标记错误已处理：断开/链路丢失可能在 send 还没回来、外层尚未
    // await completer.future 时就 completeError（无监听者 → 未处理异
    // 步错误）。ignore 只切断"无人监听"的报错通道，后续 await 仍能收
    // 到错误。
    completer.future.ignore();
    final gen = _generation;
    unawaited(_runTimeout(gen, completer, command));
    try {
      try {
        await _transport.send(latin1.encode('$command\r'));
      } catch (e) {
        throw Elm327SessionException('发送失败', e);
      }
      return await completer.future;
    } finally {
      if (_frameWaiter == completer) {
        _frameWaiter = null;
      }
    }
  }

  /// 超时竞速任务：等注入延时到点，若指令仍未应答完成 completer 为超
  /// 时错误。代数（generation）守卫：断开/清尾后代数已变，迟到的超时
  /// 任务对完成态 completer 与新代数请求都无副作用。
  Future<void> _runTimeout(
    int gen,
    Completer<String> completer,
    String command,
  ) async {
    await _delay(responseTimeout);
    if (gen == _generation &&
        !completer.isCompleted &&
        _frameWaiter == completer) {
      _assembler.clear();
      _frames.clear();
      completer.completeError(
        Elm327TimeoutException(command),
        StackTrace.current,
      );
    }
  }

  /// 字节到达：喂组帧缓冲、入帧队列、唤醒等帧的在途请求（取队列最老
  /// 帧——多余帧留给下一条指令，独立提示符帧不丢不粘）。
  void _onBytes(List<int> bytes) {
    // 空白帧（纯提示符残留，如超时清缓冲后迟到的 `\r>`）不入队——
    // 入队会被下一条指令当响应消费，读数在行间错位一格（story 15 行
    // 归属被破坏）。合法响应帧必有内容（OK/banner/数据行）。
    // 空白帧（纯提示符残留，如超时清缓冲后迟到的 `\r>`）不入队——
    // 在途请求会被它打断、把空帧当响应消费，读数错位（story 15）。
    // 合法响应帧必有内容（OK/banner/数据行）。
    // 空白帧（纯提示符残留，如超时清缓冲后迟到的 `\r>`）不入队——
    // 在途请求会被它打断、把空帧当响应消费，读数错位（story 15）。
    // 合法响应帧必有内容（OK/banner/数据行）。
    _frames.addAll(
      _assembler.push(bytes).where((frame) => frame.trim().isNotEmpty),
    );
    final waiter = _frameWaiter;
    if (waiter != null && !waiter.isCompleted && _frames.isNotEmpty) {
      waiter.complete(_frames.removeFirst());
    }
  }

  /// 链路丢失（字节流 error/done）：标记断开 + 中断在途请求（在途请
  /// 求以会话异常穿出，轮询侧走断开分支退出整轮）。
  void _onLinkLost(Object? cause) {
    _markDisconnected(cause ?? '字节流关闭');
    final waiter = _frameWaiter;
    if (waiter != null && !waiter.isCompleted) {
      waiter.completeError(
        const Elm327SessionException('字节流 error/done'),
        StackTrace.current,
      );
    }
  }

  /// 进入/确认断开态：只在 connecting/connected → disconnected 的首跳
  /// 发断开事件（事件与状态永相容，页面状态条单一事实源），重复调用
  /// 幂等。
  void _markDisconnected(Object? cause) {
    if (_state == Elm327SessionState.connecting ||
        _state == Elm327SessionState.connected) {
      _state = Elm327SessionState.disconnected;
      _events.add(Elm327Disconnected(cause));
    }
  }

  /// 断开会话（幂等，终态）：停轮 + 中断在途请求 + 释放传输层与字节
  /// 流订阅。idle 直接静默置 disconnected（无链路可释放；页面从 idle
  /// 关闭时调它，不造伪事件）。
  Future<void> disconnect() async {
    _stopPolling = true;
    final waiter = _frameWaiter;
    if (waiter != null && !waiter.isCompleted) {
      waiter.completeError(
        const Elm327SessionException('会话已断开'),
        StackTrace.current,
      );
    }
    if (_state == Elm327SessionState.idle) {
      _state = Elm327SessionState.disconnected;
      return;
    }
    _markDisconnected(const Elm327SessionException('主动断开'));
    await _teardown();
  }

  /// 释放全部资源（页面 dispose 调用）：disconnect + 关闭事件流。幂
  /// 等；之后 events 流关闭、连接级事件不再产生。
  Future<void> dispose() async {
    await disconnect();
    if (!_events.isClosed) {
      _events.close();
    }
  }

  /// 清尾：停轮旗 + 代数推进（迟到的超时任务失效）+ 清帧队列与缓冲
  /// + 退订字节流 + transport 断开。幂等。
  Future<void> _teardown() async {
    _stopPolling = true;
    _generation++;
    _frames.clear();
    _assembler.clear();
    final sub = _byteSub;
    _byteSub = null;
    await sub?.cancel();
    await _transport.disconnect();
  }
}
