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

    // 其他版本号直接拒绝（ADR 0005：不做旧版本兼容）。
    final v2Json = encoded.replaceFirst(
      '"schemaVersion":${BackupCodec.currentSchemaVersion}',
      '"schemaVersion":2',
    );
    expect(() => codec.decode(v2Json), throwsUnsupportedError);
  });
}
