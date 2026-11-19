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

import '../helpers/builders.dart';
import '../helpers/widget_app.dart';

void main() {
  late AppDatabase database;
  late TestRepositories repos;
  late DiagnosticsRepository diagnostics;
  late int carId;

  setUp(() async {
    database = AppDatabase.inMemory();
    repos = testRepository(database);
    diagnostics = repos.diagnosticsRepository;
    // 每车一套（ADR 0021 修订节）：先有一辆车，bootstrap 才有宿主可
    // 播种；CRUD 用例的基准态 = 该车的三条内置种子已在库。
    carId = await repos.insertCarForTest(defaultCar());
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
      carId: carId,
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
        () => DiagnosticsProbe(carId: carId, name: '  ', command: '012F'),
        throwsArgumentError,
      );
      expect(
        () => DiagnosticsProbe(carId: carId, name: 'x', command: ''),
        throwsArgumentError,
      );
    });
  });

  group('仓库 CRUD', () {
    test('saveProbe 新增自定义检测点并出现在列表自定义段', () async {
      final id = await diagnostics.saveProbe(customProbe());
      final probes = await diagnostics.listProbes(carId);
      expect(probes, hasLength(8), reason: '7 内置 + 1 自定义');
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
      final probes = await diagnostics.listProbes(carId);
      final custom = probes.last;
      expect(custom.name, '进气压力');
      expect(custom.command, '011 0B');
      expect(custom.enabled, isTrue, reason: '编辑不碰启停');
    });

    test('updateProbe 允许内置行编辑；缺 id / 行不存在拒绝', () async {
      final builtIn = (await diagnostics.listProbes(carId)).first;
      expect(builtIn.isBuiltIn, isTrue);
      await diagnostics.updateProbe(
        builtIn.copyWith(name: '油量改', refreshIntervalSeconds: 60),
      );
      final updated = (await diagnostics.listProbes(carId)).first;
      expect(updated.name, '油量改');
      expect(updated.refreshIntervalSeconds, 60);
      expect(updated.isBuiltIn, isTrue, reason: 'catalogKey 不改写');
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
      final builtIn = (await diagnostics.listProbes(carId)).first;
      expect(
        () => diagnostics.deleteProbe(builtIn.id!),
        throwsArgumentError,
      );
      expect(() => diagnostics.deleteProbe(42), throwsArgumentError);
      await diagnostics.deleteProbe(id);
      final probes = await diagnostics.listProbes(carId);
      expect(probes, hasLength(7));
      expect(probes.where((p) => p.id == id), isEmpty);
    });

    test('setProbeEnabled 内置与自定义都可启停；行不存在拒绝', () async {
      final customId = await diagnostics.saveProbe(customProbe());
      final builtIn = (await diagnostics.listProbes(carId)).first;
      await diagnostics.setProbeEnabled(builtIn.id!, false);
      await diagnostics.setProbeEnabled(customId, false);
      final probes = await diagnostics.listProbes(carId);
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
      final probes = await diagnostics.listProbes(carId);
      expect(probes.map((p) => p.name).toList(), [
        '油量',
        '水温',
        '电压',
        '短期燃油修正',
        '长期燃油修正',
        'CVT 油温',
        '里程表',
        '甲',
        '乙',
      ]);
      expect(probes[7].id, firstId);
      expect(probes[8].id, secondId);
    });
  });

  group('最后读数写点（2026-11-15，ADR 0021 修订节）', () {
    test('saveProbeReading 写三列，实体读回带值，同步元数据不动', () async {
      final probes = await diagnostics.listProbes(carId);
      final fuel = probes.firstWhere((p) => p.name == '油量');
      final before = probes.firstWhere((p) => p.name == '电压');

      await diagnostics.saveProbeReading(
        fuel.id!,
        value: '38%',
        percent: 37.6,
        at: DateTime(2026, 11, 14, 8, 0, 0),
      );

      final after = await diagnostics.listProbes(carId);
      final fuelAfter = after.firstWhere((p) => p.name == '油量');
      expect(fuelAfter.lastValue, '38%');
      expect(fuelAfter.lastPercent, 37.6);
      expect(fuelAfter.lastReadingAt, DateTime(2026, 11, 14, 8, 0, 0));
      // 读数高频写不盖同步章：syncStatus/updatedAt/version 原样。
      final voltageBefore = before;
      final voltageAfter = after.firstWhere((p) => p.name == '电压');
      expect(voltageAfter.sync.updatedAt, voltageBefore.sync.updatedAt);
      expect(voltageAfter.sync.version, voltageBefore.sync.version);
    });

    test('saveProbeReading 只动目标行，行不存在静默跳过', () async {
      final probes = await diagnostics.listProbes(carId);
      final fuel = probes.firstWhere((p) => p.name == '油量');
      expect(fuel.lastValue, isNull);
      await diagnostics.saveProbeReading(
        99999,
        value: 'x',
        at: DateTime(2026, 11, 14, 8),
      );
      final after = await diagnostics.listProbes(carId);
      final fuelAfter = after.firstWhere((p) => p.name == '油量');
      expect(fuelAfter.lastValue, isNull);
      expect(after, hasLength(7));
    });

    test('编辑检测点不丢最后读数（updateProbe 白名单写三业务字段）', () async {
      final probeId = await diagnostics.saveProbe(customProbe(name: '进气温度'));
      await diagnostics.saveProbeReading(
        probeId,
        value: '42℃',
        percent: null,
        at: DateTime(2026, 11, 14, 8),
      );
      final probe = (await diagnostics.listProbes(carId)).firstWhere(
        (p) => p.id == probeId,
      );
      await diagnostics.updateProbe(
        DiagnosticsProbe(
          id: probe.id,
          carId: carId,
          name: '进气温度改',
          command: probe.command,
          parseType: probe.parseType,
        ),
      );
      final after = (await diagnostics.listProbes(carId)).firstWhere(
        (p) => p.id == probeId,
      );
      expect(after.name, '进气温度改');
      expect(after.lastValue, '42℃');
      expect(after.lastReadingAt, DateTime(2026, 11, 14, 8));
    });
  });

  group('种子对账（经 bootstrap 总入口）', () {
    test('首启插入七条内置种子（幂等对账并入 ensureBootstrapData）', () async {
      await repos.catalogRepository.ensureBootstrapData();
      final probes = await diagnostics.listProbes(carId);
      expect(probes, hasLength(7));
      expect(probes.map((p) => p.catalogKey), [
        'probe:fuelLevel',
        'probe:coolantTemp',
        'probe:voltage',
        'probe:stftBank1',
        'probe:ltftBank1',
        'probe:cvtOilTemp',
        'probe:odometer',
      ]);
      expect(probes.map((p) => p.name).toList(), ['油量', '水温', '电压', '短期燃油修正', '长期燃油修正', 'CVT 油温', '里程表']);
      expect(probes.map((p) => p.command).toList(), ['012F', '0167', 'ATRV', '0106', '0107', '222301', '01A6']);
      expect(probes.map((p) => p.parseType), [
        DiagnosticsParseType.fuelLevel,
        DiagnosticsParseType.coolantTempAux,
        DiagnosticsParseType.voltageText,
        DiagnosticsParseType.fuelTrimPercent,
        DiagnosticsParseType.fuelTrimPercent,
        DiagnosticsParseType.cvtOilTemp,
        DiagnosticsParseType.odometer,
      ]);
      expect(probes.every((p) => p.enabled && p.isBuiltIn), isTrue);
      expect(probes.every((p) => p.carId == carId), isTrue);
      expect(
        probes.every((p) => p.refreshIntervalSeconds == DiagnosticsRepository.defaultRefreshIntervalSeconds),
        isTrue,
      );
    });

    test('重复对账零写库（updatedAt 不动）且启停状态保留', () async {
      await repos.catalogRepository.ensureBootstrapData();
      final fuel = (await diagnostics.listProbes(carId)).first;
      await diagnostics.setProbeEnabled(fuel.id!, false);
      // 基准在启停写库"之后"取样：启停按全库约定刷新 updatedAt，
      // 若在它之前取样会把启停的合法写库误判成对账重写。
      final before = await diagnostics.listProbes(carId);

      // 隔开几毫秒再跑第二轮：若第二轮重写了行，updatedAt 至少差 5ms。
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await repos.catalogRepository.ensureBootstrapData();
      final after = await diagnostics.listProbes(carId);
      expect(after, hasLength(7), reason: '不重插');
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
      final probes = await diagnostics.listProbes(carId);
      expect(probes, hasLength(8));
      final custom = probes.last;
      expect(custom.id, id);
      expect(custom.name, '我的项');
      expect(custom.isBuiltIn, isFalse);
    });

    test('内置行不被对账改回（内置可编辑，ADR 0021 修订节）', () async {
      await repos.catalogRepository.ensureBootstrapData();
      final fuel = (await diagnostics.listProbes(carId)).first;
      await diagnostics.updateProbe(
        fuel.copyWith(name: '我的油量', refreshIntervalSeconds: 60),
      );
      await repos.catalogRepository.ensureBootstrapData();
      final after = (await diagnostics.listProbes(carId)).first;
      expect(after.name, '我的油量', reason: '对账只补缺失，不纠偏用户编辑');
      expect(after.refreshIntervalSeconds, 60);
      await diagnostics.setProbeEnabled(after.id!, false);
      final toggled = (await diagnostics.listProbes(carId)).first;
      expect(toggled.enabled, isFalse);
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
      final probes = await diagnostics.listProbes(carId);
      expect(probes, hasLength(8), reason: 'stale 清掉，7 内置 + 1 自定义');
      expect(probes.where((p) => p.catalogKey == 'probe:stale'), isEmpty);
      expect(probes.where((p) => p.id == customId), hasLength(1));
    });
    test('存量自定义同指令收编：自定义 01A6 被删、内置里程表接管（深审问题 7）', () async {
      // 模拟旧安装：推荐模板批 2 曾含 01A6，存量车可能已有自定义 01A6。
      // 裸插自定义行（catalogKey null）再跑对账，断言收编。
      await database.into(database.diagnosticsProbes).insert(
            diagnosticsProbeCompanion(
              customProbe(
                name: '里程表（模板）',
                command: '01A6',
                parseType: DiagnosticsParseType.odometer,
              ),
              777002,
            ),
          );
      await repos.catalogRepository.ensureBootstrapData();
      final probes = await diagnostics.listProbes(carId);
      // 自定义 01A6 被收编删除，内置七条接管（无双倍轮询、无双卡）。
      expect(probes, hasLength(7));
      expect(probes.where((p) => p.command == '01A6'), hasLength(1));
      expect(
        probes.where((p) => p.command == '01A6').single.isBuiltIn,
        isTrue,
      );
    });
  });
}
