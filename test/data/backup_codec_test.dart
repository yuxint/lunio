import 'package:flutter_test/flutter_test.dart';
import 'package:lunio/core/date/local_date.dart';
import 'package:lunio/data/backup/backup_codec.dart';
import 'package:lunio/domain/entities/car.dart';
import 'package:lunio/domain/entities/maintenance_record.dart';
import 'package:lunio/domain/entities/sync_metadata.dart';

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
          id: 'car-1',
          brand: '本田',
          model: '22款思域',
          currentMileageKm: 38600,
          roadDate: const LocalDate(2023, 8, 12),
          sync: sync,
        ),
      ],
      records: [
        MaintenanceRecord(
          id: 'record-1',
          carId: 'car-1',
          date: const LocalDate(2026, 5, 19),
          itemIds: const ['item-1'],
          costCents: 35000,
          mileageKm: 38600,
          sync: sync,
        ),
      ],
    );

    final decoded = codec.decode(codec.encode(payload));

    expect(decoded.schemaVersion, 1);
    expect(decoded.cars.single.brandModelKey, '本田::22款思域');
    expect(decoded.records.single.cycleKey, 'car-1::2026-05-19');
  });
}
