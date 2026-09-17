import 'package:flutter_test/flutter_test.dart';
import 'package:lunio/core/date/local_date.dart';
import 'package:lunio/data/backup/backup_codec.dart';
import 'package:lunio/domain/entities/car.dart';
import 'package:lunio/domain/entities/fuel_record.dart';
import 'package:lunio/domain/entities/maintenance_item.dart';
import 'package:lunio/domain/entities/maintenance_record.dart';
import 'package:lunio/domain/entities/powertrain_type.dart';
import 'package:lunio/domain/entities/sync_metadata.dart';

void main() {
  test('backup round-trips full data contract', () {
    final sync = SyncMetadata(
      status: SyncStatus.synced,
      updatedAt: DateTime(2026),
    );
    const codec = BackupCodec();
    final payload = BackupPayload(
      schemaVersion: BackupCodec.currentSchemaVersion,
      cars: [
        Car(
          id: 1,
          brand: '本田',
          model: '思域',
          powertrainType: PowertrainType.fuel,
          currentMileageKm: 38600,
          roadDate: const LocalDate(2023, 8, 12),
          sync: sync,
        ),
      ],
      maintenanceItems: [
        MaintenanceItem(
          id: 1,
          carsId: 1,
          name: '机油',
          enabled: true,
          remindByMileage: true,
          remindByTime: true,
          mileageIntervalKm: 5000,
          timeIntervalMonths: 6,
          sortOrder: 1,
          sync: sync,
        ),
      ],
      records: [
        MaintenanceRecord(
          id: 1,
          carId: 1,
          date: const LocalDate(2026, 5, 19),
          itemIds: const [1],
          costCents: 35000,
          mileageKm: 38600,
          sync: sync,
        ),
      ],
    );

    final encoded = codec.encode(payload);
    final decoded = codec.decode(encoded);

    expect(encoded, isNot(contains('preferences')));
    expect(encoded, isNot(contains('defaultMaintenanceItems')));
    expect(encoded, isNot(contains('isDefault')));
    expect(decoded.schemaVersion, BackupCodec.currentSchemaVersion);
    expect(decoded.cars.single.brand, '本田');
    expect(decoded.cars.single.powertrainType, PowertrainType.fuel);
    expect(decoded.maintenanceItems.single.carsId, 1);
    expect(decoded.records.single.carId, 1);
  });

  test('backup round-trips car powertrain types', () {
    final sync = SyncMetadata(
      status: SyncStatus.synced,
      updatedAt: DateTime(2026),
    );
    const codec = BackupCodec();
    final payload = BackupPayload(
      schemaVersion: BackupCodec.currentSchemaVersion,
      cars: [
        Car(
          id: 1,
          brand: '比亚迪',
          model: '汉EV',
          powertrainType: PowertrainType.electric,
          currentMileageKm: 10000,
          roadDate: const LocalDate(2024, 1, 1),
          sync: sync,
        ),
        Car(
          id: 2,
          brand: 'AITO问界',
          model: '问界M9',
          powertrainType: PowertrainType.extendedRange,
          currentMileageKm: 8000,
          roadDate: const LocalDate(2025, 1, 1),
          sync: sync,
        ),
      ],
    );

    final encoded = codec.encode(payload);
    expect(encoded, contains('"powertrainType":"ev"'));
    expect(encoded, contains('"powertrainType":"extended"'));

    final decoded = codec.decode(encoded);
    expect(decoded.schemaVersion, BackupCodec.currentSchemaVersion);
    expect(decoded.cars.first.powertrainType, PowertrainType.electric);
    expect(
      decoded.cars.last.powertrainType,
      PowertrainType.extendedRange,
    );

    // 备份里出现未知动力类型值：fail-fast 拒绝（不静默降级）。
    final badJson = encoded.replaceFirst('"powertrainType":"ev"', '"powertrainType":"nuclear"');
    expect(() => codec.decode(badJson), throwsArgumentError);

    // v1/v2 之外的版本号直接拒绝（ADR 0005：不做版本分支兼容；
    // ADR 0010：v1 是唯一例外，纯增量缺失按空读入）。
    final v99Json = encoded.replaceFirst(
      '"schemaVersion":${BackupCodec.currentSchemaVersion}',
      '"schemaVersion":99',
    );
    expect(() => codec.decode(v99Json), throwsUnsupportedError);
  });

  test('backup round-trips item costs and accepts v1 files', () {
    final sync = SyncMetadata(
      status: SyncStatus.synced,
      updatedAt: DateTime(2026),
    );
    const codec = BackupCodec();
    final payload = BackupPayload(
      schemaVersion: BackupCodec.currentSchemaVersion,
      cars: [
        Car(
          id: 1,
          brand: '本田',
          model: '思域',
          powertrainType: PowertrainType.fuel,
          currentMileageKm: 38600,
          roadDate: const LocalDate(2023, 8, 12),
          sync: sync,
        ),
      ],
      maintenanceItems: [
        MaintenanceItem(
          id: 1,
          carsId: 1,
          name: '机油',
          enabled: true,
          remindByMileage: true,
          remindByTime: true,
          mileageIntervalKm: 5000,
          timeIntervalMonths: 6,
          sortOrder: 1,
          sync: sync,
        ),
        MaintenanceItem(
          id: 2,
          carsId: 1,
          name: '机滤',
          enabled: true,
          remindByMileage: true,
          remindByTime: true,
          mileageIntervalKm: 5000,
          timeIntervalMonths: 6,
          sortOrder: 2,
          sync: sync,
        ),
      ],
      records: [
        MaintenanceRecord(
          id: 1,
          carId: 1,
          date: const LocalDate(2026, 5, 19),
          itemIds: const [1, 2],
          // 项目费用 23000 + 5000 = 28000 与总费用一致；机滤只填项目费用。
          itemCosts: const [
            RecordItemCost(
              itemId: 1,
              materialCents: 15000,
              laborCents: 8000,
              costCents: 23000,
            ),
            RecordItemCost(itemId: 2, costCents: 5000),
          ],
          costCents: 28000,
          mileageKm: 38600,
          sync: sync,
        ),
      ],
    );

    final encoded = codec.encode(payload);
    expect(encoded, contains('"itemCosts"'));

    final decoded = codec.decode(encoded);
    final decodedCosts = decoded.records.single.itemCosts;
    expect(decodedCosts, hasLength(2));
    expect(decodedCosts.first.materialCents, 15000);
    expect(decodedCosts.first.laborCents, 8000);
    expect(decodedCosts.first.costCents, 23000);
    expect(decodedCosts.last.costCents, 5000);
    expect(decodedCosts.last.laborCents, isNull);

    // v1 备份（没有 itemCosts / fuelRecords 字段）可以导入：项目费用按
    // 全空读入（ADR 0010 的纯增量兼容，v1 文件的语义就是"费用未填"），
    // 加油记录按空读入（剥字段构造真实 v1 形态）。
    final v1Json = encoded
        .replaceFirst(
          '"schemaVersion":${BackupCodec.currentSchemaVersion}',
          '"schemaVersion":1',
        )
        .replaceAll(RegExp(r'"itemCosts":\[[^\]]*\],'), '')
        .replaceFirst(RegExp(r',"fuelRecords":\[[^\]]*\]'), '');
    final v1 = codec.decode(v1Json);
    expect(v1.schemaVersion, 1);
    expect(v1.records.single.itemIds, [1, 2]);
    expect(v1.records.single.itemCosts, isEmpty);
    expect(v1.records.single.costCents, 28000);
    expect(v1.fuelRecords, isEmpty);
  });

  test('backup round-trips fuel records and reads v2 files without them', () {
    final sync = SyncMetadata(
      status: SyncStatus.synced,
      updatedAt: DateTime(2026),
    );
    const codec = BackupCodec();
    final payload = BackupPayload(
      schemaVersion: BackupCodec.currentSchemaVersion,
      cars: [
        Car(
          id: 1,
          brand: '本田',
          model: '思域',
          powertrainType: PowertrainType.fuel,
          currentMileageKm: 12100,
          roadDate: const LocalDate(2023, 8, 12),
          sync: sync,
        ),
      ],
      fuelRecords: [
        FuelRecord(
          carId: 1,
          date: const LocalDate(2026, 9, 10),
          mileageKm: 12100,
          volumeLiters: 41.5,
          totalCostCents: 31200,
          fullTank: false,
          sync: sync,
        ),
      ],
    );

    final encoded = codec.encode(payload);
    expect(encoded, contains('"fuelRecords"'));
    // 条目不带 id：行 id 恢复时重新生成雪花，备份里无人引用
    // （与 fuelPredictions 同先例，ADR 0014）。
    expect(encoded, isNot(contains('"fuelRecords":[{"id"')));

    final decoded = codec.decode(encoded);
    expect(decoded.fuelRecords, hasLength(1));
    final record = decoded.fuelRecords.single;
    expect(record.carId, 1);
    expect(record.date, const LocalDate(2026, 9, 10));
    expect(record.mileageKm, 12100);
    expect(record.volumeLiters, 41.5);
    expect(record.totalCostCents, 31200);
    expect(record.fullTank, isFalse);

    // v2 备份（没有 fuelRecords 字段）可以导入：加油记录按空读入
    // （ADR 0014 的纯增量兼容，沿用 ADR 0010 的 itemCosts 先例）。
    // fuelRecords 是契约的最后一个字段，剥字段时连前导逗号一起剥。
    final v2Json = encoded
        .replaceFirst(
          '"schemaVersion":${BackupCodec.currentSchemaVersion}',
          '"schemaVersion":2',
        )
        .replaceFirst(RegExp(r',"fuelRecords":\[[^\]]*\]'), '');
    final v2 = codec.decode(v2Json);
    expect(v2.schemaVersion, 2);
    expect(v2.fuelRecords, isEmpty);
    expect(v2.cars.single.brand, '本田');

    // 篡改出非法加油数据（0 升）：实体构造即校验，解码直接拒绝，
    // 非法数据不会静默进入恢复路径。
    final badVolumeJson = encoded.replaceFirst(
      '"volumeLiters":41.5',
      '"volumeLiters":0',
    );
    expect(() => codec.decode(badVolumeJson), throwsArgumentError);
  });
}
