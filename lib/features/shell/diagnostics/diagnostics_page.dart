// 车辆诊断页（/diagnostics）：开发者模式工具页，经 BLE OBD 适配器
// 读取车辆实时数据（GLOSSARY「车辆诊断」「诊断连接编排」词条，ADR 0020）。
//
// 页面只做三件事：数据门禁（当前应用车辆 + 每车检测点清单）、渲染
// controller 状态、把用户动作转发给 controller。连接编排（相位机、尝试
// 代数、直连/扫描分流、取消与重连、最后读数合并与落库）全部收在
// diagnostics_connection_controller.dart（plain-Dart，构造注入会话工厂/
// 扫描器/设备记忆/读数落库/ECU 里程回调与两个 UI 动作）。
//
// 三区布局（2026-11-17 拍板，ADR 0029：检测点行列表撤销、全员信息卡化）：
//   1. 连接状态条：未连接/扫描中/连接中/已连接/已断开 + 错误文案；行尾
//      动作按相位：已断开=重连、未连接/扫描中=选择设备、已连接=断开。
//   2. 信息卡网格 2×2：油量 | 水温 / 电压 | 燃油修正（内置启用探针各
//      对应一张固定卡；水温/电压/燃油修正按读数染语义色，油量不染；
//      无小字状态行，状态全靠色档）。启用的自定义探针追加通用卡（名
//      称+大字+时间，odometer 探针带「更新里程」确认入口）。显示语义：
//      实时有值优先，实时无数据不遮蔽持久化最后值（只显旧值+旧时间，
//      不染色），从未有过有效值才灰态「无数据」。启停与管理入口在
//      「我的」页车辆卡的「检测点」按钮（诊断页不再有启停与管理行）。
//   3. 调试终端（debug_panel.dart，ADR 0023）：折叠展开，连接后可暂停
//      自动轮询、发原始命令、跑一键检测并复制日志。
//
// ≈ Java 的 View：State 只持有 controller 与扫描 sheet 句柄（UI 资源），
// 业务决策一律转发；controller 经 ChangeNotifier 通知重建（ListenableBuilder）。
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
import 'ble_scan_sheet.dart';
import 'debug_panel.dart';
import 'diagnostics_connection_controller.dart';
import 'elm327_parser.dart' show ObdNoData, ObdValue;
import 'obd_runtime.dart';
import 'obd_session_log_sheet.dart';

/// 车辆诊断页主组件。
class DiagnosticsPage extends ConsumerStatefulWidget {
  const DiagnosticsPage({super.key});

  @override
  ConsumerState<DiagnosticsPage> createState() => DiagnosticsPageState();
}

class DiagnosticsPageState extends ConsumerState<DiagnosticsPage> {
  /// 连接编排控制器（App 级，ADR 0027）：从 obdConnectionControllerProvider
  /// 取唯一实例，页面只挂/摘接缝与作用域，不创建不释放。
  late final DiagnosticsConnectionController _connection;

  /// 扫描 sheet 句柄（非 null = sheet 在栈顶；onClosed 清空）。controller
  /// 经 UI port 的 open/close 驱动，句柄只是页面侧的 UI 资源。
  BleScanSheetHandle? _scanSheetHandle;

  @override
  void initState() {
    super.initState();
    _connection = ref.read(obdConnectionControllerProvider);
    // 挂 UI 接缝（扫描 sheet 开/关）与诊断作用域（轮询清单换全量启用
    // 清单）；页面销毁时全部摘除（ADR 0027 换防）。ECU 里程静默同步
    // 回调已提 App 级（runtime 装配，2026-11-18，不随页面挂摘）。
    _connection.attachUi(
      DiagnosticsConnectionUi(
        openScanSheet: _showScanSheet,
        closeScanSheet: _closeScanSheet,
      ),
    );
    _connection.setDiagnosticsScope(true);
    // 首帧先渲染「未连接」，连接动作延到首帧之后启动——状态机起点状态
    // 真实可达（widget 测试能按序断言全状态序列）。已连接/连接中/扫描中
    // 时 start 内部守卫直接返回（App 级连接复用，不重连）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_connection.start());
    });
  }

  @override
  void dispose() {
    // App 级连接不随页面销毁（ADR 0027）：只摘接缝与作用域，轮询清单
    // 换回提醒页的核心两条（若连接还在，提醒页信息卡数据源接续）。
    _connection
      ..detachUi()
      ..setDiagnosticsScope(false);
    super.dispose();
  }

  /// UI port：开扫描 sheet。sheet 数据来自 controller 的 state.scan（纯
  /// 渲染器），关闭（任何方式）回告 controller 收尾。
  void _showScanSheet() {
    if (_scanSheetHandle != null) {
      return;
    }
    _scanSheetHandle = showBleScanSheet(
      context,
      controller: _connection,
      onClosed: () {
        _scanSheetHandle = null;
        _connection.onScanSheetDismissed();
      },
    );
  }

  /// UI port：关扫描 sheet（controller 主动关闭：点选成功/门禁失败）。
  void _closeScanSheet() {
    _scanSheetHandle?.close();
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
          // 轮询快照与读数回退的数据源（不触发通知：列表由 provider 驱动）。
          _connection.setProbes(probes);
          return ListenableBuilder(
            listenable: _connection,
            builder: (context, _) =>
                _buildContent(context, probes, appliedCar),
          );
        },
      );
    }
    // pushed 子页不经过 AppShell，Scaffold（页面底色）要自己提供——
    // 页内 InkWell/chips 需要 Material 祖先，与 AppShell 同款底色。
    return Scaffold(backgroundColor: tokens.background, body: body);
  }

  /// 三区内容组装：状态条 → 信息卡网格 → 调试终端。
  Widget _buildContent(
    BuildContext context,
    List<DiagnosticsProbe> probes,
    Car? appliedCar,
  ) {
    return LunioPage(
      title: '车辆诊断',
      leading: _backKey(),
      bottomPadding: 24,
      children: [
        _buildStatusCard(context),
        const SizedBox(height: 12),
        _buildInfoCards(context, probes, appliedCar),
        const SizedBox(height: 18),
        DiagnosticsDebugPanel(
          session: _connection.session,
          connected:
              _connection.state.phase == DiagnosticsConnectionPhase.connected,
          carLabel: '${appliedCar?.brand ?? ''} ${appliedCar?.model ?? ''}'
              .trim(),
          onVerificationLog: _connection.appendVerificationLog,
          onOpenSessionLogs: () => unawaited(showObdSessionLogSheet(context)),
        ),
      ],
    );
  }

  /// 信息卡网格（2026-11-17 ADR 0029）：内置启用探针各对一张固定卡
  /// （油量 | 水温 / 电压 | 燃油修正），启用的自定义探针追加通用卡；
  /// 两张一行、IntrinsicHeight + Row stretch 等高（油量/水温卡高度不
  /// 一致的历史问题在此根治：所有卡统一「标题+右端时间 | 大字」两段
  /// 结构；滚动列表里 Row 自身拿到无界高度，必须先经 IntrinsicHeight
  /// 定高才能 stretch）。启用探针的
  /// 顺序保持 listProbes 的排序（内置按种子序、自定义按创建序）。
  Widget _buildInfoCards(
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
    final voltageProbe = _probeByCatalogKey(
      probes,
      DiagnosticsRepository.builtInVoltageKey,
    );
    final cvtProbe = _probeByCatalogKey(
      probes,
      DiagnosticsRepository.builtInCvtTempKey,
    );
    final cards = <Widget>[
      if (fuelProbe != null && fuelProbe.enabled)
        _ReadingCard(
          title: fuelProbe.name,
          snapshot: _connection.readingFor(fuelProbe),
        ),
      if (coolantProbe != null && coolantProbe.enabled)
        _ReadingCard(
          title: coolantProbe.name,
          snapshot: _connection.readingFor(coolantProbe),
          tone: _toneOf(
            coolantProbe,
            (v) => v.celsius == null
                ? null
                : DiagnosticsRules.coolantTempTone(v.celsius!),
          ),
        ),
      if (voltageProbe != null && voltageProbe.enabled)
        _ReadingCard(
          title: voltageProbe.name,
          snapshot: _connection.readingFor(voltageProbe),
          tone: _toneOf(
            voltageProbe,
            (v) => v.volts == null
                ? null
                : DiagnosticsRules.batteryVoltageTone(v.volts!),
          ),
        ),
      if (cvtProbe != null && cvtProbe.enabled)
        _ReadingCard(
          title: cvtProbe.name,
          snapshot: _connection.readingFor(cvtProbe),
          tone: _toneOf(
            cvtProbe,
            (v) => v.celsius == null
                ? null
                : DiagnosticsRules.cvtOilTempTone(v.celsius!),
          ),
        ),
      ...probes
          .where((probe) =>
              probe.enabled &&
              probe.catalogKey == null)
          .map(
            (probe) => _CustomProbeCard(
              probe: probe,
              snapshot: _connection.readingFor(probe),
            ),
          ),
    ];
    return Column(
      children: [
        for (var i = 0; i < cards.length; i += 2) ...[
          if (i > 0) const SizedBox(height: 12),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: cards[i]),
                if (i + 1 < cards.length) ...[
                  const SizedBox(width: 12),
                  Expanded(child: cards[i + 1]),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// 读数色档判定：实时有效读数优先；**持久化回退也染**（2026-11-18
  /// 深审收敛口径：ADR 0029 决定 4「percent 持久化→回退按旧值染」以
  /// 实现为准补齐）——燃油修正 percent 持久化，回退显旧值+旧色档；
  /// 水温/电压 celsius/volts 不持久化，回退重建后数值为 null、自然不
  /// 染（ink 色）。[valuePick] 返回 null（数值缺失）时不染。
  DiagnosticsReadingTone? _toneOf(
    DiagnosticsProbe probe,
    DiagnosticsReadingTone? Function(ObdValue) valuePick,
  ) {
    final reading = _connection.readingFor(probe)?.reading;
    if (reading is! ObdValue) {
      return null;
    }
    return valuePick(reading);
  }

  /// 按内置 catalogKey 定位内置检测点（信息卡数据源；key 常量与种子
  /// 对账共用一份，DiagnosticsRepository 单一事实源）。
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

  /// 状态条（第一区）：阶段徽标 + 说明文案；"已断开"追加错误文案与
  /// 手动重连按钮（连接级失败只上状态条、不弹窗）。
  Widget _buildStatusCard(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    final state = _connection.state;
    final (label, tone) = switch (state.phase) {
      DiagnosticsConnectionPhase.idle => ('未连接', LunioStatusTone.warning),
      DiagnosticsConnectionPhase.scanning => ('扫描中', LunioStatusTone.warning),
      DiagnosticsConnectionPhase.connecting => ('连接中', LunioStatusTone.warning),
      DiagnosticsConnectionPhase.connected => ('已连接', LunioStatusTone.normal),
      DiagnosticsConnectionPhase.disconnected => (
        '已断开',
        LunioStatusTone.danger,
      ),
    };
    final hintText = switch (state.phase) {
      DiagnosticsConnectionPhase.idle => '未连接适配器',
      DiagnosticsConnectionPhase.scanning => obdScanningHint,
      DiagnosticsConnectionPhase.connecting => '正在建立连接…',
      DiagnosticsConnectionPhase.connected => '已连接 · 正在轮询启用检测点',
      DiagnosticsConnectionPhase.disconnected => state.statusError ?? '连接已断开',
    };
    // 行尾动作按钮（按相位显隐）：断开=重连；未连接/扫描中=选择设备
    //（重开扫描 sheet 的再入口）；已连接=断开；连接中无动作。
    final actionLabel = switch (state.phase) {
      DiagnosticsConnectionPhase.disconnected => '重连',
      DiagnosticsConnectionPhase.idle ||
      DiagnosticsConnectionPhase.scanning =>
        '选择设备',
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
          if (state.phase == DiagnosticsConnectionPhase.connected)
            IconButton(
              tooltip: '立即刷新',
              onPressed: _connection.requestImmediatePoll,
              icon: const Icon(Icons.refresh, size: 20),
              visualDensity: VisualDensity.compact,
              color: tokens.primary,
            ),
          if (actionLabel != null)
            TextButton(
              onPressed: switch (state.phase) {
                DiagnosticsConnectionPhase.disconnected =>
                  () => unawaited(_connection.start()),
                DiagnosticsConnectionPhase.connected =>
                  () => unawaited(_connection.disconnectManually()),
                _ => () => unawaited(_connection.openScan()),
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
}

/// 信息卡通用组件（2026-11-17 ADR 0029）：固定两段结构——标题行（标
/// 题 + 右端最后更新时间）+ 大字值行，所有卡等高（Row stretch）。
/// 显示语义与 DiagnosticsConnectionController.readingFor 同源：实时有
/// 值优先、实时无数据不遮蔽持久化最后值（显示旧值+旧时间；色档按回退
/// 值算，燃油修正 percent 持久化按旧值染、水温/电压数值不持久化自然
/// 不染——见 [_toneOf]）、从未有过有效值才灰态「无数据」。
class _ReadingCard extends StatelessWidget {
  const _ReadingCard({
    required this.title,
    required this.snapshot,
    this.tone,
  });

  /// 卡标题（内置卡显短标题：油量/水温/电压/燃油修正）。
  final String title;

  /// 读取调用（实时优先、持久化回退；null = 从未有过有效值 → 灰态）。
  final ProbeReadingSnapshot? snapshot;

  /// 色档（null = 不染色，ink 色）。只对实时有效读数判定（见
  /// _toneOf）；celsius/volts 不持久化，回退显示自然不染。
  final DiagnosticsReadingTone? tone;



  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    final snapshot = this.snapshot;
    final reading = snapshot?.reading;
    final isNoData = reading is ObdNoData || snapshot == null;
    final timeText = snapshot == null
        ? '未更新'
        : formatReadingTime(snapshot.at, now: DateTime.now());
    final valueColor = isNoData
        ? tokens.subtle
        : switch (tone) {
            DiagnosticsReadingTone.normal => tokens.success,
            DiagnosticsReadingTone.warning => tokens.warning,
            DiagnosticsReadingTone.danger => tokens.danger,
            _ => tokens.ink,
          };
    final valueLine = <Widget>[
      Expanded(
        child: Text(
          reading?.display ?? '—',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: valueColor,
              ),
        ),
      ),
    ];
    return LunioCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(title, style: Theme.of(context).textTheme.bodySmall),
              const Spacer(),
              Text(
                timeText,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: tokens.muted,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(children: valueLine),
        ],
      ),
    );
  }
}

/// 自定义探针通用卡（2026-11-17 ADR 0029）：名称 + 当前值 + 时间。
/// ECU 里程同步已 App 级静默（2026-11-18 修订节），卡上无确认入口。
class _CustomProbeCard extends StatelessWidget {
  const _CustomProbeCard({
    required this.probe,
    required this.snapshot,
  });

  final DiagnosticsProbe probe;

  final ProbeReadingSnapshot? snapshot;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    final snapshot = this.snapshot;
    final reading = snapshot?.reading;
    final isNoData = reading is ObdNoData || snapshot == null;
    final timeText = snapshot == null
        ? '未更新'
        : formatReadingTime(snapshot.at, now: DateTime.now());
    return LunioCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  probe.name,
                  style: Theme.of(context).textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                timeText,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: tokens.muted,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  reading?.display ?? '—',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: isNoData ? tokens.subtle : tokens.ink,
                      ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
