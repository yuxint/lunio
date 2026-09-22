// 记录页（/records）：保养记录的列表、筛选、两步表单和删除。
//
// 页面结构（CustomScrollView + slivers，R25）：
//   1. 模式切换（按周期/按项目）+ 两条 FilterBar（年份多选 + 项目多选，
//      第一格"全部"= 清空筛选）——固定头部 sliver；
//   2. 记录列表：SliverList.builder 懒加载（每项 ValueKey）；
//      按周期 = 每条记录一张卡；按项目 = 记录×项目展开成行；
//   3. 卡片整卡可点 → 记录详情弹窗（record_detail_sheet.dart，弹窗
//      自取数据，卡片不再透传全量记录；按周期看全部项目费用、按项目
//      只看该项目，ADR 0010）；卡上的编辑/删除按钮。
//
// 新增/编辑表单是两步流：第一步填日期/里程/费用/备注/选项目（可行内
// 新增项目并自动勾选）→ 第二步确认所选项目的提醒间隔（可改，保存时
// 一并更新项目）。入口在提醒页按钮和记录卡"编辑"。
// 新增模式带同日查重拦截：表单打开时（默认日期=生效今天）和每次选完
// 日期后立即检查当天是否已有记录，有则弹「返回/去编辑」确认框——
// 「返回」自动重开日期选择器换日期，「去编辑」关新增 sheet 直接转编辑
// 该记录；拦截始终在第一步，不会带着重复日期进入第二步。编辑模式不查
// （改日期撞已有记录时由 Repository 同日唯一校验在保存时报错）。
// 第一步「下一步」另有里程单调性软提示（新增与编辑都查）：草稿与已有
// 记录构成"里程不随日期单调非降"时弹「仍要继续/返回修改」确认框，
// 纯提示不拦截保存、两分支都不写库；规则在
// RecordRules.conflictingMileageRecord，记录数据未就绪时跳过检查。
// 第一步带"详细模式"开关（ADR 0010，默认关）：开启后每个勾选项目展开
// 材料费/工时费/项目费用输入行，自动算链 = 材料+工时→项目费用→合计→
// 总费用；自动值可手改，不一致时红字 + 黄色警告角标，纯提示不拦保存。
// 算链与手改标记的实现收在 record_cost_form_controller.dart（ADR 0010
// 的唯一实现点），本文件只做接线与渲染。
// 第二步的间隔草稿与提交清单生成收在 record_interval_updates.dart
// （正整数校验在 MaintenanceRules，与保养项目表单共用），本文件只做
// 接线与渲染。
// 列表筛选/行展开口径与空态分类收在 record_rows.dart（与提醒域
// reminder_rows 同构的纯函数组装层；只有页面一个消费者，不设
// provider），本文件持有筛选选中 state 并渲染。
// ignore_for_file: use_key_in_widget_constructors, library_private_types_in_public_api

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/date/local_date.dart';
import '../../../core/theme/lunio_tokens.dart';
import '../../../core/widgets/lunio_components.dart';
import '../../../domain/entities/car.dart';
import '../../../domain/entities/fuel_record.dart';
import '../../../domain/entities/maintenance_item.dart';
import '../../../domain/entities/maintenance_record.dart';
import '../../../domain/entities/sync_metadata.dart';
import '../../../domain/rules/record_rules.dart';
import '../profile/maintenance_items.dart';
import '../shared/shell_shared.dart';
import 'cost_stats.dart';
import 'fuel_cost_stats.dart';
import 'record_cost_form_controller.dart';
import 'record_detail_sheet.dart';
import 'record_interval_updates.dart';
import 'record_rows.dart';

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
    // 头部"今年加油"数据源：应用车辆的加油记录。加载失败/未就绪按 0
    // 处理（头部金额少一块不挡记录列表主功能）。
    final fuelRecords = ref
        .watch(appliedCarFuelRecordsProvider)
        .maybeWhen(data: (value) => value, orElse: () => const <FuelRecord>[]);
    // 三页统一 loading/error 形态（§5.2）：与提醒页同构，
    // 记录 provider 就绪前整页占位。
    return records.when(
      loading: () => const LoadingPage(title: '保养记录'),
      error: (error, stackTrace) => ErrorPage(title: '保养记录', error: error),
      data: (value) {
        // 筛选选中集的有效化（R21）与列表组装口径都在 record_rows.dart，
        // 这里算一次传下去（此前筛选条和列表各算一遍有效集）。
        final selections = validSelections(
          records: value,
          items: items,
          selectedYears: selectedYears,
          selectedItemIds: selectedItemIds,
        );
        final listState = classifyRecordListState(
          car: car,
          records: value,
          items: items,
          selections: selections,
        );
        // 头部"今年保养 + 今年加油"汇总行（任一非空就显示，整行可点
        // 进费用统计页）。生效今天未就绪时兜底系统日期——与我的页
        // today 取值同款模式。
        final today = ref
            .watch(effectiveTodayProvider)
            .maybeWhen(
              data: (value) => value,
              orElse: () => LocalDate.fromDateTime(DateTime.now()),
            );
        return LunioPage.slivers(
          title: '保养记录',
          slivers: [
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (value.isNotEmpty || fuelRecords.isNotEmpty) ...[
                    _CostSummaryRow(
                      thisYearMaintenanceCents: costCentsForYear(
                        value,
                        today.year,
                      ),
                      showMaintenance: value.isNotEmpty,
                      thisYearFuelCents: fuelCostCentsForYear(
                        fuelRecords,
                        today.year,
                      ),
                      showFuel: fuelRecords.isNotEmpty,
                      onTap: () => context.push('/cost-stats'),
                    ),
                    const SizedBox(height: 14),
                  ],
                  LunioSegmentedControl(
                    values: const ['按周期', '按项目'],
                    selectedIndex: selectedMode,
                    onSelected: (index) =>
                        setState(() => selectedMode = index),
                  ),
                  const SizedBox(height: 14),
                  _buildFilterBars(value, items, selections),
                  const SizedBox(height: 14),
                ],
              ),
            ),
            _buildRecordListSliver(items, listState),
          ],
        );
      },
    );
  }

  /// 两条筛选条（年份多选 + 项目多选，第一格"全部"= 清空筛选）。
  /// 标签来自全量数据（年份取全部记录、项目取全部项目，不是筛选后
  /// 的子集）；下标映射与 toggle 规则在 record_rows.dart。
  Widget _buildFilterBars(
    List<MaintenanceRecord> records,
    List<MaintenanceItem> items,
    ({Set<int> years, Set<int> itemIds}) selections,
  ) {
    final years = recordYears(records);
    final itemIds = items.map((item) => item.id).whereType<int>().toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FilterBar(
          labels: ['全部年份', for (final year in years) '$year年'],
          selectedIndexes: filterBarSelectionIndexes(
            values: years,
            selectedValues: selections.years,
          ),
          onSelected: (index) => setState(() {
            if (index == 0) {
              selectedYears.clear();
              return;
            }
            toggleSetValue(selectedYears, years[index - 1]);
          }),
        ),
        const SizedBox(height: 8),
        _FilterBar(
          labels: ['全部项目', for (final item in items) item.name],
          selectedIndexes: filterBarSelectionIndexes(
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
              toggleSetValue(selectedItemIds, itemId);
            }
          }),
        ),
      ],
    );
  }

  /// 记录列表区：空态优先级分类在 record_rows.dart 的
  /// classifyRecordListState（无车 > 无记录 > 筛选无结果），空态是固定
  /// 卡片；正常态按当前模式返回 SliverList.builder（每项
  /// ValueKey('record-记录id')，R25）。
  Widget _buildRecordListSliver(
    List<MaintenanceItem> items,
    RecordListState listState,
  ) {
    switch (listState) {
      case RecordListNoCar():
        return const SliverToBoxAdapter(
          child: LunioEmptyCard('请先新增车辆'),
        );
      case RecordListNoRecords():
        return const SliverToBoxAdapter(
          child: LunioEmptyCard('暂无保养记录，可在提醒页点「新增保养记录」。'),
        );
      case RecordListFilteredEmpty():
        return const SliverToBoxAdapter(
          child: LunioEmptyCard('没有符合筛选条件的记录'),
        );
      case RecordListData(:final cycleRecords, :final itemRows):
        if (selectedMode == 0) {
          return SliverList.builder(
            itemCount: cycleRecords.length,
            itemBuilder: (context, index) {
              final record = cycleRecords[index];
              return Padding(
                key: ValueKey('record-${record.id}'),
                padding: EdgeInsets.only(
                  bottom: index == cycleRecords.length - 1 ? 0 : 12,
                ),
                child: RecordCycleCard(
                  record: record,
                  items: items,
                  onEdit: (record) => showMaintenanceRecordFormSheet(
                    context,
                    ref,
                    record: record,
                  ),
                  onDelete: (record) =>
                      deleteMaintenanceRecord(context, ref, record),
                ),
              );
            },
          );
        }
        // 零项目记录的退化数据会让行展开为空（按周期视图看不到它），
        // 此时按项目视图与"筛选无结果"同文案兜底。
        if (itemRows.isEmpty) {
          return const SliverToBoxAdapter(
            child: LunioEmptyCard('没有符合筛选条件的记录'),
          );
        }
        // 详情弹窗自取全量记录（record_detail_sheet.dart），这里只传
        // 筛选后的展示列表。
        return SliverList.builder(
          itemCount: itemRows.length,
          itemBuilder: (context, index) {
            final row = itemRows[index];
            return Padding(
              key: ValueKey('record-${row.record.id}-item-${row.itemId}'),
              padding: EdgeInsets.only(
                bottom: index == itemRows.length - 1 ? 0 : 12,
              ),
              child: RecordItemRowCard(
                record: row.record,
                itemId: row.itemId,
                item: row.item,
                onEdit: (record, itemId) => showMaintenanceRecordFormSheet(
                  context,
                  ref,
                  record: record,
                ),
                onDelete: (record, itemId) =>
                    deleteMaintenanceRecordItem(context, ref, record, itemId),
              ),
            );
          },
        );
    }
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
    // 整卡可点 → 记录详情弹窗（ADR 0010）；编辑/删除按钮在卡内，
    // 点击按钮不会触发整卡 onTap（InkWell 子级按钮优先消费手势）。
    return LunioCard(
      padding: EdgeInsets.zero,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(tokens.radiusLarge),
        child: InkWell(
          onTap: () => showRecordDetailSheet(context, record: record),
          borderRadius: BorderRadius.circular(tokens.radiusLarge),
          child: Padding(
            padding: const EdgeInsets.all(12),
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
                      formatMoneyCents(record.costCents),
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
        ),
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
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    // 整行可点 → 该项目的费用详情（按项目视图只看这一个项目，ADR 0010）。
    return LunioCard(
      padding: EdgeInsets.zero,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(tokens.radiusLarge),
        child: InkWell(
          onTap: () => showRecordDetailSheet(
            context,
            record: record,
            focusItemId: itemId,
          ),
          borderRadius: BorderRadius.circular(tokens.radiusLarge),
          child: Padding(
            padding: const EdgeInsets.all(12),
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
          ),
        ),
      ),
    );
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
    required this.onExitToEdit,
    this.record,
    required this.reloadItems,
    required this.onSubmit,
  });

  final Car car;
  final List<MaintenanceItem> items;
  final LocalDate initialDate;
  final LocalDate today;
  final MaintenanceRecord? record;

  /// 新增模式同日查重弹窗选「去编辑」时回调（传同日已有记录）：
  /// 关当前新增 sheet、打开该记录的编辑 sheet 都要拿到外层 context，
  /// 由入口函数（showMaintenanceRecordFormSheet）接线，表单只管发起。
  final ValueChanged<MaintenanceRecord> onExitToEdit;

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

class MaintenanceRecordFormState extends ConsumerState<MaintenanceRecordForm>
    with LunioFormSubmit {
  // ---- 第一步的字段 ----
  late LocalDate recordDate;
  late final TextEditingController mileageController;
  late final TextEditingController noteController;

  /// 已勾选的项目 id。
  late final Set<int> selectedItemIds;

  /// 表单当前可见的项目列表（行内新增后会刷新）。
  late List<MaintenanceItem> formItems;

  /// 费用区控制器（ADR 0010 自动算链与手改标记的唯一实现，见
  /// record_cost_form_controller.dart）：总费用输入框、详细模式开关、
  /// 各项目费用草稿、手改标记与不一致状态都在里面。
  late final RecordCostFormController costForm;

  /// 第二步的记录草稿（非 null 表示已进入第二步）。
  MaintenanceRecord? recordDraft;

  /// 第二步每个项目的间隔输入草稿（含各自的 controller）。
  final intervalDrafts = <RecordIntervalDraft>[];

  bool get isEditing => widget.record != null;

  @override
  void initState() {
    super.initState();
    final record = widget.record;
    recordDate = record?.date ?? widget.initialDate;
    mileageController = TextEditingController(
      text: (record?.mileageKm ?? widget.car.currentMileageKm).toString(),
    );
    noteController = TextEditingController(text: record?.note ?? '');
    selectedItemIds = {...?record?.itemIds};
    formItems = widget.items;
    costForm = RecordCostFormController(
      record: record,
      formItems: formItems,
      selectedItemIds: selectedItemIds,
      // 编辑带项目费用的记录自动进入详细模式（ADR 0010）。
      detailMode: record?.itemCosts.isNotEmpty ?? false,
    );
    // 新增模式打开即查重（默认日期=生效今天）：首帧渲染后再弹窗，
    // 等 sheet 完成布局，避免浮层叠在开窗动画上；编辑模式不查。
    if (record == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _checkDuplicateAndOfferEdit();
        }
      });
    }
  }

  @override
  void dispose() {
    _disposeIntervalDrafts();
    costForm.dispose();
    mileageController.dispose();
    noteController.dispose();
    super.dispose();
  }

  /// 项目费用输入：控制器维护手改标记 + 跑算链，这里只负责重建
  /// （红字/角标实时变化）。
  void _onItemCostInputChanged(int itemId) {
    costForm.onItemCostChanged(itemId);
    setState(() {});
  }

  /// 材料费/工时费输入：控制器跑算链，这里只负责重建。
  void _onCostInputChanged() {
    costForm.onSplitCostChanged();
    setState(() {});
  }

  /// 总费用输入：控制器维护"手改"标记 + 跑算链，这里只负责重建。
  void _onTotalInputChanged() {
    costForm.onTotalChanged();
    setState(() {});
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
    // 总费用不一致只在详细模式提示：简洁模式看不到项目费用，
    // 单独把总费用标红只会让人困惑（ADR 0010）。判定在控制器里。
    final totalMismatch = costForm.totalMismatch;
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
              child: LunioNumberField(
                controller: mileageController,
                enabled: !saving,
                labelText: '保养里程',
                onTap: isEditing
                    ? null
                    : () => LunioNumberField.clearLeadingZero(mileageController),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: LunioNumberField(
                controller: costForm.totalController,
                enabled: !saving,
                // 费用小数不限位（历史行为保留）。
                decimals: null,
                labelText: '费用',
                warning: totalMismatch,
                onTap: () => LunioNumberField.clearLeadingZero(
                  costForm.totalController,
                ),
                onChanged: (_) => _onTotalInputChanged(),
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
                '详细模式',
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
            Switch(
              value: costForm.detailMode,
              onChanged: saving
                  ? null
                  : (value) => setState(() => costForm.detailMode = value),
            ),
          ],
        ),
        const SizedBox(height: 8),
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
                  costForm.syncSelection(selectedItemIds, formItems);
                },
              ),
          ],
        ),
        if (costForm.detailMode) ...[
          const SizedBox(height: 12),
          // 间隔只加在真实渲染的行后面：未勾选的项目不渲染行也不插空隙，
          // 否则勾选不相邻的项目时行距会在 10/20 之间交替、间隔不一致。
          for (final item in availableItems)
            if (item.id != null && costForm.drafts.containsKey(item.id)) ...[
              _ItemCostRow(
                draft: costForm.drafts[item.id]!,
                enabled: !saving,
                mismatch: costForm.itemMismatch(item.id!),
                onAnyChanged: _onCostInputChanged,
                onCostChanged: () => _onItemCostInputChanged(item.id!),
              ),
              const SizedBox(height: 10),
            ],
        ],
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
  /// 项目费用清单由控制器生成（全空草稿跳过；不一致是合法数据不校验，
  /// ADR 0010）。
  MaintenanceRecord? _buildRecordDraft() {
    final mileage = int.tryParse(mileageController.text);
    final cost = double.tryParse(costForm.totalController.text);
    if (mileage == null || mileage < 0) {
      setFormError('保养里程必须是非负整数');
      return null;
    }
    if (cost == null || cost < 0) {
      setFormError('费用必须是非负数字');
      return null;
    }
    if (selectedItemIds.isEmpty) {
      setFormError('至少选择一个保养项目');
      return null;
    }

    return MaintenanceRecord(
      id: widget.record?.id,
      carId: widget.car.id!,
      date: recordDate,
      itemIds: selectedItemIds.toList(),
      itemCosts: costForm.buildItemCosts(),
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

  /// "下一步"：校验通过后先做里程单调性软提示检查（新增与编辑都查，
  /// 区别于同日查重只查新增；记录数据未就绪跳过，保存时既有校验兜底），
  /// 有冲突弹确认框——「仍要继续」放行进第二步，「返回修改」/点遮罩
  /// 留在第一步；无冲突直接进第二步。软提示两分支都不写库。
  Future<void> _goToIntervalStep() async {
    final draft = _buildRecordDraft();
    if (draft == null) {
      return;
    }
    final conflict = _findMileageConflict(draft);
    if (conflict != null) {
      final proceed = await _showMileageConflictDialog(conflict);
      if (!mounted || proceed != true) {
        return;
      }
    }
    _enterIntervalStep(draft);
  }

  /// 构造第二步的间隔输入草稿并切换视图（软提示「仍要继续」与无冲突
  /// 的共用出口）。
  void _enterIntervalStep(MaintenanceRecord draft) {
    final selectedItems = formItems
        .where((item) => item.id != null && selectedItemIds.contains(item.id))
        .toList();
    if (selectedItems.isEmpty) {
      setFormError('至少选择一个保养项目');
      return;
    }
    _disposeIntervalDrafts();
    intervalDrafts.addAll(
      selectedItems.map((item) => RecordIntervalDraft(item: item)),
    );
    setState(() => recordDraft = draft);
    setFormError(null);
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
            setState(() => recordDraft = null);
            setFormError(null);
          },
          onConfirm: _submit,
          saving: saving,
        ),
      ],
    );
  }

  /// 第二步提交：间隔输入 → buildItemUpdates（校验 + 生成 update 清单，
  /// 实现在 record_interval_updates.dart）→ onSubmit（入库）→ 成功由
  /// 外层关 sheet；失败展示中文错误。
  Future<void> _submit() async {
    final draft = recordDraft;
    if (draft == null) {
      await _goToIntervalStep();
      return;
    }
    final result = buildItemUpdates(
      drafts: intervalDrafts,
      now: DateTime.now(),
    );
    if (result.errorText != null) {
      setFormError(result.errorText!);
      return;
    }
    await runSubmit(() => widget.onSubmit(draft, result.updates));
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
      costForm.syncSelection(selectedItemIds, formItems);
    });
  }

  /// 释放第二步所有间隔草稿的 controller。
  void _disposeIntervalDrafts() {
    for (final draft in intervalDrafts) {
      draft.dispose();
    }
    intervalDrafts.clear();
  }

  /// 选记录日期：范围 = 车辆上路日期 ~ 生效今天+365（允许未来日期，R36）。
  /// 新增模式选完立即查重（编辑模式跳过——改日期撞已有记录时由
  /// Repository 同日唯一校验在保存时报错）。
  Future<void> _pickRecordDate() async {
    final picked = await _showDatePicker();
    if (picked == null || !mounted) {
      return;
    }
    setState(() => recordDate = picked);
    if (!isEditing) {
      await _checkDuplicateAndOfferEdit();
    }
  }

  /// 弹自绘日期选择器（初始值 = 当前选中日期）。范围：上路日期起、
  /// **上限今天**——不能未来（2026-09-22 拍板，与加油记录同规则）。
  Future<LocalDate?> _showDatePicker() {
    return showSimpleDatePicker(
      context,
      initialDate: recordDate,
      firstDate: widget.car.roadDate,
      lastDate: widget.today,
      today: widget.today,
    );
  }

  /// 新增模式的同日查重与处置：检查当前选中日期是否已有记录——
  /// 无重复直接结束；有重复弹「返回/去编辑」确认框：「去编辑」回调
  /// onExitToEdit 关新增 sheet 转编辑该记录（由入口函数接线）；
  /// 「返回」/点遮罩重开日期选择器换日期（初始值 = 重复日期），选完
  /// 再查一轮，循环到选出无重复日期或去编辑退出。拦截始终在第一步。
  Future<void> _checkDuplicateAndOfferEdit() async {
    final existing = _findRecordOn(recordDate);
    if (existing == null) {
      return;
    }
    final gotoEdit = await _showDuplicateDialog(existing);
    if (!mounted) {
      return;
    }
    if (gotoEdit) {
      widget.onExitToEdit(existing);
      return;
    }
    await _pickRecordDate();
  }

  /// 查当前车辆在 [date] 是否已有保养记录（{carId, date} 唯一约束保证
  /// 最多一条）。记录 provider 未就绪时返回 null 跳过检查——保存时
  /// Repository 的同日唯一校验仍会兜底报错。
  MaintenanceRecord? _findRecordOn(LocalDate date) {
    final records = ref.read(appliedCarRecordsProvider).value;
    if (records == null) {
      return null;
    }
    for (final record in records) {
      if (record.date == date) {
        return record;
      }
    }
    return null;
  }

  /// 里程单调性软提示检查（第一步「下一步」时调用，新增与编辑都查）：
  /// 草稿与该车已有记录构成"里程不随日期单调非降"时返回冲突参照记录。
  /// 记录 provider 未就绪时返回 null 跳过——保存时 Repository 的既有
  /// 校验仍会兜底；编辑模式经草稿自身 id 排除自己。
  MaintenanceRecord? _findMileageConflict(MaintenanceRecord draft) {
    final records = ref.read(appliedCarRecordsProvider).value;
    if (records == null) {
      return null;
    }
    return RecordRules.conflictingMileageRecord(
      records: records,
      draftDate: draft.date,
      draftMileageKm: draft.mileageKm,
      selfRecordId: draft.id,
    );
  }

  /// 「与已有记录不一致」软提示确认框（仿同日查重模式）：文案含参照
  /// 记录的日期与里程。返回 true = 用户选「仍要继续」（放行进第二步）；
  /// false（「返回修改」，点遮罩的 null 也折叠成 false）= 留在第一步
  /// 改日期或里程。
  Future<bool> _showMileageConflictDialog(MaintenanceRecord conflict) {
    return showConfirmDialog(
      context: context,
      title: '与已有记录不一致',
      message:
          '${formatDateForUser(conflict.date)} 已有记录里程 '
          '${formatNumber(conflict.mileageKm)} km，与本条填写的日期、'
          '里程矛盾（里程应随日期不减）。可返回修改，或仍要继续。',
      confirmLabel: '仍要继续',
      destructive: false,
      cancelLabel: '返回修改',
    ).then((result) => result == true);
  }

  /// 「该日期已有保养记录」确认框。返回 true = 用户选「去编辑」；
  /// false/null（「返回」/点遮罩）= 留在新增表单换日期。
  Future<bool> _showDuplicateDialog(MaintenanceRecord existing) {
    return showConfirmDialog(
      context: context,
      title: '该日期已有保养记录',
      message:
          '${formatDateForUser(existing.date)} 已有一条保养记录，'
          '可去编辑该记录，或返回更换日期。',
      confirmLabel: '去编辑',
      destructive: false,
      cancelLabel: '返回',
    ).then((result) => result == true);
  }
}

/// ★ 记录表单入口（提醒页按钮 / 记录卡"编辑"）：
/// 先 await 三个 provider（车/项目/生效今天）→ 无车或无可用项目时
/// toast 拦截 → 弹两步表单 sheet。
/// 新增模式表单内自带同日查重（打开时/选完日期后，见表单 state），
/// 查重弹窗选「去编辑」时经 onExitToEdit 在这里关新增 sheet、递归
/// 打开该记录的编辑 sheet。
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
    // 编辑表单：点遮罩/下滑/返回键不可关，只能走取消/保存按钮。
    barrierDismissible: false,
    builder: (sheetContext) {
      return PrototypeSheetFrame(
        title: record == null ? '新增保养记录' : '编辑保养记录',
        subtitle: '${car!.brand} ${car.model}',
        // 必须用 sheet 自己的 context 取键盘高度：外层 context 在 sheet
        // 构建时就定格为 0，键盘弹起后不会更新（曾致底部输入被遮挡）。
        bottomInset: MediaQuery.of(sheetContext).viewInsets.bottom,
        child: MaintenanceRecordForm(
          car: car,
          items: items,
          initialDate: today,
          today: today,
          record: record,
          // 新增模式同日查重弹窗选「去编辑」：先确认外层 context 仍
          // mounted 再关当前新增 sheet，然后用外层 context 打开编辑
          // sheet（关了 sheet 表单的 context 就不可用了，必须用外层）。
          onExitToEdit: (existing) {
            if (!context.mounted) {
              return;
            }
            Navigator.of(sheetContext).pop();
            showMaintenanceRecordFormSheet(context, ref, record: existing);
          },
          reloadItems: () =>
              ref.read(maintenanceItemsForCarProvider(car.id!).future),
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

// ---- 文件内私有组件（§5.2 回收：仅本页消费的不进共享层）----
// 金额展示/解析（formatMoneyCents/parseMoneyCents/formatMoneyText）
// 已升入共享 formatters.dart，经 shell_shared.dart barrel 使用。

/// 头部"今年保养 + 今年加油"汇总行（任一非空就显示）：保养金额口径
/// 见 cost_stats.dart（记录总费用权威值），加油金额口径见
/// fuel_cost_stats.dart（实付优先），整行可点进费用统计页（/cost-stats）。
/// 两段各自按域有无记录显隐（2026-09-22 二轮反馈：无加油记录不显示
/// "今年加油"；无保养记录对称地不显示"今年保养"），不显示 ¥0.00 占位。
class _CostSummaryRow extends StatelessWidget {
  const _CostSummaryRow({
    required this.thisYearMaintenanceCents,
    required this.showMaintenance,
    required this.thisYearFuelCents,
    required this.showFuel,
    required this.onTap,
  });

  final int thisYearMaintenanceCents;

  /// 保养段是否显示（当前车无保养记录时隐藏）。
  final bool showMaintenance;

  final int thisYearFuelCents;

  /// 加油段是否显示（当前车无加油记录时隐藏）。
  final bool showFuel;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    final labelStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: tokens.muted,
    );
    final moneyStyle = Theme.of(context).textTheme.titleMedium?.copyWith(
      color: tokens.primary,
      fontWeight: FontWeight.w800,
    );
    return LunioCard(
      padding: EdgeInsets.zero,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(tokens.radiusLarge),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(tokens.radiusLarge),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                if (showMaintenance) ...[
                  Text('今年保养', style: labelStyle),
                  const SizedBox(width: 8),
                  Text(
                    formatMoneyCents(thisYearMaintenanceCents),
                    style: moneyStyle,
                  ),
                ],
                if (showMaintenance && showFuel)
                  const SizedBox(width: 14),
                if (showFuel) ...[
                  Text('今年加油', style: labelStyle),
                  const SizedBox(width: 8),
                  Text(formatMoneyCents(thisYearFuelCents), style: moneyStyle),
                ],
                const Spacer(),
                Text(
                  '费用统计',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: tokens.muted,
                  ),
                ),
                Icon(Icons.chevron_right, size: 18, color: tokens.subtle),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 详细模式下单个项目的费用输入行（ADR 0010）：项目名 + 材料/工时/
/// 项目费用三个紧凑数字框。项目费用与材料+工时不一致时项目费用红字
/// 并带黄色警告角标（以项目费用为准，纯提示不拦截保存）。
class _ItemCostRow extends StatelessWidget {
  const _ItemCostRow({
    required this.draft,
    required this.enabled,
    required this.mismatch,
    required this.onAnyChanged,
    required this.onCostChanged,
  });

  final RecordCostDraft draft;
  final bool enabled;
  final bool mismatch;

  /// 材料费/工时费输入回调。
  final VoidCallback onAnyChanged;

  /// 项目费用输入回调（要额外维护手改标记，所以单独给）。
  final VoidCallback onCostChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LunioTokens>()!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                draft.item.enabled
                    ? draft.item.name
                    : '${draft.item.name}（已禁用）',
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
            if (mismatch)
              Icon(Icons.warning_amber_rounded, size: 18, color: tokens.warning),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: LunioNumberField(
                controller: draft.materialController,
                enabled: enabled,
                decimals: 2,
                labelText: '材料费',
                onChanged: (_) => onAnyChanged(),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: LunioNumberField(
                controller: draft.laborController,
                enabled: enabled,
                decimals: 2,
                labelText: '工时费',
                onChanged: (_) => onAnyChanged(),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: LunioNumberField(
                controller: draft.costController,
                enabled: enabled,
                decimals: 2,
                labelText: '项目费用',
                warning: mismatch,
                onChanged: (_) => onCostChanged(),
              ),
            ),
          ],
        ),
      ],
    );
  }
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
