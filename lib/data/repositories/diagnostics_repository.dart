// 车辆诊断仓库（DiagnosticsRepository）：检测点表（diagnostics_probes，
// ADR 0021）的唯一读写出口，外加每车内置五条种子的 bootstrap 幂等对账。
//
// ≈ Java 里按域拆出的领域 Service：管一张按车分组的表（挂 carId——指令
// 语义与车无关，但不同车的可用指令可能不同，ADR 0021 修订节）；删除车辆
// 由主仓库事务级联删除本表行；本表写点不 bump 车辆数据纪元
// （providers.dart 的 diagnosticsProbesProvider 走"写点直失效"模型，同
// 停车倒计时先例）。
//
// 对账语义（ADR 0021 修订节，"目录式安全"）：
//  1. 删除"种子集合外仍带内置 key"的行（自定义行 catalogKey 为 null，
//     不受影响）；
//  2. 缺失补插（enabled 恒 true 落库）；
//  3. 只补缺失、不纠偏用户编辑：内置行可改名称/指令/解析类型/间隔/启停，
//     对账不得把用户改动改回去。完整数据下重复对账 = 零写库
//     （updatedAt 不动）。
import 'package:drift/drift.dart';

import '../../core/id/snowflake_id_generator.dart';
import '../../domain/entities/diagnostics_parse_type.dart' as domain;
import '../../domain/entities/diagnostics_probe.dart' as domain;
import '../../domain/entities/sync_metadata.dart';
import '../database/app_database.dart';
import 'entity_row_codec.dart';

/// 内置检测点种子规格（const 可构造，供种子对账与测试引用）。
class DiagnosticsProbeSeed {
  const DiagnosticsProbeSeed({
    required this.catalogKey,
    required this.name,
    required this.command,
    required this.parseType,
  });

  /// 稳定 catalogKey（bootstrap 对账标识，{carId, catalogKey} 唯一约束
  /// 兜底）。
  final String catalogKey;

  /// 展示名。
  final String name;

  /// 指令原文。
  final String command;

  /// 解析类型。
  final domain.DiagnosticsParseType parseType;
}

class DiagnosticsRepository {
  /// 内置油量检测点 catalogKey：页面核心值卡（油量卡）定位内置行的
  /// 稳定标识（种子对账标识复用同一份，单一事实源）。
  static const builtInFuelLevelKey = 'probe:fuelLevel';

  /// 内置水温检测点 catalogKey（水温值卡定位用）。
  static const builtInCoolantKey = 'probe:coolantTemp';

  /// 内置电压检测点 catalogKey（电压卡定位用，2026-11-17 ADR 0029）。
  static const builtInVoltageKey = 'probe:voltage';

  /// 内置短期燃油修正 catalogKey（燃油修正卡 STFT 小字定位用）。
  static const builtInStftKey = 'probe:stftBank1';

  /// 内置长期燃油修正 catalogKey（燃油修正卡主值定位用）。
  static const builtInLtftKey = 'probe:ltftBank1';

  /// 内置 CVT 油温检测点 catalogKey（2026-11-18 实车验证转正，替换
  /// 燃油修正卡的位置）。
  static const builtInCvtTempKey = 'probe:cvtOilTemp';

  /// 内置里程表检测点 catalogKey（2026-11-18 升内置：ECU 里程同步的
  /// 数据源，「只要连接就在轮询清单里」——ADR 0026 修订节）。
  static const builtInOdometerKey = 'probe:odometer';

  /// 构造时注入数据库连接。
  DiagnosticsRepository(this.database);

  final AppDatabase database;

  /// 检测点默认自动轮询间隔（秒，ADR 0023）。2026-11-17 拍板 30→10：
  /// 实测单条命令总线往返 ~120-200ms（一键检测 25 条全程约 3 秒），5
  /// 条探针单轮 ~0.75s，10s 间隔总线占空比 ~7.5%，对 500k CAN 与 ECU
  /// 都远在安全区；暖机期水温 ~0.1-0.3℃/s，10s 采样粒度足够，诊断页
  /// 打开 ≤10s 必有新鲜值。
  static const int defaultRefreshIntervalSeconds = 10;

  /// 内置七条种子（ADR 0021 修订节 + ADR 0029 及修订节）：油量/水温/
  /// 电压/短期燃油修正/长期燃油修正/CVT 油温/里程表。2026-11-16 起
  /// 水温内置改 `0167`（本车 0105 不支持，全量采集分析见
  /// docs/car_obd_link/docs/全量采集分析-2026-11-16.md）；存量车的
  /// 内置行在库里已是 0105，由用户在 App 内手动编辑迁移，bootstrap
  /// 不纠偏。每辆车各一套，
  /// 顺序即列表展示顺序；catalogKey 是稳定对账标识，只增不改（改名/
  /// 换 key = 对账目标集合变化，旧 key 行会被清理重建）。
  static const List<DiagnosticsProbeSeed> builtInProbeSeeds = [
    DiagnosticsProbeSeed(
      catalogKey: builtInFuelLevelKey,
      name: '油量',
      command: '012F',
      parseType: domain.DiagnosticsParseType.fuelLevel,
    ),
    DiagnosticsProbeSeed(
      catalogKey: builtInCoolantKey,
      name: '水温',
      command: '0167',
      parseType: domain.DiagnosticsParseType.coolantTempAux,
    ),
    DiagnosticsProbeSeed(
      catalogKey: builtInVoltageKey,
      name: '电压',
      command: 'ATRV',
      parseType: domain.DiagnosticsParseType.voltageText,
    ),
    // 燃油修正两条（2026-11-17 拍板转正，ADR 0029）：本车支持集含 06/
    // 07（11-12 实测 0106 = −1.6%、0107 = 0%）。染色基准 = LTFT（卡
    // 大字），STFT 为标题行右端小字；推翻 11-16「燃油修正不加」拍板，
    // 理由已变（观察燃烧系统健康度）。存量车 bootstrap 自动补齐。
    DiagnosticsProbeSeed(
      catalogKey: builtInStftKey,
      name: '短期燃油修正',
      command: '0106',
      parseType: domain.DiagnosticsParseType.fuelTrimPercent,
    ),
    DiagnosticsProbeSeed(
      catalogKey: builtInLtftKey,
      name: '长期燃油修正',
      command: '0107',
      parseType: domain.DiagnosticsParseType.fuelTrimPercent,
    ),
    // CVT 油温（2026-11-18 实车验证转正）：私有 DID 多行帧，替换燃油
    // 修正卡（探针保留、卡撤下）；阈值五段见 diagnostics_rules。
    DiagnosticsProbeSeed(
      catalogKey: builtInCvtTempKey,
      name: 'CVT 油温',
      command: '222301',
      parseType: domain.DiagnosticsParseType.cvtOilTemp,
    ),
    // 里程表（2026-11-18 升内置，ADR 0026 修订节）：ECU 里程同步的
    // 数据源——用户拍板「只要连接上（提醒页/诊断页）读到更大就更新」，
    // 探针必须在默认轮询清单里。
    DiagnosticsProbeSeed(
      catalogKey: builtInOdometerKey,
      name: '里程表',
      command: '01A6',
      parseType: domain.DiagnosticsParseType.odometer,
    ),
  ];

  /// 某辆车的检测点全量列表：内置五条在前（按种子声明顺序）、自定义
  /// 按 id 升序（雪花 id 时间有序 = 创建顺序）。诊断页列表与轮询的
  /// "启用检测点"快照共用这一份读取。
  Future<List<domain.DiagnosticsProbe>> listProbes(int carId) async {
    final rows = await (database.select(
      database.diagnosticsProbes,
    )..where((row) => row.carId.equals(carId))).get();
    final probes = rows.map(diagnosticsProbeFromRow).toList();
    final seedOrder = {
      for (final (index, seed) in builtInProbeSeeds.indexed)
        seed.catalogKey: index,
    };
    // 未知内置 key（对账前的脏数据窗口）不崩排序：排到内置段末尾，
    // 由下次 bootstrap 对账清理。
    final unknownKeyRank = builtInProbeSeeds.length;
    probes.sort((a, b) {
      final aBuiltIn = a.catalogKey != null;
      final bBuiltIn = b.catalogKey != null;
      if (aBuiltIn != bBuiltIn) {
        return aBuiltIn ? -1 : 1;
      }
      if (aBuiltIn && bBuiltIn) {
        final aRank = seedOrder[a.catalogKey] ?? unknownKeyRank;
        final bRank = seedOrder[b.catalogKey] ?? unknownKeyRank;
        if (aRank != bRank) {
          return aRank.compareTo(bRank);
        }
      }
      return a.id!.compareTo(b.id!);
    });
    return probes;
  }

  /// 新增自定义检测点，返回新生成的雪花 id。只收自定义实体（catalogKey
  /// 非 null 即内置，内置只能由 bootstrap 种子产生，传进来是编程错误）；
  /// 副作用：syncStatus 记 pendingUpdate、updatedAt 刷新（沿用全库约定）。
  Future<int> saveProbe(domain.DiagnosticsProbe probe) async {
    probe.validate();
    if (probe.catalogKey != null) {
      throw ArgumentError(
        'saveProbe only accepts custom probes (catalogKey must be null)',
      );
    }
    final probeId = SnowflakeIdGenerator.instance.next();
    final synced = probe.copyWith(
      sync: SyncMetadata(
        status: SyncStatus.pendingUpdate,
        updatedAt: DateTime.now(),
      ),
    );
    await database
        .into(database.diagnosticsProbes)
        .insert(diagnosticsProbeCompanion(synced, probeId));
    return probeId;
  }

  /// 编辑检测点（名称/指令/解析类型/刷新间隔/header 五业务字段；启停走
  /// [setProbeEnabled]）。内置行也可编辑（ADR 0021 修订节），但
  /// catalogKey/carId 不改写——内置标识与归属保持。行不存在或 carId
  /// 不匹配拒绝（ArgumentError，防编程错误）。
  Future<void> updateProbe(domain.DiagnosticsProbe probe) async {
    final probeId = probe.id;
    if (probeId == null) {
      throw ArgumentError('Probe id is required');
    }
    probe.validate();
    final row = await (database.select(
      database.diagnosticsProbes,
    )..where((row) => row.id.equals(probeId))).getSingleOrNull();
    if (row == null) {
      throw ArgumentError('Probe not found: $probeId');
    }
    if (row.carId != probe.carId) {
      throw ArgumentError('Probe carId mismatch: $probeId');
    }
    await (database.update(
      database.diagnosticsProbes,
    )..where((row) => row.id.equals(probeId))).write(
      DiagnosticsProbesCompanion(
        name: Value(probe.name),
        command: Value(probe.command),
        parseType: Value(probe.parseType.wire),
        refreshIntervalSeconds: Value(probe.refreshIntervalSeconds),
        header: Value(probe.header),
        syncStatus: Value(SyncStatus.pendingUpdate.name),
        updatedAt: Value(DateTime.now().toIso8601String()),
      ),
    );
  }

  /// 启停检测点。内置行也允许（唯一可变的内置字段）；轮询只发启用项。
  /// 行不存在时拒绝（ArgumentError，防编程错误）。
  Future<void> setProbeEnabled(int probeId, bool enabled) async {
    final updated = await (database.update(
      database.diagnosticsProbes,
    )..where((row) => row.id.equals(probeId))).write(
      DiagnosticsProbesCompanion(
        enabled: Value(enabled),
        syncStatus: Value(SyncStatus.pendingUpdate.name),
        updatedAt: Value(DateTime.now().toIso8601String()),
      ),
    );
    if (updated == 0) {
      throw ArgumentError('Probe not found: $probeId');
    }
  }

  /// 写最后读数（2026-11-15，ADR 0021 修订节）：轮询每收到一个**有效**
  /// 读数（ObdValue）由页面调用；「无数据」读数不调用（不写库、不覆盖
  /// 旧值）。只 UPDATE 最后读数三列，syncStatus/updatedAt/version 有意
  /// 不动——读数是设备派生临时数据，高频写（约每秒 1 次）不盖同步章
  /// （与表单/启停写点分叉，理由见 ADR 0021 修订节）。行不存在静默跳
  /// 过（读数写点与列表重算竞态：检测点刚被删除，迟到读数不复活行）。
  Future<void> saveProbeReading(
    int probeId, {
    required String value,
    double? percent,
    required DateTime at,
  }) async {
    await (database.update(database.diagnosticsProbes)..where(
          (row) => row.id.equals(probeId),
        )).write(
      DiagnosticsProbesCompanion(
        lastValue: Value(value),
        lastPercent: Value(percent),
        lastReadingAt: Value(at.toIso8601String()),
      ),
    );
  }

  /// 删除自定义检测点。内置行不可删（ArgumentError，防编程错误——
  /// "内置五件套永远在、永远正确"，ADR 0021）；行不存在同样拒绝。
  Future<void> deleteProbe(int probeId) async {
    final row = await (database.select(
      database.diagnosticsProbes,
    )..where((r) => r.id.equals(probeId))).getSingleOrNull();
    if (row == null) {
      throw ArgumentError('Probe not found: $probeId');
    }
    if (row.catalogKey != null) {
      throw ArgumentError('Built-in probe cannot be deleted: $probeId');
    }
    await (database.delete(
      database.diagnosticsProbes,
    )..where((row) => row.id.equals(probeId))).go();
  }

  /// 内置五条种子的幂等对账（ADR 0021 修订节，每车一套）。并入
  /// bootstrap 总入口（BuiltInCatalogRepository.ensureBootstrapData 注入
  /// 调用）：遍历所有车辆，逐车补缺失内置、清理种子外内置 key。
  /// **只补缺失，不纠偏用户编辑**——内置行可改名称/指令/解析类型/间隔，
  /// 对账不得把用户改动改回去；自定义行不碰。
  Future<void> ensureBuiltInProbes() async {
    final carRows = await database.select(database.cars).get();
    await database.transaction(() async {
      for (final car in carRows) {
        await _ensureBuiltInProbesForCar(car.id);
      }
    });
  }

  /// 给一辆车播种内置五条（新增车辆收尾调用；bootstrap 也经上面的全量
  /// 入口走到这里）。幂等：已有 key 不动。
  Future<void> seedBuiltInProbesForCar(int carId) {
    return database.transaction(() => _ensureBuiltInProbesForCar(carId));
  }

  Future<void> _ensureBuiltInProbesForCar(int carId) async {
    final targetKeys = {
      for (final seed in builtInProbeSeeds) seed.catalogKey,
    };
    await (database.delete(database.diagnosticsProbes)..where(
          (row) =>
              row.carId.equals(carId) &
              row.catalogKey.isNotNull() &
              row.catalogKey.isNotIn(targetKeys),
        ))
        .go();
    final rows = await (database.select(
      database.diagnosticsProbes,
    )..where((row) => row.carId.equals(carId))).get();
    final rowByKey = {
      for (final row in rows)
        if (row.catalogKey != null) row.catalogKey!: row,
    };
    for (final seed in builtInProbeSeeds) {
      if (rowByKey.containsKey(seed.catalogKey)) {
        continue;
      }
      await database
          .into(database.diagnosticsProbes)
          .insert(
            diagnosticsProbeCompanion(
              domain.DiagnosticsProbe(
                carId: carId,
                name: seed.name,
                command: seed.command,
                parseType: seed.parseType,
                enabled: true,
                catalogKey: seed.catalogKey,
                refreshIntervalSeconds: defaultRefreshIntervalSeconds,
                sync: SyncMetadata(
                  status: SyncStatus.synced,
                  updatedAt: DateTime.now(),
                ),
              ),
              SnowflakeIdGenerator.instance.next(),
            ),
          );
    }
  }
}
