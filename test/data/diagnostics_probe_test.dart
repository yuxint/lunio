// 检测点数据层测试：实体校验、解析类型 wire 契约、仓库 CRUD 与只读
// 守卫、内置三条种子的 bootstrap 幂等对账（首启插入/重复零写库/启停
// 保留/自定义不碰/漂移纠偏/种子外 key 清理）。
//
// 装配走 widget_app.dart 的 TestRepositories（与数据层三文件同模式，
// 目录加载器注入测试版——默认加载器走 rootBundle 通道，在假异步区
// 等不到回包会把用例挂死）。
import 'package:flutter_test/flutter_test.dart';
import 'package:lunio/data/database/app_database.dart';
import 'package:lunio/data/repositories/entity_row_codec.dart';
import 'package:lunio/data/repositories/diagnostics_repository.dart';
import 'package:lunio/domain/entities/diagnostics_parse_type.dart';
import 'package:lunio/domain/entities/diagnostics_probe.dart';
import 'package:lunio/domain/entities/sync_metadata.dart';

import '../helpers/widget_app.dart';

void main() {
  late AppDatabase database;
  late TestRepositories repos;
  late DiagnosticsRepository diagnostics;

  setUp(() async {
    database = AppDatabase.inMemory();
    repos = testRepository(database);
    diagnostics = repos.diagnosticsRepository;
    // CRUD 用例的基准态 = 三条内置种子已在库（生产恒为真：bootstrap
    // 在 AppShell 首帧对账过）。
    await repos.catalogRepository.ensureBootstrapData();
  });

  tearDown(() async {
    await database.close();
  });

  DiagnosticsProbe customProbe({
    String name = '进气温度',
    String command = '010F',
    DiagnosticsParseType parseType = DiagnosticsParseType.coolantTemp,
    String? catalogKey,
  }) {
    return DiagnosticsProbe(
      name: name,
      command: command,
      parseType: parseType,
      catalogKey: catalogKey,
    );
  }

  group('实体与解析类型', () {
    test('解析类型 wire 往返一致，未知值 fail-fast', () {
      for (final type in DiagnosticsParseType.values) {
        expect(DiagnosticsParseType.byWire(type.wire), same(type));
      }
      expect(
        () => DiagnosticsParseType.byWire('bogus'),
        throwsArgumentError,
      );
    });

    test('实体校验：空名/空指令抛 ArgumentError', () {
      expect(
        () => DiagnosticsProbe(name: '  ', command: '012F'),
        throwsArgumentError,
      );
      expect(
        () => DiagnosticsProbe(name: 'x', command: ''),
        throwsArgumentError,
      );
    });
  });

  group('仓库 CRUD', () {
    test('saveProbe 新增自定义检测点并出现在列表自定义段', () async {
      final id = await diagnostics.saveProbe(customProbe());
      final probes = await diagnostics.listProbes();
      expect(probes, hasLength(4), reason: '3 内置 + 1 自定义');
      final custom = probes.last;
      expect(custom.id, id);
      expect(custom.name, '进气温度');
      expect(custom.command, '010F');
      expect(custom.parseType, DiagnosticsParseType.coolantTemp);
      expect(custom.enabled, isTrue);
      expect(custom.isBuiltIn, isFalse);
      expect(custom.sync.status, SyncStatus.pendingUpdate);
    });

    test('saveProbe 拒收带 catalogKey 的实体（内置只能由种子产生）', () async {
      expect(
        () => diagnostics.saveProbe(
          customProbe(catalogKey: 'probe:fuelLevel'),
        ),
        throwsArgumentError,
      );
    });

    test('updateProbe 编辑自定义检测点三业务字段', () async {
      final id = await diagnostics.saveProbe(customProbe());
      await diagnostics.updateProbe(
        customProbe(name: '进气压力', command: '011 0B').copyWith(id: id),
      );
      final probes = await diagnostics.listProbes();
      final custom = probes.last;
      expect(custom.name, '进气压力');
      expect(custom.command, '011 0B');
      expect(custom.enabled, isTrue, reason: '编辑不碰启停');
    });

    test('updateProbe 拒绝内置行 / 缺 id / 行不存在', () async {
      final builtIn = (await diagnostics.listProbes()).first;
      expect(builtIn.isBuiltIn, isTrue);
      expect(
        () => diagnostics.updateProbe(
          customProbe(name: '改名').copyWith(id: builtIn.id),
        ),
        throwsArgumentError,
      );
      expect(
        () => diagnostics.updateProbe(customProbe(name: '改名')),
        throwsArgumentError,
      );
      expect(
        () => diagnostics.updateProbe(
          customProbe(name: '改名').copyWith(id: 42),
        ),
        throwsArgumentError,
      );
    });

    test('deleteProbe 删自定义行；内置行与行不存在都拒绝', () async {
      final id = await diagnostics.saveProbe(customProbe());
      final builtIn = (await diagnostics.listProbes()).first;
      expect(
        () => diagnostics.deleteProbe(builtIn.id!),
        throwsArgumentError,
      );
      expect(() => diagnostics.deleteProbe(42), throwsArgumentError);
      await diagnostics.deleteProbe(id);
      final probes = await diagnostics.listProbes();
      expect(probes, hasLength(3));
      expect(probes.where((p) => p.id == id), isEmpty);
    });

    test('setProbeEnabled 内置与自定义都可启停；行不存在拒绝', () async {
      final customId = await diagnostics.saveProbe(customProbe());
      final builtIn = (await diagnostics.listProbes()).first;
      await diagnostics.setProbeEnabled(builtIn.id!, false);
      await diagnostics.setProbeEnabled(customId, false);
      final probes = await diagnostics.listProbes();
      expect(probes.first.enabled, isFalse, reason: '内置行启停被写库');
      expect(probes.last.enabled, isFalse, reason: '自定义行启停被写库');
      expect(() => diagnostics.setProbeEnabled(42, true), throwsArgumentError);
    });

    test('listProbes 排序：内置按种子顺序在前、自定义按创建顺序在后', () async {
      final firstId = await diagnostics.saveProbe(
        customProbe(name: '甲'),
      );
      final secondId = await diagnostics.saveProbe(
        customProbe(name: '乙'),
      );
      final probes = await diagnostics.listProbes();
      expect(probes.map((p) => p.name).toList(), [
        '油量',
        '水温',
        '电压',
        '甲',
        '乙',
      ]);
      expect(probes[3].id, firstId);
      expect(probes[4].id, secondId);
    });
  });

  group('种子对账（经 bootstrap 总入口）', () {
    test('首启插入三条内置种子（幂等对账并入 ensureBootstrapData）', () async {
      await repos.catalogRepository.ensureBootstrapData();
      final probes = await diagnostics.listProbes();
      expect(probes, hasLength(3));
      expect(probes.map((p) => p.catalogKey), [
        'probe:fuelLevel',
        'probe:coolantTemp',
        'probe:voltage',
      ]);
      expect(probes.map((p) => p.name).toList(), ['油量', '水温', '电压']);
      expect(probes.map((p) => p.command).toList(), ['012F', '0105', 'ATRV']);
      expect(probes.map((p) => p.parseType), [
        DiagnosticsParseType.fuelLevel,
        DiagnosticsParseType.coolantTemp,
        DiagnosticsParseType.voltageText,
      ]);
      expect(probes.every((p) => p.enabled && p.isBuiltIn), isTrue);
    });

    test('重复对账零写库（updatedAt 不动）且启停状态保留', () async {
      await repos.catalogRepository.ensureBootstrapData();
      final fuel = (await diagnostics.listProbes()).first;
      await diagnostics.setProbeEnabled(fuel.id!, false);
      // 基准在启停写库"之后"取样：启停按全库约定刷新 updatedAt，
      // 若在它之前取样会把启停的合法写库误判成对账重写。
      final before = await diagnostics.listProbes();

      // 隔开几毫秒再跑第二轮：若第二轮重写了行，updatedAt 至少差 5ms。
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await repos.catalogRepository.ensureBootstrapData();
      final after = await diagnostics.listProbes();
      expect(after, hasLength(3), reason: '不重插');
      expect(
        after.map((p) => p.sync.updatedAt),
        before.map((p) => p.sync.updatedAt),
        reason: '重复对账零写库（updatedAt 不动）',
      );
      expect(after.first.enabled, isFalse, reason: '启停是用户数据，对账不得重置');
    });

    test('对账不碰自定义行', () async {
      await repos.catalogRepository.ensureBootstrapData();
      final id = await diagnostics.saveProbe(customProbe(name: '我的项'));
      await repos.catalogRepository.ensureBootstrapData();
      final probes = await diagnostics.listProbes();
      expect(probes, hasLength(4));
      final custom = probes.last;
      expect(custom.id, id);
      expect(custom.name, '我的项');
      expect(custom.isBuiltIn, isFalse);
    });

    test('内置行漂移纠偏：名称纠回、启停保留', () async {
      await repos.catalogRepository.ensureBootstrapData();
      // 模拟"数据被外部改动"：裸 SQL 改内置行名称（仓库守卫挡住了
      // 一切经仓库的修改路径，漂移只可能来自库外）。
      await database.customStatement(
        "UPDATE diagnostics_probes SET name = '被改过' WHERE catalog_key = 'probe:fuelLevel'",
      );
      await repos.catalogRepository.ensureBootstrapData();
      final probes = await diagnostics.listProbes();
      final fuel = probes.first;
      expect(fuel.name, '油量', reason: '内置行永远等于内置值（ADR 0021）');
      await diagnostics.setProbeEnabled(fuel.id!, false);
      final afterToggle = (await diagnostics.listProbes()).first;
      expect(afterToggle.enabled, isFalse);
    });

    test('种子集合外的内置 key 行被清理，自定义行不受影响', () async {
      await repos.catalogRepository.ensureBootstrapData();
      // 裸插一行带内置 key 但不在种子集合内（模拟未来版本种子收缩残留）。
      await database.into(database.diagnosticsProbes).insert(
            diagnosticsProbeCompanion(
              customProbe(catalogKey: 'probe:stale'),
              777001,
            ),
          );
      final customId = await diagnostics.saveProbe(customProbe(name: '保留我'));
      await repos.catalogRepository.ensureBootstrapData();
      final probes = await diagnostics.listProbes();
      expect(probes, hasLength(4), reason: 'stale 清掉，3 内置 + 1 自定义');
      expect(probes.where((p) => p.catalogKey == 'probe:stale'), isEmpty);
      expect(probes.where((p) => p.id == customId), hasLength(1));
    });
  });
}
