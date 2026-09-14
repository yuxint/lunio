// 记录列表组装层：记录页的筛选口径与行视图模型（record_rows.dart）。
//
// 职责：年份提取、年份+项目双条件过滤、按项目视图的记录×项目行展开、
// FilterBar 下标映射、"选中值过滤成仍有效"的派生集合（R21）、空态分类。
// 这是记录列表"组装口径"的唯一出口，页面（records_page.dart）只持有
// 筛选选中 state 并做渲染，不再自己拼过滤/展开逻辑。
// 与提醒域的 reminder_rows.dart 同构；那边多一个 reminderRowsProvider
// 是因为有英雄卡/列表/通知侧三个消费者，本模块只有页面一个消费者，
// 纯函数即可，不设 provider。
// Java 类比：一组静态的视图组装工具（Assembler），widget 只是渲染皮；
// 空态分类 ≈ 返回 sealed 结果让调用方 switch 的状态模式。
//
// 本文件全部是纯函数与纯数据，无写库、无副作用，可直接单测。

import '../../../domain/entities/car.dart';
import '../../../domain/entities/maintenance_item.dart';
import '../../../domain/entities/maintenance_record.dart';
import '../shared/shell_shared.dart';

/// 按项目视图的一行：一条记录 × 记录里的一个项目。
/// [item] 为 null 表示项目已不存在（记录里的历史 itemIds 残留），
/// 渲染层兜底显示"未知项目"。
class RecordItemRow {
  const RecordItemRow({
    required this.record,
    required this.itemId,
    required this.item,
  });

  final MaintenanceRecord record;
  final int itemId;
  final MaintenanceItem? item;
}

/// 提取记录里出现过的年份（倒序去重），供年份筛选条做标签。
List<int> recordYears(List<MaintenanceRecord> records) {
  final years = records.map((record) => record.date.year).toSet().toList()
    ..sort((left, right) => right.compareTo(left));
  return years;
}

/// 双条件过滤（年份 + 项目，各自"空集=不过滤"）。
/// 项目条件的语义：记录里任一项目命中已选集合即保留。
List<MaintenanceRecord> filterRecords({
  required List<MaintenanceRecord> records,
  required Set<int> years,
  required Set<int> itemIds,
}) {
  return records.where((record) {
    if (years.isNotEmpty && !years.contains(record.date.year)) {
      return false;
    }
    if (itemIds.isNotEmpty &&
        !record.itemIds.any((itemId) => itemIds.contains(itemId))) {
      return false;
    }
    return true;
  }).toList();
}

/// 按项目视图行展开：记录顺序 × 每条记录 itemIds 顺序。
/// [selectedItemIds] 非空时只保留被选中的项目行（项目筛选对行生效）。
List<RecordItemRow> buildRecordItemRows({
  required List<MaintenanceRecord> records,
  required List<MaintenanceItem> items,
  required Set<int> selectedItemIds,
}) {
  final rows = <RecordItemRow>[];
  for (final record in records) {
    for (final itemId in record.itemIds) {
      if (selectedItemIds.isNotEmpty && !selectedItemIds.contains(itemId)) {
        continue;
      }
      rows.add(
        RecordItemRow(
          record: record,
          itemId: itemId,
          item: itemById(items, itemId),
        ),
      );
    }
  }
  return rows;
}

/// 把"已选值集合"映射成 FilterBar 的选中下标集合
/// （第 0 格是"全部"，没选中任何值时高亮第 0 格）。
Set<int> filterBarSelectionIndexes({
  required List<int> values,
  required Set<int> selectedValues,
}) {
  if (selectedValues.isEmpty) {
    return {0};
  }
  final indexes = <int>{};
  for (var index = 0; index < values.length; index++) {
    if (selectedValues.contains(values[index])) {
      indexes.add(index + 1);
    }
  }
  return indexes.isEmpty ? {0} : indexes;
}

/// 把 state 里的选中值过滤成"当前数据下仍有效"的视图集合（R21）：
/// 数据变化（删项目、年份消失）后仍选中的失效值只从派生集合里去掉，
/// 不回写 state。渲染与过滤都用返回值。
({Set<int> years, Set<int> itemIds}) validSelections({
  required List<MaintenanceRecord> records,
  required List<MaintenanceItem> items,
  required Set<int> selectedYears,
  required Set<int> selectedItemIds,
}) {
  final years = recordYears(records);
  final itemIds = items.map((item) => item.id).whereType<int>().toSet();
  return (
    years: selectedYears.where(years.contains).toSet(),
    itemIds: selectedItemIds.where(itemIds.contains).toSet(),
  );
}

/// 点同一个值：未选中则选中，已选中则取消（toggle）。
/// 直接改调用方持有的选中集（页面 state），不返回新集合。
void toggleSetValue(Set<int> values, int value) {
  if (!values.add(value)) {
    values.remove(value);
  }
}

/// 记录列表数据就绪后的四种形态（空态优先级单一出口）：
/// 无车 > 无任何记录 > 筛选无结果 > 有数据。
/// loading/error 不在其中——那两个态由页面对 AsyncValue 做 when 处理；
/// 空态文案是 UI 决策，留在页面（与 reminder_rows 的分类→文案分工一致）。
sealed class RecordListState {
  const RecordListState();
}

/// 当前应用车辆不存在（还没建车）。
class RecordListNoCar extends RecordListState {
  const RecordListNoCar();
}

/// 一条保养记录都没有。
class RecordListNoRecords extends RecordListState {
  const RecordListNoRecords();
}

/// 有记录但没有符合当前筛选条件的。
class RecordListFilteredEmpty extends RecordListState {
  const RecordListFilteredEmpty();
}

/// 有可展示数据：按周期视图用 [cycleRecords]（筛选后的记录），
/// 按项目视图用 [itemRows]（展开后的行）。两份都备好——视图模式是
/// UI 状态，分类不感知它。
class RecordListData extends RecordListState {
  const RecordListData({required this.cycleRecords, required this.itemRows});

  final List<MaintenanceRecord> cycleRecords;
  final List<RecordItemRow> itemRows;
}

/// 空态分类 + 行组装的唯一入口：内部先过滤记录再展开行，
/// 调用方（页面）拿结果直接渲染。
RecordListState classifyRecordListState({
  required Car? car,
  required List<MaintenanceRecord> records,
  required List<MaintenanceItem> items,
  required ({Set<int> years, Set<int> itemIds}) selections,
}) {
  if (car == null) {
    return const RecordListNoCar();
  }
  if (records.isEmpty) {
    return const RecordListNoRecords();
  }
  final filtered = filterRecords(
    records: records,
    years: selections.years,
    itemIds: selections.itemIds,
  );
  if (filtered.isEmpty) {
    return const RecordListFilteredEmpty();
  }
  return RecordListData(
    cycleRecords: filtered,
    itemRows: buildRecordItemRows(
      records: filtered,
      items: items,
      selectedItemIds: selections.itemIds,
    ),
  );
}
