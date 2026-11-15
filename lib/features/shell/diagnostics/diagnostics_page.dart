// 车辆诊断页（/diagnostics）：开发者模式工具页，经 BLE OBD 适配器
// 读取车辆实时数据（GLOSSARY「车辆诊断」词条，ADR 0020）。
//
// 票 05 落地三区实现（替掉票 03 占位页）：
//   1. 连接状态条：未连接/连接中/已连接/已断开 + 错误文案，断开带手
//      动重连按钮（story 7/16）；「扫描中」状态随票 07 BLE 扫描列表引入。
//   2. 核心值卡：油量（百分比大字 + 按车辆油箱容积估算升数小字，容积
//      未填只显百分比、不提示去填，story 10/11）+ 水温，横排两张。
//   3. 检测点行列表：名称 + 当前值 + 最后更新时间 + 启停开关（story
//      18/19）；单条无数据 = 行级灰态不连坐（story 15）；连接级失败
//      只上状态条、不弹窗（story 16）。
//
// 连接生命周期归页面持有（spec「会话生命周期归页面持有」）：进页面
// 建会话（首帧渲染"未连接"后自动连接）、离开断开（dispose 释放会话
// 与传输层）、断开后手动重连 = 丢弃旧会话新建实例（会话是一次性对象，
// 重连语义由会话契约给出）。连接流程（票 07）：设备记忆命中直连、无
// 记忆/直连失败自动落扫描选择 sheet（ble_scan_sheet.dart）、BLE 门禁
// 类失败（蓝牙关/不支持/权限）状态条渲染明确文案；扫描点选连接成功
// 即写记忆。启停开关走动作层（写库 → 逐出检测点 provider），轮询快
// 照 getter 每轮开头取最新启用清单——下一轮生效、不打断当前轮（会话
// 契约）。表单增改删（添加/编辑检测点）是票 06。
//
// ≈ Java 的有状态页面 + Spring 事件监听：State 持有会话引用（≈
// Service 实例），会话事件经 broadcast Stream 推送（≈ ApplicationEvent），
// 页面只做状态翻译与渲染，不做协议与数据决策。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/format/clock.dart';
import '../../../core/theme/lunio_tokens.dart';
import '../../../core/widgets/lunio_components.dart';
import '../../../data/repositories/diagnostics_repository.dart'
    show DiagnosticsRepository;
import '../../../domain/entities/car.dart';
import '../../../domain/entities/diagnostics_probe.dart';
import '../../../domain/rules/diagnostics_rules.dart';
import '../shared/shell_shared.dart';
import 'ble_obd_transport.dart';
import 'ble_scan_sheet.dart';
import 'debug_panel.dart';
import 'elm327_parser.dart' show ObdReading, ObdNoData, ObdValue;
import 'elm327_session.dart';
import 'obd_runtime.dart';
import 'probe_management_sheet.dart';

/// 页面级连接状态机（状态条渲染依据）。idle = 进页面首帧的"未连接"
/// （连接动作延到首帧之后启动，起点状态真实可达）或扫描 sheet 取消后
/// 的"未连接"；scanning = 扫描 sheet 打开中（票 07）。
enum DiagnosticsConnectionPhase { idle, scanning, connecting, connected, disconnected }

/// 单条检测点的最新读取快照（值 + 读取时刻，行尾"最后更新时间"的数据
/// 源，story 14）。键 = 检测点行 id。
class _ReadingSnapshot {
  const _ReadingSnapshot(this.reading, this.at);

  final ObdReading reading;

  /// 读取时刻（会话注入时钟打点）。
  final DateTime at;
}

/// 车辆诊断页主组件。
class DiagnosticsPage extends ConsumerStatefulWidget {
  const DiagnosticsPage({super.key});

  @override
  ConsumerState<DiagnosticsPage> createState() => DiagnosticsPageState();
}

class DiagnosticsPageState extends ConsumerState<DiagnosticsPage> {
  /// 当前会话实例（一次性对象；重连 = 丢弃新建）。null = 已释放。
  Elm327Session? _session;

  /// 会话事件订阅（dispose/重连前退订，防泄漏）。
  StreamSubscription<Elm327SessionEvent>? _sub;

  /// 页面级连接阶段（状态条单一事实源；会话状态经事件传导到这里）。
  DiagnosticsConnectionPhase _phase = DiagnosticsConnectionPhase.idle;

  /// 断连错误文案（"已断开"状态下状态条的错误说明；null = 无补充说明）。
  String? _statusError;

  /// 扫描 sheet 句柄（非 null = sheet 在栈顶；_onScanSheetClosed 清空）。
  BleScanSheetHandle? _scanSheetHandle;

  /// 连接尝试代数（每次 _connectToDevice 自增）：关闭扫描 sheet/取消
  /// 连接时自增作废在途尝试，迟到的失败回填不再改写页面相位。
  int _connectAttempt = 0;

  /// 最新读取快照表（键 = 检测点行 id；行列表与核心值卡共用）。
  final Map<int, _ReadingSnapshot> _readings = {};

  /// 最新检测点清单（build 数据分支捕获）。轮询快照 getter 读它——
  /// 不读 provider 的 AsyncValue.value（invalidate 后读侧是陈旧值，
  /// 启停会晚一轮生效）。
  List<DiagnosticsProbe> _probes = const [];

  /// 进页面首帧先渲染"未连接"，连接动作延到首帧之后启动——状态机起
  /// 点状态真实可达（story 链路：未连接→连接中→已连接→断开/错误），
  /// widget 测试能按序断言全状态序列。
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_startConnect());
    });
  }

  /// 进页面自动连接与「重连」按钮的入口：设备记忆命中 → 直连
  ///（"连接中"）；无记忆 → 落扫描 sheet（story 4/5）。扫描点选走
  /// [_connectToPicked] → [_connectToDevice]，「选择设备」按钮走
  /// [_openScanSheet]。mock 回退链路（dart-define）跳过扫描与记忆，
  /// 直连演示设备。
  Future<void> _startConnect() async {
    if (_phase == DiagnosticsConnectionPhase.connecting ||
        _phase == DiagnosticsConnectionPhase.scanning) {
      return;
    }
    if (obdMockLink) {
      await _connectToDevice('mock-device');
      return;
    }
    final preferences = ref.read(lunioPreferencesProvider);
    final remembered = await preferences.getLastObdDeviceId();
    if (!mounted) {
      return;
    }
    if (remembered == null) {
      await _openScanSheet();
      return;
    }
    await _connectToDevice(remembered);
  }

  /// 直连指定设备（记忆直连/扫描点选共用）：置连接中 → 释放旧会话 →
  /// 工厂新建会话 → 先听后连 → connect()。返回**本次尝试成功且仍是
  /// 当前会话**的实例（取消/失败/被替换返 null），点选回调按它判成功，
  /// 不读可能已被新尝试替换的 `_session`。失败按错误类别分流（story
  /// 5/8）：BLE 门禁类（蓝牙关/不支持/权限）状态条渲染错误文案；设备/
  /// 链路类（未扫到/建链失败）直连落扫描 sheet、点选流回填 sheet 行态
  /// 并恢复扫描；会话级（AT 超时等，适配器在但芯片无响应）状态条渲染
  /// 错误文案。状态条由 Disconnected 事件驱动（单一事实源），这里只做
  /// 降级分流。
  Future<Elm327Session?> _connectToDevice(String deviceId,
      {BleObdScanEntry? picked}) async {
    final attempt = ++_connectAttempt;
    setState(() {
      _phase = DiagnosticsConnectionPhase.connecting;
      _statusError = null;
    });
    await _teardownSession();
    if (!mounted || attempt != _connectAttempt) {
      return null;
    }
    final session = ref.read(obdSessionFactoryProvider)(deviceId);
    _session = session;
    _sub = session.events.listen(_onSessionEvent);
    try {
      await session.connect();
      if (!mounted || attempt != _connectAttempt) {
        return null;
      }
      return session;
    } on Elm327SessionException catch (e) {
      // 页面已退出，或连接已被取消（连接中关闭扫描 sheet）：迟到的
      // 失败不再改写相位、不再回填 sheet。
      if (!mounted || attempt != _connectAttempt) {
        return null;
      }
      final ble = _bleErrorOf(e);
      if (ble == null) {
        // 会话级失败（AT 超时等，适配器在但芯片无响应）：状态条已由
        // Disconnected 事件渲染错误文案；点选流 sheet 还开着、行不能
        // 停在"连接中…"——同样回填失败态恢复扫描。
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
        // 行态 + 恢复扫描（sheet 不关，story 6 状态反馈在列表里）。
        if (ble.kind.isGateError || ble.kind == BleObdLinkErrorKind.linkLost) {
          _scanSheetHandle?.close();
        } else {
          _resumeScanAfterPickFailed(picked, ble.statusCopy);
        }
        return null;
      }
      if (!ble.kind.isGateError) {
        // 记忆直连的设备/链路类失败：落扫描 sheet（story 5"直连失败
        // 落扫描列表"）。门禁类保持断开态错误文案，用户按文案去修系
        // 统状态，扫描也扫不出结果。
        unawaited(_openScanSheet());
      }
      return null;
    }
  }

  /// 点选连接失败回填：sheet 还在 = 行回可点 + 文案 + 恢复扫描；sheet
  /// 已关闭（连接中被取消）= 回可恢复的未连接态，不在无人可见的相位
  /// 上伪造"扫描中"。
  void _resumeScanAfterPickFailed(BleObdScanEntry picked, String copy) {
    final handle = _scanSheetHandle;
    if (handle == null) {
      setState(() {
        _phase = DiagnosticsConnectionPhase.idle;
      });
      return;
    }
    setState(() {
      _phase = DiagnosticsConnectionPhase.scanning;
    });
    handle.reportPickFailed(picked, copy);
  }

  /// 会话异常 → BLE 可辨识错误（cause 链一层解包；非 BLE 链路失败返
  /// null 走会话级文案）。
  BleObdTransportException? _bleErrorOf(Elm327SessionException e) {
    final cause = e.cause;
    return cause is BleObdTransportException ? cause : null;
  }

  /// 扫描点选（sheet 行点击回调）：建链成功即记忆（story 4 前提）+ 关
  /// sheet；失败由 _connectToDevice 分流回 sheet。成功判据用返回值与
  /// 当前会话同一性（await connect() 恢复时广播事件尚未递送，页面相
  /// 位此刻还是 connecting——状态条由事件单一事实源渲染，这里不看
  /// 它）。取消后重选的新尝试已把 `_session` 换成新实例，旧续体按同
  /// 一性检查退出，不会写旧设备标识或关掉新 sheet。
  Future<void> _connectToPicked(BleObdScanEntry entry) async {
    final session = await _connectToDevice(entry.id, picked: entry);
    if (!mounted ||
        session == null ||
        _session != session ||
        session.state != Elm327SessionState.connected) {
      return;
    }
    await rememberObdDevice(ref, entry.id);
    if (!mounted || _session != session) {
      return;
    }
    _scanSheetHandle?.close();
  }

  /// 打开扫描 sheet（story 5）：先过适配器门禁（无记忆首用不能把
  /// 权限拒绝/蓝牙未开藏进空列表——门禁失败状态条渲染文案、不落扫
  /// 描），再置扫描中相位。sheet 关闭回调里扫描中相位回 idle（取消
  /// 路径），连接中关闭 = 取消本次连接。
  Future<void> _openScanSheet() async {
    if (_scanSheetHandle != null) {
      return;
    }
    try {
      await ref.read(obdScannerProvider).ensureReady();
    } on BleObdTransportException catch (e) {
      if (!mounted) {
        return;
      }
      if (!e.kind.isGateError) {
        _openScanSheetNow();
      } else {
        setState(() {
          _phase = DiagnosticsConnectionPhase.disconnected;
          _statusError = e.statusCopy;
        });
      }
      return;
    } catch (_) {
      // 未知门禁异常仍落 sheet，由 sheet 顶部提示兜底。
      if (!mounted) {
        return;
      }
      _openScanSheetNow();
      return;
    }
    if (!mounted ||
        _scanSheetHandle != null ||
        _phase == DiagnosticsConnectionPhase.connecting ||
        _phase == DiagnosticsConnectionPhase.connected) {
      return;
    }
    _openScanSheetNow();
  }

  /// 门禁已过/兜底路径：置扫描中并挂 sheet。
  void _openScanSheetNow() {
    if (!mounted || _scanSheetHandle != null) {
      return;
    }
    setState(() {
      _phase = DiagnosticsConnectionPhase.scanning;
    });
    _scanSheetHandle = showBleScanSheet(
      context,
      onDevicePicked: (entry) => unawaited(_connectToPicked(entry)),
      onGateFailed: _onScanGateFailed,
      onClosed: _onScanSheetClosed,
    );
  }

  /// sheet 关闭回调：句柄清空 + 相位收尾。扫描中关闭 = 取消扫描回
  /// 未连接；**连接中关闭 = 取消本次连接**（在途建链可能还要等 15
  /// 秒，不能把页面停在无 sheet 的"连接中"）。
  void _onScanSheetClosed() {
    _scanSheetHandle = null;
    if (!mounted) return;
    if (_phase == DiagnosticsConnectionPhase.connecting) {
      // 建链成功但 Connected 事件尚未递送（点选成功路径会在这里关
      // sheet）：不取消已成功的连接，相位交给事件渲染。
      if (_session?.state == Elm327SessionState.connected) {
        return;
      }
      _connectAttempt++;
      unawaited(_teardownSession());
      setState(() {
        _phase = DiagnosticsConnectionPhase.idle;
        _statusError = null;
      });
      return;
    }
    if (_phase == DiagnosticsConnectionPhase.scanning) {
      setState(() {
        _phase = DiagnosticsConnectionPhase.idle;
      });
    }
  }

  /// 扫描启动时的门禁失败（Android 运行时权限在 startScan 才请求）：
  /// 关 sheet，由状态条渲染错误文案（story 8）。
  void _onScanGateFailed(BleObdTransportException error) {
    if (!mounted) {
      return;
    }
    _scanSheetHandle?.close();
    setState(() {
      _phase = DiagnosticsConnectionPhase.disconnected;
      _statusError = error.statusCopy;
    });
  }

  /// 手动断开（已连接相位「断开」按钮，2026-11-15 新增）：释放会话并
  /// 落「未连接」相位——手动断开不是异常，不落红色「已断开」；设备记
  /// 忆不清除（重进页面仍自动直连记忆设备）。连接尝试代数自增作废在
  /// 途尝试，迟到的失败回填不改写相位。
  Future<void> _disconnectManually() async {
    _connectAttempt++;
    setState(() {
      _phase = DiagnosticsConnectionPhase.idle;
      _statusError = null;
    });
    await _teardownSession();
  }

  /// 会话事件 → 页面状态（状态条/读取快照表），每处进 setState 前
  /// mounted 守卫（dispose 后迟到事件不再改 UI）。会话为 null（已释放/
  /// 已手动断开）时迟到事件一律忽略——手动断开后迟到的 Disconnected
  /// 事件不再把「未连接」改写成「已断开」。
  void _onSessionEvent(Elm327SessionEvent event) {
    if (!mounted || _session == null) {
      return;
    }
    switch (event) {
      case Elm327Connected():
        setState(() {
          _phase = DiagnosticsConnectionPhase.connected;
          _statusError = null;
        });
        _session?.startPolling(enabledProbes: _enabledProbesSnapshot);
      case Elm327Disconnected(:final cause):
        setState(() {
          _phase = DiagnosticsConnectionPhase.disconnected;
          _statusError = _disconnectCopy(cause);
        });
      case Elm327ProbeReading(:final probeId, :final reading, :final at):
        setState(() {
          _readings[probeId] = _ReadingSnapshot(reading, at);
        });
        // 最后读数落库（只存有效值）：unawaited 交给事件循环，写失败
        // 不打断渲染链——读数是临时数据，下一轮轮询会再写。
        if (reading is ObdValue) {
          final repository = ref.read(diagnosticsRepositoryProvider);
          unawaited(
            repository
                .saveProbeReading(
                  probeId,
                  value: reading.display,
                  percent: reading.percent,
                  at: at,
                )
                .catchError((_) {}),
          );
        }
    }
  }

  /// 释放会话与事件订阅（dispose/重连前调用，幂等）：会话与其订阅在
  /// 首行成对捕获，随后清空页面字段。dispose 可能长时间等待传输层断
  /// 开，期间新尝试可以创建新会话；续体只取消自己捕获的旧订阅，不会
  /// 误取消新会话的订阅。
  Future<void> _teardownSession() async {
    final session = _session;
    final sub = _sub;
    _session = null;
    _sub = null;
    // 先 dispose 会话（停轮 + 断开传输层 + 关事件流——离开页断开的可
    // 观察出口在它身上），事件订阅取消放后且不等待其完成时机（广播订
    // 阅取消的完成时机与假异步环境耦合，不该挡住会话释放）。
    await session?.dispose();
    unawaited(sub?.cancel());
  }

  /// 释放会话（离开页面断开，story 9）：dispose 是同步签名，会话释放
  /// 是异步链——unawaited 交给事件循环，widget 测试用例收尾经 pump 冲
  /// 刷余量定时器（夹具惯用语）。
  @override
  void dispose() {
    unawaited(_teardownSession());
    super.dispose();
  }

  /// 轮询快照 getter（每轮开头被会话调用）：当前启用检测点清单。读
  /// provider 当前值（不碰 BuildContext）；页面卸载后返回空表（会话
  /// dispose 时停轮在先，这里只是最后一道守卫）。
  List<DiagnosticsProbe> _enabledProbesSnapshot() {
    if (!mounted) {
      return const [];
    }
    return _probes.where((probe) => probe.enabled).toList();
  }

  /// 检测点快照取值（行列表与核心值卡共源）：实时读数优先（本会话的
  /// 最新轮询），页内还没有实时读数时回退持久化的最后读数（重进页面
  /// 可见，2026-11-15）。两者都无 = null（行显"—/未更新"，卡显占位）。
  _ReadingSnapshot? _snapshotFor(DiagnosticsProbe probe) {
    final live = _readings[probe.id];
    if (live != null) {
      return live;
    }
    final value = probe.lastValue;
    final at = probe.lastReadingAt;
    if (value == null || at == null) {
      return null;
    }
    // 重建快照：display + percent 足够渲染（水温/电压只显 display，
    // 油量卡升数估算用 percent）；celsius 不持久化，重建后不需要。
    return _ReadingSnapshot(
      ObdValue(display: value, percent: probe.lastPercent),
      at,
    );
  }

  /// 返回键（pushed 子页，LunioTopBar leading 位，费用统计页先例）。
  Widget _backKey() => LunioIconButton(
        icon: Icons.arrow_back_ios_new,
        tooltip: '返回',
        onPressed: () => context.pop(),
      );

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    // 检测点列表单门卫收口（费用统计页先例）：loading/error 整页占位。
    // 会话连接与检测点列表互相独立（initState 已启动，不受列表装载影
    // 响），装载失败只影响列表区，连接状态条随数据分支一起消失——与
    // 三页主数据门卫同构。
    // 检测点每车一套（ADR 0021 修订节）：先取当前应用车辆，再 watch
    // 它自己的 family；无车时页面只给空态提示。
    final appliedCarAsync = ref.watch(appliedCarProvider);
    final appliedCar = appliedCarAsync.maybeWhen(
      data: (car) => car,
      orElse: () => null,
    );
    final carId = appliedCar?.id;
    final Widget body;
    if (appliedCarAsync.isLoading && !appliedCarAsync.hasValue) {
      body = const LoadingPage(title: '车辆诊断');
    } else if (appliedCarAsync.hasError && !appliedCarAsync.hasValue) {
      body = ErrorPage(
        title: '车辆诊断',
        error: appliedCarAsync.error!,
        leading: _backKey(),
      );
    } else if (carId == null) {
      body = LunioPage(
        title: '车辆诊断',
        leading: _backKey(),
        // 空态占位统一走 LunioEmptyCard（记录/加油/费用统计三页同文案
        // 先例），不手写 Padding + Center + Text。
        children: const [LunioEmptyCard('请先新增车辆')],
      );
    } else {
      final probesAsync = ref.watch(diagnosticsProbesProvider(carId));
      body = probesAsync.when(
        // skipLoadingOnReload：启停写库后的列表重算窗口保持旧内容渲染
        //（逐出重算只是换数据源，不该整页闪加载占位），fresh 到达自然重绘。
        skipLoadingOnReload: true,
        loading: () => const LoadingPage(title: '车辆诊断'),
        error: (error, stackTrace) =>
            ErrorPage(title: '车辆诊断', error: error, leading: _backKey()),
        data: (probes) {
          _probes = probes;
          return _buildContent(context, probes, appliedCar, carId);
        },
      );
    }
    // pushed 子页不经过 AppShell，Scaffold（页面底色）要自己提供——
    // 页内 InkWell/chips 需要 Material 祖先，与 AppShell 同款底色。
    return Scaffold(backgroundColor: tokens.background, body: body);
  }

  /// 三区内容组装：状态条 → 核心值卡横排 → 检测点行列表。
  Widget _buildContent(
    BuildContext context,
    List<DiagnosticsProbe> probes,
    Car? appliedCar,
    int carId,
  ) {
    final fuelProbe = _probeByCatalogKey(
      probes,
      DiagnosticsRepository.builtInFuelLevelKey,
    );
    final coolantProbe = _probeByCatalogKey(
      probes,
      DiagnosticsRepository.builtInCoolantKey,
    );
    return LunioPage(
      title: '车辆诊断',
      leading: _backKey(),
      bottomPadding: 24,
      children: [
        _buildStatusCard(context),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _buildFuelCard(context, fuelProbe, appliedCar)),
            const SizedBox(width: 12),
            Expanded(child: _buildCoolantCard(context, coolantProbe)),
          ],
        ),
        const SizedBox(height: 18),
        LunioSection(
          title: '检测点',
          children: [
            for (final probe in probes)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _ProbeRow(
                  probe: probe,
                  snapshot: _snapshotFor(probe),
                  onToggle: (value) =>
                      setDiagnosticsProbeEnabled(ref, probe, value),
                ),
              ),
            _AddProbeRow(
              onTap: () => showProbeManagementSheet(
                context,
                car: appliedCar!,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        DiagnosticsDebugPanel(
          session: _session,
          connected: _phase == DiagnosticsConnectionPhase.connected,
          carLabel: '${appliedCar?.brand ?? ''} ${appliedCar?.model ?? ''}'
              .trim(),
        ),
      ],
    );
  }

  /// 状态条（第一区）：阶段徽标 + 说明文案；"已断开"追加错误文案与
  /// 手动重连按钮（story 7/16：连接级失败只上状态条、不弹窗）。
  Widget _buildStatusCard(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    final (label, tone) = switch (_phase) {
      DiagnosticsConnectionPhase.idle => ('未连接', LunioStatusTone.warning),
      DiagnosticsConnectionPhase.scanning => ('扫描中', LunioStatusTone.warning),
      DiagnosticsConnectionPhase.connecting => ('连接中', LunioStatusTone.warning),
      DiagnosticsConnectionPhase.connected => ('已连接', LunioStatusTone.normal),
      DiagnosticsConnectionPhase.disconnected => (
        '已断开',
        LunioStatusTone.danger,
      ),
    };
    final hintText = switch (_phase) {
      DiagnosticsConnectionPhase.idle => '未连接适配器',
      DiagnosticsConnectionPhase.scanning => obdScanningHint,
      DiagnosticsConnectionPhase.connecting => '正在建立连接…',
      DiagnosticsConnectionPhase.connected => '已连接 · 正在轮询启用检测点',
      DiagnosticsConnectionPhase.disconnected => _statusError ?? '连接已断开',
    };
    // 行尾动作按钮（按相位显隐）：断开=重连；未连接/扫描中=选择设备
    //（重开扫描 sheet 的再入口）；已连接=断开（2026-11-15 新增，落
    // 未连接相位）；连接中无动作（拍板保持范围，不加取消）。
    final actionLabel = switch (_phase) {
      DiagnosticsConnectionPhase.disconnected => '重连',
      DiagnosticsConnectionPhase.idle ||
      DiagnosticsConnectionPhase.scanning => '选择设备',
      DiagnosticsConnectionPhase.connected => '断开',
      DiagnosticsConnectionPhase.connecting => null,
    };
    return LunioCard(
      child: Row(
        children: [
          LunioStatusBadge(label: label, tone: tone),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              hintText,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: tokens.muted),
            ),
          ),
          if (_phase == DiagnosticsConnectionPhase.connected)
            IconButton(
              tooltip: '立即刷新',
              onPressed: () => _session?.requestImmediatePoll(),
              icon: const Icon(Icons.refresh, size: 20),
              visualDensity: VisualDensity.compact,
              color: tokens.primary,
            ),
          if (actionLabel != null)
            TextButton(
              onPressed: switch (_phase) {
                DiagnosticsConnectionPhase.disconnected =>
                  () => unawaited(_startConnect()),
                DiagnosticsConnectionPhase.connected =>
                  () => unawaited(_disconnectManually()),
                _ => () => unawaited(_openScanSheet()),
              },
              // 紧凑行尾按钮（ProfileSettingRow 同款）——LunioSecondaryButton
              // 的 FilledButton 带主题全宽 minimumSize，放进 Row 拿到无界
              // 宽约束直接布局崩溃。
              style: TextButton.styleFrom(
                backgroundColor: tokens.surface2,
                foregroundColor: tokens.primary,
                minimumSize: const Size(0, 34),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(tokens.radiusSmall),
                  side: BorderSide(color: tokens.line),
                ),
              ),
              child: Text(actionLabel),
            ),
        ],
      ),
    );
  }

  /// 油量卡（第二区左）：百分比大字 + 双油量小字（ADR 0022）。可用油量
  /// 用加满可加油量；总油量 = 储备 + 可用，总容积未填只显可用。容积未
  /// 填只显百分比、不提示去填（story 11）；无读取/无数据显占位符。
  Widget _buildFuelCard(
    BuildContext context,
    DiagnosticsProbe? fuelProbe,
    Car? appliedCar,
  ) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    final snapshot = fuelProbe == null ? null : _snapshotFor(fuelProbe);
    final reading = snapshot?.reading;
    // 油量百分比只认 fuelLevel 解析类型的值（无数据/未读取都显占位符）。
    final percent = reading is ObdValue ? reading.percent : null;
    final estimate = percent == null
        ? null
        : DiagnosticsRules.estimateFuel(
            percent: percent,
            tankCapacityLiters: appliedCar?.tankCapacityLiters,
            totalTankCapacityLiters: appliedCar?.totalTankCapacityLiters,
          );
    return LunioCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('油量', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 6),
          Text(
            reading?.display ?? '—',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: reading is ObdNoData ? tokens.subtle : tokens.ink,
                ),
          ),
          if (estimate != null) ...[
            const SizedBox(height: 4),
            Text(
              estimate.totalLiters == null
                  ? '≈ ${estimate.usableLiters.toStringAsFixed(1)} 升'
                  : '可用 ${estimate.usableLiters.toStringAsFixed(1)} 升 · '
                      '估算总油量 ${estimate.totalLiters!.toStringAsFixed(1)} 升',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: tokens.muted,
                  ),
            ),
          ],
        ],
      ),
    );
  }

  /// 水温卡（第二区右）：温度大字。无读取/无数据显占位符（灰态）。
  Widget _buildCoolantCard(
    BuildContext context,
    DiagnosticsProbe? coolantProbe,
  ) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    final snapshot = coolantProbe == null
        ? null
        : _snapshotFor(coolantProbe);
    final reading = snapshot?.reading;
    return LunioCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('水温', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 6),
          Text(
            reading?.display ?? '—',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: reading is ObdNoData ? tokens.subtle : tokens.ink,
                ),
          ),
        ],
      ),
    );
  }

  /// 按内置 catalogKey 定位内置检测点（核心值卡数据源；key 常量与种
  /// 子对账共用一份，DiagnosticsRepository 单一事实源）。
  DiagnosticsProbe? _probeByCatalogKey(
    List<DiagnosticsProbe> probes,
    String catalogKey,
  ) {
    for (final probe in probes) {
      if (probe.catalogKey == catalogKey) {
        return probe;
      }
    }
    return null;
  }

  /// 断连原因 → 状态条错误文案（story 7/16/8）。BLE 可辨识异常按 kind
  /// 映射（statusCopy 单一出口）；会话异常直接用其消息（消息文案在
  /// throw 点书写）；其他原因类型给通用文案。
  String _disconnectCopy(Object? cause) {
    if (cause is BleObdTransportException) {
      return cause.statusCopy;
    }
    if (cause is Elm327SessionException) {
      return cause.message;
    }
    return '连接已断开';
  }
}

/// 检测点行（第三区）：名称 + 当前值 + 最后更新时间 + 启停开关（story
/// 18/19）。无数据 = 行级灰态（值列灰字"无数据"），其他行照常更新，
/// 不连坐（story 15）；未读取（连接后还没轮到）显"—"与"未更新"。
class _ProbeRow extends StatelessWidget {
  const _ProbeRow({
    required this.probe,
    required this.snapshot,
    required this.onToggle,
  });

  final DiagnosticsProbe probe;

  /// 最新读取快照（null = 未读取）。
  final _ReadingSnapshot? snapshot;

  /// 启停开关回调（动作层编排：写库 → 逐出检测点 provider）。
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    final snapshot = this.snapshot;
    final reading = snapshot?.reading;
    final isNoData = reading is ObdNoData;
    final valueText = reading?.display ?? '—';
    // 跨天读数带日期（今天 HH:mm:ss、非今天 M/d HH:mm:ss，2026-11-15）。
    final timeText = snapshot == null
        ? '未更新'
        : formatReadingTime(snapshot.at, now: DateTime.now());
    final row = Row(
      children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(probe.name, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(
                  timeText,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: tokens.muted,
                      ),
                ),
                if (reading is ObdNoData) ...[
                  const SizedBox(height: 2),
                  Text(
                    reading.reason,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: tokens.subtle,
                        ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              valueText,
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: isNoData ? tokens.subtle : tokens.ink,
                  ),
            ),
          ),
          const SizedBox(width: 12),
          Switch(value: probe.enabled, onChanged: onToggle),
        ],
    );
    // 页面只负责实时读数；编辑/增删统一走管理 sheet（项目看齐）。
    return LunioCard(child: row);
  }
}

/// 列表尾"管理检测点"行：打开项目式的检测点管理 sheet（新增/编辑/
/// 启停/删除都在 sheet 内）。
class _AddProbeRow extends StatelessWidget {
  const _AddProbeRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    return LunioTappableCard(
      onTap: onTap,
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.tune, size: 18, color: tokens.muted),
            const SizedBox(width: 6),
            Text(
              '管理检测点',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: tokens.muted,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
