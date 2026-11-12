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
