import 'package:flutter_test/flutter_test.dart';
import 'package:lunio/core/date/local_date.dart';
import 'package:lunio/domain/entities/maintenance_record.dart';
import 'package:lunio/domain/entities/sync_metadata.dart';
import 'package:lunio/domain/rules/record_rules.dart';

void main() {
  test('record item ids are deduplicated and keep first-seen order', () {
    expect(RecordRules.uniqueItemIds([1, 2, 1, 3]), [1, 2, 3]);
  });

  test('record mileage can only lift car mileage', () {
    expect(
      RecordRules.mileageAfterRecord(
        currentMileageKm: 100,
        recordMileageKm: 90,
      ),
      100,
    );
    expect(
      RecordRules.mileageAfterRecord(
        currentMileageKm: 100,
        recordMileageKm: 120,
      ),
      120,
    );
  });

  test('item cost sum only counts entries with item cost filled', () {
    expect(RecordRules.sumItemCostCents(const []), 0);
    expect(
      RecordRules.sumItemCostCents(const [
        RecordItemCost(
          itemId: 1,
          materialCents: 15000,
          laborCents: 8000,
          costCents: 23000,
        ),
        RecordItemCost(itemId: 2, costCents: 5000),
        // 没填项目费用的条目不计入合计（权威值是项目费用，ADR 0010）。
        RecordItemCost(itemId: 3, materialCents: 1000),
      ]),
      28000,
    );
  });

  test('item cost mismatch requires material and labor both positive', () {
    // 都 > 0 且项目费用 ≠ 两者之和 → 不一致（如优惠改价）。
    expect(
      RecordRules.itemCostMismatch(
        const RecordItemCost(
          itemId: 1,
          materialCents: 15000,
          laborCents: 8000,
          costCents: 20000,
        ),
      ),
      isTrue,
    );
    // 一致 → 不提示。
    expect(
      RecordRules.itemCostMismatch(
        const RecordItemCost(
          itemId: 1,
          materialCents: 15000,
          laborCents: 8000,
          costCents: 23000,
        ),
      ),
      isFalse,
    );
    // 只填一个组成部分：项目费用自由填写，不比。
    expect(
      RecordRules.itemCostMismatch(
        const RecordItemCost(itemId: 1, materialCents: 15000, costCents: 500),
      ),
      isFalse,
    );
    // 0 与未填等价（ADR 0010：都为 0 时项目费用自由填写）。
    expect(
      RecordRules.itemCostMismatch(
        const RecordItemCost(
          itemId: 1,
          materialCents: 0,
          laborCents: 8000,
          costCents: 1,
        ),
      ),
      isFalse,
    );
    // 项目费用未填不比（表单会自动算出，不会停在未填态）。
    expect(
      RecordRules.itemCostMismatch(
        const RecordItemCost(itemId: 1, materialCents: 15000, laborCents: 8000),
      ),
      isFalse,
    );
  });

  test('total cost mismatch only when item cost sum is positive', () {
    // 没有任何项目费用（含简洁模式）：总费用纯手填，不比。
    expect(
      RecordRules.totalCostMismatch(totalCostCents: 10000, itemCosts: const []),
      isFalse,
    );
    // 总费用低于合计（优惠）→ 不一致提示，但仍是合法数据。
    expect(
      RecordRules.totalCostMismatch(
        totalCostCents: 20000,
        itemCosts: const [RecordItemCost(itemId: 1, costCents: 23000)],
      ),
      isTrue,
    );
    // 总费用高于合计同样是不一致（有变动就提示）。
    expect(
      RecordRules.totalCostMismatch(
        totalCostCents: 25000,
        itemCosts: const [RecordItemCost(itemId: 1, costCents: 23000)],
      ),
      isTrue,
    );
    expect(
      RecordRules.totalCostMismatch(
        totalCostCents: 23000,
        itemCosts: const [RecordItemCost(itemId: 1, costCents: 23000)],
      ),
      isFalse,
    );
  });

  test('validate record rejects item costs outside items or negative', () {
    final sync = SyncMetadata(
      status: SyncStatus.synced,
      updatedAt: DateTime(2026),
    );
    MaintenanceRecord record(List<RecordItemCost> itemCosts) =>
        MaintenanceRecord(
          carId: 1,
          date: const LocalDate(2026, 5, 19),
          itemIds: const [1],
          itemCosts: itemCosts,
          costCents: 10000,
          mileageKm: 12000,
          sync: sync,
        );

    // itemId 不在记录的项目集合内 → 拒绝。
    expect(
      () => RecordRules.validateRecord(
        record([
          const RecordItemCost(itemId: 99, costCents: 100),
        ]),
      ),
      throwsArgumentError,
    );
    // 负数金额 → 拒绝。
    expect(
      () => RecordRules.validateRecord(
        record([
          const RecordItemCost(itemId: 1, materialCents: -1),
        ]),
      ),
      throwsArgumentError,
    );
    // 不一致（项目费用 ≠ 材料+工时）是合法数据，不拒绝（ADR 0010）。
    RecordRules.validateRecord(
      record([
        const RecordItemCost(
          itemId: 1,
          materialCents: 15000,
          laborCents: 8000,
          costCents: 20000,
        ),
      ]),
    );
  });
}
