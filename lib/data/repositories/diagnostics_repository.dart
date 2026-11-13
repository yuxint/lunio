// 车辆诊断仓库（DiagnosticsRepository）：检测点表（diagnostics_probes，
// ADR 0021）的唯一读写出口，外加内置三条种子的 bootstrap 幂等对账。
//
// ≈ Java 里按域拆出的领域 Service：管一张全局表（不挂 carId——指令
// 语义与车无关），与车辆/项目/记录核心域几乎无耦合；删除车辆不级联
// 本表，本表写点不 bump 车辆数据纪元（providers.dart 的
// diagnosticsProbesProvider 走"写点直失效"模型，同停车倒计时先例）。
//
// 对账语义（ADR 0021 决定 3，"目录式安全"）：
//  1. 删除"种子集合外仍带内置 key"的行（自定义行 catalogKey 为 null，
//     不受影响）；
//  2. 缺失补插（enabled 恒 true 落库）；
//  3. 内置行漂移纠偏：只纠名称/指令/解析类型三列（内置只读，漂移即
//     数据被外部改动），enabled 故意不比不写——启停是用户数据，对账
//     不得重置。完整数据下重复对账 = 零写库（updatedAt 不动）。
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

  /// 稳定 catalogKey（bootstrap 对账标识，全库唯一约束兜底）。
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

  /// 构造时注入数据库连接。
  DiagnosticsRepository(this.database);

  final AppDatabase database;

  /// 内置三条种子（ADR 0021）：油量/水温/电压。顺序即列表展示顺序；
  /// catalogKey 是稳定对账标识，只增不改（改名/换 key = 对账目标集合
  /// 变化，旧 key 行会被清理重建）。
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
      command: '0105',
      parseType: domain.DiagnosticsParseType.coolantTemp,
    ),
    DiagnosticsProbeSeed(
      catalogKey: 'probe:voltage',
      name: '电压',
      command: 'ATRV',
      parseType: domain.DiagnosticsParseType.voltageText,
    ),
  ];

  /// 检测点全量列表：内置三条在前（按种子声明顺序）、自定义按 id 升序
  /// （雪花 id 时间有序 = 创建顺序）。诊断页列表与轮询的"启用检测点"
  /// 快照共用这一份读取。
  Future<List<domain.DiagnosticsProbe>> listProbes() async {
    final rows = await database.select(database.diagnosticsProbes).get();
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

  /// 编辑自定义检测点（名称/指令/解析类型三业务字段；启停走
  /// [setProbeEnabled]，不混在本方法里）。内置行只读：目标行带内置
  /// key 时拒绝（ArgumentError，防编程错误——UI 侧不给内置行编辑入口）。
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
    if (row.catalogKey != null) {
      throw ArgumentError('Built-in probe is read-only: $probeId');
    }
    await (database.update(
      database.diagnosticsProbes,
    )..where((row) => row.id.equals(probeId))).write(
      DiagnosticsProbesCompanion(
        name: Value(probe.name),
        command: Value(probe.command),
        parseType: Value(probe.parseType.wire),
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

  /// 删除自定义检测点。内置行不可删（ArgumentError，防编程错误——
  /// "内置三件套永远在、永远正确"，ADR 0021）；行不存在同样拒绝。
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

  /// 内置三条种子的幂等对账（ADR 0021 决定 3）。并入 bootstrap 总入口
  /// （BuiltInCatalogRepository.ensureBootstrapData 注入调用），首启
  /// 插入、重复运行零写库、漂移纠偏、种子外内置 key 清理、自定义行
  /// 不碰。事务内三步：
  ///  1. 删除"种子集合外仍带内置 key"的行（未来版本种子收缩时清残留；
  ///     自定义行 catalogKey 为 null，不在删除范围）；
  ///  2. 缺失补插（enabled 恒 true 落库）；
  ///  3. 漂移纠偏：内置行名称/指令/解析类型三列 ≠ 种子值时纠回（内置
  ///     只读，漂移即数据被外部改动）；enabled 故意不比不写——启停是
  ///     用户数据，对账不得重置。
  Future<void> ensureBuiltInProbes() async {
    final targetKeys = {
      for (final seed in builtInProbeSeeds) seed.catalogKey,
    };
    await database.transaction(() async {
      await (database.delete(database.diagnosticsProbes)..where(
            (row) =>
                row.catalogKey.isNotNull() &
                row.catalogKey.isNotIn(targetKeys),
          ))
          .go();
      final rows = await database.select(database.diagnosticsProbes).get();
      final rowByKey = {
        for (final row in rows)
          if (row.catalogKey != null) row.catalogKey!: row,
      };
      for (final seed in builtInProbeSeeds) {
        final row = rowByKey[seed.catalogKey];
        if (row == null) {
          await database
              .into(database.diagnosticsProbes)
              .insert(
                diagnosticsProbeCompanion(
                  domain.DiagnosticsProbe(
                    name: seed.name,
                    command: seed.command,
                    parseType: seed.parseType,
                    enabled: true,
                    catalogKey: seed.catalogKey,
                    sync: SyncMetadata(
                      status: SyncStatus.synced,
                      updatedAt: DateTime.now(),
                    ),
                  ),
                  SnowflakeIdGenerator.instance.next(),
                ),
              );
        } else if (row.name != seed.name ||
            row.command != seed.command ||
            row.parseType != seed.parseType.wire) {
          final probeId = row.id;
          await (database.update(
            database.diagnosticsProbes,
          )..where((r) => r.id.equals(probeId))).write(
            DiagnosticsProbesCompanion(
              name: Value(seed.name),
              command: Value(seed.command),
              parseType: Value(seed.parseType.wire),
              syncStatus: Value(SyncStatus.synced.name),
              updatedAt: Value(DateTime.now().toIso8601String()),
            ),
          );
        }
      }
    });
  }
}
