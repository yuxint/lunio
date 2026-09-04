// 加油预测数据层测试：设置表（剩余油量）的 upsert/级联删除/清空、
// 车辆容积随车存取、备份往返、油价缓存与手填价偏好
// （临时数据不进备份）。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lunio/core/date/local_date.dart';
import 'package:lunio/data/backup/backup_codec.dart';
import 'package:lunio/data/database/app_database.dart';
import 'package:lunio/data/preferences/app_preferences.dart';
import 'package:lunio/data/repositories/backup_repository.dart';
import 'package:lunio/data/repositories/fuel_repository.dart';
import 'package:lunio/data/repositories/lunio_repository.dart';
import 'package:lunio/domain/entities/car.dart';
import 'package:lunio/domain/entities/maintenance_item.dart';
import 'package:lunio/domain/entities/fuel_prediction.dart';
import 'package:lunio/domain/entities/fuel_price.dart';
import 'package:lunio/domain/entities/sync_metadata.dart';

void main() {
  late AppDatabase database;
  late LunioRepository repository;
  late LunioPreferences preferences;
  late BackupRepository backupRepository;
  late FuelRepository fuelRepository;
  late SyncMetadata sync;

  setUp(() {
    database = AppDatabase.inMemory();
    preferences = LunioPreferences(database);
    backupRepository = BackupRepository(database, preferences);
    fuelRepository = FuelRepository(database, preferences);
    repository = LunioRepository(
      database,
      preferences: preferences,
      fuel: fuelRepository,
    );
    sync = SyncMetadata(status: SyncStatus.synced, updatedAt: DateTime(2026));
  });

  tearDown(() async {
    await database.close();
  });

  Future<int> seedCar({double? tankCapacityLiters}) async {
    // 建车规则要求至少一个启用项目（R26 口径），这里带一个最小项目。
    final carId = await repository.createCarWithMaintenanceItems(
      Car(
        brand: '本田',
        model: '22款思域',
        currentMileageKm: 10000,
        roadDate: const LocalDate(2023, 8, 12),
        tankCapacityLiters: tankCapacityLiters,
        sync: sync,
      ),
      [
        MaintenanceItem(
          carsId: 0,
          name: '机油',
          enabled: true,
          remindByMileage: true,
          remindByTime: false,
          mileageIntervalKm: 5000,
          timeIntervalMonths: null,
          notOverdueUpperLimit: 100,
          overdueUpperLimit: 125,
          sortOrder: 0,
          sync: sync,
        ),
      ],
    );
    return carId;
  }

  group('加油预测设置表', () {
    test('save 后 get 读回，重复 save 走更新不新增行', () async {
      final carId = await seedCar();
      await fuelRepository.saveFuelPrediction(
        FuelPrediction(carId: carId, fuelPercent: 50, sync: sync),
      );
      final saved = await fuelRepository.getFuelPredictionForCar(carId);
      expect(saved?.fuelPercent, 50);

      // 第二次保存：同车 upsert，只改字段不加行。
      await fuelRepository.saveFuelPrediction(
        FuelPrediction(carId: carId, fuelPercent: 48, sync: sync),
      );
      final updated = await fuelRepository.getFuelPredictionForCar(carId);
      expect(updated?.fuelPercent, 48);
      expect(
        await database.select(database.fuelPredictions).get(),
        hasLength(1),
      );
    });

    test('没保存过返回 null（页面按默认 50% 展示）', () async {
      final carId = await seedCar();
      expect(await fuelRepository.getFuelPredictionForCar(carId), isNull);
    });

    test('油箱容积随车存取：建车可带、编辑可改、非法值拒绝', () async {
      // 容积在 cars 表（车的属性），随 createCarWithMaintenanceItems
      // / updateCar 读写，不走 saveFuelPrediction。
      await seedCar(tankCapacityLiters: 55.1234);
      var car = (await repository.listCars()).single;
      expect(car.tankCapacityLiters, 55.1234);

      car = car.copyWith(tankCapacityLiters: 64.5, keepCapacity: false);
      await repository.updateCar(car);
      expect((await repository.listCars()).single.tankCapacityLiters, 64.5);

      await repository.updateCar(car.copyWith(keepCapacity: false));
      expect(
        (await repository.listCars()).single.tankCapacityLiters,
        isNull,
      );

      // 非法容积在建车入口就被 Repository 拒绝。
      expect(
        () => seedCar(tankCapacityLiters: 0.5),
        throwsArgumentError,
      );
      expect(
        () => seedCar(tankCapacityLiters: 55.55555),
        throwsArgumentError,
      );
    });

    test('非法油量被实体校验拒绝', () async {
      final carId = await seedCar();
      expect(
        () => fuelRepository.saveFuelPrediction(
          FuelPrediction(carId: carId, fuelPercent: 101, sync: sync),
        ),
        throwsArgumentError,
      );
    });

    test('删除车辆级联删除加油设置', () async {
      final carId = await seedCar();
      await fuelRepository.saveFuelPrediction(
        FuelPrediction(carId: carId, fuelPercent: 50),
      );
      await repository.deleteCar(carId);
      expect(
        await database.select(database.fuelPredictions).get(),
        isEmpty,
      );
    });

    test('清空数据同时清掉加油设置和油价/手填价偏好', () async {
      final carId = await seedCar();
      await fuelRepository.saveFuelPrediction(
        FuelPrediction(carId: carId, fuelPercent: 50),
      );
      await fuelRepository.saveFuelPriceCache(
        FuelPriceData(
          fetchedAt: DateTime(2026, 8, 31),
          pricesByProvince: {
            '湖北': {FuelGrade.gasoline92: 7.45},
          },
        ),
      );
      await fuelRepository.setFuelManualPrice(
        province: '湖北',
        grade: FuelGrade.gasoline92,
        pricePerLiter: 7.6,
      );
      await backupRepository.clearAllData();

      expect(
        await database.select(database.fuelPredictions).get(),
        isEmpty,
      );
      expect(await fuelRepository.getFuelPriceCache(), isNull);
      expect(await fuelRepository.getFuelManualPrices(), isEmpty);
    });
  });

  group('油价缓存与手填价偏好', () {
    test('缓存 JSON 往返（全国价表 + 调价预告）', () async {
      expect(await fuelRepository.getFuelPriceCache(), isNull);
      final data = FuelPriceData(
        fetchedAt: DateTime(2026, 8, 31, 9),
        pricesByProvince: {
          '湖北': {
            FuelGrade.gasoline92: 7.45,
            FuelGrade.diesel0: 7.12,
          },
          '广东': {FuelGrade.gasoline92: 8.10},
        },
        forecast: const FuelAdjustmentForecast(
          month: 9,
          day: 11,
          trend: FuelPriceTrend.down,
          minChangePerLiter: 0.05,
          maxChangePerLiter: 0.06,
        ),
      );
      await fuelRepository.saveFuelPriceCache(data);
      // FuelPriceData 未重写 ==，按字段比较（与备份 sync 时间戳还原一致）。
      final restored = await fuelRepository.getFuelPriceCache();
      expect(restored?.fetchedAt, data.fetchedAt);
      expect(
        restored?.priceFor(province: '湖北', grade: FuelGrade.gasoline92),
        7.45,
      );
      expect(restored?.priceFor(province: '湖北', grade: FuelGrade.diesel0), 7.12);
      expect(restored?.priceFor(province: '广东', grade: FuelGrade.gasoline92), 8.10);
      // 调价预告往返。
      expect(restored?.forecast?.month, 9);
      expect(restored?.forecast?.day, 11);
      expect(restored?.forecast?.trend, FuelPriceTrend.down);
      expect(restored?.forecast?.midChangePerLiter, closeTo(0.055, 1e-9));
    });

    test('旧版单省缓存 JSON 按损坏处理（无缓存，触发重新拉取）', () async {
      // 旧结构：province + prices 平铺，不符合当前全国价表契约。
      await preferences.writeRaw(
        'fuelPriceCache',
        '{"province":"湖北","fetchedAt":"2026-08-31T00:00:00.000","prices":{"92":7.45}}',
      );
      expect(await fuelRepository.getFuelPriceCache(), isNull);
    });

    test('缓存 JSON 损坏按无缓存处理', () async {
      await preferences.writeRaw('fuelPriceCache', '{bad json');
      expect(await fuelRepository.getFuelPriceCache(), isNull);
    });

    test('手填价按"省+油品"组合存取与清除', () async {
      expect(
        await fuelRepository.getFuelManualPrice(
          province: '湖北',
          grade: FuelGrade.gasoline92,
        ),
        isNull,
      );
      await fuelRepository.setFuelManualPrice(
        province: '湖北',
        grade: FuelGrade.gasoline92,
        pricePerLiter: 7.6,
      );
      expect(
        await fuelRepository.getFuelManualPrice(
          province: '湖北',
          grade: FuelGrade.gasoline92,
        ),
        7.6,
      );
      // 其他组合不受影响。
      expect(
        await fuelRepository.getFuelManualPrice(
          province: '湖北',
          grade: FuelGrade.gasoline95,
        ),
        isNull,
      );
      // 清除后回到无手填状态，且偏好 key 一并删除（不留空壳）。
      await fuelRepository.setFuelManualPrice(
        province: '湖北',
        grade: FuelGrade.gasoline92,
        pricePerLiter: null,
      );
      expect(
        await fuelRepository.getFuelManualPrice(
          province: '湖北',
          grade: FuelGrade.gasoline92,
        ),
        isNull,
      );
      expect(
        await preferences.readRaw('fuelManualPrices'),
        isNull,
      );
    });
  });

  group('备份', () {
    test('导出包含车辆容积与剩余油量，油价缓存与手填价不进备份', () async {
      final carId = await seedCar(tankCapacityLiters: 55);
      await fuelRepository.saveFuelPrediction(
        FuelPrediction(carId: carId, fuelPercent: 50, sync: sync),
      );
      await preferences.writeRaw('fuelProvince', '湖北');
      await preferences.writeRaw('fuelGrade', '95');
      await fuelRepository.saveFuelPriceCache(
        FuelPriceData(
          fetchedAt: DateTime(2026, 8, 31),
          pricesByProvince: {
            '湖北': {FuelGrade.gasoline92: 7.45},
          },
        ),
      );
      await fuelRepository.setFuelManualPrice(
        province: '湖北',
        grade: FuelGrade.gasoline92,
        pricePerLiter: 7.6,
      );

      final backup = await backupRepository.exportBackupPayload();
      final json = const BackupCodec().encode(backup);
      // 车带动力类型、加油设置进备份。
      expect(backup.schemaVersion, 1);
      expect(json, contains('fuelPrediction'));
      expect(json, contains('fuelPredictions'));
      expect(json, contains('湖北'));
      // 容积在车辆条目里，加油条目只剩油量。
      expect(backup.cars.single.tankCapacityLiters, 55);
      expect(backup.fuelPredictions.single.fuelPercent, 50);
      expect(json, contains('tankCapacityLiters'));
      // 临时数据不进备份：键名不出现，手填价的数值也不出现。
      // 数值判断走解码后的结构遍历，不做全文子串匹配——备份里合法的
      // ISO 时间戳（秒+毫秒如 :47.6xx）会让"7.6"子串断言偶发误报。
      expect(json, isNot(contains('fuelPriceCache')));
      expect(json, isNot(contains('fuelManualPrice')));
      bool containsNumValue(Object? node, num target) {
        if (node is num) return node == target;
        if (node is Map) return node.values.any((v) => containsNumValue(v, target));
        if (node is List) return node.any((v) => containsNumValue(v, target));
        return false;
      }

      expect(containsNumValue(jsonDecode(json), 7.6), isFalse);
    });

    test('恢复备份：加油设置按新车 id 重插并覆盖省份/油品偏好', () async {
      final carId = await seedCar(tankCapacityLiters: 55);
      await fuelRepository.saveFuelPrediction(
        FuelPrediction(carId: carId, fuelPercent: 50, sync: sync),
      );
      await preferences.writeRaw('fuelProvince', '湖北');
      await preferences.writeRaw('fuelGrade', '95');
      final backup = await backupRepository.exportBackupPayload();

      await database.close();
      database = AppDatabase.inMemory();
      // 换新连接后全部模块实例同步重建（模块无状态，但握着连接）。
      preferences = LunioPreferences(database);
      backupRepository = BackupRepository(database, preferences);
      fuelRepository = FuelRepository(database, preferences);
      repository = LunioRepository(
        database,
        preferences: preferences,
        fuel: fuelRepository,
      );
      // 恢复前预置不同省份/油品：备份应覆盖它们。
      await preferences.writeRaw('fuelProvince', '广东');
      await preferences.writeRaw('fuelGrade', '98');

      await backupRepository.restoreBackupPayload(backup);

      expect(
        await preferences.readRaw('fuelProvince'),
        '湖北',
      );
      expect(await preferences.readRaw('fuelGrade'), '95');
      // 容积随车辆条目恢复；加油条目只恢复油量。
      final restoredCar = (await database.select(database.cars).get()).single;
      expect(restoredCar.tankCapacityLiters, 55);
      final restoredFuel = await fuelRepository.getFuelPredictionForCar(
        restoredCar.id,
      );
      expect(restoredFuel?.fuelPercent, 50);
    });

    test('codec 解码：非当前版本拒绝', () {
      const codec = BackupCodec();
      expect(
        () => codec.decode(
          jsonEncode({
            'schemaVersion': 2,
            'cars': [],
            'maintenanceItems': [],
            'records': [],
          }),
        ),
        throwsUnsupportedError,
      );
    });
  });
}
