// record_rows.dart 的纯函数单测：年份提取、双条件过滤、按项目行展开、
// FilterBar 下标映射、R21 有效集、空态分类优先级。
// 不打 widget、不连数据库——直接构造实体。列表组装口径此前只有 widget
// 测试间接覆盖，这是它的第一个直接测试面。

import 'package:flutter_test/flutter_test.dart';
import 'package:lunio/core/date/local_date.dart';
import 'package:lunio/domain/entities/car.dart';
import 'package:lunio/domain/entities/maintenance_item.dart';
import 'package:lunio/domain/entities/maintenance_record.dart';
import 'package:lunio/domain/entities/sync_metadata.dart';
import 'package:lunio/features/shell/records/record_rows.dart';

final _sync = SyncMetadata(
  status: SyncStatus.synced,
  updatedAt: DateTime(2026, 1, 1),
);

Car _car() => Car(
  id: 1,
  brand: '丰田',
  model: '卡罗拉',
  currentMileageKm: 20000,
  roadDate: const LocalDate(2025, 1, 1),
  sync: _sync,
);

MaintenanceItem _item({required int id, required String name}) =>
    MaintenanceItem(
      id: id,
      carsId: 1,
      name: name,
      enabled: true,
      remindByMileage: false,
      remindByTime: true,
      timeIntervalMonths: 6,
      sortOrder: id,
      sync: _sync,
    );

MaintenanceRecord _record({
  required LocalDate date,
  required List<int> itemIds,
}) => MaintenanceRecord(
  carId: 1,
  date: date,
  itemIds: itemIds,
  costCents: 0,
  mileageKm: 10000,
  sync: _sync,
);

void main() {
  group('recordYears 年份提取', () {
    test('去重 + 倒序', () {
      final years = recordYears([
        _record(date: const LocalDate(2025, 3, 1), itemIds: [1]),
        _record(date: const LocalDate(2026, 1, 10), itemIds: [1]),
        _record(date: const LocalDate(2026, 8, 2), itemIds: [1]),
        _record(date: const LocalDate(2024, 12, 31), itemIds: [1]),
      ]);
      expect(years, [2026, 2025, 2024]);
    });

    test('无记录 → 空列表', () {
      expect(recordYears(const []), isEmpty);
    });
  });

  group('filterRecords 双条件过滤', () {
    final records = [
      _record(date: const LocalDate(2025, 3, 1), itemIds: [1, 2]),
      _record(date: const LocalDate(2026, 1, 10), itemIds: [2]),
      _record(date: const LocalDate(2026, 8, 2), itemIds: [3]),
    ];

    test('空集=不过滤：两个条件都空 → 全保留', () {
      expect(
        filterRecords(records: records, years: const {}, itemIds: const {}),
        records,
      );
    });

    test('年份与项目同时生效（AND）', () {
      final filtered = filterRecords(
        records: records,
        years: {2026},
        itemIds: {2},
      );
      // 2026 年且含项目 2 的只有第二条。
      expect(filtered, [records[1]]);
    });

    test('项目条件：记录里任一项目命中即保留', () {
      final filtered = filterRecords(
        records: records,
        years: const {},
        itemIds: {1},
      );
      expect(filtered, [records[0]]);
    });

    test('无命中 → 空', () {
      expect(
        filterRecords(records: records, years: {2024}, itemIds: const {}),
        isEmpty,
      );
    });
  });

  group('buildRecordItemRows 行展开', () {
    final items = [_item(id: 1, name: '机油'), _item(id: 2, name: '机滤')];

    test('顺序 = 记录顺序 × record.itemIds 顺序，item 按 id 取到', () {
      final r1 = _record(date: const LocalDate(2026, 1, 10), itemIds: [2, 1]);
      final r2 = _record(date: const LocalDate(2026, 8, 2), itemIds: [1]);
      final rows = buildRecordItemRows(
        records: [r1, r2],
        items: items,
        selectedItemIds: const {},
      );
      expect(rows.map((row) => row.itemId).toList(), [2, 1, 1]);
      expect(rows[0].record, r1);
      expect(rows[0].item?.name, '机滤');
      expect(rows[1].item?.name, '机油');
    });

    test('项目选中集非空时只保留命中的行', () {
      final rows = buildRecordItemRows(
        records: [
          _record(date: const LocalDate(2026, 1, 10), itemIds: [2, 1]),
        ],
        items: items,
        selectedItemIds: {1},
      );
      expect(rows.map((row) => row.itemId).toList(), [1]);
    });

    test('记录里的残留 itemIds 找不到项目 → item 为 null', () {
      final rows = buildRecordItemRows(
        records: [
          _record(date: const LocalDate(2026, 1, 10), itemIds: [99]),
        ],
        items: items,
        selectedItemIds: const {},
      );
      expect(rows.single.item, isNull);
      expect(rows.single.itemId, 99);
    });
  });

  group('filterBarSelectionIndexes 下标映射', () {
    test('未选中任何值 → 高亮第 0 格（全部）', () {
      expect(
        filterBarSelectionIndexes(
          values: [2025, 2026],
          selectedValues: const {},
        ),
        {0},
      );
    });

    test('选中值映射到 +1 下标', () {
      expect(
        filterBarSelectionIndexes(
          values: [2025, 2026],
          selectedValues: {2025, 2026},
        ),
        {1, 2},
      );
    });

    test('选中值全部失效 → 回落第 0 格', () {
      expect(
        filterBarSelectionIndexes(
          values: [2025, 2026],
          selectedValues: {1999},
        ),
        {0},
      );
    });
  });

  group('validSelections R21 有效集', () {
    test('state 里失效的年份/项目被过滤，不回写 state', () {
      final selections = validSelections(
        records: [
          _record(date: const LocalDate(2026, 1, 10), itemIds: [1]),
        ],
        items: [_item(id: 1, name: '机油')],
        selectedYears: {2026, 1999},
        selectedItemIds: {1, 99},
      );
      expect(selections.years, {2026});
      expect(selections.itemIds, {1});
    });
  });

  group('toggleSetValue toggle', () {
    test('未选中 → 加入；已选中 → 移除', () {
      final values = <int>{1};
      toggleSetValue(values, 2);
      expect(values, {1, 2});
      toggleSetValue(values, 2);
      expect(values, {1});
    });
  });

  group('classifyRecordListState 空态分类', () {
    final items = [_item(id: 1, name: '机油')];
    final records = [
      _record(date: const LocalDate(2026, 1, 10), itemIds: [1]),
    ];
    final none = (
      years: const <int>{},
      itemIds: const <int>{},
    );

    test('优先级：无车 > 无记录 > 筛选无结果 > 有数据', () {
      expect(
        classifyRecordListState(
          car: null,
          records: records,
          items: items,
          selections: none,
        ),
        isA<RecordListNoCar>(),
      );
      expect(
        classifyRecordListState(
          car: _car(),
          records: const [],
          items: items,
          selections: none,
        ),
        isA<RecordListNoRecords>(),
      );
      // 年份选一个不存在的 → 筛选无结果（优先于有数据）。
      expect(
        classifyRecordListState(
          car: _car(),
          records: records,
          items: items,
          selections: (years: {1999}, itemIds: const <int>{}),
        ),
        isA<RecordListFilteredEmpty>(),
      );
      final data = classifyRecordListState(
        car: _car(),
        records: records,
        items: items,
        selections: none,
      );
      expect(data, isA<RecordListData>());
    });

    test('有数据：两视图各自组装，记录顺序保持', () {
      final r1 = _record(date: const LocalDate(2026, 1, 10), itemIds: [1]);
      final r2 = _record(date: const LocalDate(2026, 8, 2), itemIds: [1]);
      final data =
          classifyRecordListState(
                car: _car(),
                records: [r1, r2],
                items: items,
                selections: none,
              )
              as RecordListData;
      expect(data.cycleRecords, [r1, r2]);
      expect(data.itemRows.map((row) => row.record).toList(), [r1, r2]);
    });
  });
}
