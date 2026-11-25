// 诊断连接编排（GLOSSARY「诊断连接编排」词条，ADR 0027）：诊断连接的
// 整条流程决策体——相位机、尝试代数、直连/扫描分流、扫描会话、取消与
// 重连、最后读数合并与落库策略。plain-Dart 控制器，不碰 BuildContext；
// 会话工厂、扫描器、设备记忆、读数落库经构造注入，扫描 sheet 的开/关
// （DiagnosticsConnectionUi）由诊断页经 attachUi 挂载；ECU 里程与油量
// 静默同步回调（ADR 0026 / ADR 0030）经 setOdometerSyncHandler /
// setFuelLevelSyncHandler 挂载，装配在 App 级连接 provider（obd_runtime）。
//
// 生命周期归 App 级（ADR 0027，2026-11-16）：本类由 keepAlive provider
// 持有（obd_runtime.dart 的 obdConnectionControllerProvider），提醒页
// 「连接OBD」快速连接与诊断页共享同一连接——离诊断页不断开，进诊断页
// 已连接则复用；轮询清单按作用域换防：诊断页在栈顶 = 全量启用清单，
// 退回提醒页 = 核心两条（油量/水温）。会话仍是一次性对象：本类持有
// 当前会话、调用方只负责触发（按钮/页面调对应方法）；重连 = 丢弃旧
// 会话新建实例。
//
// ≈ Java 的有状态 Service + 门面：页面 ≈ Controller，本类 ≈ 领域
// Service（App 级单例 Bean），DiagnosticsConnectionUi ≈ 回调接口（诊断
// 页实现开/关扫描 sheet 两个 UI 动作）。
//
// 行为契约（票 04 迁入 + ADR 0027 增补）：
//   - 直连：设备记忆命中 → 定向建链；无记忆 → 先过适配器门禁再开扫描 sheet；
//   - 快速连接（connectRemembered）：只直连设备记忆，不落扫描——失败都
//     落「已断开」错误文案，由调用方（提醒页）toast 反馈；
//   - 扫描：点选即停扫并建链；失败在 sheet 内回填并恢复扫描；连接中关闭
//     sheet = 取消本次连接（会话 dispose 收尾，迟到失败不改写相位）；
//   - 门禁类失败（蓝牙关/适配器不支持/权限）状态条渲染文案、不落扫描；
//   - 会话级失败（AT 超时等）状态条渲染错误文案，点选流同样回填恢复扫描；
//   - 诊断页进入时已连接则复用（start 的 connected 守卫），离开不断开；
//   - 最后读数：有效值写库（无数据不写不覆盖），实时值优先、持久化回退。
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../domain/entities/diagnostics_parse_type.dart';
import '../../../domain/entities/diagnostics_probe.dart';
import 'ble_obd_errors.dart';
import 'ble_scan_entries.dart';
import 'elm327_parser.dart' show ObdReading, ObdValue;
import 'elm327_session.dart';
import 'fuel_level_gate.dart';
import 'obd_session_log.dart';
import 'obd_runtime.dart';
import 'obd_scanner.dart';

/// 页面级连接相位（状态条渲染依据）。idle = 进页面首帧的「未连接」或
/// 扫描 sheet 取消后的「未连接」；scanning = 扫描 sheet 打开中。
enum DiagnosticsConnectionPhase {
  idle,
  scanning,
  connecting,
  connected,
  disconnected,
}

/// 单条检测点的读取快照（展示值 + 读取时刻）。行尾「最后更新时间」与
/// 信息卡共用；实时读数与持久化回退都用这一种形状。
@immutable
class ProbeReadingSnapshot {
  const ProbeReadingSnapshot({required this.reading, required this.at});

  final ObdReading reading;

  /// 读取时刻（会话注入时钟打点；持久化回退用行上记录的时刻）。
  final DateTime at;
}

/// 扫描会话视图（sheet 渲染数据；决策在 controller）。
@immutable
class DiagnosticsScanState {
  const DiagnosticsScanState({
    this.entries = const [],
    this.connectingId,
    this.hint,
  });

  /// 当前扫描清单（扫描器已按首见定序 + ≤1Hz 合并整备）。
  final List<BleObdScanEntry> entries;

  /// 正在连接中的设备行 id（null = 无在途点选）。
  final String? connectingId;

  /// 顶部提示文案（失败/门禁说明；null = 默认「正在扫描」）。
  final String? hint;
}

/// 连接编排的完整渲染面（不可变快照）。页面经 [DiagnosticsConnectionController.state]
/// 读取；每次通知重建一份。
@immutable
class DiagnosticsConnectionState {
  const DiagnosticsConnectionState({
    required this.phase,
    this.statusError,
    this.scan = const DiagnosticsScanState(),
    this.readings = const <int, ProbeReadingSnapshot>{},
  });

  final DiagnosticsConnectionPhase phase;

  /// 断连错误文案（「已断开」状态下的补充说明；null = 无）。
  final String? statusError;

  final DiagnosticsScanState scan;

  /// 本会话实时读数表（键 = 检测点 id）。
  final Map<int, ProbeReadingSnapshot> readings;
}

/// 页面实现的 UI 动作接缝（两个命令；数据走 [DiagnosticsConnectionState]）。
/// 打开与关闭扫描 sheet 是唯一需要 BuildContext 的连接侧动作，收在这里，
/// 测试用假实现直接断言调用。
class DiagnosticsConnectionUi {
  const DiagnosticsConnectionUi({
    required this.openScanSheet,
    required this.closeScanSheet,
  });

  /// 打开扫描 sheet。返回 **false = 页面此刻开不了**（栈顶被别的 sheet
  /// 占着，例如调试终端的会话日志 sheet）——controller 据此撤销这次扫描，
  /// 落在可恢复的未连接/已断开态，绝不叠加两个 sheet（2026-11-21 拍板）。
  final bool Function() openScanSheet;

  final void Function() closeScanSheet;
}

/// 诊断连接编排控制器（职责与契约见文件头）。App 级一次性对象（ADR
/// 0027）：keepAlive provider 创建、provider onDispose 释放；诊断页只
/// 挂/摘 UI 接缝与作用域，不创建不释放。释放后所有命令静默返回。
class DiagnosticsConnectionController extends ChangeNotifier {
  DiagnosticsConnectionController({
    required this.sessionFactory,
    required this.scanner,
    required this.readDeviceId,
    required this.rememberDevice,
    required this.saveReading,
    this.sessionLogSink,
    bool? mockLink,
  }) : mockLink = mockLink ?? obdMockLink;

  /// 会话工厂（每次连接新建会话 + 传输层；测试注入门闩夹具）。
  final ObdSessionFactory sessionFactory;

  /// 设备扫描器接缝（扫描会话归本类驱动）。
  final ObdScanner scanner;

  /// 读设备记忆（`lastObdDeviceId`）。
  final Future<String?> Function() readDeviceId;

  /// 写设备记忆（扫描点选连接成功即写）。
  final Future<void> Function(String deviceId) rememberDevice;

  /// 最后读数落库（只存有效值；写失败由本类吞掉，下一轮再写）。
  final Future<void> Function(
    int probeId, {
    required String value,
    double? percent,
    required DateTime at,
  }) saveReading;

  /// mock 回退链路（`--dart-define=LUNIO_OBD_MOCK=true` 或测试显式传
  /// false/true）：跳过设备记忆与扫描，直连演示设备。
  final bool mockLink;

  /// 会话日志接缝（2026-11-18 拍板：单次连接的轮询读数记录为 JSONL
  /// 文件，7 天/50 个双上限；null = 不记录，测试默认不传）。
  final ObdSessionLogSink? sessionLogSink;

  /// 当前连接的设备标识（建链时记录；会话日志 start 行用）。
  String? _currentDeviceId;

  /// 开/关扫描 sheet 的 UI 接缝（诊断页 attachUi 挂载、detachUi 摘除）。
  /// null = 无诊断页在栈顶。扫描只从诊断页发起，快速连接不扫描。
  DiagnosticsConnectionUi? _ui;

  /// ECU 里程静默同步回调（ADR 0026，App 级装配挂载、随 provider 释放）：
  /// 收到有效里程读数（kilometers 非 null）时回调，静默自动写开关的读库
  /// 与守卫在接缝实现里。controller 不碰偏好与仓库；回调在连接期间常驻
  /// （提醒页背景清单与诊断页全量清单都生效），不随诊断页销毁摘除。
  void Function(ObdValue reading)? _odometerHandler;

  /// ECU 油量静默同步回调（ADR 0030，App 级装配挂载）：收到门限放行后
  /// 的有效油量读数时回调。开关读库、目标车选择与写库都在接缝实现里，
  /// controller 不碰偏好与仓库。
  void Function(DiagnosticsProbe probe, ObdValue reading)? _fuelLevelHandler;

  // ---- 内部状态（对外只经 state 快照） ----
  DiagnosticsConnectionPhase _phase = DiagnosticsConnectionPhase.idle;
  String? _statusError;
  List<BleObdScanEntry> _scanEntries = const [];
  String? _connectingId;
  String? _scanHint;
  final Map<int, ProbeReadingSnapshot> _readings = {};

  /// 当前会话（一次性对象；null = 已释放/未建链）。
  Elm327Session? _session;
  StreamSubscription<Elm327SessionEvent>? _sub;

  /// 扫描结果订阅（扫描会话内存在，关 sheet/点选即撤）。
  StreamSubscription<List<BleObdScanEntry>>? _scanResultsSub;

  /// 扫描 sheet 是否由本类打开且尚未收尾（controller 主动关闭时先置
  /// false，页面回来的 onScanSheetDismissed 即幂等返回）。
  bool _scanSheetOpen = false;

  /// 连接尝试代数（每次 _connectToDevice 自增）：关闭扫描 sheet/取消
  /// 连接时自增作废在途尝试，迟到的失败回填不再改写相位。
  int _connectAttempt = 0;

  /// 最新检测点快照（诊断页 setProbes 推入的全量清单；轮询快照 getter
  /// 读它——不读 provider 的 AsyncValue.value，invalidate 后读侧是陈旧
  /// 值，启停会晚一轮生效）。
  List<DiagnosticsProbe> _probes = const [];

  /// 诊断页作用域旗：true = 诊断页在栈顶，轮询用全量清单；false = 退回
  /// 提醒页，轮询用 [_backgroundProbes] 核心清单（ADR 0027 作用域换防）。
  bool _diagnosticsScope = false;

  /// 后台核心清单（提醒页 setBackgroundProbes 推入的油量/水温两条；无
  /// 诊断页作用域时轮询快照 getter 用它）。
  List<DiagnosticsProbe> _backgroundProbes = const [];

  bool _disposed = false;

  /// 渲染面快照（每次通知重建；readings 复制为不可修改视图）。
  DiagnosticsConnectionState get state => DiagnosticsConnectionState(
        phase: _phase,
        statusError: _statusError,
        scan: DiagnosticsScanState(
          entries: _scanEntries,
          connectingId: _connectingId,
          hint: _scanHint,
        ),
        readings: Map.unmodifiable(_readings),
      );

  /// 当前会话（调试终端用；null = 未建链/已释放）。
  Elm327Session? get session => _session;

  /// 推送最新检测点清单（诊断页数据分支调用；不触发通知——列表数据本身
  /// 由 provider 驱动重建，读数合并用读取时计算）。
  void setProbes(List<DiagnosticsProbe> probes) {
    _probes = probes;
  }

  /// 推送后台核心清单（提醒页推入的油量/水温两条；无诊断页作用域时的
  /// 轮询数据源。不触发通知，理由同 [setProbes]）。
  void setBackgroundProbes(List<DiagnosticsProbe> probes) {
    _backgroundProbes = probes;
  }

  /// 切换诊断页作用域（诊断页 initState 置 true、dispose 置 false）：
  /// 轮询快照 getter 按它选数据源（ADR 0027 作用域换防）。
  void setDiagnosticsScope(bool active) {
    _diagnosticsScope = active;
  }

  /// 按 id 找检测点（轮询读数落会话日志用；清单由页面/提醒页推入）。
  DiagnosticsProbe? _probeById(int probeId) {
    for (final probe in [..._probes, ..._backgroundProbes]) {
      if (probe.id == probeId) {
        return probe;
      }
    }
    return null;
  }

  /// 油量门限（2026-11-20 起，2026-11-21 改为窗口聚合）：按探针 id 各一份，
  /// 跨会话/跨作用域保留——熄火加油前后油量是连续的，重建门限反而会吃进
  /// 一个新的晃动值。
  final Map<int, FuelLevelGate> _fuelGates = {};

  /// 过油量门限：返回要上卡的读数，null = 本拍丢弃。
  ///
  /// 只作用于 `fuelLevel` 解析类型（本车即内置 `012F`）；其他解析类型
  /// 原样放行。无数据行、缺 percent 的读数不进门限，但**会消费掉手动
  /// 刷新的一次性放行旗**——见 [_manualPollBypass]。
  ///
  /// 语义（2026-11-21 二次修订）：最近 3 拍极差 ≤5 个点、且三拍严格全
  /// 在卡片一侧 → 卡片更新为窗口中位数；否则保持现值并写一行
  /// `fuel_gate` 日志（原始值已由调用方先记过读数行）。放行值可能不等于
  /// 本拍原始值——窗口里带边缘值时，中位数比最新值更可信。
  ///
  /// 手动刷新（[requestImmediatePoll] 的 manual 分支）例外：直显原始值，
  /// 不做任何平滑。
  ObdReading? _gateFuelReading(
    DiagnosticsProbe? probe,
    ObdReading reading,
    DateTime at,
  ) {
    if (probe == null ||
        probe.id == null ||
        probe.parseType != DiagnosticsParseType.fuelLevel) {
      return reading;
    }
    // 放行旗无论本拍是否有效都消费（2026-11-21 深审修复）：手动那一轮
    // 若油量回 NO DATA/超时，旗子留着会让下一次**自动**轮询的晃动值
    // 被当成「用户想看的值」直显、写 lastPercent 与 fuel_predictions。
    final bypass = _manualPollBypass;
    _manualPollBypass = false;
    if (reading is! ObdValue || reading.percent == null) {
      return reading;
    }
    final raw = reading.percent!;
    final gate = _fuelGates.putIfAbsent(probe.id!, () {
      // 用库里最后读数播种：页面重开时卡片显示的就是它，前两拍凑窗口
      // 期间不至于空白。库值过期（熄火期间加过油）时由窗口聚合法在
      // 第 3 拍纠正。
      return FuelLevelGate()..seed(probe.lastPercent);
    });
    if (bypass) {
      // 手动刷新：读到多少显示多少，并把它定为新基准（清窗口重来），
      // 否则随后的自动轮询会拿旧样本把刚显示的值顶回去。
      gate.override(raw);
      return reading;
    }
    final admitted = gate.admit(raw);
    if (admitted == null) {
      sessionLogSink?.onFuelGateRejected(
        probeName: probe.name,
        raw: raw,
        held: gate.acceptedPercent,
        samples: gate.windowSampleCount,
        span: gate.windowSpan,
        at: at,
      );
      return null;
    }
    if (admitted == raw) {
      return reading;
    }
    // 中位数与原始值不同：按油量口径重建展示文本（与 parser 的格式一致：
    // 取整百分比）。celsius/volts/kilometers 对油量探针恒为 null。
    return ObdValue(display: '${admitted.round()}%', percent: admitted);
  }

  /// 一键检测日志落会话文件（调试面板调用；无会话记录时静默）。
  void appendVerificationLog(String log) {
    sessionLogSink?.onVerificationLog(log, DateTime.now());
  }

  /// 检测点快照取值（信息卡共源）：**实时有值优先**（本会话最新轮询）；
  /// 实时「无数据」**不遮蔽**持久化最后值（2026-11-17 拍板，ADR 0029：
  /// 再连接后轮询读到 NO DATA/超时，页面保留最后有效值+旧时间戳，不切
  /// 灰态——只有明确数据值才覆盖显示）；实时无读数或无值时回退持久化
  /// 最后读数。两者都无 = null（灰态「无数据」只在从未有过有效值时）。
  ProbeReadingSnapshot? readingFor(DiagnosticsProbe probe) {
    final live = _readings[probe.id];
    if (live != null && live.reading is ObdValue) {
      return live;
    }
    final value = probe.lastValue;
    final at = probe.lastReadingAt;
    if (value == null || at == null) {
      return null;
    }
    // 重建快照：display + percent 足够渲染（信息卡只显 display 与
    // percent 染色）；celsius/volts 不持久化，重建后不染色（ink 色）。
    return ProbeReadingSnapshot(
      reading: ObdValue(display: value, percent: probe.lastPercent),
      at: at,
    );
  }

  /// 只取本会话实时读数（提醒页油量水温信息卡用；ADR 0027 拍板「不回
  /// 退最后读数」——持久化快照只在诊断页展示，提醒页只信本轮连接拿到
  /// 的值）。两者皆无返回 null。
  ProbeReadingSnapshot? liveReadingFor(DiagnosticsProbe probe) {
    return _readings[probe.id];
  }

  /// 进页面自动连接与「重连」按钮的入口：mock 分支 → 演示设备；否则读
  /// 设备记忆，命中直连、无记忆落扫描 sheet。已连接/连接中/扫描中直接
  /// 返回（connected 守卫：App 级连接在诊断页进入时复用，不重连）。
  Future<void> start() async {
    if (_disposed ||
        _phase == DiagnosticsConnectionPhase.connecting ||
        _phase == DiagnosticsConnectionPhase.scanning ||
        _phase == DiagnosticsConnectionPhase.connected) {
      return;
    }
    if (mockLink) {
      await _connectToDevice('mock-device');
      return;
    }
    final remembered = await readDeviceId();
    if (_disposed) {
      return;
    }
    if (remembered == null) {
      await openScan();
      return;
    }
    await _connectToDevice(remembered);
  }

  /// 快速连接（提醒页「连接OBD」按钮）：只直连设备记忆，**不落扫描**。
  /// 门禁类失败与设备/链路类失败都由会话层发 Disconnected 事件落「已断
  /// 开」+ 错误文案，返回 false 供调用方 toast；成功返回 true。已在连
  /// 接中/扫描中/已连接时返回当前连接态（无效果，调用方不 toast）。
  Future<bool> connectRemembered() async {
    if (_disposed) {
      return false;
    }
    if (_phase == DiagnosticsConnectionPhase.connecting ||
        _phase == DiagnosticsConnectionPhase.scanning) {
      return false;
    }
    if (_phase == DiagnosticsConnectionPhase.connected) {
      return true;
    }
    if (mockLink) {
      final session = await _connectToDevice(
        'mock-device',
        allowScanFallback: false,
      );
      return session != null;
    }
    final remembered = await readDeviceId();
    if (_disposed) {
      return false;
    }
    // 按钮只在有设备记忆时显示；无记忆属防御分支，静默返回。
    if (remembered == null) {
      return false;
    }
    final session = await _connectToDevice(
      remembered,
      allowScanFallback: false,
    );
    return session != null;
  }

  /// 「选择设备」按钮与无记忆首用的扫描入口：先过适配器门禁（权限拒绝/
  /// 蓝牙未开/不支持不能藏进空列表），再开扫描 sheet。
  Future<void> openScan() async {
    if (_disposed || _scanSheetOpen) {
      return;
    }
    try {
      await scanner.ensureReady();
    } on BleObdTransportException catch (e) {
      if (_disposed) {
        return;
      }
      if (!e.kind.isGateError) {
        _openScanSheetNow();
      } else {
        _phase = DiagnosticsConnectionPhase.disconnected;
        _statusError = e.statusCopy;
        _notify();
      }
      return;
    } catch (_) {
      // 未知门禁异常仍落 sheet，由 sheet 顶部提示兜底。
      if (!_disposed) {
        _openScanSheetNow();
      }
      return;
    }
    if (_disposed ||
        _scanSheetOpen ||
        _phase == DiagnosticsConnectionPhase.connecting ||
        _phase == DiagnosticsConnectionPhase.connected) {
      return;
    }
    _openScanSheetNow();
  }

  /// 扫描 sheet 行点选：置连接中行态 + 停扫 + 回页面建链。
  void pickDevice(BleObdScanEntry entry) {
    if (_disposed || !_scanSheetOpen || _connectingId != null) {
      return;
    }
    _connectingId = entry.id;
    _notify();
    unawaited(scanner.stop());
    unawaited(_connectToPicked(entry));
  }

  /// sheet 以任何方式关闭后由页面告知（取消/下滑/遮罩/程序关闭）。
  /// controller 主动关闭时 `_scanSheetOpen` 已先置 false，这里幂等返回。
  void onScanSheetDismissed() {
    if (_disposed || !_scanSheetOpen) {
      return;
    }
    _scanSheetOpen = false;
    _cancelScanResources();
    if (_phase == DiagnosticsConnectionPhase.connecting) {
      // 建链成功但 Connected 事件尚未递送（点选成功路径会在这里关
      // sheet）：不取消已成功的连接，相位交给事件渲染。
      if (_session?.state == Elm327SessionState.connected) {
        return;
      }
      // 连接中关闭 sheet = 取消本次连接（在途建链可能还要等 15 秒，
      // 不能把页面停在无 sheet 的「连接中」）。
      _connectAttempt++;
      unawaited(_teardownSession(reason: '取消连接'));
      _phase = DiagnosticsConnectionPhase.idle;
      _statusError = null;
      _notify();
      return;
    }
    if (_phase == DiagnosticsConnectionPhase.scanning) {
      _phase = DiagnosticsConnectionPhase.idle;
      _notify();
    }
  }

  /// 手动断开（状态条「断开」）：释放会话并落「未连接」相位——手动断开
  /// 不是异常，不落红色「已断开」；设备记忆不清除（重进页面仍自动直连）。
  Future<void> disconnectManually() async {
    if (_disposed) {
      return;
    }
    _connectAttempt++;
    _phase = DiagnosticsConnectionPhase.idle;
    _statusError = null;
    _notify();
    await _teardownSession(reason: '手动断开');
  }

  /// 「立即刷新」：手动轮询全部启用项（会话不持有时静默）。
  ///
  /// [manual] = 用户主动点了刷新按钮（诊断页状态条 / 提醒页信息卡）：
  /// 用户拍板（2026-11-21）「我既然手动刷新，肯定是想知道当前的状态」，
  /// 所以这一次油量读数直接上卡、不过门限（见 [_gateFuelReading]）。
  /// 自动轮询与进页面/回前台补的那次不传，仍走门限。
  void requestImmediatePoll({bool manual = false}) {
    if (manual) {
      _manualPollBypass = true;
    }
    _session?.requestImmediatePoll();
  }

  /// 手动刷新的一次性放行旗：下一次油量读数直显并作为新基准。
  ///
  /// 一次性而不是时间窗：手动刷新的那一轮必然包含启用中的油量探针（种子
  /// 顺序第一）。消费点收在 [_gateFuelReading] 的解析类型判断之后——
  /// **无论那一拍是不是有效值都消费**（2026-11-21 深审修复：NO DATA/
  /// 超时不再把旗子漏给下一轮自动轮询），断开/重连时由 [_teardownSession]
  /// 清掉，不跨会话生效。油量探针被禁用时这面旗仍会留到下次启用，那一
  /// 次直显一次——这是已知且接受的残余口径（没有读数事件可消费）。
  bool _manualPollBypass = false;

  /// 应用生命周期上报（2026-11-20）：主壳层把 `AppLifecycleState.name`
  /// 原样传进来，转交会话日志落一行 `lifecycle`。只做记账，不改连接
  /// 状态、不触发轮询（resume 后的立即轮询仍由主壳层显式调
  /// [requestImmediatePoll]）。无会话时 sink 侧静默丢弃。
  ///
  /// 收字符串而不是 Flutter 的 `AppLifecycleState`：本类刻意保持
  /// plain-Dart（不 import Flutter），枚举到字符串的映射留在 UI 侧。
  void logAppLifecycle(String state) {
    sessionLogSink?.onAppLifecycle(state, DateTime.now());
  }

  /// 挂载扫描 sheet 的 UI 接缝（诊断页 initState）。重复挂载以最后一次
  /// 为准（诊断页是唯一挂载方，单实例不并发）。
  void attachUi(DiagnosticsConnectionUi ui) {
    _ui = ui;
  }

  /// 摘除 UI 接缝（诊断页 dispose）：摘除后扫描入口全走防御分支。
  void detachUi() {
    _ui = null;
  }

  /// 挂载 ECU 里程静默同步回调（诊断页 initState）；传 null 摘除。
  void setOdometerSyncHandler(void Function(ObdValue reading)? handler) {
    _odometerHandler = handler;
  }

  /// 挂载 ECU 油量静默同步回调（ADR 0030，App 级装配挂载）；传 null 摘除。
  /// 回调带探针：接缝侧按 catalogKey 限定内置油量探针，controller 不做
  /// 该策略判断。
  void setFuelLevelSyncHandler(
    void Function(DiagnosticsProbe probe, ObdValue reading)? handler,
  ) {
    _fuelLevelHandler = handler;
  }

  /// App 级释放（keepAlive provider onDispose；App 生命周期内不会触发，
  /// 测试用）：停扫 + 撤扫描订阅 + 释放会话。幂等。
  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _cancelScanResources();
    unawaited(_teardownSession());
    super.dispose();
  }

  /// 开 sheet 的落地：置扫描中相位 + 订阅扫描结果 + 开 UI + 启动扫描。
  void _openScanSheetNow() {
    if (_disposed || _scanSheetOpen) {
      return;
    }
    // UI 接缝未挂载（无诊断页在栈顶）时不开 sheet：扫描只从诊断页发起，
    // 这里是防御分支——落可恢复的未连接态而不是崩溃。
    final ui = _ui;
    if (ui == null) {
      _phase = DiagnosticsConnectionPhase.idle;
      _notify();
      return;
    }
    // 失败原因先留着：页面开不了 sheet 时要把它还给状态条，否则「连接
    // 失败 → 本该落扫描」这条链上用户看不到任何原因。
    final previousError = _statusError;
    _scanSheetOpen = true;
    _scanEntries = const [];
    _connectingId = null;
    _scanHint = null;
    _phase = DiagnosticsConnectionPhase.scanning;
    _statusError = null;
    _scanResultsSub = scanner.results.listen(
      (entries) {
        if (_disposed || !_scanSheetOpen) {
          return;
        }
        _scanEntries = entries;
        _notify();
      },
      onError: (Object error) {
        if (_disposed || !_scanSheetOpen) {
          return;
        }
        _scanHint = _scanHintCopy(error);
        _notify();
      },
    );
    _notify();
    if (!ui.openScanSheet()) {
      // 页面栈顶被别的 sheet 占着（会话日志 sheet 等）：不叠加，撤销这次
      // 扫描并回到可恢复态。有失败原因的落「已断开 + 原因」，否则回「未
      // 连接」——两种都能靠状态条整卡点击重新发起。
      _scanSheetOpen = false;
      _cancelScanResources();
      _phase = previousError == null
          ? DiagnosticsConnectionPhase.idle
          : DiagnosticsConnectionPhase.disconnected;
      _statusError = previousError;
      _notify();
      return;
    }
    unawaited(_startScan());
  }

  /// 启动扫描；门禁类失败关 sheet、状态条渲染文案；其余失败挂顶部提示
  /// （sheet 不关）。
  Future<void> _startScan() async {
    try {
      await scanner.start();
    } catch (e) {
      if (_disposed || !_scanSheetOpen) {
        return;
      }
      if (e is BleObdTransportException && e.kind.isGateError) {
        _closeScanSheet();
        _phase = DiagnosticsConnectionPhase.disconnected;
        _statusError = e.statusCopy;
        _notify();
        return;
      }
      _scanHint = _scanHintCopy(e);
      _notify();
    }
  }

  String _scanHintCopy(Object error) {
    return error is BleObdTransportException
        ? error.statusCopy
        : '扫描失败，请重试';
  }

  /// 直连指定设备（记忆直连/扫描点选共用）：置连接中 → 释放旧会话 →
  /// 工厂新建会话 → 先听后连 → connect()。返回**本次尝试成功且仍是当前
  /// 会话**的实例（取消/失败/被替换返 null），点选回调按它判成功，不读
  /// 可能已被新尝试替换的 `_session`。失败按错误类别分流（见文件头）。
  Future<Elm327Session?> _connectToDevice(
    String deviceId, {
    BleObdScanEntry? picked,
    bool allowScanFallback = true,
  }) async {
    final attempt = ++_connectAttempt;
    _phase = DiagnosticsConnectionPhase.connecting;
    _statusError = null;
    _notify();
    await _teardownSession(reason: '连接重建');
    if (_disposed || attempt != _connectAttempt) {
      return null;
    }
    _currentDeviceId = deviceId;
    final session = sessionFactory(deviceId);
    _session = session;
    _sub = session.events.listen((event) => _onSessionEvent(session, event));
    try {
      await session.connect();
      if (_disposed || attempt != _connectAttempt) {
        return null;
      }
      return session;
    } on Elm327SessionException catch (e) {
      // 页面已退出，或连接已被取消（连接中关闭扫描 sheet）：迟到的
      // 失败不再改写相位、不再回填 sheet。
      if (_disposed || attempt != _connectAttempt) {
        return null;
      }
      final ble = _bleErrorOf(e);
      if (ble == null) {
        // 会话级失败（AT 超时等，适配器在但芯片无响应）：状态条已由
        // Disconnected 事件渲染错误文案；点选流 sheet 还开着、行不能
        // 停在「连接中…」——同样回填失败态恢复扫描。
        if (picked != null) {
          final detail = e.cause is Elm327SessionException
              ? (e.cause as Elm327SessionException).message
              : e.message;
          _resumeScanAfterPickFailed(picked, detail);
        }
        return null;
      }
      if (picked != null) {
        // 扫描点选流：门禁类关 sheet 露出错误状态条；设备/链路类回填
        // 行态 + 恢复扫描（sheet 不关，状态反馈在列表里）。
        if (ble.kind.isGateError ||
            ble.kind == BleObdLinkErrorKind.linkLost) {
          _closeScanSheet();
        } else {
          _resumeScanAfterPickFailed(picked, ble.statusCopy);
        }
        return null;
      }
      if (!ble.kind.isGateError) {
        // 记忆直连的设备/链路类失败：落扫描 sheet。门禁类保持断开态
        // 错误文案，用户按文案去修系统状态，扫描也扫不出结果。
        // 快速连接（allowScanFallback=false）不落扫描：失败交调用方
        // toast，保持「连上一次那台」的语义（ADR 0027）。
        if (allowScanFallback) {
          unawaited(openScan());
        }
      }
      return null;
    }
  }

  /// 点选连接调用链：等本次建链结果 → 成功判据（返回值与当前会话同一
  /// 性 + 会话状态）→ 写设备记忆 → 关 sheet。取消后重选的新尝试已把
  /// `_session` 换成新实例，旧续体按同一性检查退出。
  Future<void> _connectToPicked(BleObdScanEntry entry) async {
    final Elm327Session? session;
    try {
      session = await _connectToDevice(entry.id, picked: entry);
    } catch (error) {
      // 会话工厂/收尾的意外异常（动作层契约的调用点翻译）：行不能停在
      // 「连接中…」，回填失败文案并恢复扫描。
      if (!_disposed) {
        _resumeScanAfterPickFailed(
          entry,
          error is BleObdTransportException
              ? error.statusCopy
              : '连接失败，请重试',
        );
      }
      return;
    }
    if (_disposed ||
        session == null ||
        _session != session ||
        session.state != Elm327SessionState.connected) {
      return;
    }
    try {
      await rememberDevice(entry.id);
    } catch (_) {
      // 设备记忆只是下次直连的便利数据：偏好写失败不影响本次已建成的
      // 连接与 sheet 关闭（否则行永久停在「连接中…」）。
    }
    if (_disposed || _session != session) {
      return;
    }
    _closeScanSheet();
  }

  /// 点选连接失败回填：sheet 还在 = 行回可点态 + 文案 + 恢复扫描；sheet
  /// 已关闭（连接中被取消）= 回可恢复的未连接态，不在无人可见的相位
  /// 上伪造「扫描中」。
  void _resumeScanAfterPickFailed(BleObdScanEntry picked, String copy) {
    if (!_scanSheetOpen) {
      _phase = DiagnosticsConnectionPhase.idle;
      _statusError = null;
      _notify();
      return;
    }
    _phase = DiagnosticsConnectionPhase.scanning;
    _connectingId = null;
    _scanHint = copy;
    _notify();
    unawaited(_startScan());
  }

  /// 关闭扫描 sheet（controller 主动）：先置关闭旗（页面回来的 dismissed
  /// 回调即幂等）、撤扫描资源，再调 UI。
  void _closeScanSheet() {
    if (!_scanSheetOpen) {
      return;
    }
    _scanSheetOpen = false;
    _cancelScanResources();
    _ui?.closeScanSheet();
  }

  /// 撤扫描结果订阅 + 停扫（scanner 是共享单例，只停不释放）。
  void _cancelScanResources() {
    unawaited(_scanResultsSub?.cancel());
    _scanResultsSub = null;
    unawaited(scanner.stop());
  }

  /// 会话事件 → 连接状态（状态条/读数表）。来源同一性守卫：迟到的旧
  /// 会话事件不得改写新会话的相位；释放后一律忽略。
  void _onSessionEvent(Elm327Session session, Elm327SessionEvent event) {
    if (_disposed || !identical(session, _session)) {
      return;
    }
    switch (event) {
      case Elm327Connected():
        _phase = DiagnosticsConnectionPhase.connected;
        _statusError = null;
        _notify();
        sessionLogSink?.onSessionStart(
          DateTime.now(),
          deviceId: _currentDeviceId,
          mock: mockLink,
        );
        session.startPolling(enabledProbes: _enabledProbesSnapshot);
      case Elm327Disconnected(:final cause):
        _phase = DiagnosticsConnectionPhase.disconnected;
        _statusError = _disconnectCopy(cause);
        sessionLogSink?.onSessionEnd(DateTime.now(), reason: '$cause');
        _notify();
      case Elm327RawExchange(
          :final command,
          :final header,
          :final at,
          :final frameText,
          :final error
        ):
        // 调试终端往返（2026-11-21）：原样转交 sink，不做任何裁剪——
        // 失败的往返同样留档（`err` 字段），「没回来」本身就是要查的现象。
        sessionLogSink?.onRawExchange(
          command: command,
          header: header,
          at: at,
          rawText: frameText,
          errorText: error == null ? null : '$error',
        );
      case Elm327ProbeReading(
          :final probeId,
          :final reading,
          :final at,
          :final frameText,
          :final header
        ):
        final probe = _probeById(probeId);
        // 原始读数先入会话日志（2026-11-20）：日志记「看到的全部」，门限
        // 只管「采用哪一个」——被丢掉的晃动值必须留档，否则事后无法判断
        // 门限是否误杀。2026-11-21 起连同原始帧与生效头一起记（日志以
        // 原始字节为准，解析值只是它的一种解读）。
        if (probe != null) {
          sessionLogSink?.onProbeReading(
            probe,
            reading,
            at,
            rawText: frameText,
            header: header,
          );
        }
        final admitted = _gateFuelReading(probe, reading, at);
        if (admitted == null) {
          // 丢弃：卡片快照、最后更新时间、库里的最后读数都不动（原始值
          // 已入日志，门限判定另记 fuel_gate 行）。
          return;
        }
        _readings[probeId] = ProbeReadingSnapshot(reading: admitted, at: at);
        _notify();
        // 最后读数落库（只存有效值）：unawaited 交给事件循环，写失败
        // 不打断渲染链——读数是临时数据，下一轮轮询会再写。用 admitted
        // 而不是原始 reading：门限放行的是哪一条，落库的就是哪一条。
        if (admitted is ObdValue) {
          unawaited(
            saveReading(
              probeId,
              value: admitted.display,
              percent: admitted.percent,
              at: at,
            ).catchError((_) {}),
          );
        }
        // ECU 里程同步（ADR 0026）：有效里程读数经接缝回调（静默自动
        // 写的开关读库与守卫在接缝实现里，controller 不碰偏好与仓库）。
        if (admitted is ObdValue && admitted.kilometers != null) {
          _odometerHandler?.call(admitted);
        }
        // ECU 油量同步（ADR 0030）：门限放行后的油量读数经接缝回调。
        // 门限丢弃的晃动值不在这里——卡片显示哪一条，同步就写哪一条。
        if (probe != null &&
            probe.parseType == DiagnosticsParseType.fuelLevel &&
            admitted is ObdValue &&
            admitted.percent != null) {
          _fuelLevelHandler?.call(probe, admitted);
        }
    }
  }

  /// 轮询快照 getter（每轮开头被会话调用）：当前启用检测点清单。页面
  /// 卸载后返回空表（会话 dispose 时停轮在先，这里只是最后一道守卫）。
  List<DiagnosticsProbe> _enabledProbesSnapshot() {
    if (_disposed) {
      return const [];
    }
    // background 未推入（提醒页从未挂载过，多见于测试直连场景）时
    // 回退全量清单，避免「已连接但轮询空表」的空转连接。
    final source = _diagnosticsScope || _backgroundProbes.isEmpty
        ? _probes
        : _backgroundProbes;
    return source.where((probe) => probe.enabled).toList();
  }

  /// 释放会话与事件订阅（dispose/重连前调用，幂等）：会话与其订阅在
  /// 首行成对捕获，随后清空字段。dispose 可能长时间等待传输层断开，
  /// 期间新尝试可以创建新会话；续体只取消自己捕获的旧订阅。
  ///
  /// 会话日志收尾（2026-11-18 深审修复）：收尾行不能只挂在链路自发掉
  /// 线的 [Elm327Disconnected] 事件上——手动断开/重连清理/controller
  /// 释放都走 dispose()，其首行置释放旗，触发的断开事件在 _emit 处丢
  /// 弃，事件路径收不到。这里在释放会话前直调 sink（幂等：链路掉线
  /// 路径事件已写过一次收尾行，recorder 已空，这次是空操作）。
  Future<void> _teardownSession({String reason = '会话释放'}) async {
    final session = _session;
    final sub = _sub;
    _session = null;
    _sub = null;
    // 手动放行旗只属于「点刷新时那一个会话」：断开/重连/重建会话都作废，
    // 否则一次没读到值的刷新会在下一个会话的第一拍直显并写库。
    _manualPollBypass = false;
    if (session != null) {
      sessionLogSink?.onSessionEnd(DateTime.now(), reason: reason);
    }
    await session?.dispose();
    unawaited(sub?.cancel());
  }

  /// 会话异常 → BLE 可辨识错误（cause 链一层解包；非 BLE 链路失败返
  /// null 走会话级文案）。
  BleObdTransportException? _bleErrorOf(Elm327SessionException e) {
    final cause = e.cause;
    return cause is BleObdTransportException ? cause : null;
  }

  /// 断连原因 → 状态条错误文案：BLE 可辨识异常按 kind 映射（statusCopy
  /// 单一出口）；会话异常直接用其消息（文案在 throw 点书写）。
  String _disconnectCopy(Object? cause) {
    if (cause is BleObdTransportException) {
      return cause.statusCopy;
    }
    if (cause is Elm327SessionException) {
      return cause.message;
    }
    return '连接已断开';
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }
}
