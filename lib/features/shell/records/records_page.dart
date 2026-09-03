// 记录页（/records）：保养记录的列表、筛选、两步表单和删除。
//
// 页面结构（CustomScrollView + slivers，R25）：
//   1. 模式切换（按周期/按项目）+ 两条 FilterBar（年份多选 + 项目多选，
//      第一格"全部"= 清空筛选）——固定头部 sliver；
//   2. 记录列表：SliverList.builder 懒加载（每项 ValueKey）；
//      按周期 = 每条记录一张卡；按项目 = 记录×项目展开成行；
//   3. 卡片上的编辑/删除按钮。
//
// 新增/编辑表单是两步流：第一步填日期/里程/费用/备注/选项目（可行内
// 新增项目并自动勾选）→ 第二步确认所选项目的提醒间隔（可改，保存时
// 一并更新项目）。入口在提醒页按钮和记录卡"编辑"。
// ignore_for_file: use_key_in_widget_constructors, library_private_types_in_public_api

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/date/local_date.dart';
import '../../../core/theme/lunio_tokens.dart';
import '../../../core/widgets/lunio_components.dart';
import '../../../domain/entities/car.dart';
import '../../../domain/entities/maintenance_item.dart';
import '../../../domain/entities/maintenance_record.dart';
import '../../../domain/entities/sync_metadata.dart';
import '../profile/maintenance_items.dart';
import '../shared/shell_shared.dart';

/// 记录页主组件。
class RecordsPreviewPage extends ConsumerStatefulWidget {
  const RecordsPreviewPage();

  @override
  ConsumerState<RecordsPreviewPage> createState() => RecordsPreviewPageState();
}

class RecordsPreviewPageState extends ConsumerState<RecordsPreviewPage> {
  /// 0 = 按周期视图，1 = 按项目视图。
  int selectedMode = 0;

  /// 年份/项目筛选的已选集合（空 = 全部）。
  /// 只由用户点击变更；数据变化导致的"失效选中"在 build 里用派生集合
  /// 过滤（validSelectedXxx），不再回写 state（R21）。
  final selectedYears = <int>{};
  final selectedItemIds = <int>{};

  /// build：watch 数据 → 标题栏/筛选条为固定头部 sliver，记录列表用
  /// SliverList.builder 懒加载（R25；长列表只构建可视区，每项带
  /// ValueKey 便于 diff）。
  @override
  Widget build(BuildContext context) {
    final car = ref
        .watch(appliedCarProvider)
        .maybeWhen(data: (value) => value, orElse: () => null);
    final records = ref.watch(appliedCarRecordsProvider);
    final items = ref
        .watch(appliedCarMaintenanceItemsProvider)
        .maybeWhen(
          data: (value) => value,
          orElse: () => const <MaintenanceItem>[],
        );
    // 三页统一 loading/error 形态（§5.2）：与提醒页同构，
    // 记录 provider 就绪前整页占位。
    return records.when(
      loading: () => const LoadingPage(title: '保养记录'),
      error: (error, stackTrace) => ErrorPage(title: '保养记录', error: error),
      data: (value) => LunioPage.slivers(
        title: '保养记录',
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LunioSegmentedControl(
                  values: const ['按周期', '按项目'],
                  selectedIndex: selectedMode,
                  onSelected: (index) => setState(() => selectedMode = index),
                ),
                const SizedBox(height: 14),
                _buildFilterBars(value, items),
                const SizedBox(height: 14),
              ],
            ),
          ),
          _buildRecordListSliver(car, value, items),
        ],
      ),
    );
  }

  /// 派生集合：把 state 里的选中值过滤成"当前数据下仍有效"的视图集合，
  /// 渲染与过滤都用它，不改 state（R21）。
  ({Set<int> years, Set<int> itemIds}) _validSelections(
    List<MaintenanceRecord> records,
    List<MaintenanceItem> items,
  ) {
    final years = _recordYears(records);
    final itemIds = items.map((item) => item.id).whereType<int>().toSet();
    return (
      years: selectedYears.where(years.contains).toSet(),
      itemIds: selectedItemIds.where(itemIds.contains).toSet(),
    );
  }

  /// 两条筛选条（年份多选 + 项目多选，第一格"全部"= 清空筛选）。
  Widget _buildFilterBars(
    List<MaintenanceRecord> records,
    List<MaintenanceItem> items,
  ) {
    final years = _recordYears(records);
    final selections = _validSelections(records, items);
    final itemIds = items.map((item) => item.id).whereType<int>().toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FilterBar(
          labels: ['全部年份', for (final year in years) '$year年'],
          selectedIndexes: _selectedFilterIndexes(
            values: years,
            selectedValues: selections.years,
          ),
          onSelected: (index) => setState(() {
            if (index == 0) {
              selectedYears.clear();
              return;
            }
            _toggleSelection(selectedYears, years[index - 1]);
          }),
        ),
        const SizedBox(height: 8),
        _FilterBar(
          labels: ['全部项目', for (final item in items) item.name],
          selectedIndexes: _selectedFilterIndexes(
            values: itemIds,
            selectedValues: selections.itemIds,
          ),
          onSelected: (index) => setState(() {
            if (index == 0) {
              selectedItemIds.clear();
              return;
            }
            final itemId = items[index - 1].id;
            if (itemId != null) {
              _toggleSelection(selectedItemIds, itemId);
            }
          }),
        ),
      ],
    );
  }

  /// 记录列表区：空态/过滤空态是固定卡片，正常态按当前模式返回
  /// SliverList.builder（每项 ValueKey('record-记录id')，R25）。
  Widget _buildRecordListSliver(
    Car? car,
    List<MaintenanceRecord> records,
    List<MaintenanceItem> items,
  ) {
    if (car == null) {
      return const SliverToBoxAdapter(child: LunioCard(child: Text('请先新增车辆')));
    }
    if (records.isEmpty) {
      return const SliverToBoxAdapter(
        child: LunioCard(child: Text('暂无保养记录，可在提醒页点「新增保养记录」。')),
      );
    }
    final selections = _validSelections(records, items);
    final filteredRecords = _filterRecords(
      records: records,
      years: selections.years,
      itemIds: selections.itemIds,
    );
    if (filteredRecords.isEmpty) {
      return const SliverToBoxAdapter(
        child: LunioCard(child: Text('没有符合筛选条件的记录')),
      );
    }
    if (selectedMode == 0) {
      return SliverList.builder(
        itemCount: filteredRecords.length,
        itemBuilder: (context, index) {
          final record = filteredRecords[index];
          return Padding(
            key: ValueKey('record-${record.id}'),
            padding: EdgeInsets.only(
              bottom: index == filteredRecords.length - 1 ? 0 : 12,
            ),
            child: RecordCycleCard(
              record: record,
              items: items,
              onEdit: (record) =>
                  showMaintenanceRecordFormSheet(context, ref, record: record),
              onDelete: (record) =>
                  deleteMaintenanceRecord(context, ref, record),
            ),
          );
        },
      );
    }
    return _buildItemRowsSliver(filteredRecords, items, selections.itemIds);
  }

  /// 按项目视图：记录×项目展开成行，同样走 SliverList.builder。
  Widget _buildItemRowsSliver(
    List<MaintenanceRecord> records,
    List<MaintenanceItem> items,
    Set<int> validSelectedItemIds,
  ) {
    final rows =
        <({MaintenanceRecord record, int itemId, MaintenanceItem? item})>[];
    for (final record in records) {
      for (final itemId in record.itemIds) {
        if (validSelectedItemIds.isNotEmpty &&
            !validSelectedItemIds.contains(itemId)) {
          continue;
        }
        rows.add((
          record: record,
          itemId: itemId,
          item: itemById(items, itemId),
        ));
      }
    }
    if (rows.isEmpty) {
      return const SliverToBoxAdapter(
        child: LunioCard(child: Text('没有符合筛选条件的记录')),
      );
    }
    return SliverList.builder(
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final row = rows[index];
        return Padding(
          key: ValueKey('record-${row.record.id}-item-${row.itemId}'),
          padding: EdgeInsets.only(bottom: index == rows.length - 1 ? 0 : 12),
          child: RecordItemRowCard(
            record: row.record,
            itemId: row.itemId,
            item: row.item,
            onEdit: (record, itemId) =>
                showMaintenanceRecordFormSheet(context, ref, record: record),
            onDelete: (record, itemId) =>
                deleteMaintenanceRecordItem(context, ref, record, itemId),
          ),
        );
      },
    );
  }
}

/// 按周期视图的单张记录卡（日期+金额 / 里程+备注 / 项目 pills /
/// 编辑+删除）。由页面的 SliverList.builder 逐条构建（R24/R25 后不再
/// 有列表容器组件，行距由 builder 的 Padding 控制）。
class RecordCycleCard extends StatelessWidget {
  const RecordCycleCard({
    required this.record,
    required this.items,
    required this.onEdit,
    required this.onDelete,
  });

  final MaintenanceRecord record;
  final List<MaintenanceItem> items;
  final ValueChanged<MaintenanceRecord> onEdit;
  final ValueChanged<MaintenanceRecord> onDelete;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    return LunioCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                record.date.toString(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Spacer(),
              const SizedBox(width: 10),
              Text(
                _formatMoney(record.costCents),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: tokens.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Text(
                      '${formatNumber(record.mileageKm)} km',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if ((record.note ?? '').trim().isNotEmpty) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          record.note!.trim(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SmallActionButton(
                    label: '编辑',
                    onPressed: () => onEdit(record),
                  ),
                  const SizedBox(width: 8),
                  SmallActionButton(
                    label: '删除',
                    danger: true,
                    onPressed: () => onDelete(record),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          ItemPills(labels: recordItemNameList(record, items)),
        ],
      ),
    );
  }
}

/// 按项目视图的单行卡（记录×项目展开后一行一个项目，可单独删该项）。
/// 编辑按钮打开整条记录的表单，删除只删该记录里的这个项目。
class RecordItemRowCard extends StatelessWidget {
  const RecordItemRowCard({
    required this.record,
    required this.itemId,
    required this.item,
    required this.onEdit,
    required this.onDelete,
  });

  final MaintenanceRecord record;
  final int itemId;
  final MaintenanceItem? item;
  final void Function(MaintenanceRecord record, int itemId) onEdit;
  final void Function(MaintenanceRecord record, int itemId) onDelete;

  @override
  Widget build(BuildContext context) {
    return LunioCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item?.name ?? '未知项目',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${record.date} · ${formatNumber(record.mileageKm)} km',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const SizedBox(width: 10),
              SmallActionButton(
                label: '编辑',
                onPressed: () => onEdit(record, itemId),
              ),
              const SizedBox(width: 8),
              SmallActionButton(
                label: '删除',
                danger: true,
                onPressed: () => onDelete(record, itemId),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 提取记录里出现过的年份（倒序去重）。
List<int> _recordYears(List<MaintenanceRecord> records) {
  final years = records.map((record) => record.date.year).toSet().toList()
    ..sort((left, right) => right.compareTo(left));
  return years;
}

/// 双条件过滤（年份 + 项目，各自"空集=不过滤"）。
List<MaintenanceRecord> _filterRecords({
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

/// 把"已选值集合"映射成 FilterBar 的选中下标集合
/// （第 0 格是"全部"，没选中任何值时高亮第 0 格）。
Set<int> _selectedFilterIndexes({
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

/// 点同一个值：未选中则选中，已选中则取消（toggle）。
void _toggleSelection(Set<int> values, int value) {
  if (!values.add(value)) {
    values.remove(value);
  }
}

/// 新增/编辑记录的两步表单。
/// record == null 为新增（默认日期=生效今天、里程=车辆当前里程、费用 0）；
/// 非 null 为编辑（回填原值；已禁用但曾被选中的项目仍展示可选）。
/// reloadItems：行内新增项目保存后从库重拉项目列表并自动勾选新项。
class MaintenanceRecordForm extends ConsumerStatefulWidget {
  const MaintenanceRecordForm({
    required this.car,
    required this.items,
    required this.initialDate,
    required this.today,
    this.record,
    required this.reloadItems,
    required this.onSubmit,
  });

  final Car car;
  final List<MaintenanceItem> items;
  final LocalDate initialDate;
  final LocalDate today;
  final MaintenanceRecord? record;
  final Future<List<MaintenanceItem>> Function() reloadItems;
  final Future<void> Function(
    MaintenanceRecord record,
    List<MaintenanceItem> itemUpdates,
  )
  onSubmit;

  @override
  ConsumerState<MaintenanceRecordForm> createState() =>
      MaintenanceRecordFormState();
}

class MaintenanceRecordFormState extends ConsumerState<MaintenanceRecordForm> {
  // ---- 第一步的字段 ----
  late LocalDate recordDate;
  late final TextEditingController mileageController;
  late final TextEditingController costController;
  late final TextEditingController noteController;

  /// 已勾选的项目 id。
  late final Set<int> selectedItemIds;

  /// 表单当前可见的项目列表（行内新增后会刷新）。
  late List<MaintenanceItem> formItems;

  /// 第二步的记录草稿（非 null 表示已进入第二步）。
  MaintenanceRecord? recordDraft;

  /// 第二步每个项目的间隔输入草稿（含各自的 controller）。
  final intervalDrafts = <RecordIntervalDraft>[];
  bool saving = false;
  String? errorText;

  bool get isEditing => widget.record != null;

  @override
  void initState() {
    super.initState();
    final record = widget.record;
    recordDate = record?.date ?? widget.initialDate;
    mileageController = TextEditingController(
      text: (record?.mileageKm ?? widget.car.currentMileageKm).toString(),
    );
    costController = TextEditingController(
      text: record == null ? '0' : (record.costCents / 100).toStringAsFixed(2),
    );
    noteController = TextEditingController(text: record?.note ?? '');
    selectedItemIds = {...?record?.itemIds};
    formItems = widget.items;
  }

  @override
  void dispose() {
    _disposeIntervalDrafts();
    mileageController.dispose();
    costController.dispose();
    noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (recordDraft != null) {
      return _buildIntervalStep(context);
    }
    final availableItems = widget.record == null
        ? formItems.where((item) => item.enabled).toList()
        : formItems
              .where(
                (item) => item.enabled || selectedItemIds.contains(item.id),
              )
              .toList();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LunioPickerTile(
          label: '保养日期',
          value: formatDateForUser(recordDate),
          enabled: !saving,
          onTap: _pickRecordDate,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: mileageController,
                enabled: !saving,
                // 数字输入统一用数字键盘（与油箱容积同款方式）。
                keyboardType: const TextInputType.numberWithOptions(),
                textInputAction: TextInputAction.done,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onTap: () {
                  if (!isEditing) {
                    _clearZero(mileageController);
                  }
                },
                onSubmitted: (_) => FocusScope.of(context).unfocus(),
                decoration: numberInputDecoration(labelText: '保养里程'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: costController,
                enabled: !saving,
                // 费用可带小数 → 数字键盘带小数点。
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                textInputAction: TextInputAction.done,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                onTap: () {
                  _clearZero(costController);
                },
                onSubmitted: (_) => FocusScope.of(context).unfocus(),
                decoration: numberInputDecoration(labelText: '费用'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          controller: noteController,
          enabled: !saving,
          minLines: 2,
          maxLines: 3,
          decoration: const InputDecoration(labelText: '备注'),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                '保养项目',
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
            SmallActionButton(
              label: '新增',
              primary: true,
              onPressed: saving ? null : _addMaintenanceItem,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final item in availableItems)
              _ChoiceChipButton(
                label: item.enabled ? item.name : '${item.name}（已禁用）',
                selected: item.id != null && selectedItemIds.contains(item.id),
                enabled: !saving && item.id != null,
                onTap: () {
                  setState(() {
                    if (selectedItemIds.contains(item.id)) {
                      selectedItemIds.remove(item.id);
                    } else {
                      selectedItemIds.add(item.id!);
                    }
                  });
                },
              ),
          ],
        ),
        if (errorText != null) ...[
          const SizedBox(height: 10),
          LunioInlineMessage(message: errorText!, tone: LunioStatusTone.danger),
        ],
        const SizedBox(height: 16),
        LunioFormActions(
          confirmLabel: '下一步',
          onCancel: () => Navigator.of(context).pop(),
          onConfirm: _goToIntervalStep,
          saving: saving,
        ),
      ],
    );
  }

  /// 第一步校验 + 构造记录草稿：里程非负整数、费用非负数字、
  /// 至少选一个项目。费用元→分四舍五入。失败返回 null 并设置错误文案。
  MaintenanceRecord? _buildRecordDraft() {
    final mileage = int.tryParse(mileageController.text);
    final cost = double.tryParse(costController.text);
    if (mileage == null || mileage < 0) {
      setState(() => errorText = '保养里程必须是非负整数');
      return null;
    }
    if (cost == null || cost < 0) {
      setState(() => errorText = '费用必须是非负数字');
      return null;
    }
    if (selectedItemIds.isEmpty) {
      setState(() => errorText = '至少选择一个保养项目');
      return null;
    }

    return MaintenanceRecord(
      id: widget.record?.id,
      carId: widget.car.id!,
      date: recordDate,
      itemIds: selectedItemIds.toList(),
      costCents: (cost * 100).round(),
      mileageKm: mileage,
      note: noteController.text.trim().isEmpty
          ? null
          : noteController.text.trim(),
      sync: SyncMetadata(
        status: isEditing ? SyncStatus.pendingUpdate : SyncStatus.pendingCreate,
        updatedAt: DateTime.now(),
      ),
    );
  }

  /// "下一步"：校验通过后为每个选中项目建间隔输入草稿，进入第二步。
  void _goToIntervalStep() {
    final draft = _buildRecordDraft();
    if (draft == null) {
      return;
    }
    final selectedItems = formItems
        .where((item) => item.id != null && selectedItemIds.contains(item.id))
        .toList();
    if (selectedItems.isEmpty) {
      setState(() => errorText = '至少选择一个保养项目');
      return;
    }
    _disposeIntervalDrafts();
    intervalDrafts.addAll(
      selectedItems.map((item) => RecordIntervalDraft(item: item)),
    );
    setState(() {
      recordDraft = draft;
      errorText = null;
    });
  }

  /// 第二步 UI：逐项目展示"按里程/按时间"间隔输入行（预填当前间隔，
  /// 缺省 5000km / 1 个月），可返回上一步。
  Widget _buildIntervalStep(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('确认下次提醒间隔', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        Text(
          '间隔会存为项目默认值，下次提醒从最近一次保养记录起算。',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        for (final draft in intervalDrafts) ...[
          Text(draft.item.name, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          if (draft.item.remindByMileage) ...[
            IntervalNumberInputRow(
              title: '按里程提醒',
              controller: draft.mileageController,
              unit: 'km',
              enabled: !saving,
            ),
            const SizedBox(height: 10),
          ],
          if (draft.item.remindByTime) ...[
            IntervalNumberInputRow(
              title: '按时间提醒',
              controller: draft.monthsController,
              unit: '月',
              enabled: !saving,
            ),
            const SizedBox(height: 10),
          ],
        ],
        if (errorText != null) ...[
          const SizedBox(height: 2),
          LunioInlineMessage(message: errorText!, tone: LunioStatusTone.danger),
        ],
        const SizedBox(height: 16),
        LunioFormActions(
          cancelLabel: '上一步',
          confirmLabel: '保存记录',
          onCancel: () {
            _disposeIntervalDrafts();
            setState(() {
              recordDraft = null;
              errorText = null;
            });
          },
          onConfirm: _submit,
          saving: saving,
        ),
      ],
    );
  }

  /// 第二步提交：间隔校验（正整数）→ 有变化的项目生成 update 列表 →
  /// onSubmit（入库）→ 成功由外层关 sheet；失败展示中文错误。
  Future<void> _submit() async {
    final draft = recordDraft;
    if (draft == null) {
      _goToIntervalStep();
      return;
    }
    final itemUpdates = _buildItemUpdates();
    if (itemUpdates == null) {
      return;
    }
    setState(() {
      saving = true;
      errorText = null;
    });
    try {
      await widget.onSubmit(draft, itemUpdates);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        saving = false;
        errorText = friendlyError(error);
      });
    }
  }

  /// 把第二步的间隔输入整理成"待更新的项目实体"列表：
  /// 间隔没变的项目跳过（不生成 update）；非法值返回 null + 错误文案。
  List<MaintenanceItem>? _buildItemUpdates() {
    final updates = <MaintenanceItem>[];
    for (final draft in intervalDrafts) {
      final item = draft.item;
      final mileageInterval = item.remindByMileage
          ? int.tryParse(draft.mileageController.text)
          : item.mileageIntervalKm;
      final timeInterval = item.remindByTime
          ? int.tryParse(draft.monthsController.text)
          : item.timeIntervalMonths;

      if (item.remindByMileage &&
          (mileageInterval == null || mileageInterval <= 0)) {
        setState(() => errorText = '${item.name} 的里程间隔必须填写正整数');
        return null;
      }
      if (item.remindByTime && (timeInterval == null || timeInterval <= 0)) {
        setState(() => errorText = '${item.name} 的时间间隔必须填写正整数');
        return null;
      }
      if (mileageInterval == item.mileageIntervalKm &&
          timeInterval == item.timeIntervalMonths) {
        continue;
      }
      updates.add(
        MaintenanceItem(
          id: item.id,
          carsId: item.carsId,
          name: item.name,
          enabled: item.enabled,
          remindByMileage: item.remindByMileage,
          remindByTime: item.remindByTime,
          mileageIntervalKm: item.remindByMileage ? mileageInterval : null,
          timeIntervalMonths: item.remindByTime ? timeInterval : null,
          notOverdueUpperLimit: item.notOverdueUpperLimit,
          overdueUpperLimit: item.overdueUpperLimit,
          sortOrder: item.sortOrder,
          sync: SyncMetadata(
            status: SyncStatus.pendingUpdate,
            updatedAt: DateTime.now(),
          ),
        ),
      );
    }
    return updates;
  }

  /// 行内"新增"项目：打开项目表单 sheet → 保存成功后重拉项目列表 →
  /// diff 出新项目 id 自动勾选（用户不用再找）。
  Future<void> _addMaintenanceItem() async {
    final beforeIds = formItems.map((item) => item.id).whereType<int>().toSet();
    final saved = await showMaintenanceItemFormSheet(
      context,
      ref,
      carId: widget.car.id!,
    );
    if (saved != true || !mounted) {
      return;
    }
    final refreshedItems = await widget.reloadItems();
    if (!mounted) {
      return;
    }
    MaintenanceItem? newItem;
    for (final item in refreshedItems) {
      if (item.id != null && !beforeIds.contains(item.id)) {
        newItem = item;
        break;
      }
    }
    setState(() {
      formItems = refreshedItems;
      if (newItem?.id != null) {
        selectedItemIds.add(newItem!.id!);
      }
    });
  }

  /// 点输入框时清掉占位的 "0"/"0.00"，方便直接输入。
  void _clearZero(TextEditingController controller) {
    if (controller.text == '0' || controller.text == '0.00') {
      controller.clear();
    }
  }

  /// 释放第二步所有间隔草稿的 controller。
  void _disposeIntervalDrafts() {
    for (final draft in intervalDrafts) {
      draft.dispose();
    }
    intervalDrafts.clear();
  }

  /// 选记录日期：范围 = 车辆上路日期 ~ 生效今天+365（允许未来日期，R36）。
  Future<void> _pickRecordDate() async {
    final picked = await showSimpleDatePicker(
      context,
      initialDate: recordDate,
      firstDate: widget.car.roadDate,
      lastDate: LocalDate.fromDateTime(
        widget.today.toDateTime().add(const Duration(days: 365)),
      ),
      today: widget.today,
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() => recordDate = picked);
  }
}

/// 第二步单个项目的间隔输入草稿（项目 + 两个 controller，
/// 缺省值 5000km / 1 个月）。dispose 释放 controller。
class RecordIntervalDraft {
  RecordIntervalDraft({required this.item})
    : mileageController = TextEditingController(
        text: item.remindByMileage
            ? (item.mileageIntervalKm ?? 5000).toString()
            : '',
      ),
      monthsController = TextEditingController(
        text: item.remindByTime
            ? (item.timeIntervalMonths ?? 1).toString()
            : '',
      );

  final MaintenanceItem item;
  final TextEditingController mileageController;
  final TextEditingController monthsController;

  void dispose() {
    mileageController.dispose();
    monthsController.dispose();
  }
}

/// ★ 记录表单入口（提醒页按钮 / 记录卡"编辑"）：
/// 先 await 三个 provider（车/项目/生效今天）→ 无车或无可用项目时
/// toast 拦截 → 弹两步表单 sheet。
/// onSubmit：新增走 saveMaintenanceRecordWithItemUpdates、编辑走
/// updateMaintenanceRecordWithItemUpdates（Repository 事务）→
/// invalidateVehicleProviders → 关 sheet。
Future<void> showMaintenanceRecordFormSheet(
  BuildContext context,
  WidgetRef ref, {
  MaintenanceRecord? record,
}) async {
  final car = await ref.read(appliedCarProvider.future);
  final items = await ref.read(appliedCarMaintenanceItemsProvider.future);
  final today = await ref.read(effectiveTodayProvider.future);
  if (!context.mounted) {
    return;
  }
  if (car?.id == null) {
    showStatusOverlay(context, '请先新增车辆', StatusOverlayTone.info);
    return;
  }
  if (items
      .where(
        (item) => item.enabled || record?.itemIds.contains(item.id) == true,
      )
      .isEmpty) {
    showStatusOverlay(context, '请先配置可用保养项目', StatusOverlayTone.info);
    return;
  }
  showLunioModalSheet<void>(
    context: context,
    builder: (sheetContext) {
      return PrototypeSheetFrame(
        title: record == null ? '新增保养记录' : '编辑保养记录',
        subtitle: '${car!.brand} ${car.model}',
        bottomInset: MediaQuery.of(context).viewInsets.bottom,
        child: MaintenanceRecordForm(
          car: car,
          items: items,
          initialDate: today,
          today: today,
          record: record,
          reloadItems: () => ref
              .read(lunioRepositoryProvider)
              .listMaintenanceItemsForCar(car.id!),
          onSubmit: (value, itemUpdates) async {
            // 写库+失效收进动作层（ADR 0007），这里只留反馈薄壳。
            await saveMaintenanceRecord(ref, value, itemUpdates);
            if (sheetContext.mounted) {
              Navigator.of(sheetContext).pop();
            }
            if (context.mounted) {
              showStatusOverlay(context, '保养记录已保存', StatusOverlayTone.success);
            }
          },
        ),
      );
    },
  );
}

/// 删除整条记录（按周期视图）：确认框 → 事务删记录+关联 → invalidate。
Future<void> deleteMaintenanceRecord(
  BuildContext context,
  WidgetRef ref,
  MaintenanceRecord record,
) async {
  final confirmed = await showConfirmDialog(
    context: context,
    title: '删除保养记录',
    message: '确定删除 ${record.date} 的保养记录？',
    confirmLabel: '删除',
  );
  if (confirmed != true || record.id == null) {
    return;
  }
  await removeMaintenanceRecord(ref, record.id!);
}

/// 从记录删除单个项目（按项目视图）：确认框（带项目名）→
/// removeMaintenanceRecordItem（只剩一项时连记录一起删）→ invalidate。
Future<void> deleteMaintenanceRecordItem(
  BuildContext context,
  WidgetRef ref,
  MaintenanceRecord record,
  int itemId,
) async {
  final itemName = ref
      .read(appliedCarMaintenanceItemsProvider)
      .maybeWhen(
        data: (items) => itemById(items, itemId)?.name,
        orElse: () => null,
      );
  final confirmed = await showConfirmDialog(
    context: context,
    title: '删除保养项目',
    message: '确定从 ${record.date} 的保养记录中删除 ${itemName ?? '该项目'}？',
    confirmLabel: '删除',
  );
  if (confirmed != true || record.id == null) {
    return;
  }
  await removeMaintenanceRecordItem(
    ref,
    recordId: record.id!,
    itemId: itemId,
  );
}

// ---- 文件内私有组件与格式化（§5.2 回收：仅本页消费的不进共享层）----

/// 金额（分 → ¥xx.xx）。仅记录列表使用。
String _formatMoney(int costCents) {
  return '¥${(costCents / 100).toStringAsFixed(2)}';
}

/// 横向可滚动的多选筛选条（chip 选中态 + 右下角小对勾）。
/// 年份/项目两条筛选在用（原 shared_widgets 公共组件，仅本页消费，
/// §5.2 回收为私有）。
class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.labels,
    required this.selectedIndexes,
    required this.onSelected,
  });

  final List<String> labels;
  final Set<int> selectedIndexes;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var index = 0; index < labels.length; index++) ...[
            Builder(
              builder: (context) {
                final selected = selectedIndexes.contains(index);
                return InkWell(
                  onTap: () => onSelected(index),
                  borderRadius: BorderRadius.circular(12),
                  overlayColor: WidgetStateProperty.all(Colors.transparent),
                  splashColor: Colors.transparent,
                  highlightColor: Colors.transparent,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        height: 34,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: selected ? tokens.primarySoft : tokens.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: selected
                                ? tokens.primary.withValues(alpha: 0.34)
                                : tokens.line,
                          ),
                        ),
                        child: Text(
                          labels[index],
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(
                                color: selected ? tokens.primary : tokens.ink,
                              ),
                        ),
                      ),
                      if (selected)
                        Positioned(
                          right: 2,
                          bottom: 2,
                          child: Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              color: tokens.primary,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: tokens.surface,
                                width: 1.5,
                              ),
                            ),
                            child: const Icon(
                              Icons.check,
                              size: 9,
                              color: Colors.white,
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
            if (index != labels.length - 1) const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

/// 可多选的项目 chip（记录表单选保养项目用；enabled=false 展示
/// "已停用但历史上被选过"的项目；原 shared_widgets 公共组件，
/// 仅本页消费，§5.2 回收为私有）。
class _ChoiceChipButton extends StatelessWidget {
  const _ChoiceChipButton({
    required this.label,
    required this.selected,
    required this.onTap,
    this.enabled = true,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        constraints: const BoxConstraints(minHeight: 36),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? tokens.primarySoft : tokens.surface2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? tokens.primary.withValues(alpha: 0.3)
                : tokens.line,
          ),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: selected ? tokens.primary : tokens.ink,
          ),
        ),
      ),
    );
  }
}
