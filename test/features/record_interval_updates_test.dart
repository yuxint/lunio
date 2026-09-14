// 记录表单第二步「间隔确认」收编模块（record_interval_updates.dart）
// 的单元测试。
//
// 直接打纯函数接口（不用 pump widget），锁死间隔链的完整语义：
//  - 草稿预填：开启轴预填存量间隔，存量 null 用缺省 5000km / 1 个月，
//    未开启轴留空；
//  - 正整数校验：开启轴为空/0/负数/非数字 → 带项目名的中文错误文案；
//    未开启轴不校验（存量 null 也放行）；
//  - 「间隔没变不产生 update」：全部没改 → 清单为空、无错误；
//  - 有变化 → 按原字段重建 pendingUpdate 实体（业务字段与注入的 now
//    逐一锁定，防止重建时静默丢字段）；
//  - 多项目：首个非法值报对应项目，合法且有变化的按草稿顺序生成。
//
// 正整数规则本体在 MaintenanceRules.validateIntervals，由
// maintenance_rules_test.dart 覆盖；这里只验输入→实体的转换编排。
import 'package:flutter_test/flutter_test.dart';
import 'package:lunio/domain/entities/maintenance_item.dart';
import 'package:lunio/domain/entities/sync_metadata.dart';
import 'package:lunio/features/shell/records/record_interval_updates.dart';

MaintenanceItem makeItem(
  int id,
  String name, {
  bool byMileage = true,
  bool byTime = true,
  int? mileageIntervalKm = 5000,
  int? timeIntervalMonths = 6,
}) {
  return MaintenanceItem(
    id: id,
    carsId: 1,
    name: name,
    enabled: true,
    remindByMileage: byMileage,
    remindByTime: byTime,
    mileageIntervalKm: mileageIntervalKm,
    timeIntervalMonths: timeIntervalMonths,
    notOverdueUpperLimit: 100,
    overdueUpperLimit: 125,
    sortOrder: 7,
    sync: SyncMetadata(
      status: SyncStatus.synced,
      updatedAt: DateTime(2026, 9, 1),
    ),
  );
}

void main() {
  final now = DateTime(2026, 9, 14, 8, 30);

  test('draft prefills stored intervals; null falls back to defaults', () {
    final draft = RecordIntervalDraft(item: makeItem(1, '机油'));
    expect(draft.mileageController.text, '5000');
    expect(draft.monthsController.text, '6');

    final sparse = RecordIntervalDraft(
      item: makeItem(
        2,
        '机滤',
        mileageIntervalKm: null,
        timeIntervalMonths: null,
      ),
    );
    expect(sparse.mileageController.text, '5000');
    expect(sparse.monthsController.text, '1');
  });

  test('disabled axes leave controllers empty and stay out of the chain', () {
    final draft = RecordIntervalDraft(
      item: makeItem(1, '机油', byMileage: false, byTime: false),
    );
    expect(draft.mileageController.text, '');
    expect(draft.monthsController.text, '');

    // 未开启轴沿用存量值 → 两轴都无变化 → 无错误、清单为空。
    final result = buildItemUpdates(drafts: [draft], now: now);
    expect(result.errorText, isNull);
    expect(result.updates, isEmpty);
  });

  test('empty mileage interval reports with item name prefix', () {
    final draft = RecordIntervalDraft(item: makeItem(1, '机油'));
    draft.mileageController.text = '';
    final result = buildItemUpdates(drafts: [draft], now: now);
    expect(result.errorText, '机油 的里程间隔必须填写正整数');
    expect(result.updates, isEmpty);
  });

  test('zero / negative / non-numeric time intervals are rejected', () {
    for (final text in ['0', '-3', 'abc']) {
      final draft = RecordIntervalDraft(item: makeItem(1, '机油'));
      draft.monthsController.text = text;
      final result = buildItemUpdates(drafts: [draft], now: now);
      expect(
        result.errorText,
        '机油 的时间间隔必须填写正整数',
        reason: 'text=$text',
      );
      expect(result.updates, isEmpty);
    }
  });

  test('disabled axis with null stored value is not validated', () {
    final draft = RecordIntervalDraft(
      item: makeItem(1, '机油', byTime: false, timeIntervalMonths: null),
    );
    // 里程轴没动（与存量一致），时间轴未开启且存量 null → 不校验、无 update。
    final result = buildItemUpdates(drafts: [draft], now: now);
    expect(result.errorText, isNull);
    expect(result.updates, isEmpty);
  });

  test('unchanged intervals produce no updates', () {
    // 「间隔没变不产生 update」是收编前只能靠整页 widget 测试间接路过的
    // 规则，这里从接口直接断言。
    final draft = RecordIntervalDraft(item: makeItem(1, '机油'));
    final result = buildItemUpdates(drafts: [draft], now: now);
    expect(result.errorText, isNull);
    expect(result.updates, isEmpty);
  });

  test('changed intervals rebuild the entity with every field locked', () {
    final draft = RecordIntervalDraft(item: makeItem(1, '机油'));
    draft.mileageController.text = '8000';
    draft.monthsController.text = '12';
    final result = buildItemUpdates(drafts: [draft], now: now);
    expect(result.errorText, isNull);
    expect(result.updates, hasLength(1));
    final update = result.updates.single;
    expect(update.id, 1);
    expect(update.carsId, 1);
    expect(update.name, '机油');
    expect(update.enabled, isTrue);
    expect(update.remindByMileage, isTrue);
    expect(update.remindByTime, isTrue);
    expect(update.mileageIntervalKm, 8000);
    expect(update.timeIntervalMonths, 12);
    expect(update.notOverdueUpperLimit, 100);
    expect(update.overdueUpperLimit, 125);
    expect(update.sortOrder, 7);
    expect(update.sync.status, SyncStatus.pendingUpdate);
    expect(update.sync.updatedAt, now);
  });

  test('disabled axis is rebuilt as null even when stored value differs', () {
    // 存量规律是"未开启轴为 null"，但历史脏数据可能带值：重建按开关
    // 口径强制置 null（与收编前行为一致）。
    final draft = RecordIntervalDraft(
      item: makeItem(1, '机油', byMileage: false, mileageIntervalKm: 3000),
    );
    draft.monthsController.text = '9'; // 时间轴改动触发 update
    final result = buildItemUpdates(drafts: [draft], now: now);
    expect(result.errorText, isNull);
    expect(result.updates, hasLength(1));
    expect(result.updates.single.timeIntervalMonths, 9);
    expect(result.updates.single.mileageIntervalKm, isNull);
  });

  test('first invalid draft wins; valid changed drafts still generate', () {
    final oil = RecordIntervalDraft(item: makeItem(1, '机油'));
    oil.mileageController.text = '8000';
    final filter = RecordIntervalDraft(item: makeItem(2, '机滤'));
    filter.monthsController.text = '0';
    final result = buildItemUpdates(drafts: [oil, filter], now: now);
    expect(result.errorText, '机滤 的时间间隔必须填写正整数');
    expect(result.updates, isEmpty);

    // 修好机滤后：机油（有变化）进清单，机滤（没改）跳过，保持草稿顺序。
    filter.monthsController.text = '6';
    final fixed = buildItemUpdates(drafts: [oil, filter], now: now);
    expect(fixed.errorText, isNull);
    expect(fixed.updates.map((update) => update.name), ['机油']);
  });
}
