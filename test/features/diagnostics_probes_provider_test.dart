// 检测点列表 provider 机制测试（ADR 0021"写点直失效"模型）：
//  1. 首启种子就位后列表可读（读侧显式 await bootstrap，与 cars 同款）；
//  2. 写点直失效：写库 + 逐出后读侧可见；未逐出时缓存不变（锁住
//     "provider 不自动重查"的模型边界）；
//  3. 边界保持：不随车辆数据纪元重算（表不挂车，ADR 0021）——写库
//     只走逐出，bump 纪元不牵动检测点列表。
//
// ProviderContainer 驱动真实装配（与 vehicle_data_epoch_test 同手法）。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunio/app/providers.dart';
import 'package:lunio/data/database/app_database.dart';
import 'package:lunio/data/repositories/built_in_catalog_repository.dart';
import 'package:lunio/data/repositories/diagnostics_repository.dart';
import 'package:lunio/domain/entities/diagnostics_probe.dart';

import '../helpers/builders.dart';
import '../helpers/built_in_catalog_loader.dart';
import '../helpers/widget_app.dart';

void main() {
  late AppDatabase database;
  late DiagnosticsRepository diagnostics;
  late ProviderContainer container;
  late int carId;

  setUp(() async {
    database = AppDatabase.inMemory();
    final repos = testRepository(database);
    carId = await repos.insertCarForTest(defaultCar());
    diagnostics = repos.diagnosticsRepository;
    container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(database),
      builtInCatalogRepositoryProvider.overrideWithValue(
        BuiltInCatalogRepository(
          database,
          loadBuiltInVehicleCatalog: () async =>
              loadBuiltInVehicleCatalogForTest(),
          ensureProbes: () => diagnostics.ensureBuiltInProbes(),
        ),
      ),
    ]);
  });

  tearDown(() async {
    container.dispose();
    await database.close();
  });

  test('读侧 await bootstrap：首帧即读到该车内置五条种子', () async {
    final probes = await container.read(
      diagnosticsProbesProvider(carId).future,
    );
    expect(probes, hasLength(5));
    expect(probes.map((p) => p.name).toList(), ['油量', '水温', '电压', '短期燃油修正', '长期燃油修正']);
    expect(probes.every((p) => p.isBuiltIn), isTrue);
    expect(probes.every((p) => p.carId == carId), isTrue);
  });

  test('写点直失效：写库后读侧缓存不变，逐出后才可见新值', () async {
    final first = await container.read(
      diagnosticsProbesProvider(carId).future,
    );
    expect(first, hasLength(5));
    await diagnostics.saveProbe(
      DiagnosticsProbe(carId: carId, name: '进气温度', command: '010F'),
    );
    // 未逐出：provider 缓存住旧列表（本 provider 不 watch 任何纪元，
    // 也不监听数据库——写点必须显式逐出，这正是要锁住的契约）。
    final cached = await container.read(
      diagnosticsProbesProvider(carId).future,
    );
    expect(cached, same(first));
    // 写点逐出（动作层诊断分节协议，后续 UI 票接入）。
    container.invalidate(diagnosticsProbesProvider(carId));
    final second = await container.read(
      diagnosticsProbesProvider(carId).future,
    );
    expect(second, hasLength(6));
    expect(second.last.name, '进气温度');
  });

  test('不随车辆数据纪元重算（写点直失效模型）', () async {
    final first = await container.read(
      diagnosticsProbesProvider(carId).future,
    );
    expect(first, hasLength(5));
    container.read(vehicleDataEpochProvider.notifier).bump();
    final second = await container.read(
      diagnosticsProbesProvider(carId).future,
    );
    expect(second, same(first), reason: '纪元 bump 不得牵动检测点列表');
  });
}
