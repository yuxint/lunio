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
// 的唯一实现点）。
// 两步表单的状态机（字段、步进、校验、同日查重循环、两个软提示决策）
// 收在 record_form_controller.dart：plain-Dart 控制器，弹窗/日期选择器
// 的实现与文案经 RecordFormUi 注入、已有记录经快照 getter 注入，决策可
// 无 widget 单测；本文件只做装配、渲染与事件转发。
// 第二步的间隔草稿与提交清单生成收在 record_interval_updates.dart
// （正整数校验在 MaintenanceRules，与保养项目表单共用），控制器调用，
// 本文件只做接线与渲染。
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
import '../profile/maintenance_items.dart';
import '../shared/shell_shared.dart';
import 'cost_stats.dart';
import 'fuel_cost_stats.dart';
import 'record_cost_form_controller.dart';
import 'record_detail_sheet.dart';
import 'record_form_controller.dart';
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
/// 状态机（字段、步进、校验、软提示决策、查重循环）在
/// RecordFormController，本 widget 渲染两步视图、注入弹窗/日期选择器
/// 实现并转发事件；reloadItems：行内新增项目保存后从库重拉项目列表。
class MaintenanceRecordForm extends ConsumerStatefulWidget {
  const MaintenanceRecordForm({
    required this.car,
    required this.items,
    required this.initialDate,
    required this.today,
    required this.handle,
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

  /// 表单运行时把手（ADR 0016）：saving/行内错误/提交/关闭都经它，
  /// pop 与 toast 不再由表单或入口闭包手写。
  final FormSheetHandle<void> handle;

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

class MaintenanceRecordFormState extends ConsumerState<MaintenanceRecordForm> {
  // ---- 提交运行时（ADR 0016）：saving/行内错误/提交/关闭统一在把手
  // 上，本 State 只做渲染与事件转发。错误文案的显示经把手（宿主监听
  // 重建），控制器的报错经注入闭包落到把手。
  bool get saving => widget.handle.saving;
  String? get errorText => widget.handle.errorText;

  /// 两步表单状态机（record_form_controller.dart）：字段、步进、校验、
  /// 两个软提示决策与查重循环都在里面，本 State 持有生命周期并转发事件。
  late final RecordFormController form;

  @override
  void initState() {
    super.initState();
    form = RecordFormController(
      car: widget.car,
      items: widget.items,
      initialDate: widget.initialDate,
      record: widget.record,
      ui: RecordFormUi(
        pickDate: _showDatePicker,
        askDuplicate: _showDuplicateDialog,
        askMileageProceed: _showMileageConflictDialog,
        exitToEdit: (existing) {
          if (mounted) {
            widget.onExitToEdit(existing);
          }
        },
      ),
      // 生命周期守卫收在每个注入闭包里（widget 的 mounted 是唯一可信的
      // 生命周期真值）：弹窗/选择器 await 期间表单可能已被卸载（查重
      // 循环在飞），各闭包先查 mounted 再碰 context/ref——日期选择器
      // 未挂载按取消返回 null，两个确认框未挂载按「返回」折叠成 false，
      // 读记录快照未挂载按"未就绪"返回 null（查重/软提示跳过，保存时
      // Repository 唯一校验兜底），错误写入直接丢弃。
      readRecords: () =>
          mounted ? ref.read(appliedCarRecordsProvider).value : null,
      reportError: (text) {
        if (mounted) {
          widget.handle.setFormError(text);
        }
      },
      // 选完日期立即重建：查重循环中途（弹窗悬着）tile 也显示新值，
      // 与收编前"选完日期即 setState"一致；循环结束的整体重建在
      // _pickRecordDate 兜底。
      onDateChanged: () {
        if (mounted) {
          setState(() {});
        }
      },
    );
    // 新增模式打开即查重（默认日期=生效今天）：首帧渲染后再弹窗，等
    // sheet 完成布局，避免浮层叠在开窗动画上；编辑模式不查（决策在
    // formOpened 里）。
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        return;
      }
      await form.formOpened();
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    form.dispose();
    super.dispose();
  }

  /// 项目费用输入：控制器维护手改标记 + 跑算链，这里只负责重建
  /// （红字/角标实时变化）。
  void _onItemCostInputChanged(int itemId) {
    form.onItemCostChanged(itemId);
    setState(() {});
  }

  /// 材料费/工时费输入：控制器跑算链，这里只负责重建。
  void _onCostInputChanged() {
    form.onSplitCostChanged();
    setState(() {});
  }

  /// 总费用输入：控制器维护"手改"标记 + 跑算链，这里只负责重建。
  void _onTotalInputChanged() {
    form.onTotalChanged();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (form.recordDraft != null) {
      return _buildIntervalStep(context);
    }
    final availableItems = form.availableItems;
    // 总费用不一致只在详细模式提示：简洁模式看不到项目费用，
    // 单独把总费用标红只会让人困惑（ADR 0010）。判定在控制器里。
    final totalMismatch = form.totalMismatch;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LunioPickerTile(
          label: '保养日期',
          value: formatDateForUser(form.recordDate),
          enabled: !saving,
          onTap: _pickRecordDate,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: LunioNumberField(
                controller: form.mileageController,
                enabled: !saving,
                labelText: '保养里程',
                onTap: form.isEditing
                    ? null
                    : () =>
                          LunioNumberField.clearLeadingZero(form.mileageController),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: LunioNumberField(
                controller: form.totalController,
                enabled: !saving,
                // 费用小数不限位（历史行为保留）。
                decimals: null,
                labelText: '费用',
                warning: totalMismatch,
                onTap: () => LunioNumberField.clearLeadingZero(
                  form.totalController,
                ),
                onChanged: (_) => _onTotalInputChanged(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          controller: form.noteController,
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
              value: form.detailMode,
              onChanged: saving
                  ? null
                  : (value) => setState(() => form.setDetailMode(value)),
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
                selected: item.id != null &&
                    form.selectedItemIds.contains(item.id),
                enabled: !saving && item.id != null,
                onTap: () => setState(() => form.toggleItem(item.id!)),
              ),
          ],
        ),
        if (form.detailMode) ...[
          const SizedBox(height: 12),
          // 间隔只加在真实渲染的行后面：未勾选的项目不渲染行也不插空隙，
          // 否则勾选不相邻的项目时行距会在 10/20 之间交替、间隔不一致。
          for (final item in availableItems)
            if (item.id != null && form.costDrafts.containsKey(item.id)) ...[
              _ItemCostRow(
                draft: form.costDrafts[item.id]!,
                enabled: !saving,
                mismatch: form.costItemMismatch(item.id!),
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
          // 取消 = 关 sheet，pop 归表单运行时（ADR 0016）。
          onCancel: () => widget.handle.close(),
          onConfirm: _goToIntervalStep,
          saving: saving,
        ),
      ],
    );
  }

  /// 第一步「下一步」：校验、里程单调软提示与进第二步都在控制器里
  /// （决策有 plain-Dart 单测覆盖），这里只转发并重建。
  Future<void> _goToIntervalStep() async {
    await form.goToIntervalStep();
    if (mounted) {
      setState(() {});
    }
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
        for (final draft in form.intervalDrafts) ...[
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
          onCancel: () => setState(form.backToFirstStep),
          onConfirm: _submit,
          saving: saving,
        ),
      ],
    );
  }

  /// 第二步提交：间隔输入 → 提交载荷（校验与 buildItemUpdates 在控制器
  /// 里，失败报行内错误返回 null）→ handle.submit（入库）。成功关 sheet
  /// 与失败行内错误都归表单运行时 handle（ADR 0016）；写库动作仍由入口
  /// 接线到保存动作层（ADR 0007）。
  Future<void> _submit() async {
    final payload = await form.submitPayload();
    if (payload == null || !mounted) {
      return;
    }
    await widget.handle.submit(
      () => widget.onSubmit(payload.draft, payload.updates),
    );
  }

  /// 行内"新增"项目：打开项目表单 sheet → 保存成功后重拉项目列表；
  /// diff 出新项目自动勾选的决策在控制器 itemPoolRefreshed 里。
  Future<void> _addMaintenanceItem() async {
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
    setState(() => form.itemPoolRefreshed(refreshedItems));
  }

  /// 点"保养日期"：弹窗实现与范围留在 widget 侧（UI 决策），日期落状态、
  /// 新增模式选后查重与循环驱动都在控制器；日期落定时控制器经
  /// onDateChanged 已通知本 State 立即重建（循环中途弹窗悬着也显示新值），
  /// 这里在循环结束后再兜底重建一次。
  Future<void> _pickRecordDate() async {
    await form.pickRecordDate();
    if (mounted) {
      setState(() {});
    }
  }

  /// 弹自绘日期选择器（初始值 = 控制器当前选中日期）。范围：上路日期起、
  /// **上限今天**——不能未来（2026-09-22 拍板，与加油记录同规则）。
  /// 作为 RecordFormUi.pickDate 注入控制器；await 期间表单可能已被卸载
  /// （查重循环在飞），此时按"取消"折叠成 null，不再碰 context。
  Future<LocalDate?> _showDatePicker(LocalDate initialDate) async {
    if (!mounted) {
      return null;
    }
    return showSimpleDatePicker(
      context,
      initialDate: initialDate,
      firstDate: widget.car.roadDate,
      lastDate: widget.today,
      today: widget.today,
    );
  }

  /// 「与已有记录不一致」软提示确认框（仿同日查重模式）：文案含参照
  /// 记录的日期与里程。返回 true = 用户选「仍要继续」（放行进第二步）；
  /// false（「返回修改」，点遮罩的 null 也折叠成 false）= 留在第一步
  /// 改日期或里程。作为 RecordFormUi.askMileageProceed 注入；表单已卸载
  /// 时按「返回修改」折叠，不再碰 context。
  Future<bool> _showMileageConflictDialog(MaintenanceRecord conflict) async {
    if (!mounted) {
      return false;
    }
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
  /// false/null（「返回」/点遮罩）= 留在新增表单换日期。作为
  /// RecordFormUi.askDuplicate 注入；表单已卸载时按「返回」折叠，
  /// 不再碰 context。
  Future<bool> _showDuplicateDialog(MaintenanceRecord existing) async {
    if (!mounted) {
      return false;
    }
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
/// 装载/守卫/键盘 inset/pop/toast 的时序归 showLunioFormSheet（ADR 0016），
/// 这里只声明装载内容、"无车/无项目"守卫文案、头部副标题与提交动作。
/// 新增模式表单内自带同日查重（打开时/选完日期后，决策在
/// RecordFormController），查重弹窗选「去编辑」时经 onExitToEdit 用
/// handle.close() 关新增 sheet、再用外层 context 递归打开该记录的编辑
/// sheet。
Future<void> showMaintenanceRecordFormSheet(
  BuildContext context,
  WidgetRef ref, {
  MaintenanceRecord? record,
}) {
  // 装载结果写入闭包捕获变量，在 load/guard/builder 之间共享（ADR 0016）。
  Car? car;
  List<MaintenanceItem> items = const [];
  LocalDate today = LocalDate.fromDateTime(DateTime.now());
  return showLunioFormSheet<void>(
    context: context,
    title: record == null ? '新增保养记录' : '编辑保养记录',
    load: (handle) async {
      car = await ref.read(appliedCarProvider.future);
      items = await ref.read(appliedCarMaintenanceItemsProvider.future);
      today = await ref.read(effectiveTodayProvider.future);
      // 闭包捕获变量不做类型提升（装载数据跨闭包共享的标准写法），
      // 先落本地再判空。
      final loadedCar = car;
      if (loadedCar != null) {
        handle.setSubtitle('${loadedCar.brand} ${loadedCar.model}');
      }
    },
    guard: () {
      if (car?.id == null) {
        return '请先新增车辆';
      }
      final usable = items.where(
        (item) => item.enabled || record?.itemIds.contains(item.id) == true,
      );
      if (usable.isEmpty) {
        return '请先配置可用保养项目';
      }
      return null;
    },
    builder: (sheetContext, handle) {
      return MaintenanceRecordForm(
        car: car!,
        items: items,
        initialDate: today,
        today: today,
        record: record,
        handle: handle,
        // 新增模式同日查重弹窗选「去编辑」：先关当前新增 sheet（pop 归
        // handle），再用外层 context 打开编辑 sheet（关了 sheet 表单的
        // context 就不可用了，必须用外层）。
        onExitToEdit: (existing) {
          if (!context.mounted) {
            return;
          }
          handle.close();
          showMaintenanceRecordFormSheet(context, ref, record: existing);
        },
        reloadItems: () =>
            ref.read(maintenanceItemsForCarProvider(car!.id!).future),
        // 写库+失效收进动作层（ADR 0007）；关 sheet 与成功 toast 归表单
        // 运行时（ADR 0016）。
        onSubmit: (value, itemUpdates) =>
            saveMaintenanceRecord(ref, value, itemUpdates),
      );
    },
    successMessage: '保养记录已保存',
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
