// 偏好纪元机制测试（ADR 0017）：偏好表派生 provider watch 纪元、写点
// bump 后自动重查库——2026-09-26 取代手工失效名单（providers.dart 的
// _invalidatePreferences 家族）后，这是新机制的测试面。
//
// 与通知同步代数（notification_sync_guard）同构的 Notifier 模式，这里
// 锁三件事：
//  1. bump 一次，providers.dart 域的抽样 provider（主题）重查库；
//  2. bump 一次，fuel_prices.dart 域的抽样 provider（省份）重查库——
//     证明油价域文件里的 watch 行在位（旧名单时代它靠跨文件名单逐出）；
//  3. 边界保持（grilling Q3 拍板）：parkingCountdownProvider 不随纪元
//     重算——它是"写点直失效自己"模型（动作层 saveParkingCountdown /
//     clearParkingCountdown 各自逐出），纪元不该牵动它。
//
// 依赖可替换：内存数据库 + 计数偏好门面子类（spy），ProviderContainer
// 驱动真实装配（与 fuel_prices_test 同手法）。
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunio/app/providers.dart';
import 'package:lunio/data/database/app_database.dart';
import 'package:lunio/data/preferences/app_preferences.dart';
import 'package:lunio/domain/entities/parking_countdown.dart';
import 'package:lunio/features/shell/fuel/fuel_prices.dart';

/// 计数偏好门面：只统计两个抽样 getter 的读次数，读写都透传真实现。
class _CountingPreferences extends LunioPreferences {
  _CountingPreferences(super.database);

  int themeModeReads = 0;
  int fuelProvinceReads = 0;

  @override
  Future<ThemeMode> getThemeMode() async {
    themeModeReads++;
    return super.getThemeMode();
  }

  @override
  Future<String> getFuelProvince() async {
    fuelProvinceReads++;
    return super.getFuelProvince();
  }
}

void main() {
  late AppDatabase database;
  late _CountingPreferences preferences;
  late ProviderContainer container;

  setUp(() {
    database = AppDatabase.inMemory();
    preferences = _CountingPreferences(database);
    container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(database),
      lunioPreferencesProvider.overrideWithValue(preferences),
    ]);
  });

  tearDown(() async {
    container.dispose();
    await database.close();
  });

  group('偏好纪元', () {
    test('bump 后 providers.dart 域的抽样 provider（主题）重查库', () async {
      await container.read(themeModePreferenceProvider.future);
      expect(preferences.themeModeReads, 1);

      container.read(preferencesEpochProvider.notifier).bump();
      await container.read(themeModePreferenceProvider.future);

      expect(preferences.themeModeReads, 2);
    });

    test('bump 后 fuel_prices.dart 域的抽样 provider（省份）重查库', () async {
      await container.read(fuelProvinceProvider.future);
      expect(preferences.fuelProvinceReads, 1);

      container.read(preferencesEpochProvider.notifier).bump();
      await container.read(fuelProvinceProvider.future);

      expect(preferences.fuelProvinceReads, 2);
    });

    test('parkingCountdownProvider 不随纪元重算（写点直失效模型，边界保持）',
        () async {
      final countdown = ParkingCountdown(
        startedAt: DateTime(2026, 9, 26, 10),
        durationSeconds: 3600,
      );
      await container
          .read(lunioPreferencesProvider)
          .saveParkingCountdown(countdown);
      final first = await container.read(parkingCountdownProvider.future);

      // 绕过动作层直接改库再 bump 纪元：停车卡片不该被偏好写入牵动，
      // 它的刷新只属于自己的写点（动作层显式 invalidate）。
      await container
          .read(lunioPreferencesProvider)
          .saveParkingCountdown(
            ParkingCountdown(
              startedAt: DateTime(2026, 9, 26, 11),
              durationSeconds: 7200,
            ),
          );
      container.read(preferencesEpochProvider.notifier).bump();
      final second = await container.read(parkingCountdownProvider.future);

      expect(second, same(first));
    });
  });
}
