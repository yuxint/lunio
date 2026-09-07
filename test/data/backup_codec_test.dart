import 'package:flutter_test/flutter_test.dart';
import 'package:lunio/core/date/local_date.dart';
import 'package:lunio/data/backup/backup_codec.dart';
import 'package:lunio/domain/entities/car.dart';
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

    // v1 备份（没有 itemCosts 字段）可以导入：项目费用按全空读入
    // （ADR 0010 的纯增量兼容，v1 文件的语义就是"费用未填"）。
    final v1Json = encoded
        .replaceFirst('"schemaVersion":2', '"schemaVersion":1')
        .replaceAll(RegExp(r'"itemCosts":\[[^\]]*\],'), '');
    final v1 = codec.decode(v1Json);
    expect(v1.schemaVersion, 1);
    expect(v1.records.single.itemIds, [1, 2]);
    expect(v1.records.single.itemCosts, isEmpty);
    expect(v1.records.single.costCents, 28000);
  });
}
