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
import 'elm327_parser.dart' show ObdReading, ObdNoData, ObdValue;
import 'elm327_session.dart';
import 'obd_runtime.dart';
import 'probe_form.dart';

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

  /// 连接流程单一入口（进页面自动触发 / 重连按钮 / 扫描点选都汇到
  /// 它）：设备记忆命中 → 直连（"连接中"）；无记忆 → 落扫描 sheet
  /// （story 4/5）。mock 回退链路（dart-define）跳过扫描与记忆，直连
  /// 演示设备。
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
      _openScanSheet();
      return;
    }
    await _connectToDevice(remembered);
  }

  /// 直连指定设备（记忆直连/扫描点选共用）：置连接中 → 释放旧会话 →
  /// 工厂新建会话 → 先听后连 → connect()。失败按错误类别分流（story
  /// 5/8）：BLE 门禁类（蓝牙关/不支持/权限）状态条渲染错误文案；设备/
  /// 链路类（未扫到/建链失败）直连落扫描 sheet、点选流回填 sheet 行态
  /// 并恢复扫描；会话级（AT 超时等，适配器在但芯片无响应）状态条渲染
  /// 错误文案。状态条由 Disconnected 事件驱动（单一事实源），这里只做
  /// 降级分流。
  Future<void> _connectToDevice(String deviceId,
      {BleObdScanEntry? picked}) async {
    setState(() {
      _phase = DiagnosticsConnectionPhase.connecting;
      _statusError = null;
    });
    await _teardownSession();
    final session = ref.read(obdSessionFactoryProvider)(deviceId);
    _session = session;
    _sub = session.events.listen(_onSessionEvent);
    try {
      await session.connect();
      return;
    } on Elm327SessionException catch (e) {
      final ble = _bleErrorOf(e);
      if (!mounted) {
        return;
      }
      if (ble == null) {
        // 会话级失败（AT 超时等，适配器在但芯片无响应）：状态条已由
        // Disconnected 事件渲染错误文案；点选流 sheet 还开着、行不能
        // 停在"连接中…"——同样回填失败态恢复扫描。
        if (picked != null) {
          setState(() {
            _phase = DiagnosticsConnectionPhase.scanning;
          });
          final detail = e.cause is Elm327SessionException
              ? (e.cause as Elm327SessionException).message
              : e.message;
          _scanSheetHandle?.reportPickFailed(picked, detail);
        }
        return;
      }
      if (picked != null) {
        // 扫描点选流：门禁类关 sheet 露出错误状态条；设备/链路类回填
        // 行态 + 恢复扫描（sheet 不关，story 6 状态反馈在列表里）。
        if (ble.kind.isGateError || ble.kind == BleObdLinkErrorKind.linkLost) {
          _scanSheetHandle?.close();
        } else {
          setState(() {
            _phase = DiagnosticsConnectionPhase.scanning;
          });
          _scanSheetHandle?.reportPickFailed(picked, ble.statusCopy);
        }
        return;
      }
      if (!ble.kind.isGateError) {
        // 记忆直连的设备/链路类失败：落扫描 sheet（story 5"直连失败
        // 落扫描列表"）。门禁类保持断开态错误文案，用户按文案去修系
        // 统状态，扫描也扫不出结果。
        _openScanSheet();
      }
    }
  }

  /// 会话异常 → BLE 可辨识错误（cause 链一层解包；非 BLE 链路失败返
  /// null 走会话级文案）。
  BleObdTransportException? _bleErrorOf(Elm327SessionException e) {
    final cause = e.cause;
    return cause is BleObdTransportException ? cause : null;
  }

  /// 扫描点选（sheet 行点击回调）：建链成功即记忆（story 4 前提）+ 关
  /// sheet；失败由 _connectToDevice 分流回 sheet。成功判据用会话状态
  ///（await connect() 恢复时广播事件尚未递送，页面相位此刻还是
  /// connecting——状态条由事件单一事实源渲染，这里不看它）。
  Future<void> _connectToPicked(BleObdScanEntry entry) async {
    await _connectToDevice(entry.id, picked: entry);
    final session = _session;
    if (!mounted ||
        session == null ||
        session.state != Elm327SessionState.connected) {
      return;
    }
    await rememberObdDevice(ref, entry.id);
    _scanSheetHandle?.close();
  }

  /// 打开扫描 sheet（story 5）：置扫描中相位；sheet 关闭回调里扫描中
  /// 相位回 idle（取消路径），成功/门禁失败关闭保持原相位。
  void _openScanSheet() {
    if (_scanSheetHandle != null) return;
    setState(() {
      _phase = DiagnosticsConnectionPhase.scanning;
    });
    _scanSheetHandle = showBleScanSheet(
      context,
      onDevicePicked: (entry) => unawaited(_connectToPicked(entry)),
      onClosed: _onScanSheetClosed,
    );
  }

  /// sheet 关闭回调：句柄清空 + 扫描中相位回 idle（取消/下滑路径）。
  void _onScanSheetClosed() {
    _scanSheetHandle = null;
    if (!mounted) return;
    if (_phase == DiagnosticsConnectionPhase.scanning) {
      setState(() {
        _phase = DiagnosticsConnectionPhase.idle;
      });
    }
  }

  /// 会话事件 → 页面状态（状态条/读取快照表），每处进 setState 前
  /// mounted 守卫（dispose 后迟到事件不再改 UI）。
  void _onSessionEvent(Elm327SessionEvent event) {
    if (!mounted) {
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
    }
  }

  /// 释放会话与事件订阅（dispose/重连前调用，幂等）：退订事件流 →
  /// 会话 dispose（停轮 + 断开传输层 + 关事件流）。
  Future<void> _teardownSession() async {
    final session = _session;
    _session = null;
    // 先 dispose 会话（停轮 + 断开传输层 + 关事件流——离开页断开的可
    // 观察出口在它身上），事件订阅取消放后且不等待其完成时机（广播订
    // 阅取消的完成时机与假异步环境耦合，不该挡住会话释放）。
    await session?.dispose();
    unawaited(_sub?.cancel());
    _sub = null;
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
    final probesAsync = ref.watch(diagnosticsProbesProvider);
    // 油箱容积（油量卡升数估算的数据源，story 10/11）：当前应用车辆
    // 就绪才取，未就绪/无车按未填处理（只显百分比）。
    final appliedCar = ref
        .watch(appliedCarProvider)
        .maybeWhen(data: (car) => car, orElse: () => null);
    final Widget body = probesAsync.when(
      // skipLoadingOnReload：启停写库后的列表重算窗口保持旧内容渲染
      //（逐出重算只是换数据源，不该整页闪加载占位），fresh 到达自然重绘。
      skipLoadingOnReload: true,
      loading: () => const LoadingPage(title: '车辆诊断'),
      error: (error, stackTrace) =>
          ErrorPage(title: '车辆诊断', error: error, leading: _backKey()),
      data: (probes) {
        _probes = probes;
        return _buildContent(context, probes, appliedCar);
      },
    );
    // pushed 子页不经过 AppShell，Scaffold（页面底色）要自己提供——
    // 页内 InkWell/chips 需要 Material 祖先，与 AppShell 同款底色。
    return Scaffold(backgroundColor: tokens.background, body: body);
  }

  /// 三区内容组装：状态条 → 核心值卡横排 → 检测点行列表。
  Widget _buildContent(
    BuildContext context,
    List<DiagnosticsProbe> probes,
    Car? appliedCar,
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
                  snapshot: _readings[probe.id],
                  onToggle: (value) =>
                      setDiagnosticsProbeEnabled(ref, probe, value),
                  onTap: probe.isBuiltIn
                      ? null
                      : () => showProbeFormSheet(context, ref, probe: probe),
                ),
              ),
            _AddProbeRow(
              onTap: () => showProbeFormSheet(context, ref),
            ),
          ],
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
    //（重开扫描 sheet 的再入口）。
    final actionLabel = switch (_phase) {
      DiagnosticsConnectionPhase.disconnected => '重连',
      DiagnosticsConnectionPhase.idle ||
      DiagnosticsConnectionPhase.scanning => '选择设备',
      DiagnosticsConnectionPhase.connecting ||
      DiagnosticsConnectionPhase.connected => null,
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
          if (actionLabel != null)
            TextButton(
              onPressed: _phase == DiagnosticsConnectionPhase.disconnected
                  ? () => unawaited(_startConnect())
                  : () => _openScanSheet(),
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

  /// 油量卡（第二区左）：百分比大字 + 估算升数小字（story 10）。容积
  /// 未填只显百分比、不提示去填（story 11）；无读取/无数据显占位符。
  Widget _buildFuelCard(
    BuildContext context,
    DiagnosticsProbe? fuelProbe,
    Car? appliedCar,
  ) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    final snapshot = fuelProbe == null ? null : _readings[fuelProbe.id];
    final reading = snapshot?.reading;
    // 油量百分比只认 fuelLevel 解析类型的值（无数据/未读取都显占位符）。
    final percent = reading is ObdValue ? reading.percent : null;
    final liters = percent == null
        ? null
        : DiagnosticsRules.estimateFuelLiters(
            percent,
            appliedCar?.tankCapacityLiters,
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
          if (liters != null) ...[
            const SizedBox(height: 4),
            Text(
              '≈ ${liters.toStringAsFixed(1)} 升',
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
    final snapshot = coolantProbe == null ? null : _readings[coolantProbe.id];
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
    this.onTap,
  });

  final DiagnosticsProbe probe;

  /// 最新读取快照（null = 未读取）。
  final _ReadingSnapshot? snapshot;

  /// 启停开关回调（动作层编排：写库 → 逐出检测点 provider）。
  final ValueChanged<bool> onToggle;

  /// 整行点按 → 编辑表单（仅自定义行非 null；内置行 null = 无编辑入口，
  /// story 23"内置三件套只能启停、不可改删"的 UI 呈现）。
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    final snapshot = this.snapshot;
    final reading = snapshot?.reading;
    final isNoData = reading is ObdNoData;
    final valueText = reading?.display ?? '—';
    final timeText = snapshot == null ? '未更新' : formatClock(snapshot.at);
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
    // 内置行 = 普通卡（点按无反应，story 23 只读守卫的 UI 呈现）；
    // 自定义行 = 整卡可点进编辑表单（LunioTappableCard：卡圆角与水波
    // 裁剪圆角组件内部对齐，不手写三明治）。
    if (onTap == null) {
      return LunioCard(child: row);
    }
    return LunioTappableCard(onTap: onTap!, child: row);
  }
}

/// 列表尾"添加检测点"行（story 20 入口）：整卡可点，居中 ＋ 图标 + 文案。
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
            Icon(Icons.add, size: 18, color: tokens.muted),
            const SizedBox(width: 6),
            Text(
              '添加检测点',
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
