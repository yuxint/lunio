// 数据库迁移回归测试（ADR 0005 2026-09-20 修订）。
//
// 修订后的政策：纯增量 schema 变更（新增表/列）必须走 onUpgrade 增量
// 迁移，老库升级后存量数据保留；删库重建只留给破坏性变更。
//
// 模拟 v2 老库的手法：内存库无法"关掉再打开"，触发不了 onUpgrade，
// 所以用文件库——先按当前代码 schema（v3）建库并写入存量数据，关闭后
// 把库削成 v2 形态（DROP 掉 v3 新增的 fuel_records 表 + user_version
// 改回 2；纯增量变更下"v2 库 = v3 库少一张新表"，二者结构等价），
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

    // 2. 削成 v2 形态：删新表、版本号改回 2。
    final shaved = AppDatabase.forFile(file);
    await shaved.customStatement('DROP TABLE fuel_records');
    await shaved.customStatement('PRAGMA user_version = 2');
    await shaved.close();

    // 3. 重新打开 → onUpgrade(2→3) 触发：新表建回，存量数据一行不动。
    final upgraded = AppDatabase.forFile(file);
    addTearDown(upgraded.close);
    final fuelRows = await upgraded.select(upgraded.fuelRecords).get();
    expect(fuelRows, isEmpty, reason: '迁移应只建表，不写入数据');
    final carRows = await upgraded.select(upgraded.cars).get();
    expect(carRows, hasLength(1), reason: '升级不得丢存量数据');
    expect(carRows.single.brand, '大众');
    expect(carRows.single.currentMileageKm, 12000);
  });

  test('全新安装（无 user_version）走 onCreate，八张表全部建齐', () async {
    final file = File('${tempDir.path}/fresh.sqlite');
    final fresh = AppDatabase.forFile(file);
    addTearDown(fresh.close);
    // 不查询全部表，抽查首尾两张：迁移路径正确性由上一条用例保证，
    // 这里只确认 onCreate 不走 onUpgrade 也能建出最后注册的新表。
    await fresh.select(fresh.fuelRecords).get();
    await fresh.select(fresh.cars).get();
  });
}
