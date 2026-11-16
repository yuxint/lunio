// 车辆诊断页（/diagnostics）：开发者模式工具页，经 BLE OBD 适配器
// 读取车辆实时数据（GLOSSARY「车辆诊断」「诊断连接编排」词条，ADR 0020）。
//
// 页面只做三件事：数据门禁（当前应用车辆 + 每车检测点清单）、渲染
// controller 状态、把用户动作转发给 controller。连接编排（相位机、尝试
// 代数、直连/扫描分流、取消与重连、最后读数合并与落库）全部收在
// diagnostics_connection_controller.dart（plain-Dart，构造注入会话工厂/
// 扫描器/设备记忆/读数落库/两个 UI 动作）。
//
// 三区布局（票 05，未变）：
//   1. 连接状态条：未连接/扫描中/连接中/已连接/已断开 + 错误文案；行尾
//      动作按相位：已断开=重连、未连接/扫描中=选择设备、已连接=断开。
//   2. 核心值卡：油量（百分比大字 + 双油量小字，ADR 0022）+ 水温；数据
//      经 controller.readingFor 取（实时优先、持久化回退）。
//   3. 检测点行列表：名称 + 当前值 + 最后更新时间 + 启停开关；无数据
//      行级灰态不连坐；列表尾「管理检测点」打开项目式管理 sheet。
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
import '../../../domain/entities/diagnostics_parse_type.dart';
import '../../../domain/entities/diagnostics_probe.dart';
import '../../../domain/rules/diagnostics_rules.dart';
import '../shared/shell_shared.dart';
import 'ble_scan_sheet.dart';
import 'debug_panel.dart';
import 'diagnostics_connection_controller.dart';
import 'elm327_parser.dart' show ObdNoData, ObdValue;
import 'obd_runtime.dart';
import 'probe_management_sheet.dart';

/// 车辆诊断页主组件。
class DiagnosticsPage extends ConsumerStatefulWidget {
  const DiagnosticsPage({super.key});

  @override
  ConsumerState<DiagnosticsPage> createState() => DiagnosticsPageState();
}

class DiagnosticsPageState extends ConsumerState<DiagnosticsPage> {
  /// 连接编排控制器（一次性对象；页面 initState 创建、dispose 释放）。
  late final DiagnosticsConnectionController _connection;

  /// 扫描 sheet 句柄（非 null = sheet 在栈顶；onClosed 清空）。controller
  /// 经 UI port 的 open/close 驱动，句柄只是页面侧的 UI 资源。
  BleScanSheetHandle? _scanSheetHandle;

  @override
  void initState() {
    super.initState();
    _connection = DiagnosticsConnectionController(
      ui: DiagnosticsConnectionUi(
        openScanSheet: _showScanSheet,
        closeScanSheet: _closeScanSheet,
      ),
      sessionFactory: ref.read(obdSessionFactoryProvider),
      scanner: ref.read(obdScannerProvider),
      readDeviceId: () =>
          ref.read(lunioPreferencesProvider).getLastObdDeviceId(),
      rememberDevice: (deviceId) => rememberObdDevice(ref, deviceId),
      saveReading: (probeId, {required value, percent, required at}) => ref
          .read(diagnosticsRepositoryProvider)
          .saveProbeReading(probeId, value: value, percent: percent, at: at),
      onOdometerReading: (reading) =>
          unawaited(_syncOdometerSilently(reading)),
    );
    // 首帧先渲染「未连接」，连接动作延到首帧之后启动——状态机起点状态
    // 真实可达（widget 测试能按序断言全状态序列）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_connection.start());
    });
  }

  @override
  void dispose() {
    _connection.dispose();
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

  /// ECU 里程静默自动同步（ADR 0026）：controller 每收到有效里程读数
  /// 回调一次。开关关（默认档）= 确认式，这里直接返回；开关开 = 读开
  /// 关、当前应用车辆后守卫写入（守卫在动作层 syncCarMileageFromEcu）。
  /// 失败降级不提示（静默档语义），下一轮轮询再试。
  Future<void> _syncOdometerSilently(ObdValue reading) async {
    final km = reading.kilometers;
    if (km == null || !mounted) {
      return;
    }
    final autoSync = await ref.read(obdOdometerAutoSyncProvider.future);
    if (!autoSync || !mounted) {
      return;
    }
    final car = await ref.read(appliedCarProvider.future);
    if (car == null || !mounted) {
      return;
    }
    await syncCarMileageFromEcu(ref, car, km);
  }

  /// 确认式里程同步（开关关 = 默认档）：确认框两值对照，确认后走动作
  /// 层 [syncCarMileageFromEcu]（守卫「只增不减」在动作层兜底）。
  Future<void> _confirmMileageSync(Car car, int ecuKm) async {
    final confirmed = await showConfirmDialog(
      context: context,
      title: '更新车辆里程',
      message:
          'ECU 里程 ${formatNumber(ecuKm)} km 大于当前车辆里程 ${formatNumber(car.currentMileageKm)} km，更新为 ECU 读数？',
      confirmLabel: '更新',
    );
    if (confirmed != true || !mounted) {
      return;
    }
    final current = await ref.read(appliedCarProvider.future);
    if (current == null || !mounted) {
      return;
    }
    await syncCarMileageFromEcu(ref, current, ecuKm);
  }

  /// 检测点单行组装：读取快照每行取一次；里程同步确认入口按 ADR 0026
  /// 只挂 odometer 探针行（开关关 = 确认式；开关开时静默写，不显入口）。
  Widget _probeRow(DiagnosticsProbe probe, Car car) {
    final snapshot = _connection.readingFor(probe);
    final km = switch (snapshot?.reading) {
      ObdValue(:final kilometers) => kilometers,
      _ => null,
    };
    final autoSync = ref.watch(obdOdometerAutoSyncProvider).value ?? false;
    final canSync = probe.parseType == DiagnosticsParseType.odometer &&
        km != null &&
        km > car.currentMileageKm &&
        !autoSync;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _ProbeRow(
        probe: probe,
        snapshot: snapshot,
        onToggle: (value) => setDiagnosticsProbeEnabled(ref, probe, value),
        mileageSyncAvailable: canSync,
        onSyncMileage: canSync ? () => _confirmMileageSync(car, km) : null,
      ),
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
            for (final probe in probes) _probeRow(probe, appliedCar!),
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
          session: _connection.session,
          connected:
              _connection.state.phase == DiagnosticsConnectionPhase.connected,
          carLabel: '${appliedCar?.brand ?? ''} ${appliedCar?.model ?? ''}'
              .trim(),
        ),
      ],
    );
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

  /// 油量卡（第二区左）：百分比大字 + 双油量小字（ADR 0022）。可用油量
  /// 用加满可加油量；总油量 = 储备 + 可用，总容积未填只显可用。容积未
  /// 填只显百分比（story 11）；无读取/无数据显占位符。
  Widget _buildFuelCard(
    BuildContext context,
    DiagnosticsProbe? fuelProbe,
    Car? appliedCar,
  ) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    final snapshot = fuelProbe == null ? null : _connection.readingFor(fuelProbe);
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
    final snapshot =
        coolantProbe == null ? null : _connection.readingFor(coolantProbe);
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
}

/// 检测点行（第三区）：名称 + 当前值 + 最后更新时间 + 启停开关。无数据 =
/// 行级灰态（值列灰字"无数据"），其他行照常更新，不连坐；未读取（连接后
/// 还没轮到）显"—"与"未更新"。
class _ProbeRow extends StatelessWidget {
  const _ProbeRow({
    required this.probe,
    required this.snapshot,
    required this.onToggle,
    this.mileageSyncAvailable = false,
    this.onSyncMileage,
  });

  final DiagnosticsProbe probe;

  /// 最新读取快照（null = 未读取）。
  final ProbeReadingSnapshot? snapshot;

  /// 启停开关回调（动作层编排：写库 → 逐出检测点 provider）。
  final ValueChanged<bool> onToggle;

  /// 里程同步确认入口显隐（ADR 0026：odometer 探针 + ECU > 车辆里程 +
  /// 静默自动写开关关）。写点守卫在动作层，行内入口只是显隐。
  final bool mileageSyncAvailable;

  /// 确认式里程同步回调（null = 不显入口）。
  final VoidCallback? onSyncMileage;

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
        if (mileageSyncAvailable && onSyncMileage != null) ...[
          SmallActionButton(
            label: '更新里程',
            primary: true,
            onPressed: onSyncMileage,
          ),
          const SizedBox(width: 12),
        ],
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
