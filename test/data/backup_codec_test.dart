import 'package:flutter_test/flutter_test.dart';
import 'package:lunio/core/date/local_date.dart';
import 'package:lunio/data/backup/backup_codec.dart';
import 'package:lunio/domain/entities/car.dart';
import 'package:lunio/domain/entities/maintenance_item.dart';
import 'package:lunio/domain/entities/maintenance_record.dart';
import 'package:lunio/domain/entities/sync_metadata.dart';
import 'package:lunio/domain/entities/vehicle_default_maintenance_item.dart';

void main() {
  test('schemaVersion 1 backup round-trips new data contract', () {
    final sync = SyncMetadata(
      status: SyncStatus.synced,
      updatedAt: DateTime(2026),
    );
    const codec = BackupCodec();
    final payload = BackupPayload(
      schemaVersion: 1,
      cars: [
        Car(
          id: 1,
          brand: '本田',
          model: '22款思域',
          currentMileageKm: 38600,
          roadDate: const LocalDate(2023, 8, 12),
          sync: sync,
        ),
      ],
      defaultMaintenanceItems: [
        VehicleDefaultMaintenanceItem(
          id: 1,
          vehicleBrand: '本田',
          vehicleModel: '22款思域',
          itemName: '机油',
          remindByMileage: true,
          remindByTime: true,
          mileageIntervalKm: 5000,
          timeIntervalMonths: 6,
          sortOrder: 1,
          sync: sync,
        ),
      ],
      maintenanceItems: [
        MaintenanceItem(
          id: 1,
          carsId: 1,
          name: '机油',
          isDefault: true,
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
      preferences: [
        BackupPreference(id: 1, key: 'appliedCarId', value: '1', sync: sync),
      ],
    );

    final decoded = codec.decode(codec.encode(payload));

    expect(decoded.schemaVersion, 1);
    expect(decoded.cars.single.brand, '本田');
    expect(decoded.defaultMaintenanceItems.single.itemName, '机油');
    expect(decoded.maintenanceItems.single.carsId, 1);
    expect(decoded.records.single.carId, 1);
    expect(decoded.preferences.single.value, '1');
  });
}
