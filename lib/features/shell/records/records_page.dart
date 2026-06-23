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
import '../profile/profile_page.dart';
import '../shared/shell_shared.dart';

class RecordsPreviewPage extends ConsumerStatefulWidget {
  const RecordsPreviewPage();

  @override
  ConsumerState<RecordsPreviewPage> createState() => RecordsPreviewPageState();
}

class RecordsPreviewPageState extends ConsumerState<RecordsPreviewPage> {
  int selectedMode = 0;
  final selectedYears = <int>{};
  final selectedItemIds = <int>{};

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
    return LunioPage(
      title: '保养记录',
      children: [
        LunioSegmentedControl(
          values: const ['按周期', '按项目'],
          selectedIndex: selectedMode,
          onSelected: (index) => setState(() => selectedMode = index),
        ),
        const SizedBox(height: 14),
        records.maybeWhen(
          data: (value) {
            final years = _recordYears(value);
            selectedYears.removeWhere((year) => !years.contains(year));
            final itemIds = items
                .map((item) => item.id)
                .whereType<int>()
                .toSet();
            selectedItemIds.removeWhere((itemId) => !itemIds.contains(itemId));
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FilterBar(
                  labels: ['全部年份', for (final year in years) '$year年'],
                  selectedIndexes: _selectedFilterIndexes(
                    values: years,
                    selectedValues: selectedYears,
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
                FilterBar(
                  labels: ['全部项目', for (final item in items) item.name],
                  selectedIndexes: _selectedFilterIndexes(
                    values: items
                        .map((item) => item.id)
                        .whereType<int>()
                        .toList(),
                    selectedValues: selectedItemIds,
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
          },
          orElse: () => const SizedBox.shrink(),
        ),
        const SizedBox(height: 14),
        records.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stackTrace) =>
              LunioCard(child: Text('记录加载失败：${friendlyError(error)}')),
          data: (value) {
            if (car == null) {
              return const LunioCard(child: Text('请先新增车辆'));
            }
            if (value.isEmpty) {
              return LunioCard(
                child: Text(
                  '暂无保养记录，点击右下角 + 新增。',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              );
            }
            final filteredRecords = _filterRecords(
              records: value,
              years: selectedYears,
              itemIds: selectedItemIds,
            );
            if (filteredRecords.isEmpty) {
              return LunioCard(
                child: Text(
                  '没有符合筛选条件的记录',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              );
            }
            if (selectedMode == 0) {
              return RecordCycleList(
                records: filteredRecords,
                items: items,
                onEdit: (record) => showMaintenanceRecordFormSheet(
                  context,
                  ref,
                  record: record,
                ),
                onDelete: (record) =>
                    deleteMaintenanceRecord(context, ref, record),
              );
            }
            return RecordItemList(
              records: filteredRecords,
              items: items,
              selectedItemIds: selectedItemIds,
              onEdit: (record, itemId) =>
                  showMaintenanceRecordFormSheet(context, ref, record: record),
              onDelete: (record, itemId) =>
                  deleteMaintenanceRecordItem(context, ref, record, itemId),
            );
          },
        ),
      ],
    );
  }
}

class RecordCycleList extends StatelessWidget {
  const RecordCycleList({
    required this.records,
    required this.items,
    required this.onEdit,
    required this.onDelete,
  });

  final List<MaintenanceRecord> records;
  final List<MaintenanceItem> items;
  final ValueChanged<MaintenanceRecord> onEdit;
  final ValueChanged<MaintenanceRecord> onDelete;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    return Column(
      children: [
        for (final record in records) ...[
          LunioCard(
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
                      formatMoney(record.costCents),
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
          ),
          if (record != records.last) const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class RecordItemList extends StatelessWidget {
  const RecordItemList({
    required this.records,
    required this.items,
    required this.selectedItemIds,
    required this.onEdit,
    required this.onDelete,
  });

  final List<MaintenanceRecord> records;
  final List<MaintenanceItem> items;
  final Set<int> selectedItemIds;
  final void Function(MaintenanceRecord record, int itemId) onEdit;
  final void Function(MaintenanceRecord record, int itemId) onDelete;

  @override
  Widget build(BuildContext context) {
    final rows =
        <({MaintenanceRecord record, int itemId, MaintenanceItem? item})>[];
    for (final record in records) {
      for (final itemId in record.itemIds) {
        if (selectedItemIds.isNotEmpty && !selectedItemIds.contains(itemId)) {
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
      return LunioCard(
        child: Text(
          '没有符合筛选条件的记录',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }
    return Column(
      children: [
        for (final row in rows) ...[
          LunioCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.item?.name ?? '未知项目',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${row.record.date} · ${formatNumber(row.record.mileageKm)} km',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    const SizedBox(width: 10),
                    SmallActionButton(
                      label: '编辑',
                      onPressed: () => onEdit(row.record, row.itemId),
                    ),
                    const SizedBox(width: 8),
                    SmallActionButton(
                      label: '删除',
                      danger: true,
                      onPressed: () => onDelete(row.record, row.itemId),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

List<int> _recordYears(List<MaintenanceRecord> records) {
  final years = records.map((record) => record.date.year).toSet().toList()
    ..sort((left, right) => right.compareTo(left));
  return years;
}

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

void _toggleSelection(Set<int> values, int value) {
  if (!values.add(value)) {
    values.remove(value);
  }
}

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
  late LocalDate recordDate;
  late final TextEditingController mileageController;
  late final TextEditingController costController;
  late final TextEditingController noteController;
  late final Set<int> selectedItemIds;
  late List<MaintenanceItem> formItems;
  MaintenanceRecord? recordDraft;
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
                keyboardType: TextInputType.text,
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
                keyboardType: TextInputType.text,
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
              ChoiceChipButton(
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
        Row(
          children: [
            Expanded(
              child: LunioSecondaryButton(
                label: '取消',
                onPressed: saving ? null : () => Navigator.of(context).pop(),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: LunioPrimaryButton(
                label: '下一步',
                onPressed: saving ? null : _goToIntervalStep,
              ),
            ),
          ],
        ),
      ],
    );
  }

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

  Widget _buildIntervalStep(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('确认下次提醒间隔', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        Text(
          '保存后会同时更新本次保养项目的默认提醒间隔。',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        for (final draft in intervalDrafts) ...[
          Text(draft.item.name, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          if (draft.item.remindByMileage) ...[
            RecordIntervalInputRow(
              title: '按里程提醒',
              controller: draft.mileageController,
              unit: 'km',
              enabled: !saving,
            ),
            const SizedBox(height: 10),
          ],
          if (draft.item.remindByTime) ...[
            RecordIntervalInputRow(
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
        Row(
          children: [
            Expanded(
              child: LunioSecondaryButton(
                label: '上一步',
                onPressed: saving
                    ? null
                    : () {
                        _disposeIntervalDrafts();
                        setState(() {
                          recordDraft = null;
                          errorText = null;
                        });
                      },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: LunioPrimaryButton(
                label: saving ? '保存中' : '保存记录',
                onPressed: saving ? null : _submit,
              ),
            ),
          ],
        ),
      ],
    );
  }

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

  void _clearZero(TextEditingController controller) {
    if (controller.text == '0' || controller.text == '0.00') {
      controller.clear();
    }
  }

  void _disposeIntervalDrafts() {
    for (final draft in intervalDrafts) {
      draft.dispose();
    }
    intervalDrafts.clear();
  }

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

class RecordIntervalInputRow extends StatelessWidget {
  const RecordIntervalInputRow({
    required this.title,
    required this.controller,
    required this.unit,
    required this.enabled,
  });

  final String title;
  final TextEditingController controller;
  final String unit;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    return Container(
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: tokens.surface2,
        borderRadius: BorderRadius.circular(tokens.radiusMedium),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: enabled ? tokens.ink : tokens.subtle,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 116,
            child: TextField(
              controller: controller,
              enabled: enabled,
              keyboardType: TextInputType.text,
              textInputAction: TextInputAction.done,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onSubmitted: (_) => FocusScope.of(context).unfocus(),
              textAlign: TextAlign.center,
              decoration: numberInputDecoration(suffixText: unit).copyWith(
                fillColor: enabled
                    ? tokens.surface
                    : tokens.surface3.withValues(alpha: 0.55),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                constraints: const BoxConstraints(minHeight: 46),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

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
    isScrollControlled: true,
    showDragHandle: false,
    backgroundColor: Colors.transparent,
    builder: (context) {
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
            final repository = ref.read(lunioRepositoryProvider);
            if (value.id == null) {
              await repository.saveMaintenanceRecordWithItemUpdates(
                record: value,
                itemUpdates: itemUpdates,
              );
            } else {
              await repository.updateMaintenanceRecordWithItemUpdates(
                record: value,
                itemUpdates: itemUpdates,
              );
            }
            invalidateVehicleProviders(ref);
            if (context.mounted) {
              Navigator.of(context).pop();
            }
          },
        ),
      );
    },
  );
}

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
  await ref.read(lunioRepositoryProvider).deleteMaintenanceRecord(record.id!);
  invalidateVehicleProviders(ref);
}

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
  await ref
      .read(lunioRepositoryProvider)
      .removeMaintenanceRecordItem(recordId: record.id!, itemId: itemId);
  invalidateVehicleProviders(ref);
}
