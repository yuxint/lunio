// 数据库迁移回归测试（ADR 0005 2026-09-20 修订）。
//
// 修订后的政策：纯增量 schema 变更（新增表/列）必须走 onUpgrade 增量
// 迁移，老库升级后存量数据保留；删库重建只留给破坏性变更。
//
// 模拟老库的手法：内存库无法"关掉再打开"，触发不了 onUpgrade，
// 所以用文件库——先按当前代码 schema 建库并写入存量数据，关闭后
// 把库削成老版本形态（DROP 掉该版本之后新增的表 + user_version 改回
// 老版本号；纯增量变更下"老库 = 新库少若干张新表"，二者结构等价），
// 再重新打开，让真实迁移链路（Drift 读 user_version → onUpgrade）跑通。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lunio/data/database/app_database.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('lunio_migration_test');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test('v2 老库升级到 v3：建出 fuel_records，存量表数据原样保留', () async {
    final file = File('${tempDir.path}/lunio.sqlite');

    // 1. 按当前代码（v3）建库，插一条"升级前就存在"的车辆数据。
    final v3 = AppDatabase.forFile(file);
    await v3.customStatement(
      "INSERT INTO cars (id, brand, model, powertrain_type,"
      " current_mileage_km, road_date, sync_status, updated_at, version)"
      " VALUES (1, '大众', '朗逸', 'fuel', 12000, '2024-01-01',"
      " 'synced', '2024-01-01T00:00:00', 1)",
    );
    await v3.close();

    // 2. 削成 v2 形态：v2 之后新增的表全部删掉（v4 代码下是两张）、
    //    版本号改回 2。真实 v2 老库升到 v4 会依次跑全部分支。
    final shaved = AppDatabase.forFile(file);
    await shaved.customStatement('DROP TABLE fuel_records');
    await shaved.customStatement('DROP TABLE diagnostics_probes');
    // v6 新增的 cars 总容积列在 v2 形态里不存在。
    await shaved.customStatement(
      'ALTER TABLE cars DROP COLUMN total_tank_capacity_liters',
    );
    await shaved.customStatement('PRAGMA user_version = 2');
    await shaved.close();

    // 3. 重新打开 → onUpgrade(2→3) 触发：新表建回，存量数据一行不动。
    final upgraded = AppDatabase.forFile(file);
    addTearDown(upgraded.close);
    final fuelRows = await upgraded.select(upgraded.fuelRecords).get();
    expect(fuelRows, isEmpty, reason: '迁移应只建表，不写入数据');
    // v3 的 fuel_records 结构以 ADR 0015（2026-09-22 就地重定义）为准：
    // 迁移建出的必须是新五字段结构，不是旧五字段（里程/加满已删）。
    final columnRows = await upgraded
        .customSelect('PRAGMA table_info(fuel_records)')
        .get();
    final columnNames = columnRows.map((row) => row.data['name']).toSet();
    expect(
      columnNames,
      containsAll([
        'grade',
        'unit_price_cents',
        'payable_cents',
        'actual_cents',
      ]),
    );
    expect(columnNames, isNot(contains('mileage_km')));
    expect(columnNames, isNot(contains('full_tank')));
    // v2→v4 跨版本升级：from<4 分支同样要跑，diagnostics_probes 也建出。
    final probeRows = await upgraded.select(upgraded.diagnosticsProbes).get();
    expect(probeRows, isEmpty);
    final carRows = await upgraded.select(upgraded.cars).get();
    expect(carRows, hasLength(1), reason: '升级不得丢存量数据');
    expect(carRows.single.brand, '大众');
    expect(carRows.single.currentMileageKm, 12000);
  });

  test('v3 老库升级到 v4：建出 diagnostics_probes，存量表数据原样保留', () async {
    final file = File('${tempDir.path}/lunio-v3.sqlite');

    // 1. 按当前代码（v4）建库，插一条"升级前就存在"的车辆数据。
    final v4 = AppDatabase.forFile(file);
    await v4.customStatement(
      "INSERT INTO cars (id, brand, model, powertrain_type,"
      " current_mileage_km, road_date, sync_status, updated_at, version)"
      " VALUES (1, '大众', '朗逸', 'fuel', 12000, '2024-01-01',"
      " 'synced', '2024-01-01T00:00:00', 1)",
    );
    await v4.close();

    // 2. 削成 v3 形态：删新表、版本号改回 3。
    final shaved = AppDatabase.forFile(file);
    await shaved.customStatement('DROP TABLE diagnostics_probes');
    // v6 新增的 cars 总容积列在 v3 形态里不存在。
    await shaved.customStatement(
      'ALTER TABLE cars DROP COLUMN total_tank_capacity_liters',
    );
    await shaved.customStatement('PRAGMA user_version = 3');
    await shaved.close();

    // 3. 重新打开 → onUpgrade(3→4) 触发：新表建回（空表——种子不在
    //    迁移里插，由 bootstrap 幂等对账写入），存量数据一行不动。
    final upgraded = AppDatabase.forFile(file);
    addTearDown(upgraded.close);
    final probeRows = await upgraded.select(upgraded.diagnosticsProbes).get();
    expect(probeRows, isEmpty, reason: '迁移应只建表，不写入数据');
    final columnRows = await upgraded
        .customSelect('PRAGMA table_info(diagnostics_probes)')
        .get();
    final columnNames = columnRows.map((row) => row.data['name']).toSet();
    expect(
      columnNames,
      containsAll([
        'name',
        'command',
        'parse_type',
        'enabled',
        'catalog_key',
        'car_id',
        'refresh_interval_seconds',
        'header',
        'sync_status',
        'updated_at',
        'version',
      ]),
    );
    final carRows = await upgraded.select(upgraded.cars).get();
    expect(carRows, hasLength(1), reason: '升级不得丢存量数据');
    expect(carRows.single.brand, '大众');
    expect(carRows.single.currentMileageKm, 12000);
  });

  test('v4 老库升级到 v6：读数三列 + 每车/间隔/header + 总容积', () async {
    final file = File('${tempDir.path}/lunio-v6-from-v4.sqlite');

    // 1. 按当前代码建库，只留车辆存量；检测点表随后按 v4 形态重建。
    final current = AppDatabase.forFile(file);
    await current.customStatement(
      "INSERT INTO cars (id, brand, model, powertrain_type,"
      " current_mileage_km, road_date, sync_status, updated_at, version)"
      " VALUES (1, '大众', '朗逸', 'fuel', 12000, '2024-01-01',"
      " 'synced', '2024-01-01T00:00:00', 1)",
    );
    await current.close();

    // 2. 削成 v4 形态：cars 去掉 v6 总容积列；diagnostics_probes 重建为
    //    v4 表（无读数三列、无 car_id/refresh/header，唯一键仍 catalogKey）。
    final shaved = AppDatabase.forFile(file);
    await shaved.customStatement(
      'ALTER TABLE cars DROP COLUMN total_tank_capacity_liters',
    );
    await shaved.customStatement('DROP TABLE diagnostics_probes');
    await shaved.customStatement('''
      CREATE TABLE diagnostics_probes (
        id INTEGER NOT NULL PRIMARY KEY,
        name TEXT NOT NULL,
        command TEXT NOT NULL,
        parse_type TEXT NOT NULL,
        enabled INTEGER NOT NULL DEFAULT 1,
        catalog_key TEXT NULL,
        sync_status TEXT NOT NULL DEFAULT 'synced',
        updated_at TEXT NOT NULL,
        version INTEGER NOT NULL DEFAULT 1,
        UNIQUE (catalog_key)
      )
    ''');
    await shaved.customStatement(
      "INSERT INTO diagnostics_probes (id, name, command, parse_type,"
      " enabled, catalog_key, sync_status, updated_at, version)"
      " VALUES (1, '油量', '012F', 'fuelLevel', 1, 'probe:fuelLevel',"
      " 'synced', '2026-11-15T08:00:00.000', 1)",
    );
    await shaved.customStatement('PRAGMA user_version = 4');
    await shaved.close();

    // 3. 重开 → 4→5 加读数三列、5→6 重建每车/间隔/header 与总容积。
    final upgraded = AppDatabase.forFile(file);
    addTearDown(upgraded.close);
    final columnRows = await upgraded
        .customSelect('PRAGMA table_info(diagnostics_probes)')
        .get();
    final columnNames = columnRows.map((row) => row.data['name']).toSet();
    expect(
      columnNames,
      containsAll([
        'last_value',
        'last_percent',
        'last_reading_at',
        'car_id',
        'refresh_interval_seconds',
        'header',
      ]),
    );
    final probes = await upgraded.select(upgraded.diagnosticsProbes).get();
    expect(probes, hasLength(1));
    expect(probes.single.name, '油量');
    expect(probes.single.command, '012F');
    expect(probes.single.enabled, isTrue);
    expect(probes.single.carId, 1, reason: '存量行归第一辆车');
    // v6 回填 30（当时的旧默认），v7 内置行统一迁到 60（当前默认）。
    expect(probes.single.refreshIntervalSeconds, 60);
    expect(probes.single.header, isNull);
    expect(probes.single.lastValue, isNull, reason: '升级后读数列从 NULL 起步');
    final carRows = await upgraded.select(upgraded.cars).get();
    expect(carRows, hasLength(1), reason: '升级不得丢存量数据');
    expect(carRows.single.currentMileageKm, 12000);
    expect(carRows.single.totalTankCapacityLiters, isNull);
  });

  test('v5 老库升级到 v6：读数保留，每车/间隔/header + 总容积补齐', () async {
    final file = File('${tempDir.path}/lunio-v6-from-v5.sqlite');

    final current = AppDatabase.forFile(file);
    await current.customStatement(
      "INSERT INTO cars (id, brand, model, powertrain_type,"
      " current_mileage_km, road_date, sync_status, updated_at, version)"
      " VALUES (1, '大众', '朗逸', 'fuel', 12000, '2024-01-01',"
      " 'synced', '2024-01-01T00:00:00', 1)",
    );
    await current.close();

    // v5 形态：有读数三列，无 car_id/refresh/header，唯一键 catalogKey。
    final shaved = AppDatabase.forFile(file);
    await shaved.customStatement(
      'ALTER TABLE cars DROP COLUMN total_tank_capacity_liters',
    );
    await shaved.customStatement('DROP TABLE diagnostics_probes');
    await shaved.customStatement('''
      CREATE TABLE diagnostics_probes (
        id INTEGER NOT NULL PRIMARY KEY,
        name TEXT NOT NULL,
        command TEXT NOT NULL,
        parse_type TEXT NOT NULL,
        enabled INTEGER NOT NULL DEFAULT 1,
        catalog_key TEXT NULL,
        last_value TEXT NULL,
        last_percent REAL NULL,
        last_reading_at TEXT NULL,
        sync_status TEXT NOT NULL DEFAULT 'synced',
        updated_at TEXT NOT NULL,
        version INTEGER NOT NULL DEFAULT 1,
        UNIQUE (catalog_key)
      )
    ''');
    await shaved.customStatement(
      "INSERT INTO diagnostics_probes (id, name, command, parse_type,"
      " enabled, catalog_key, last_value, last_percent, last_reading_at,"
      " sync_status, updated_at, version) VALUES (1, '油量', '012F',"
      " 'fuelLevel', 1, 'probe:fuelLevel', '37.6%', 37.6,"
      " '2026-11-14T08:00:00.000', 'synced', '2026-11-15T08:00:00.000', 1)",
    );
    await shaved.customStatement('PRAGMA user_version = 5');
    await shaved.close();

    final upgraded = AppDatabase.forFile(file);
    addTearDown(upgraded.close);
    final probes = await upgraded.select(upgraded.diagnosticsProbes).get();
    expect(probes, hasLength(1));
    expect(probes.single.carId, 1);
    // v6 回填 30（当时的旧默认），v7 内置行统一迁到 60（当前默认）；
    // 读数三列不受间隔迁移影响。
    expect(probes.single.refreshIntervalSeconds, 60);
    expect(probes.single.header, isNull);
    expect(probes.single.lastValue, '37.6%', reason: '读数随迁移保留');
    expect(probes.single.lastPercent, 37.6);
    expect(
      probes.single.lastReadingAt,
      '2026-11-14T08:00:00.000',
    );
    final carRows = await upgraded.select(upgraded.cars).get();
    expect(carRows.single.totalTankCapacityLiters, isNull);
  });

  test('v4 无车老库升级到 v6：孤儿检测点行就地清理', () async {
    final file = File('${tempDir.path}/lunio-v6-from-v4-no-car.sqlite');

    // 1. 按当前代码建库，不放任何车辆，削成 v4 形态的检测点表并插入
    //    两行（内置 + 自定义）——模拟"删光车辆后残留检测点"的 v4 老库
    //    （v4 检测点是全局表，删车不删行）。
    final current = AppDatabase.forFile(file);
    await current.select(current.cars).get();
    await current.close();

    final shaved = AppDatabase.forFile(file);
    await shaved.customStatement(
      'ALTER TABLE cars DROP COLUMN total_tank_capacity_liters',
    );
    await shaved.customStatement('DROP TABLE diagnostics_probes');
    await shaved.customStatement('''
      CREATE TABLE diagnostics_probes (
        id INTEGER NOT NULL PRIMARY KEY,
        name TEXT NOT NULL,
        command TEXT NOT NULL,
        parse_type TEXT NOT NULL,
        enabled INTEGER NOT NULL DEFAULT 1,
        catalog_key TEXT NULL,
        sync_status TEXT NOT NULL DEFAULT 'synced',
        updated_at TEXT NOT NULL,
        version INTEGER NOT NULL DEFAULT 1,
        UNIQUE (catalog_key)
      )
    ''');
    await shaved.customStatement(
      "INSERT INTO diagnostics_probes (id, name, command, parse_type,"
      " enabled, catalog_key, sync_status, updated_at, version)"
      " VALUES (1, '油量', '012F', 'fuelLevel', 1, 'probe:fuelLevel',"
      " 'synced', '2026-11-15T08:00:00.000', 1)",
    );
    await shaved.customStatement(
      "INSERT INTO diagnostics_probes (id, name, command, parse_type,"
      " enabled, catalog_key, sync_status, updated_at, version)"
      " VALUES (2, '进气温度', '010F', 'coolantTemp', 1, NULL,"
      " 'synced', '2026-11-15T08:00:00.000', 1)",
    );
    await shaved.customStatement('PRAGMA user_version = 4');
    await shaved.close();

    // 2. 重开 → 4→5 加读数列、5→6 重建每车结构。没有车时 car_id 回填
    //    NULL，孤儿行没有宿主（仓库按 carId 过滤读不到、种子对账不认领、
    //    备份导出实体 carId 必填会崩）——升级即清理，一行不留。
    final upgraded = AppDatabase.forFile(file);
    addTearDown(upgraded.close);
    final probes = await upgraded.select(upgraded.diagnosticsProbes).get();
    expect(probes, isEmpty, reason: '无车库升级时孤儿检测点行应就地清理');
    final carRows = await upgraded.select(upgraded.cars).get();
    expect(carRows, isEmpty);
  });

  test('v6 老库升级到 v7：内置行电压换源 + 间隔 10/30→60，且只跑一次', () async {
    final file = File('${tempDir.path}/lunio-v7-from-v6.sqlite');

    // 1. 按当前代码建库（v7 与 v6 表结构相同），写入 v6 形态存量：
    //    电压仍是 ATRV + 旧读数；两条内置行分别停在两代旧默认 10/30；
    //    一条用户改过的 15；一条自定义行 10。
    final current = AppDatabase.forFile(file);
    await current.customStatement(
      "INSERT INTO cars (id, brand, model, powertrain_type,"
      " current_mileage_km, road_date, sync_status, updated_at, version)"
      " VALUES (1, '大众', '朗逸', 'fuel', 12000, '2024-01-01',"
      " 'synced', '2024-01-01T00:00:00', 1)",
    );
    Future<void> insertProbe(
      int id,
      String name,
      String command,
      String parseType,
      String? catalogKey,
      int interval, {
      String? lastValue,
      double? lastPercent,
      String? lastReadingAt,
    }) {
      return current.customStatement(
        'INSERT INTO diagnostics_probes (id, car_id, name, command,'
        ' parse_type, enabled, catalog_key, refresh_interval_seconds,'
        ' last_value, last_percent, last_reading_at, sync_status,'
        ' updated_at, version)'
        ' VALUES (?, 1, ?, ?, ?, 1, ?, ?, ?, ?, ?, ?, ?, 1)',
        [
          id,
          name,
          command,
          parseType,
          catalogKey,
          interval,
          lastValue,
          lastPercent,
          lastReadingAt,
          'synced',
          '2026-11-20T08:00:00.000',
        ],
      );
    }

    await insertProbe(
      1,
      '电压',
      'ATRV',
      'voltageText',
      'probe:voltage',
      30,
      lastValue: '11.2V',
      lastPercent: 11.2,
      lastReadingAt: '2026-11-20T07:58:00.000',
    );
    await insertProbe(
      2,
      '水温',
      '0167',
      'coolantTempAux',
      'probe:coolantTemp',
      10,
      lastValue: '95℃',
      lastPercent: 95,
    );
    // 用户手改成 15 秒的内置行：迁移不得覆盖。
    await insertProbe(
      3,
      '油量',
      '012F',
      'fuelLevel',
      'probe:fuelLevel',
      15,
    );
    // 自定义行：节奏由用户自己定，迁移一律不碰。
    await insertProbe(4, '我的项', '0105', 'coolantTemp', null, 10);
    await current.customStatement('PRAGMA user_version = 6');
    await current.close();

    // 2. 重开 → v6→v7：电压换 0142 并清旧读数，内置行 10/30 → 60，
    //    用户改过的 15 与自定义 10 原样保留。
    final upgraded = AppDatabase.forFile(file);
    final probes = await upgraded.select(upgraded.diagnosticsProbes).get();
    final byId = {for (final p in probes) p.id: p};

    final voltage = byId[1]!;
    expect(voltage.command, '0142', reason: 'ATRV 是读数缺陷，一次性换源');
    expect(voltage.parseType, 'moduleVoltage');
    expect(voltage.name, '电压', reason: '只动命令/解析类型，名称是用户数据');
    expect(voltage.refreshIntervalSeconds, 60);
    expect(voltage.lastValue, isNull, reason: '旧读数是 ATRV 口径，必须清掉');
    expect(voltage.lastPercent, isNull);
    expect(voltage.lastReadingAt, isNull);
    expect(voltage.syncStatus, 'pendingUpdate');

    expect(byId[2]!.command, '0167');
    expect(byId[2]!.refreshIntervalSeconds, 60);
    expect(byId[2]!.lastValue, '95℃', reason: '非电压行的读数不受影响');
    expect(byId[3]!.refreshIntervalSeconds, 15, reason: '用户改过的间隔不动');
    expect(byId[4]!.refreshIntervalSeconds, 10, reason: '自定义行一律不碰');

    // 3. 一次性：用户在升级后手动改回 ATRV / 10 秒，重开（不再升级）
    //    必须原样保留——这正是把迁移从 bootstrap 挪到 schema 的原因。
    await upgraded.customStatement(
      "UPDATE diagnostics_probes SET command = 'ATRV',"
      " parse_type = 'voltageText' WHERE id = 1",
    );
    await upgraded.customStatement(
      'UPDATE diagnostics_probes SET refresh_interval_seconds = 10 '
      'WHERE id = 2',
    );
    await upgraded.close();

    final reopened = AppDatabase.forFile(file);
    addTearDown(reopened.close);
    final after = {
      for (final p in await reopened.select(reopened.diagnosticsProbes).get())
        p.id: p,
    };
    expect(after[1]!.command, 'ATRV', reason: '迁移只跑一次，用户改动保留');
    expect(after[2]!.refreshIntervalSeconds, 10);
  });

  test('全新安装（无 user_version）走 onCreate，全部表建齐', () async {
    final file = File('${tempDir.path}/fresh.sqlite');
    final fresh = AppDatabase.forFile(file);
    addTearDown(fresh.close);
    // 不逐张查询全部表，抽查首尾与最新两张：迁移路径正确性由上面两条
    // 用例保证，这里只确认 onCreate 不走 onUpgrade 也能建出末位注册表。
    await fresh.select(fresh.fuelRecords).get();
    await fresh.select(fresh.diagnosticsProbes).get();
    await fresh.select(fresh.cars).get();
  });
}
