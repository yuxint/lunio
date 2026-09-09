// 记录表单费用区控制器（RecordCostFormController）的单元测试。
//
// 直接打控制器接口（不用 pump widget），锁死 ADR 0010 自动算链与
// "手改标记"的完整语义：
//  - 详细模式才跑算链：材料>0 且工时>0 → 项目费用；有项目费用 → 总费用；
//  - 手改后不再被自动覆盖；清空 = 放弃手改，恢复自动跟随；
//  - 程序写入（自动回填）不算手改——递归保护是语义的一部分；
//  - 编辑打开时存量不一致（优惠价）预置为已手改，存量一致保持自动跟随；
//  - 提交清单：全空草稿跳过、取消勾选的草稿消失、预填历史费用。
//
// 算术判定（求和/不一致）本体在 RecordRules，由 record_rules_test.dart
// 覆盖，这里只验控制器的输入态编排。
import 'package:flutter_test/flutter_test.dart';
import 'package:lunio/core/date/local_date.dart';
import 'package:lunio/domain/entities/maintenance_item.dart';
import 'package:lunio/domain/entities/maintenance_record.dart';
import 'package:lunio/domain/entities/sync_metadata.dart';
import 'package:lunio/features/shell/records/record_cost_form_controller.dart';

MaintenanceItem makeItem(int id, String name) {
  return MaintenanceItem(
    id: id,
    carsId: 1,
    name: name,
    enabled: true,
    remindByMileage: true,
    remindByTime: true,
    mileageIntervalKm: 5000,
    timeIntervalMonths: 6,
    sortOrder: 0,
    sync: SyncMetadata(
      status: SyncStatus.synced,
      updatedAt: DateTime(2026, 9, 1),
    ),
  );
}

MaintenanceRecord makeRecord({
  required List<int> itemIds,
  List<RecordItemCost> itemCosts = const [],
  required int costCents,
}) {
  return MaintenanceRecord(
    id: 100,
    carId: 1,
    date: const LocalDate(2026, 9, 1),
    itemIds: itemIds,
    itemCosts: itemCosts,
    costCents: costCents,
    mileageKm: 10000,
    sync: SyncMetadata(
      status: SyncStatus.synced,
      updatedAt: DateTime(2026, 9, 1),
    ),
  );
}

void main() {
  final items = [makeItem(1, '机油'), makeItem(2, '机滤')];

  RecordCostFormController buildController({
    MaintenanceRecord? record,
    Set<int> selected = const {1},
    bool detailMode = true,
  }) {
    return RecordCostFormController(
      record: record,
      formItems: items,
      selectedItemIds: selected,
      detailMode: detailMode,
    );
  }

  test('simple mode never runs the auto fill chain', () {
    final controller = buildController(detailMode: false);
    final draft = controller.drafts[1]!;

    draft.materialController.text = '100';
    controller.onSplitCostChanged();
    draft.laborController.text = '50';
    controller.onSplitCostChanged();

    expect(draft.costController.text, '');
    expect(controller.totalController.text, '0');
  });

  test('detail mode auto fills costs without marking touched', () {
    final controller = buildController(selected: {1});
    final draft = controller.drafts[1]!;

    // 只填材料不触发：工时缺位不算链。
    draft.materialController.text = '100';
    controller.onSplitCostChanged();
    expect(draft.costController.text, '');

    draft.laborController.text = '50';
    controller.onSplitCostChanged();

    // 项目费用 = 材料+工时，总费用 = 项目费用合计；都是程序写入，
    // 不得记成手改（下次输入仍要能继续自动跟随）。
    expect(draft.costController.text, '150.00');
    expect(controller.totalController.text, '150.00');
    expect(draft.costTouched, isFalse);
    expect(controller.totalTouched, isFalse);
  });

  test('touched cost survives edits and reports mismatch', () {
    final controller = buildController(selected: {1});
    final draft = controller.drafts[1]!;
    draft.materialController.text = '100';
    draft.laborController.text = '50';
    controller.onSplitCostChanged();

    // 手改项目费用为 120（优惠），之后改工时不再覆盖它。
    draft.costController.text = '120';
    controller.onItemCostChanged(1);
    expect(draft.costTouched, isTrue);

    draft.laborController.text = '60';
    controller.onSplitCostChanged();
    expect(draft.costController.text, '120');
    expect(controller.itemMismatch(1), isTrue);

    // 合计取项目费用权威值 120，总费用继续自动跟随。
    expect(controller.totalController.text, '120.00');

    // 手改总费用后合计变化也不再覆盖。
    controller.totalController.text = '100';
    controller.onTotalChanged();
    expect(controller.totalTouched, isTrue);
    draft.materialController.text = '80';
    controller.onSplitCostChanged();
    expect(controller.totalController.text, '100');
    expect(controller.totalMismatch, isTrue);
  });

  test('clearing a field releases touched and restores auto follow', () {
    final controller = buildController(selected: {1});
    final draft = controller.drafts[1]!;
    draft.materialController.text = '100';
    draft.laborController.text = '50';
    draft.costController.text = '120';
    controller.onItemCostChanged(1);
    controller.totalController.text = '100';
    controller.onTotalChanged();

    // 清空 = 放弃手改：项目费用恢复自动、总费用恢复跟随合计。
    draft.costController.text = '';
    controller.onItemCostChanged(1);
    controller.totalController.text = '';
    controller.onTotalChanged();
    expect(draft.costTouched, isFalse);
    expect(controller.totalTouched, isFalse);

    draft.laborController.text = '70';
    controller.onSplitCostChanged();
    expect(draft.costController.text, '170.00');
    expect(controller.totalController.text, '170.00');
  });

  test('inconsistent stored costs open as already touched (discount case)', () {
    // 存量：项目费用 120 ≠ 材料 100 + 工时 50（优惠改价），
    // 总费用 100 ≠ 合计 120。打开即视为已手改，输入不冲掉预填值。
    final record = makeRecord(
      itemIds: const [1],
      itemCosts: const [
        RecordItemCost(
          itemId: 1,
          materialCents: 10000,
          laborCents: 5000,
          costCents: 12000,
        ),
      ],
      costCents: 10000,
    );
    final controller = buildController(record: record, selected: {1});
    final draft = controller.drafts[1]!;

    expect(draft.costController.text, '120.00');
    expect(controller.totalController.text, '100.00');
    expect(draft.costTouched, isTrue);
    expect(controller.totalTouched, isTrue);
    expect(controller.itemMismatch(1), isTrue);
    expect(controller.totalMismatch, isTrue);

    draft.materialController.text = '200';
    controller.onSplitCostChanged();
    expect(draft.costController.text, '120.00');
    expect(controller.totalController.text, '100.00');
  });

  test('consistent stored costs keep following the auto fill chain', () {
    final record = makeRecord(
      itemIds: const [1],
      itemCosts: const [
        RecordItemCost(
          itemId: 1,
          materialCents: 10000,
          laborCents: 5000,
          costCents: 15000,
        ),
      ],
      costCents: 15000,
    );
    final controller = buildController(record: record, selected: {1});
    final draft = controller.drafts[1]!;

    expect(draft.costTouched, isFalse);
    expect(controller.totalTouched, isFalse);
    expect(controller.itemMismatch(1), isFalse);
    expect(controller.totalMismatch, isFalse);

    draft.materialController.text = '110';
    controller.onSplitCostChanged();
    expect(draft.costController.text, '160.00');
    expect(controller.totalController.text, '160.00');
  });

  test('buildItemCosts skips empty drafts and dropped selections', () {
    final controller = buildController(selected: {1, 2});
    expect(controller.buildItemCosts(), isEmpty);

    controller.drafts[1]!.costController.text = '99.9';
    controller.onItemCostChanged(1);
    var costs = controller.buildItemCosts();
    expect(costs.length, 1);
    expect(costs.first.itemId, 1);
    expect(costs.first.costCents, 9990);

    // 取消勾选项目 1：草稿销毁，费用从提交清单里消失。
    controller.syncSelection({2}, items);
    expect(controller.drafts.containsKey(1), isFalse);
    expect(controller.buildItemCosts(), isEmpty);
  });

  test('syncSelection prefills historical costs for newly selected items', () {
    final record = makeRecord(
      itemIds: const [1, 2],
      itemCosts: const [
        RecordItemCost(itemId: 2, costCents: 888),
      ],
      costCents: 888,
    );
    final controller = buildController(record: record, selected: {1});

    // 行内新增/补勾选后同步：项目 2 预填历史项目费用。
    controller.syncSelection({1, 2}, items);
    expect(controller.drafts[2]!.costController.text, '8.88');
  });
}
